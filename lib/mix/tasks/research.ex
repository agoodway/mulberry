defmodule Mix.Tasks.Research do
  @moduledoc """
  Conducts comprehensive research on a topic using Mulberry's research capabilities.

  ## Usage

      mix research TOPIC [options]

  ## Options

    * `--strategy` - Research strategy: web, local, or hybrid (default: web)
    * `--max-sources` - Maximum number of sources to analyze (default: 5)
    * `--depth` - Research depth 1-3, higher is more thorough (default: 1)
    * `--format` - Output format: text, markdown, or json (default: text)
    * `--save` - Save results to specified file
    * `--verbose` - Show detailed progress information
    * `--search-paths` - Directories to search (local strategy only)
    * `--file-patterns` - File patterns to match (local strategy only)
    * `--domains` - Domains to include in web search
    * `--exclude-domains` - Domains to exclude from web search
    * `--content-length` - Detail level for content: short, medium, long, comprehensive (default: medium)
    * `--search-module` - Search module to use (e.g., brave, reddit)
    * `--search-modules` - JSON array of search module configs for multi-source search

  ## Examples

      # Basic web research
      mix research "quantum computing applications"

      # Hybrid research with more sources
      mix research "machine learning trends" --strategy hybrid --max-sources 10

      # Local document research
      mix research "project documentation" --strategy local \\
        --search-paths ./docs --file-patterns "*.md,*.txt"

      # Save results to markdown
      mix research "renewable energy" --save results.md --format markdown

      # Verbose mode with JSON output
      mix research "AI safety" --verbose --format json --save research.json

      # Web research with domain filtering
      mix research "elixir programming" --domains "elixir-lang.org,hexdocs.pm" \\
        --exclude-domains "reddit.com"
      
      # Research using Reddit as search source
      mix research "machine learning" --search-module reddit
      
      # Multi-source research with Brave and Reddit
      mix research "elixir tips" --search-modules '[
        {"module": "brave", "options": {}},
        {"module": "reddit", "options": {"sort": "top"}, "weight": 1.5}
      ]'
  """

  use Mix.Task

  @shortdoc "Conducts research on a topic using various strategies"

  @impl Mix.Task
  def run(args) do
    {opts, args_list, _} =
      OptionParser.parse(args,
        switches: [
          strategy: :string,
          max_sources: :integer,
          depth: :integer,
          format: :string,
          save: :string,
          verbose: :boolean,
          search_paths: :string,
          file_patterns: :string,
          domains: :string,
          exclude_domains: :string,
          content_length: :string,
          search_module: :string,
          search_modules: :string
        ],
        aliases: [
          s: :strategy,
          m: :max_sources,
          d: :depth,
          f: :format,
          v: :verbose,
          c: :content_length
        ]
      )

    topic = Enum.join(args_list, " ")

    unless String.trim(topic) != "" do
      Mix.raise("Topic is required. Usage: mix research TOPIC [options]")
    end

    # Start the application
    Mix.Task.run("app.start")

    # Validate and prepare options
    opts = validate_options(opts)
    research_opts = build_research_options(opts, topic)

    Mix.shell().info("Researching: #{topic}")
    Mix.shell().info("Strategy: #{opts[:strategy] || "web"}")
    Mix.shell().info("")

    # Conduct research
    result = Mulberry.research(topic, research_opts)

    case result do
      {:ok, research_result} ->
        handle_success(research_result, opts)

      {:error, reason} ->
        Mix.shell().error("Research failed: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp validate_options(opts) do
    opts = validate_strategy(opts)
    opts = validate_depth(opts)
    opts = validate_format(opts)
    opts = validate_content_length(opts)
    opts
  end

  defp validate_strategy(opts) do
    case opts[:strategy] do
      nil ->
        opts

      "web" ->
        Keyword.put(opts, :strategy, :web)

      "local" ->
        Keyword.put(opts, :strategy, :local)

      "hybrid" ->
        Keyword.put(opts, :strategy, :hybrid)

      strategy ->
        Mix.raise("Invalid strategy: #{strategy}. Must be web, local, or hybrid")
    end
  end

  defp validate_depth(opts) do
    case opts[:depth] do
      nil ->
        opts

      depth when depth in 1..3 ->
        opts

      depth ->
        Mix.raise("Invalid depth: #{depth}. Must be between 1 and 3")
    end
  end

  defp validate_format(opts) do
    case opts[:format] do
      nil ->
        Keyword.put(opts, :format, "text")

      format when format in ["text", "markdown", "json"] ->
        opts

      format ->
        Mix.raise("Invalid format: #{format}. Must be text, markdown, or json")
    end
  end

  defp validate_content_length(opts) do
    case opts[:content_length] do
      nil ->
        opts

      length when length in ["short", "medium", "long", "comprehensive"] ->
        opts

      length ->
        Mix.raise(
          "Invalid content length: #{length}. Must be short, medium, long, or comprehensive"
        )
    end
  end

  defp build_research_options(opts, _topic) do
    research_opts = []

    # Add basic options
    research_opts = maybe_add_option(research_opts, :strategy, opts[:strategy])
    research_opts = maybe_add_option(research_opts, :max_sources, opts[:max_sources])
    research_opts = maybe_add_option(research_opts, :depth, opts[:depth])
    research_opts = maybe_add_option(research_opts, :content_length, opts[:content_length])

    # Add search module configuration
    research_opts = add_search_module_options(research_opts, opts)

    # Add progress callback if verbose
    research_opts =
      if opts[:verbose] do
        Keyword.put(research_opts, :on_progress, &progress_callback/2)
      else
        research_opts
      end

    # Add search options
    search_options = build_search_options(opts)

    if map_size(search_options) > 0 do
      Keyword.put(research_opts, :search_options, search_options)
    else
      research_opts
    end
  end

  defp maybe_add_option(list, _key, nil), do: list
  defp maybe_add_option(list, key, value), do: Keyword.put(list, key, value)

  defp add_search_module_options(research_opts, opts) do
    cond do
      # Multiple modules specified as JSON
      modules_json = opts[:search_modules] ->
        parse_and_add_search_modules(research_opts, modules_json)

      # Single module specified
      module_name = opts[:search_module] ->
        module = get_module_atom(module_name)
        Keyword.put(research_opts, :search_module, module)

      # No modules specified
      true ->
        research_opts
    end
  end

  defp parse_and_add_search_modules(research_opts, modules_json) do
    case Jason.decode(modules_json) do
      {:ok, modules} ->
        modules = Enum.map(modules, &build_module_config/1)
        Keyword.put(research_opts, :search_modules, modules)

      {:error, _} ->
        Mix.raise("Invalid JSON for search_modules: #{modules_json}")
    end
  end

  defp build_module_config(module_config) do
    %{
      module: get_module_atom(module_config["module"]),
      options: parse_module_options(module_config["options"] || %{}),
      weight: module_config["weight"] || 1.0
    }
  end

  defp get_module_atom("brave"), do: Mulberry.Search.Brave
  defp get_module_atom("reddit"), do: Mulberry.Search.Reddit

  defp get_module_atom(module) when is_binary(module) do
    Mix.raise("Unknown search module: #{module}. Available: brave, reddit")
  end

  defp parse_module_options(options) when is_map(options) do
    # Convert string keys to atoms for known Reddit options
    Enum.reduce(options, %{}, fn {key, value}, acc ->
      atom_key =
        case key do
          "sort" -> :sort
          "timeframe" -> :timeframe
          "subreddit" -> :subreddit
          "after" -> :after
          "trim" -> :trim
          "result_filter" -> :result_filter
          _ -> String.to_atom(key)
        end

      Map.put(acc, atom_key, value)
    end)
  end

  defp build_search_options(opts) do
    search_opts = %{}

    # Local strategy options
    search_opts =
      if paths = opts[:search_paths] do
        Map.put(search_opts, :search_paths, String.split(paths, ","))
      else
        search_opts
      end

    search_opts =
      if patterns = opts[:file_patterns] do
        Map.put(search_opts, :file_patterns, String.split(patterns, ","))
      else
        search_opts
      end

    # Web strategy options
    search_opts =
      if domains = opts[:domains] do
        Map.put(search_opts, :include_domains, String.split(domains, ","))
      else
        search_opts
      end

    search_opts =
      if exclude = opts[:exclude_domains] do
        Map.put(search_opts, :exclude_domains, String.split(exclude, ","))
      else
        search_opts
      end

    search_opts
  end

  defp progress_callback(stage, info) do
    timestamp = Calendar.strftime(DateTime.utc_now(), "%H:%M:%S")
    message = format_progress_message(timestamp, stage, info)
    Mix.shell().info(message)
  end

  defp format_progress_message(timestamp, stage, info) do
    case stage do
      :sources_gathered ->
        "[#{timestamp}] ✓ Gathered #{info.count} sources"

      :documents_selected ->
        "[#{timestamp}] ✓ Selected #{info.selected} of #{info.total_found} documents"

      :analyzing_source ->
        source_name = get_source_name(info)
        "[#{timestamp}] → Analyzing #{source_name} (#{info.current}/#{info.total})"

      :analysis_complete ->
        "[#{timestamp}] ✓ Completed analysis of #{info.sources_analyzed} sources"

      :chunks_created ->
        "[#{timestamp}] ✓ Created #{info.count} text chunks"

      :fetching_document ->
        "[#{timestamp}] → Fetching #{info.url}"

      _ ->
        "[#{timestamp}] → #{stage}: #{inspect(info)}"
    end
  end

  defp get_source_name(%{file: file}), do: Path.basename(file)
  defp get_source_name(%{url: url}), do: URI.parse(url).host || url
  defp get_source_name(_), do: "source"

  defp handle_success(result, opts) do
    # Format the output
    output =
      case opts[:format] do
        "json" -> format_json(result)
        "markdown" -> format_markdown(result)
        _ -> format_text(result)
      end

    # Save or display
    if save_path = opts[:save] do
      save_results(output, save_path, opts[:format])
    else
      display_results(output)
    end
  end

  defp format_text(result) do
    """
    Research Topic: #{result.topic}

    SUMMARY
    ═══════════════════════════════════════════════════════════════════════════════
    #{result.summary}

    #{format_text_detailed_content(result.detailed_content)}

    KEY FINDINGS
    ═══════════════════════════════════════════════════════════════════════════════
    #{format_text_findings(result.key_findings)}

    SOURCES (#{length(result.sources || [])})
    ═══════════════════════════════════════════════════════════════════════════════
    #{format_text_sources(result.sources)}

    THEMES
    ═══════════════════════════════════════════════════════════════════════════════
    #{format_text_list(result.themes)}

    CONFIDENCE SCORE: #{format_confidence(result.confidence_score)}

    RELATED TOPICS
    ═══════════════════════════════════════════════════════════════════════════════
    #{format_text_list(result.related_topics)}

    #{format_text_stats(result.stats)}
    """
  end

  defp format_text_findings(nil), do: "No findings recorded"
  defp format_text_findings([]), do: "No findings recorded"

  defp format_text_findings(findings) do
    findings
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {finding, index} ->
      "#{index}. #{finding.text}\n   Confidence: #{format_confidence(finding.confidence)}"
    end)
  end

  defp format_text_sources(nil), do: "No sources"
  defp format_text_sources([]), do: "No sources"

  defp format_text_sources(sources) do
    sources
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {source, index} ->
      title = get_source_title(source)
      "#{index}. #{title}"
    end)
  end

  defp format_text_list(nil), do: "None"
  defp format_text_list([]), do: "None"
  defp format_text_list(items), do: Enum.map_join(items, "\n", &"• #{&1}")

  defp format_text_detailed_content(nil), do: ""

  defp format_text_detailed_content(content) do
    """
    DETAILED CONTENT
    ═══════════════════════════════════════════════════════════════════════════════
    #{content}
    """
  end

  defp format_markdown(result) do
    """
    # Research: #{result.topic}

    ## Summary

    #{result.summary}

    #{format_markdown_detailed_content(result.detailed_content)}

    ## Key Findings

    #{format_markdown_findings(result.key_findings)}

    ## Sources

    #{format_markdown_sources(result.sources)}

    ## Themes

    #{format_markdown_list(result.themes)}

    ## Confidence Score

    #{format_confidence(result.confidence_score)}

    ## Related Topics

    #{format_markdown_list(result.related_topics)}

    #{format_markdown_stats(result.stats)}

    ---

    *Research conducted on #{DateTime.utc_now() |> DateTime.to_string()}*
    *Strategy: #{result.metadata[:strategy]}*
    """
  end

  defp format_markdown_findings(nil), do: "*No findings recorded*"
  defp format_markdown_findings([]), do: "*No findings recorded*"

  defp format_markdown_findings(findings) do
    findings
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {finding, index} ->
      "#{index}. **#{finding.text}**\n   - Confidence: #{format_confidence(finding.confidence)}"
    end)
  end

  defp format_markdown_sources(nil), do: "*No sources*"
  defp format_markdown_sources([]), do: "*No sources*"

  defp format_markdown_sources(sources) do
    sources
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {source, index} ->
      title = get_source_title(source)
      url = get_source_url(source)

      if url do
        "#{index}. [#{title}](#{url})"
      else
        "#{index}. #{title}"
      end
    end)
  end

  defp format_markdown_list(nil), do: "*None*"
  defp format_markdown_list([]), do: "*None*"
  defp format_markdown_list(items), do: Enum.map_join(items, "\n", &"- #{&1}")

  defp format_markdown_detailed_content(nil), do: ""

  defp format_markdown_detailed_content(content) do
    """
    ## Detailed Content

    #{content}
    """
  end

  defp format_json(result) do
    result
    |> Map.from_struct()
    |> Jason.encode!(pretty: true)
  end

  defp get_source_title(%{title: title}) when is_binary(title), do: title
  defp get_source_title(%{url: url}) when is_binary(url), do: url
  defp get_source_title(%{path: path}) when is_binary(path), do: Path.basename(path)
  defp get_source_title(_), do: "Unknown source"

  defp get_source_url(%{url: url}) when is_binary(url), do: url
  defp get_source_url(_), do: nil

  defp format_confidence(nil), do: "N/A"
  defp format_confidence(score) when is_float(score), do: "#{round(score * 100)}%"
  defp format_confidence(score) when is_integer(score), do: "#{score}%"

  defp format_text_stats(nil), do: ""

  defp format_text_stats(stats) when is_map(stats) do
    sections =
      stats
      |> Enum.map(fn {category, items} ->
        format_stat_category_text(category, items)
      end)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n\n")

    if sections == "" do
      ""
    else
      """

      STATISTICS & KEY DATA
      ═══════════════════════════════════════════════════════════════════════════════
      #{sections}
      """
    end
  end

  defp format_markdown_stats(nil), do: ""

  defp format_markdown_stats(stats) when is_map(stats) do
    sections =
      stats
      |> Enum.map(fn {category, items} ->
        format_stat_category_markdown(category, items)
      end)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n\n")

    if sections == "" do
      ""
    else
      """

      ## Statistics & Key Data

      #{sections}
      """
    end
  end

  defp format_stat_category_text(category, items) when is_list(items) and length(items) > 0 do
    title = format_category_title(category)

    stats =
      items
      |> Enum.map_join("\n", fn item ->
        "• #{item.value}: #{item.context}"
      end)

    "#{title}:\n#{stats}"
  end

  defp format_stat_category_text(_, _), do: ""

  defp format_stat_category_markdown(category, items) when is_list(items) and length(items) > 0 do
    title = format_category_title(category)

    stats =
      items
      |> Enum.map_join("\n", fn item ->
        "- **#{item.value}**: #{item.context}"
      end)

    "### #{title}\n\n#{stats}"
  end

  defp format_stat_category_markdown(_, _), do: ""

  defp format_category_title(:numbers_and_percentages), do: "Key Numbers & Percentages"
  defp format_category_title(:dates_and_timelines), do: "Dates & Timelines"
  defp format_category_title(:comparisons), do: "Comparisons & Rankings"
  defp format_category_title(:quantities), do: "Quantities & Measurements"
  defp format_category_title(:financial), do: "Financial Data"
  defp format_category_title(:other), do: "Other Statistics"

  defp format_category_title(category),
    do: category |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp save_results(content, path, format) do
    case File.write(path, content) do
      :ok ->
        Mix.shell().info("")
        Mix.shell().info("Results saved to: #{path}")
        Mix.shell().info("Format: #{format}")
        Mix.shell().info("Size: #{byte_size(content)} bytes")

      {:error, reason} ->
        Mix.shell().error("Failed to save file: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp display_results(output) do
    Mix.shell().info("")
    Mix.shell().info(output)
  end
end
