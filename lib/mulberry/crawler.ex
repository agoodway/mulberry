defmodule Mulberry.Crawler do
  @moduledoc """
  Public API for the Mulberry web crawler.

  This module provides a simple interface for crawling websites and URL lists.
  The crawler supports:
  - Concurrent crawling with configurable worker pools
  - Rate limiting per domain
  - Custom data extraction via behaviours
  - Two crawling modes: URL list and website crawling

  ## Examples

      # Crawl a list of specific URLs
      {:ok, results} = Mulberry.Crawler.crawl_urls(
        ["https://example.com/page1", "https://example.com/page2"],
        max_workers: 5,
        rate_limit: 10
      )

      # Crawl an entire website
      {:ok, results} = Mulberry.Crawler.crawl_website(
        "https://example.com",
        max_depth: 3,
        max_workers: 10
      )

      # Use a custom crawler implementation
      defmodule MyCrawler do
        @behaviour Mulberry.Crawler.Behaviour
        # ... implement callbacks
      end

      {:ok, results} = Mulberry.Crawler.crawl_website(
        "https://example.com",
        crawler_impl: MyCrawler
      )
  """

  alias Mulberry.Crawler.{Supervisor, Orchestrator}

  @type crawl_result :: %{
          url: String.t(),
          title: String.t() | nil,
          description: String.t() | nil,
          content: String.t() | nil,
          meta: map(),
          crawled_at: DateTime.t()
        }

  @type crawl_stats :: %{
          urls_crawled: non_neg_integer(),
          urls_failed: non_neg_integer(),
          start_time: integer(),
          end_time: integer() | nil,
          duration_ms: integer() | nil
        }

  @doc """
  Crawls a list of specific URLs.

  This function will crawl only the provided URLs without following any links.

  ## Options
    - `:crawler_impl` - Module implementing Mulberry.Crawler.Behaviour (default: Mulberry.Crawler.Default)
    - `:max_workers` - Maximum concurrent workers (default: 5)
    - `:retriever` - Retriever module(s) to use (default: Mulberry.Retriever.Req)
    - `:timeout` - Timeout for the entire crawl operation in milliseconds (default: :infinity)
    - `:rate_limit` - Requests per second per domain (default: 1.0)
    - `:async` - If true, returns immediately with orchestrator PID (default: false)

  ## Returns
    - `{:ok, results}` - List of crawl results
    - `{:ok, orchestrator_pid}` - If async is true
    - `{:error, reason}` - If crawling fails

  ## Examples

      # Basic usage
      {:ok, results} = Mulberry.Crawler.crawl_urls([
        "https://example.com/page1",
        "https://example.com/page2"
      ])

      # With options
      {:ok, results} = Mulberry.Crawler.crawl_urls(
        urls,
        max_workers: 10,
        rate_limit: 5.0,
        timeout: 60_000
      )

      # Async mode
      {:ok, orchestrator} = Mulberry.Crawler.crawl_urls(urls, async: true)
      # ... do other work ...
      {:ok, results} = Mulberry.Crawler.Orchestrator.await_completion(orchestrator)
  """
  @spec crawl_urls([String.t()], keyword()) :: {:ok, [crawl_result()]} | {:ok, pid()} | {:error, any()}
  def crawl_urls(urls, opts \\ []) when is_list(urls) do
    # Ensure supervisor is started
    ensure_supervisor_started(opts)
    
    # Set mode to url_list
    opts = Keyword.put(opts, :mode, :url_list)
    
    # Extract async option
    {async, opts} = Keyword.pop(opts, :async, false)
    {timeout, opts} = Keyword.pop(opts, :timeout, :infinity)
    
    # Set default crawler implementation
    opts = Keyword.put_new(opts, :crawler_impl, Mulberry.Crawler.Default)
    
    # Configure rate limiter if needed
    configure_rate_limiter(opts)
    
    # Start orchestrator
    case Supervisor.start_crawler(opts) do
      {:ok, orchestrator} ->
        # Start crawling
        Orchestrator.crawl_urls(orchestrator, urls)
        
        if async do
          {:ok, orchestrator}
        else
          Orchestrator.await_completion(orchestrator, timeout)
        end
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Crawls a website starting from the given URL.

  This function will crawl the starting URL and follow links within the same domain
  up to the specified depth.

  ## Options
    - `:crawler_impl` - Module implementing Mulberry.Crawler.Behaviour (default: Mulberry.Crawler.Default)
    - `:max_depth` - Maximum crawl depth (default: 3)
    - `:max_workers` - Maximum concurrent workers (default: 5)
    - `:retriever` - Retriever module(s) to use (default: Mulberry.Retriever.Req)
    - `:timeout` - Timeout for the entire crawl operation in milliseconds (default: :infinity)
    - `:rate_limit` - Requests per second per domain (default: 1.0)
    - `:async` - If true, returns immediately with orchestrator PID (default: false)

  ## Returns
    - `{:ok, results}` - List of crawl results
    - `{:ok, orchestrator_pid}` - If async is true
    - `{:error, reason}` - If crawling fails

  ## Examples

      # Basic usage
      {:ok, results} = Mulberry.Crawler.crawl_website("https://example.com")

      # With options
      {:ok, results} = Mulberry.Crawler.crawl_website(
        "https://example.com",
        max_depth: 5,
        max_workers: 20,
        rate_limit: 10.0
      )

      # Custom crawler implementation
      {:ok, results} = Mulberry.Crawler.crawl_website(
        "https://example.com",
        crawler_impl: MyCustomCrawler,
        max_depth: 2
      )
  """
  @spec crawl_website(String.t(), keyword()) :: {:ok, [crawl_result()]} | {:ok, pid()} | {:error, any()}
  def crawl_website(start_url, opts \\ []) when is_binary(start_url) do
    # Ensure supervisor is started
    ensure_supervisor_started(opts)
    
    # Set mode to website
    opts = Keyword.put(opts, :mode, :website)
    
    # Extract async option
    {async, opts} = Keyword.pop(opts, :async, false)
    {timeout, opts} = Keyword.pop(opts, :timeout, :infinity)
    
    # Set default crawler implementation
    opts = Keyword.put_new(opts, :crawler_impl, Mulberry.Crawler.Default)
    
    # Configure rate limiter if needed
    configure_rate_limiter(opts)
    
    # Start orchestrator
    case Supervisor.start_crawler(opts) do
      {:ok, orchestrator} ->
        # Start crawling
        Orchestrator.crawl_website(orchestrator, start_url)
        
        if async do
          {:ok, orchestrator}
        else
          Orchestrator.await_completion(orchestrator, timeout)
        end
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets the current statistics for an active crawl.

  ## Parameters
    - `orchestrator` - PID of the orchestrator returned from async crawl

  ## Returns
    Map containing crawl statistics including:
    - `:urls_crawled` - Number of successfully crawled URLs
    - `:urls_failed` - Number of failed URLs
    - `:queue_size` - Current size of the URL queue
    - `:active_workers` - Number of active workers
    - `:visited_urls` - Total number of visited URLs
    - `:results_count` - Number of results collected

  ## Example

      {:ok, orchestrator} = Mulberry.Crawler.crawl_website(url, async: true)
      stats = Mulberry.Crawler.get_stats(orchestrator)
      IO.inspect(stats)
      # %{urls_crawled: 10, urls_failed: 2, queue_size: 5, ...}
  """
  @spec get_stats(pid()) :: crawl_stats()
  def get_stats(orchestrator) when is_pid(orchestrator) do
    Orchestrator.get_stats(orchestrator)
  end

  # Private functions

  defp ensure_supervisor_started(opts) do
    case Process.whereis(Mulberry.Crawler.Supervisor) do
      nil ->
        rate_limiter_opts = build_rate_limiter_opts(opts)
        {:ok, _} = Mulberry.Crawler.Supervisor.start_link(rate_limiter_opts: rate_limiter_opts)
        
      _pid ->
        :ok
    end
  end

  defp configure_rate_limiter(_opts) do
    # Rate limiter is configured when supervisor starts
    :ok
  end

  defp build_rate_limiter_opts(opts) do
    rate_limit = Keyword.get(opts, :rate_limit, 1.0)
    
    [
      default_max_tokens: 10,
      default_refill_rate: rate_limit
    ]
  end
end