defmodule Mix.Tasks.Crawl do
  @moduledoc """
  Crawls websites or lists of URLs using Mulberry's crawler.

  This task provides command-line access to Mulberry's web crawling functionality,
  supporting URL list crawling, website crawling, and sitemap-based crawling modes.
  Results can be output as console text, JSONL, or markdown files.

  ## Usage

  ### Crawl a single website:
      mix crawl --url https://example.com

  ### Crawl with custom depth:
      mix crawl --url https://example.com --max-depth 5

  ### Crawl a list of URLs from a file:
      mix crawl --urls urls.txt

  ### Crawl from sitemap:
      mix crawl --sitemap example.com
      mix crawl --sitemap https://example.com/sitemap.xml

  ### Crawl with custom settings:
      mix crawl --url https://example.com --max-workers 10 --rate-limit 5

  ### Save results to a file (JSONL):
      mix crawl --url https://example.com --output results.jsonl

  ### Export as Markdown:
      mix crawl --url https://example.com --format markdown --output-dir ./crawled

  ## Options

  ### Crawl Options

    * `--url` - URL to start crawling from (for website mode)
    * `--urls` - Path to file containing URLs to crawl (one per line)
    * `--sitemap` - Domain or sitemap URL to crawl from (discovers sitemaps automatically)
    * `--max-depth` - Maximum crawl depth for website mode (default: 3)
    * `--max-workers` - Maximum concurrent workers (default: 5)
    * `--rate-limit` - Requests per second per domain (default: 1.0)
    * `--retriever` - Retriever to use: req, playwright, or scraping_bee (default: req)
    * `--no-robots` - Disable robots.txt compliance checking (default: false)
    * `--include-pattern` - Regex pattern for URLs to include (can be repeated)
    * `--exclude-pattern` - Regex pattern for URLs to exclude (can be repeated)

  ### Output Options

    * `--format` - Output format: console, jsonl, or markdown (default: console)
    * `--output` - Path to save results as JSONL (for jsonl format)
    * `--output-dir` - Directory for markdown files (required for markdown format)
    * `--filename-pattern` - Filename pattern: url, title, or hash (default: url)
    * `--combined-filename` - Name for combined file (default: combined)
    * `--combine-files` - Combine all pages into single markdown file (default: false)
    * `--add-metadata` - Add crawl metadata to each file (default: true)
    * `--no-metadata` - Disable metadata addition
    * `--overwrite` - Overwrite existing files (default: increment)
    * `--skip-existing` - Skip crawling URLs that would overwrite files
    * `--error-on-exists` - Raise error if file would be overwritten
    * `--cleanup-on-fail` - Remove partially-written files on failure (default: false)
    * `--resume` - Skip already-written files, continue crawl (default: false)
    * `--progress` - Show progress bar during file writes (default: false)

  ### Resource Management Options

    * `--max-disk-usage` - Maximum disk usage in MB before stopping (default: no limit)
    * `--avg-page-size` - Average page size in KB for space estimation (default: 50)

  ### Logging Options

    * `--quiet` - Suppress progress output, only show final summary
    * `--verbose` - Enable verbose logging (show each URL as it's crawled)
    * `--verbosity` - Output verbosity: quiet, normal, verbose, debug (default: normal)

  ## Examples

      # Crawl a website and save results as JSONL
      mix crawl --url https://elixir-lang.org --max-depth 2 --output elixir-docs.jsonl

      # Export as markdown files
      mix crawl --url https://example.com --format markdown --output-dir ./crawled

      # Export with title-based filenames
      mix crawl --url https://example.com --format markdown --output-dir ./crawled --filename-pattern title

      # Combine all pages into single markdown file
      mix crawl --url https://example.com --format markdown --output-dir ./docs --combine-files

      # Crawl with URL filtering and markdown export
      mix crawl --sitemap example.com --include-pattern "/blog/" --format markdown --output-dir ./blog

      # Crawl with Playwright for JavaScript-heavy sites
      mix crawl --url https://spa-example.com --retriever playwright --format markdown --output-dir ./spa

      # Resume interrupted crawl
      mix crawl --url https://example.com --format markdown --output-dir ./crawled --resume
  """

  use Mix.Task
  require Logger

  alias Mulberry.Export.Markdown, as: MarkdownExport
  alias Mulberry.Util.FileWriter

  @shortdoc "Crawls websites or lists of URLs"

  @valid_formats ~w[console jsonl markdown]
  @valid_filename_patterns ~w[url title hash]
  @default_avg_page_size_kb 50

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _args, invalid} = parse_args(args)
    validate_options!(invalid)
    validate_format_options!(opts)
    configure_logging(opts)
    execute_crawl(opts)
  end

  defp parse_args(args) do
    OptionParser.parse(args,
      strict: [
        # Crawl options
        url: :string,
        urls: :string,
        sitemap: :string,
        max_depth: :integer,
        max_workers: :integer,
        rate_limit: :float,
        retriever: :string,
        no_robots: :boolean,
        include_pattern: :keep,
        exclude_pattern: :keep,
        # Output options
        format: :string,
        output: :string,
        output_dir: :string,
        filename_pattern: :string,
        combined_filename: :string,
        combine_files: :boolean,
        add_metadata: :boolean,
        no_metadata: :boolean,
        overwrite: :boolean,
        skip_existing: :boolean,
        error_on_exists: :boolean,
        cleanup_on_fail: :boolean,
        resume: :boolean,
        progress: :boolean,
        # Resource management
        max_disk_usage: :integer,
        avg_page_size: :integer,
        # Logging options
        verbose: :boolean,
        quiet: :boolean,
        verbosity: :string
      ],
      aliases: [
        d: :max_depth,
        w: :max_workers,
        r: :rate_limit,
        o: :output,
        v: :verbose,
        i: :include_pattern,
        e: :exclude_pattern,
        s: :sitemap,
        q: :quiet,
        f: :format
      ]
    )
  end

  defp validate_options!([]), do: :ok

  defp validate_options!(invalid) do
    Mix.raise("Invalid options: #{inspect(invalid)}")
  end

  defp validate_format_options!(opts) do
    format = opts[:format] || "console"

    unless format in @valid_formats do
      Mix.raise("Invalid format: #{format}. Must be one of: #{Enum.join(@valid_formats, ", ")}")
    end

    if format == "markdown" do
      unless opts[:output_dir] do
        Mix.raise("--output-dir is required when --format markdown is specified")
      end

      if opts[:filename_pattern] && opts[:filename_pattern] not in @valid_filename_patterns do
        Mix.raise(
          "Invalid filename pattern: #{opts[:filename_pattern]}. Must be one of: #{Enum.join(@valid_filename_patterns, ", ")}"
        )
      end
    end

    :ok
  end

  defp configure_logging(opts) do
    verbosity = determine_verbosity(opts)

    case verbosity do
      :quiet -> Logger.configure(level: :error)
      :normal -> Logger.configure(level: :info)
      :verbose -> Logger.configure(level: :debug)
      :debug -> Logger.configure(level: :debug)
    end
  end

  defp execute_crawl(opts) do
    mode_count = Enum.count([opts[:url], opts[:urls], opts[:sitemap]], & &1)

    cond do
      mode_count > 1 ->
        Mix.raise("Cannot specify multiple modes. Use only one of: --url, --urls, or --sitemap")

      opts[:url] ->
        crawl_website(opts[:url], opts)

      opts[:urls] ->
        crawl_urls_from_file(opts[:urls], opts)

      opts[:sitemap] ->
        crawl_from_sitemap(opts[:sitemap], opts)

      true ->
        Mix.raise("Must specify one of: --url, --urls, or --sitemap")
    end
  end

  defp crawl_website(url, opts) do
    Mix.shell().info("Starting website crawl from: #{url}")

    with :ok <- pre_flight_validation(opts),
         crawl_opts = build_crawl_opts(opts),
         start_time = System.monotonic_time(:millisecond),
         {:ok, results} <- Mulberry.Crawler.crawl_website(url, crawl_opts) do
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      Mix.shell().info("\nCrawl completed in #{duration}ms")
      Mix.shell().info("Total pages crawled: #{length(results)}")

      handle_results(results, opts)
    else
      {:error, :insufficient_disk_space, required_mb, available_mb} ->
        Mix.raise("""
        Insufficient disk space
        Required: #{required_mb} MB
        Available: #{available_mb} MB
        Please free up disk space or use --max-disk-usage to limit usage
        """)

      {:error, reason} ->
        Mix.raise("Crawl failed: #{inspect(reason)}")
    end
  end

  defp crawl_urls_from_file(file_path, opts) do
    unless File.exists?(file_path) do
      Mix.raise("File not found: #{file_path}")
    end

    urls =
      file_path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" || String.starts_with?(&1, "#")))

    if urls == [] do
      Mix.raise("No valid URLs found in file: #{file_path}")
    end

    Mix.shell().info("Crawling #{length(urls)} URLs from: #{file_path}")

    with :ok <- pre_flight_validation(opts),
         crawl_opts = build_crawl_opts(opts),
         start_time = System.monotonic_time(:millisecond),
         {:ok, results} <- Mulberry.Crawler.crawl_urls(urls, crawl_opts) do
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      Mix.shell().info("\nCrawl completed in #{duration}ms")
      Mix.shell().info("Total pages crawled: #{length(results)}")

      handle_results(results, opts)
    else
      {:error, :insufficient_disk_space, required_mb, available_mb} ->
        Mix.raise("""
        Insufficient disk space
        Required: #{required_mb} MB
        Available: #{available_mb} MB
        Please free up disk space or use --max-disk-usage to limit usage
        """)

      {:error, reason} ->
        Mix.raise("Crawl failed: #{inspect(reason)}")
    end
  end

  defp crawl_from_sitemap(sitemap_input, opts) do
    # Determine if input is a full URL or just a domain
    {domain, sitemap_url} =
      if String.starts_with?(sitemap_input, "http://") ||
           String.starts_with?(sitemap_input, "https://") do
        # Extract domain from URL for display
        uri = URI.parse(sitemap_input)
        {uri.host, sitemap_input}
      else
        {sitemap_input, nil}
      end

    Mix.shell().info("Starting sitemap crawl for: #{domain}")

    if sitemap_url do
      Mix.shell().info("Using sitemap: #{sitemap_url}")
    else
      Mix.shell().info("Discovering sitemaps...")
    end

    crawl_opts = build_crawl_opts(opts)

    crawl_opts =
      if sitemap_url do
        Keyword.put(crawl_opts, :sitemap_url, sitemap_url)
      else
        crawl_opts
      end

    with :ok <- pre_flight_validation(opts),
         start_time = System.monotonic_time(:millisecond),
         {:ok, results} <- Mulberry.Crawler.crawl_from_sitemap(domain, crawl_opts) do
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      Mix.shell().info("\nCrawl completed in #{duration}ms")
      Mix.shell().info("Total pages crawled: #{length(results)}")

      handle_results(results, opts)
    else
      {:error, :no_sitemaps_found} ->
        Mix.raise("No sitemaps found for domain: #{domain}")

      {:error, :no_urls_in_sitemap} ->
        Mix.raise("No URLs found in sitemap(s) for domain: #{domain}")

      {:error, :insufficient_disk_space, required_mb, available_mb} ->
        Mix.raise("""
        Insufficient disk space
        Required: #{required_mb} MB
        Available: #{available_mb} MB
        Please free up disk space or use --max-disk-usage to limit usage
        """)

      {:error, reason} ->
        Mix.raise("Crawl failed: #{inspect(reason)}")
    end
  end

  defp pre_flight_validation(opts) do
    format = opts[:format] || "console"

    if format == "markdown" do
      output_dir = opts[:output_dir]

      # Ensure output directory exists
      case FileWriter.ensure_output_directory(output_dir) do
        :ok ->
          # Check disk space (estimate 100 pages as default)
          check_disk_space_if_needed(output_dir, 100, opts)

        {:error, :directory_creation_failed, reason} ->
          Mix.raise("Cannot create output directory #{output_dir}: #{inspect(reason)}")

        {:error, :not_writable, reason} ->
          Mix.raise("Output directory is not writable #{output_dir}: #{inspect(reason)}")
      end
    else
      :ok
    end
  end

  defp check_disk_space_if_needed(output_dir, estimated_pages, opts) do
    if opts[:max_disk_usage] do
      avg_page_size = opts[:avg_page_size] || @default_avg_page_size_kb

      FileWriter.check_disk_space(output_dir, estimated_pages,
        avg_page_size_kb: avg_page_size,
        max_disk_usage_mb: opts[:max_disk_usage]
      )
    else
      :ok
    end
  end

  defp build_crawl_opts(opts) do
    crawl_opts = []

    crawl_opts =
      if opts[:max_depth] do
        Keyword.put(crawl_opts, :max_depth, opts[:max_depth])
      else
        crawl_opts
      end

    crawl_opts =
      if opts[:max_workers] do
        Keyword.put(crawl_opts, :max_workers, opts[:max_workers])
      else
        crawl_opts
      end

    crawl_opts =
      if opts[:rate_limit] do
        Keyword.put(crawl_opts, :rate_limit, opts[:rate_limit])
      else
        crawl_opts
      end

    crawl_opts =
      if opts[:retriever] do
        retriever = parse_retriever(opts[:retriever])
        Keyword.put(crawl_opts, :retriever, retriever)
      else
        crawl_opts
      end

    crawl_opts =
      if opts[:no_robots] do
        Keyword.put(crawl_opts, :respect_robots_txt, false)
      else
        crawl_opts
      end

    # Handle include patterns (can be specified multiple times with :keep)
    include_patterns = collect_patterns(opts, :include_pattern)

    crawl_opts =
      if include_patterns != [] do
        Keyword.put(crawl_opts, :include_patterns, include_patterns)
      else
        crawl_opts
      end

    # Handle exclude patterns
    exclude_patterns = collect_patterns(opts, :exclude_pattern)

    crawl_opts =
      if exclude_patterns != [] do
        Keyword.put(crawl_opts, :exclude_patterns, exclude_patterns)
      else
        crawl_opts
      end

    crawl_opts
  end

  defp collect_patterns(opts, key) do
    opts
    |> Keyword.get_values(key)
    |> List.flatten()
  end

  defp parse_retriever("req"), do: Mulberry.Retriever.Req
  defp parse_retriever("playwright"), do: Mulberry.Retriever.Playwright
  defp parse_retriever("scraping_bee"), do: Mulberry.Retriever.ScrapingBee

  defp parse_retriever(other) do
    Mix.raise("Invalid retriever: #{other}. Must be one of: req, playwright, scraping_bee")
  end

  defp determine_verbosity(opts) do
    cond do
      opts[:quiet] -> :quiet
      opts[:verbose] -> :verbose
      opts[:verbosity] -> parse_verbosity(opts[:verbosity])
      true -> :normal
    end
  end

  defp parse_verbosity("quiet"), do: :quiet
  defp parse_verbosity("normal"), do: :normal
  defp parse_verbosity("verbose"), do: :verbose
  defp parse_verbosity("debug"), do: :debug

  defp parse_verbosity(other) do
    Mix.raise("Invalid verbosity: #{other}. Must be one of: quiet, normal, verbose, debug")
  end

  # Result handling

  defp handle_results(results, opts) do
    format = opts[:format] || "console"

    case format do
      "console" ->
        handle_console_output(results)

      "jsonl" ->
        handle_jsonl_output(results, opts[:output])

      "markdown" ->
        handle_markdown_output(results, opts)
    end
  end

  defp handle_console_output(results) do
    # Print results to console
    Mix.shell().info("\nResults:")
    Mix.shell().info(String.duplicate("-", 80))

    Enum.each(results, fn result ->
      Mix.shell().info("\nURL: #{result.url}")

      if result.title do
        Mix.shell().info("Title: #{result.title}")
      end

      if result.description do
        Mix.shell().info("Description: #{String.slice(result.description, 0, 100)}...")
      end

      Mix.shell().info("Crawled at: #{result.crawled_at}")
    end)
  end

  defp handle_jsonl_output(results, nil) do
    # No output file specified, print to console as JSON
    Enum.each(results, fn result ->
      json_line = encode_result_to_json(result)
      Mix.shell().info(json_line)
    end)
  end

  defp handle_jsonl_output(results, output_path) do
    # Open file for writing
    file = File.open!(output_path, [:write, :utf8])

    # Write each result as a separate JSON line
    Enum.each(results, fn result ->
      json_line = encode_result_to_json(result)
      IO.puts(file, json_line)
    end)

    # Close the file
    File.close(file)

    Mix.shell().info("\nResults saved as JSONL to: #{output_path}")
    Mix.shell().info("Total lines written: #{length(results)}")
  end

  defp encode_result_to_json(result) do
    %{
      url: result.url,
      title: result.title,
      description: result.description,
      content: result.content,
      meta: result.meta,
      structured_data: Map.get(result, :structured_data),
      crawled_at: DateTime.to_iso8601(result.crawled_at)
    }
    |> Jason.encode!()
  end

  defp handle_markdown_output(results, opts) do
    output_dir = opts[:output_dir]
    combine_files = opts[:combine_files] || false

    # Check disk space with actual page count
    case check_disk_space_with_results(output_dir, results, opts) do
      :ok ->
        if combine_files do
          write_combined_markdown(results, output_dir, opts)
        else
          write_individual_markdown_files(results, output_dir, opts)
        end

      {:error, :insufficient_disk_space, required_mb, available_mb} ->
        Mix.raise("""
        Insufficient disk space for export
        Required: #{required_mb} MB
        Available: #{available_mb} MB
        """)
    end
  end

  defp check_disk_space_with_results(output_dir, results, opts) do
    if opts[:max_disk_usage] do
      avg_page_size = opts[:avg_page_size] || @default_avg_page_size_kb

      MarkdownExport.check_disk_space(output_dir, length(results),
        avg_page_size_kb: avg_page_size,
        max_disk_usage_mb: opts[:max_disk_usage]
      )
    else
      :ok
    end
  end

  defp write_individual_markdown_files(results, output_dir, opts) do
    filename_pattern = opts[:filename_pattern] || "url"
    add_metadata = !opts[:no_metadata]
    overwrite_policy = determine_overwrite_policy(opts)
    show_progress = opts[:progress] || false

    # Use parallel writes for better performance
    progress_fn =
      if show_progress do
        fn index, total ->
          Mix.shell().info("Progress: #{index}/#{total} (#{round(index / total * 100)}%)")
        end
      else
        nil
      end

    {:ok, stats} =
      MarkdownExport.export_individual(results, output_dir,
        filename_pattern: filename_pattern,
        add_metadata: add_metadata,
        overwrite_policy: overwrite_policy,
        parallel: true,
        on_progress: progress_fn
      )

    Mix.shell().info("\nMarkdown files saved to: #{output_dir}")

    Mix.shell().info(
      "Written: #{stats.written}, Skipped: #{stats.skipped}, Errors: #{stats.errors}"
    )
  end

  defp write_combined_markdown(results, output_dir, opts) do
    combined_filename = opts[:combined_filename] || "combined"
    add_metadata = !opts[:no_metadata]

    case MarkdownExport.export_combined(results, output_dir,
           combined_filename: combined_filename,
           add_metadata: add_metadata
         ) do
      {:ok, filepath} ->
        Mix.shell().info("\nCombined markdown saved to: #{filepath}")
        Mix.shell().info("Total pages included: #{length(results)}")

      {:error, reason} ->
        Mix.raise("Failed to write combined markdown: #{inspect(reason)}")
    end
  end

  defp determine_overwrite_policy(opts) do
    cond do
      opts[:overwrite] -> :overwrite
      opts[:skip_existing] || opts[:resume] -> :skip
      opts[:error_on_exists] -> :error
      true -> :increment
    end
  end
end
