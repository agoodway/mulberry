defmodule Mix.Tasks.Crawl do
  @moduledoc """
  Crawls websites or lists of URLs using Mulberry's crawler.

  This task provides command-line access to Mulberry's web crawling functionality,
  supporting both URL list crawling and full website crawling modes.

  ## Usage

  ### Crawl a single website:
      mix crawl --url https://example.com

  ### Crawl with custom depth:
      mix crawl --url https://example.com --max-depth 5

  ### Crawl a list of URLs from a file:
      mix crawl --urls urls.txt

  ### Crawl with custom settings:
      mix crawl --url https://example.com --max-workers 10 --rate-limit 5

  ### Save results to a file:
      mix crawl --url https://example.com --output results.jsonl

  ## Options

    * `--url` - URL to start crawling from (for website mode)
    * `--urls` - Path to file containing URLs to crawl (one per line)
    * `--max-depth` - Maximum crawl depth for website mode (default: 3)
    * `--max-workers` - Maximum concurrent workers (default: 5)
    * `--rate-limit` - Requests per second per domain (default: 1.0)
    * `--output` - Path to save results as JSONL (default: print to console)
    * `--retriever` - Retriever to use: req, playwright, or scraping_bee (default: req)
    * `--verbose` - Enable verbose logging

  ## Examples

      # Crawl a website and save results
      mix crawl --url https://elixir-lang.org --max-depth 2 --output elixir-docs.jsonl

      # Crawl specific URLs from a file
      echo "https://example.com/page1" > urls.txt
      echo "https://example.com/page2" >> urls.txt
      mix crawl --urls urls.txt --max-workers 10

      # Crawl with Playwright for JavaScript-heavy sites
      mix crawl --url https://spa-example.com --retriever playwright
  """

  use Mix.Task
  require Logger

  @shortdoc "Crawls websites or lists of URLs"

  @impl Mix.Task
  def run(args) do
    # Start the application
    Mix.Task.run("app.start")

    # Parse arguments
    {opts, _args, invalid} = OptionParser.parse(args,
      strict: [
        url: :string,
        urls: :string,
        max_depth: :integer,
        max_workers: :integer,
        rate_limit: :float,
        output: :string,
        retriever: :string,
        verbose: :boolean
      ],
      aliases: [
        d: :max_depth,
        w: :max_workers,
        r: :rate_limit,
        o: :output,
        v: :verbose
      ]
    )

    # Handle invalid options
    if invalid != [] do
      Mix.raise("Invalid options: #{inspect(invalid)}")
    end

    # Configure logging
    if opts[:verbose] do
      Logger.configure(level: :debug)
    end

    # Determine crawl mode and execute
    cond do
      opts[:url] && opts[:urls] ->
        Mix.raise("Cannot specify both --url and --urls options")

      opts[:url] ->
        crawl_website(opts[:url], opts)

      opts[:urls] ->
        crawl_urls_from_file(opts[:urls], opts)

      true ->
        Mix.raise("Must specify either --url or --urls option")
    end
  end

  defp crawl_website(url, opts) do
    Mix.shell().info("Starting website crawl from: #{url}")

    crawl_opts = build_crawl_opts(opts)
    start_time = System.monotonic_time(:millisecond)

    case Mulberry.Crawler.crawl_website(url, crawl_opts) do
      {:ok, results} ->
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time

        Mix.shell().info("\nCrawl completed in #{duration}ms")
        Mix.shell().info("Total pages crawled: #{length(results)}")

        handle_results(results, opts[:output])

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

    crawl_opts = build_crawl_opts(opts)
    start_time = System.monotonic_time(:millisecond)

    case Mulberry.Crawler.crawl_urls(urls, crawl_opts) do
      {:ok, results} ->
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time

        Mix.shell().info("\nCrawl completed in #{duration}ms")
        Mix.shell().info("Total pages crawled: #{length(results)}")

        handle_results(results, opts[:output])

      {:error, reason} ->
        Mix.raise("Crawl failed: #{inspect(reason)}")
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

    crawl_opts
  end

  defp parse_retriever("req"), do: Mulberry.Retriever.Req
  defp parse_retriever("playwright"), do: Mulberry.Retriever.Playwright
  defp parse_retriever("scraping_bee"), do: Mulberry.Retriever.ScrapingBee
  defp parse_retriever(other) do
    Mix.raise("Invalid retriever: #{other}. Must be one of: req, playwright, scraping_bee")
  end

  defp handle_results(results, nil) do
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

  defp handle_results(results, output_path) do
    # Open file for writing
    file = File.open!(output_path, [:write, :utf8])

    # Write each result as a separate JSON line
    results
    |> Enum.each(fn result ->
      json_line = 
        %{
          url: result.url,
          title: result.title,
          description: result.description,
          content: result.content,
          meta: result.meta,
          crawled_at: DateTime.to_iso8601(result.crawled_at)
        }
        |> Jason.encode!()
      
      IO.puts(file, json_line)
    end)

    # Close the file
    File.close(file)

    Mix.shell().info("\nResults saved as JSONL to: #{output_path}")
    Mix.shell().info("Total lines written: #{length(results)}")
  end
end