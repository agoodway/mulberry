defmodule Mulberry.Export.Markdown do
  @moduledoc """
  Exports crawl results to markdown files.

  This module provides functionality to export crawled web pages to markdown format,
  supporting both individual files and combined output. It handles:

  - Individual markdown files with customizable naming patterns
  - Combined markdown files with table of contents
  - YAML frontmatter generation with proper escaping
  - Parallel file writes for improved performance
  - Atomic writes to prevent corruption

  ## Usage

      # Export to individual files
      results = [%{url: "...", title: "...", content: "..."}]
      {:ok, stats} = Markdown.export_individual(results, "/output", filename_pattern: "title")

      # Export to combined file
      {:ok, filepath} = Markdown.export_combined(results, "/output", combined_filename: "all-pages")

  ## Options

  ### Individual Export Options
    - `:filename_pattern` - How to generate filenames: "url", "title", or "hash" (default: "url")
    - `:add_metadata` - Include YAML frontmatter (default: true)
    - `:overwrite_policy` - How to handle existing files: :skip, :overwrite, :error, :increment
    - `:parallel` - Use parallel writes (default: true)
    - `:max_concurrency` - Max parallel writes (default: System.schedulers_online() * 2)

  ### Combined Export Options
    - `:combined_filename` - Name for combined file (default: "combined")
    - `:add_metadata` - Include metadata and TOC (default: true)
  """

  require Logger

  alias Mulberry.Document.WebPage
  alias Mulberry.Util.{Filename, FileWriter}

  @type export_result :: %{
          written: non_neg_integer(),
          skipped: non_neg_integer(),
          errors: non_neg_integer()
        }

  @type crawl_result :: %{
          url: String.t(),
          title: String.t() | nil,
          description: String.t() | nil,
          content: String.t() | nil,
          crawled_at: DateTime.t(),
          meta: map()
        }

  # Public API

  @doc """
  Exports crawl results to individual markdown files.

  Uses parallel writes by default for improved performance on large crawls.

  ## Options
    - `:filename_pattern` - "url", "title", or "hash" (default: "url")
    - `:add_metadata` - Include YAML frontmatter (default: true)
    - `:overwrite_policy` - :skip, :overwrite, :error, :increment (default: :increment)
    - `:parallel` - Use parallel writes (default: true)
    - `:max_concurrency` - Max parallel writes (default: System.schedulers_online() * 2)
    - `:on_progress` - Optional callback fn(index, total) for progress updates

  ## Returns
    - `{:ok, %{written: n, skipped: n, errors: n}}`
  """
  @spec export_individual([crawl_result()], String.t(), keyword()) :: {:ok, export_result()}
  def export_individual(results, output_dir, opts \\ []) do
    filename_pattern = Keyword.get(opts, :filename_pattern, "url")
    add_metadata = Keyword.get(opts, :add_metadata, true)
    overwrite_policy = Keyword.get(opts, :overwrite_policy, :increment)
    parallel = Keyword.get(opts, :parallel, true)
    max_concurrency = Keyword.get(opts, :max_concurrency, System.schedulers_online() * 2)
    on_progress = Keyword.get(opts, :on_progress)

    total = length(results)

    write_fn = fn {result, index} ->
      if on_progress, do: on_progress.(index, total)

      write_single_file(result, output_dir, filename_pattern, add_metadata, overwrite_policy)
    end

    stats =
      if parallel and total > 1 do
        export_parallel(results, write_fn, max_concurrency)
      else
        export_sequential(results, write_fn)
      end

    {:ok, stats}
  end

  @doc """
  Exports crawl results to a single combined markdown file.

  Uses streaming to avoid OOM with large result sets.

  ## Options
    - `:combined_filename` - Name for output file without extension (default: "combined")
    - `:add_metadata` - Include header with TOC (default: true)

  ## Returns
    - `{:ok, filepath}` on success
    - `{:error, reason}` on failure
  """
  @spec export_combined([crawl_result()], String.t(), keyword()) ::
          {:ok, String.t()} | {:error, any()}
  def export_combined(results, output_dir, opts \\ []) do
    combined_filename = Keyword.get(opts, :combined_filename, "combined")
    add_metadata = Keyword.get(opts, :add_metadata, true)

    filepath = Path.join(output_dir, "#{combined_filename}.md")
    content_stream = build_combined_stream(results, add_metadata)

    case FileWriter.write_file_atomic_stream(filepath, content_stream) do
      :ok -> {:ok, filepath}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Checks if sufficient disk space is available for export.

  Uses actual page count for accurate estimation.

  ## Options
    - `:avg_page_size_kb` - Average page size in KB (default: 50)
    - `:max_disk_usage_mb` - Maximum disk usage allowed (optional)

  ## Returns
    - `:ok` if sufficient space
    - `{:error, :insufficient_disk_space, required_mb, available_mb}` if not
  """
  @spec check_disk_space(String.t(), non_neg_integer(), keyword()) ::
          :ok | {:error, :insufficient_disk_space, pos_integer(), pos_integer()}
  def check_disk_space(output_dir, page_count, opts \\ []) do
    FileWriter.check_disk_space(output_dir, page_count, opts)
  end

  # Markdown Building Functions

  @doc """
  Builds YAML frontmatter for a crawl result.

  Properly escapes values to prevent YAML injection.
  """
  @spec build_frontmatter(crawl_result()) :: String.t()
  def build_frontmatter(result) do
    crawled_at =
      case result.crawled_at do
        %DateTime{} = dt -> DateTime.to_iso8601(dt)
        other -> to_string(other)
      end

    safe_url = yaml_escape(result.url || "")
    safe_title = yaml_escape(result.title || "")

    """
    ---
    url: #{safe_url}
    title: #{safe_title}
    crawled_at: #{crawled_at}
    ---

    """
  end

  @doc """
  Generates a URL-safe anchor from a title.

  Returns a fallback anchor if title sanitizes to empty.
  """
  @spec generate_anchor(String.t() | nil, pos_integer()) :: String.t()
  def generate_anchor(title, index) do
    base =
      (title || "")
      |> String.downcase()
      |> String.replace(~r/[^\w\s-]/, "")
      |> String.replace(~r/\s+/, "-")
      |> String.trim("-")

    if base == "" do
      "page-#{index}"
    else
      base
    end
  end

  @doc """
  Builds a table of contents from crawl results.
  """
  @spec build_toc([crawl_result()]) :: String.t()
  def build_toc(results) do
    results
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {result, index} ->
      title = result.title || "Page #{index}"
      anchor = generate_anchor(title, index)
      "- [#{title}](##{anchor})"
    end)
  end

  # Private Functions - Parallel/Sequential Export

  defp export_parallel(results, write_fn, max_concurrency) do
    results
    |> Enum.with_index(1)
    |> Task.async_stream(write_fn,
      max_concurrency: max_concurrency,
      timeout: 30_000,
      on_timeout: :kill_task
    )
    |> Enum.reduce(%{written: 0, skipped: 0, errors: 0}, fn
      {:ok, {:ok, :written, _}}, acc ->
        %{acc | written: acc.written + 1}

      {:ok, {:ok, :skipped}}, acc ->
        %{acc | skipped: acc.skipped + 1}

      {:ok, {:error, _reason}}, acc ->
        %{acc | errors: acc.errors + 1}

      {:exit, _reason}, acc ->
        %{acc | errors: acc.errors + 1}
    end)
  end

  defp export_sequential(results, write_fn) do
    results
    |> Enum.with_index(1)
    |> Enum.reduce(%{written: 0, skipped: 0, errors: 0}, fn item, acc ->
      case write_fn.(item) do
        {:ok, :written, _} -> %{acc | written: acc.written + 1}
        {:ok, :skipped} -> %{acc | skipped: acc.skipped + 1}
        {:error, _} -> %{acc | errors: acc.errors + 1}
      end
    end)
  end

  # Private Functions - Single File Write

  defp write_single_file(result, output_dir, filename_pattern, add_metadata, overwrite_policy) do
    web_page = build_web_page(result)

    with {:ok, markdown} <- Mulberry.Document.to_markdown(web_page),
         {:ok, filename} <- generate_filename(result, filename_pattern, output_dir),
         filepath = Path.join(output_dir, filename),
         content = build_file_content(markdown, result, add_metadata),
         {:ok, action, path} <- do_file_write(filepath, content, overwrite_policy) do
      format_result(action, path)
    else
      {:error, :file_exists, path} -> {:error, {:file_exists, path}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_web_page(result) do
    %WebPage{
      url: result.url,
      title: result.title,
      description: result.description,
      content: result.content,
      markdown: result[:markdown] || convert_to_markdown(result.content),
      meta: result.meta
    }
  end

  defp build_file_content(markdown, result, true), do: build_frontmatter(result) <> markdown
  defp build_file_content(markdown, _result, false), do: markdown

  defp do_file_write(filepath, content, overwrite_policy) do
    case Filename.handle_existing_file(filepath, overwrite_policy) do
      {:ok, :write, final_path} ->
        case FileWriter.write_file_atomic(final_path, content) do
          :ok -> {:ok, :written, final_path}
          error -> error
        end

      {:ok, :skip} ->
        {:ok, :skipped, nil}

      {:error, :file_exists, path} ->
        {:error, :file_exists, path}
    end
  end

  defp format_result(:written, path), do: {:ok, :written, Path.basename(path)}
  defp format_result(:skipped, _), do: {:ok, :skipped}

  # Private Functions - Combined Markdown

  defp build_combined_stream(results, add_metadata) do
    header = build_combined_header(results, add_metadata)
    total = length(results)

    Stream.concat([
      [header],
      results
      |> Stream.with_index(1)
      |> Stream.flat_map(fn {result, index} ->
        section = build_page_section(result, index, add_metadata)

        if index < total do
          [section, "\n\n---\n\n"]
        else
          [section]
        end
      end)
    ])
  end

  defp build_combined_header(results, true) do
    first_result = List.first(results)
    source_url = if first_result, do: URI.parse(first_result.url).host, else: "Unknown"
    crawled_at = DateTime.utc_now() |> DateTime.to_iso8601()

    """
    # Crawl Results

    **Source:** #{source_url}
    **Crawled:** #{crawled_at}
    **Pages:** #{length(results)}

    ## Table of Contents

    #{build_toc(results)}

    ---

    """
  end

  defp build_combined_header(_results, false) do
    "# Crawl Results\n\n---\n\n"
  end

  defp build_page_section(result, index, add_metadata) do
    web_page = build_web_page(result)
    title = result.title || "Page #{index}"
    anchor = generate_anchor(title, index)

    header =
      if add_metadata do
        """
        <a id="#{anchor}"></a>

        ## #{title}

        **URL:** #{result.url}
        **Title:** #{title}

        """
      else
        "<a id=\"#{anchor}\"></a>\n\n## #{title}\n\n"
      end

    markdown =
      case Mulberry.Document.to_markdown(web_page) do
        {:ok, md} -> md
        {:error, _} -> result.content || ""
      end

    header <> markdown
  end

  # Private Functions - Filename Generation

  defp generate_filename(result, pattern, output_dir) do
    opts = [output_dir: output_dir]

    case pattern do
      "url" ->
        Filename.from_url(result.url, opts)

      "title" ->
        Filename.from_title(result.title || "", Keyword.put(opts, :fallback_url, result.url))

      "hash" ->
        Filename.from_hash(result.url, opts)
    end
  end

  # Private Functions - YAML Escaping

  defp yaml_escape(value) when is_binary(value) do
    if needs_yaml_quoting?(value) do
      "\"" <> escape_yaml_string(value) <> "\""
    else
      value
    end
  end

  defp yaml_escape(value), do: to_string(value)

  defp needs_yaml_quoting?(value) do
    String.match?(value, ~r/[:\n\r\t"'\\#\[\]{}|>&*!?@`]/) or
      String.starts_with?(value, [" ", "-", "?", ":", ",", "[", "]", "{", "}"]) or
      String.ends_with?(value, [" ", ":"]) or
      value == ""
  end

  defp escape_yaml_string(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end

  # Private Functions - Content Conversion

  defp convert_to_markdown(nil), do: ""

  defp convert_to_markdown(content) when is_binary(content) do
    case Mulberry.HTML.to_markdown(content) do
      {:ok, markdown} -> markdown
      {:error, _} -> content
    end
  end
end
