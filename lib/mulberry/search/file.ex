defmodule Mulberry.Search.File do
  @moduledoc """
  File search implementation for local file system.

  This module implements the Search.Behaviour for searching local files
  by filename and content. It supports various search strategies including
  pattern matching, content search using grep/ripgrep, and fuzzy matching.

  ## Examples

      # Basic filename search
      File.search("README", 10, "filename")

      # Content search
      File.search("defmodule", 20, "content", paths: ["./lib"])

      # Combined search with filters
      File.search("test", 50, "combined",
        paths: ["./test", "./lib"],
        patterns: ["*.ex", "*.exs"],
        exclude: ["_build", "deps"]
      )
  """

  @behaviour Mulberry.Search.Behaviour

  require Logger

  @type search_mode :: String.t()
  @type search_result :: %{
          path: String.t(),
          score: float(),
          matches: list(String.t()),
          preview: String.t() | nil
        }

  @impl true
  @spec search(String.t(), pos_integer(), String.t(), Keyword.t()) ::
          {:ok, map()} | {:error, String.t()}
  def search(query, count \\ 20, mode \\ "combined", opts \\ []) do
    search_paths = Keyword.get(opts, :paths, ["."])
    file_patterns = Keyword.get(opts, :patterns, ["*"])
    exclude_dirs = Keyword.get(opts, :exclude, ["_build", "deps", ".git", "node_modules"])
    max_file_size = Keyword.get(opts, :max_file_size, 10_485_760)  # 10MB default

    case mode do
      "filename" ->
        search_by_filename(query, search_paths, file_patterns, exclude_dirs, count)

      "content" ->
        search_by_content(query, search_paths, file_patterns, exclude_dirs, count, max_file_size)

      "combined" ->
        search_combined(query, search_paths, file_patterns, exclude_dirs, count, max_file_size)

      _ ->
        {:error, "Invalid search mode. Must be one of: filename, content, combined"}
    end
  end

  @impl true
  @spec to_documents(any()) :: {:ok, [Mulberry.Document.File.t()]} | {:error, atom()}
  def to_documents(results) do
    case results do
      %{"results" => results} when is_list(results) ->
        docs =
          results
          |> Enum.map(fn result ->
            attrs = %{
              path: result["path"],
              title: Path.basename(result["path"]),
              meta: [
                score: result["score"],
                matches: result["matches"],
                preview: result["preview"]
              ]
            }

            Mulberry.Document.File.new(attrs)
          end)

        {:ok, docs}

      [] ->
        {:ok, []}

      list when is_list(list) ->
        docs =
          list
          |> Enum.map(fn result ->
            attrs = %{
              path: result["path"],
              title: Path.basename(result["path"]),
              meta: [
                score: result["score"],
                matches: result["matches"],
                preview: result["preview"]
              ]
            }

            Mulberry.Document.File.new(attrs)
          end)

        {:ok, docs}

      _ ->
        {:error, :invalid_search_results}
    end
  end

  # Private functions

  defp search_by_filename(query, search_paths, patterns, exclude_dirs, count) do
    query_lower = String.downcase(query)
    query_parts = String.split(query_lower, ~r/\s+/)

    results =
      search_paths
      |> find_all_files(patterns, exclude_dirs)
      |> Enum.map(fn path ->
        filename = Path.basename(path) |> String.downcase()
        score = calculate_filename_score(filename, query_lower, query_parts)

        %{
          "path" => path,
          "score" => score,
          "matches" => find_filename_matches(filename, query_parts),
          "preview" => nil
        }
      end)
      |> Enum.filter(fn result -> result["score"] > 0 end)
      |> Enum.sort_by(fn result -> result["score"] end, :desc)
      |> Enum.take(count)

    {:ok, %{"results" => results}}
  end

  defp search_by_content(query, search_paths, patterns, exclude_dirs, count, max_file_size) do
    # Use ripgrep if available, fallback to grep
    results =
      if ripgrep_available?() do
        search_with_ripgrep(query, search_paths, patterns, exclude_dirs, count, max_file_size)
      else
        search_with_grep(query, search_paths, patterns, exclude_dirs, count, max_file_size)
      end

    case results do
      {:ok, files} -> {:ok, %{"results" => files}}
      error -> error
    end
  end

  defp search_combined(query, search_paths, patterns, exclude_dirs, count, max_file_size) do
    with {:ok, %{"results" => filename_results}} <-
           search_by_filename(query, search_paths, patterns, exclude_dirs, count * 2),
         {:ok, %{"results" => content_results}} <-
           search_by_content(query, search_paths, patterns, exclude_dirs, count * 2, max_file_size) do
      # Merge and deduplicate results
      all_results =
        merge_search_results(filename_results, content_results)
        |> Enum.sort_by(fn result -> result["score"] end, :desc)
        |> Enum.take(count)

      {:ok, %{"results" => all_results}}
    end
  end

  defp find_all_files(search_paths, patterns, exclude_dirs) do
    exclude_regex = build_exclude_regex(exclude_dirs)

    search_paths
    |> Enum.flat_map(fn path ->
      patterns
      |> Enum.flat_map(fn pattern ->
        Path.wildcard(Path.join([path, "**", pattern]))
      end)
    end)
    |> Enum.uniq()
    |> Enum.filter(&Elixir.File.regular?/1)
    |> Enum.reject(fn path ->
      Regex.match?(exclude_regex, path)
    end)
  end

  defp build_exclude_regex(exclude_dirs) do
    pattern = Enum.map_join(exclude_dirs, "|", &Regex.escape/1)

    Regex.compile!("/(#{pattern})/")
  end

  defp calculate_filename_score(filename, query, query_parts) do
    # Normalize by replacing underscores with spaces and removing extension for comparison
    base_filename = Path.basename(filename, Path.extname(filename))
    normalized_filename = String.replace(base_filename, "_", " ")
    
    cond do
      # Exact match (with normalization)
      normalized_filename == query -> 1.0

      # Contains full query
      String.contains?(filename, query) || String.contains?(normalized_filename, query) -> 0.8

      # All parts match
      Enum.all?(query_parts, &(String.contains?(filename, &1) || String.contains?(normalized_filename, &1))) ->
        0.6 + (0.2 * (length(query_parts) / String.length(filename)))

      # Some parts match
      true ->
        matches = Enum.count(query_parts, &(String.contains?(filename, &1) || String.contains?(normalized_filename, &1)))
        matches / length(query_parts) * 0.5
    end
  end

  defp find_filename_matches(filename, query_parts) do
    query_parts
    |> Enum.filter(&String.contains?(filename, &1))
    |> Enum.uniq()
  end

  defp ripgrep_available?() do
    case System.cmd("which", ["rg"]) do
      {_, 0} -> true
      _ -> false
    end
  end

  defp search_with_ripgrep(query, search_paths, patterns, exclude_dirs, count, max_file_size) do
    args =
      build_ripgrep_args(query, patterns, exclude_dirs, max_file_size) ++
        ["--"] ++ search_paths

    case System.cmd("rg", args, stderr_to_stdout: true) do
      {output, 0} ->
        results = parse_ripgrep_output(output, count)
        {:ok, results}

      {_, _} ->
        # No matches found or error
        {:ok, []}
    end
  end

  defp build_ripgrep_args(query, patterns, exclude_dirs, max_file_size) do
    base_args = [
      query,
      "--json",
      "--max-count", "5",
      "--max-filesize", "#{max_file_size}"
    ]

    pattern_args =
      Enum.flat_map(patterns, fn pattern ->
        ["--glob", pattern]
      end)

    exclude_args =
      Enum.flat_map(exclude_dirs, fn dir ->
        ["--glob", "!#{dir}/**"]
      end)

    base_args ++ pattern_args ++ exclude_args
  end

  defp parse_ripgrep_output(output, count) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(&Jason.decode/1)
    |> Enum.filter(fn
      {:ok, %{"type" => "match"}} -> true
      _ -> false
    end)
    |> Enum.map(fn {:ok, match_data} -> match_data end)
    |> group_by_file()
    |> Enum.map(fn {path, matches} ->
      %{
        "path" => path,
        "score" => calculate_content_score(matches),
        "matches" => extract_match_lines(matches),
        "preview" => create_preview(matches)
      }
    end)
    |> Enum.sort_by(fn result -> result["score"] end, :desc)
    |> Enum.take(count)
  end

  defp group_by_file(matches) do
    matches
    |> Enum.group_by(fn match ->
      match["data"]["path"]["text"]
    end)
  end

  defp calculate_content_score(matches) do
    # Score based on number of matches and their distribution
    match_count = length(matches)
    unique_lines = matches |> Enum.map(fn m -> m["data"]["line_number"] end) |> Enum.uniq() |> length()

    base_score = min(match_count * 0.1, 0.5)
    line_bonus = min(unique_lines * 0.05, 0.3)
    
    min(base_score + line_bonus, 1.0)
  end

  defp extract_match_lines(matches) do
    matches
    |> Enum.map(fn match ->
      match["data"]["lines"]["text"]
      |> String.trim()
    end)
    |> Enum.uniq()
    |> Enum.take(5)
  end

  defp create_preview(matches) do
    matches
    |> Enum.take(3)
    |> Enum.map_join("\n", fn match ->
      line_num = match["data"]["line_number"]
      text = String.trim(match["data"]["lines"]["text"])
      "L#{line_num}: #{text}"
    end)
  end

  defp search_with_grep(query, search_paths, patterns, exclude_dirs, count, max_file_size) do
    # Simplified grep implementation
    files = find_all_files(search_paths, patterns, exclude_dirs)

    results =
      files
      |> Enum.filter(fn path ->
        case Elixir.File.stat(path) do
          {:ok, %{size: size}} -> size <= max_file_size
          _ -> false
        end
      end)
      |> Enum.map(fn path ->
        case search_file_with_grep(path, query) do
          {:ok, [_ | _] = matches} ->
            %{
              "path" => path,
              "score" => min(length(matches) * 0.1, 1.0),
              "matches" => Enum.take(matches, 5),
              "preview" => Enum.join(Enum.take(matches, 3), "\n")
            }

          _ ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(fn result -> result["score"] end, :desc)
      |> Enum.take(count)

    {:ok, results}
  end

  defp search_file_with_grep(path, query) do
    case System.cmd("grep", ["-n", "-i", query, path], stderr_to_stdout: true) do
      {output, 0} ->
        matches = parse_grep_output(output)
        {:ok, matches}

      _ ->
        {:ok, []}
    end
  end

  defp parse_grep_output(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(&format_grep_line/1)
  end

  defp format_grep_line(line) do
    case String.split(line, ":", parts: 2) do
      [line_num, text] -> "L#{line_num}: #{String.trim(text)}"
      _ -> String.trim(line)
    end
  end

  defp merge_search_results(filename_results, content_results) do
    # Create a map of path -> result for easy lookup
    content_map = Map.new(content_results, fn r -> {r["path"], r} end)

    # Merge filename results with content results
    merged =
      filename_results
      |> Enum.map(fn filename_result ->
        case Map.get(content_map, filename_result["path"]) do
          nil ->
            filename_result

          content_result ->
            # Combine scores and matches
            %{
              "path" => filename_result["path"],
              "score" => (filename_result["score"] + content_result["score"]) / 2,
              "matches" => 
                (filename_result["matches"] || []) ++ (content_result["matches"] || [])
                |> Enum.uniq()
                |> Enum.take(5),
              "preview" => content_result["preview"] || filename_result["preview"]
            }
        end
      end)

    # Add content results that weren't in filename results
    content_only =
      content_results
      |> Enum.reject(fn r -> Map.has_key?(Map.new(filename_results, fn r -> {r["path"], r} end), r["path"]) end)

    merged ++ content_only
  end
end