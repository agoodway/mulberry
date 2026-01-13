defmodule Mulberry.Crawler.Behaviour do
  @moduledoc """
  Defines the behaviour for implementing custom web crawlers.

  This behaviour allows you to customize how URLs are filtered, what data is extracted,
  and how the crawler discovers new URLs to follow.

  ## Example Implementation

      defmodule MyCrawler do
        @behaviour Mulberry.Crawler.Behaviour

        @impl true
        def should_crawl?(url, context) do
          # Only crawl URLs from the same domain
          URI.parse(url).host == URI.parse(context.start_url).host
        end

        @impl true
        def extract_data(document, url) do
          {:ok, %{
            url: url,
            title: document.title,
            description: document.description,
            custom_field: extract_custom_field(document)
          }}
        end

        @impl true
        def extract_urls(document, base_url) do
          # Extract all links from the page
          {:ok, Mulberry.Crawler.Default.extract_urls(document, base_url)}
        end

        @impl true
        def on_url_success(url, result, _context) do
          IO.puts("✓ \#{url}")
          :ok
        end

        @impl true
        def on_url_failure(url, reason, _context) do
          IO.puts("✗ \#{url}: \#{inspect(reason)}")
          :ok
        end

        @impl true
        def on_complete(results) do
          # Process the crawled results
          IO.puts("Crawled \#{length(results)} pages")
          :ok
        end
      end
  """

  alias Mulberry.Document.WebPage

  @type url :: String.t()
  @type crawl_context :: %{
          start_url: url(),
          max_depth: non_neg_integer(),
          current_depth: non_neg_integer(),
          visited_urls: MapSet.t(url()),
          mode: :url_list | :website,
          options: keyword()
        }
  @type crawl_result :: map()

  @doc """
  Determines whether a URL should be crawled.

  This callback is called for each discovered URL to decide if it should be added
  to the crawl queue. You can implement custom logic based on the URL pattern,
  domain, path, or any other criteria.

  ## Parameters
    - `url` - The URL to evaluate
    - `context` - The current crawl context containing metadata about the crawl

  ## Returns
    - `true` if the URL should be crawled
    - `false` if the URL should be skipped
  """
  @callback should_crawl?(url(), crawl_context()) :: boolean()

  @doc """
  Extracts data from a crawled document.

  This callback is called after a page has been successfully fetched and loaded.
  You can extract any data you need from the document and return it as a map.

  ## Parameters
    - `document` - The loaded WebPage document
    - `url` - The URL of the document

  ## Returns
    - `{:ok, data}` where `data` is a map containing the extracted information
    - `{:error, reason}` if data extraction fails
  """
  @callback extract_data(WebPage.t(), url()) :: {:ok, map()} | {:error, any()}

  @doc """
  Extracts URLs from a document for further crawling.

  This callback is called to discover new URLs to add to the crawl queue.
  You can implement custom logic to filter or transform the URLs before
  they are added to the queue.

  ## Parameters
    - `document` - The loaded WebPage document
    - `base_url` - The base URL for resolving relative links

  ## Returns
    - `{:ok, urls}` where `urls` is a list of absolute URLs to crawl
    - `{:error, reason}` if URL extraction fails
  """
  @callback extract_urls(WebPage.t(), url()) :: {:ok, [url()]} | {:error, any()}

  @doc """
  Called when a URL is successfully crawled.

  This callback is invoked immediately after a URL has been successfully processed,
  including document fetching, data extraction, and URL discovery. It allows for
  real-time monitoring, progress tracking, and custom success handling.

  ## Parameters
    - `url` - The URL that was successfully crawled
    - `result` - The successful result containing extracted data and discovered URLs
    - `context` - The current crawl context

  ## Returns
    - `:ok` on success
    - `{:error, reason}` if the callback fails (this won't affect the crawl)

  ## Example

      @impl true
      def on_url_success(url, result, _context) do
        IO.puts("Successfully crawled: \#{url}")
        Logger.info("Extracted \#{length(result.urls)} URLs from \#{url}")
        :ok
      end
  """
  @callback on_url_success(url(), map(), crawl_context()) :: :ok | {:error, any()}

  @doc """
  Called when a URL fails to be crawled.

  This callback is invoked when any step of crawling a URL fails, including
  fetch failures, data extraction errors, or URL discovery problems. It enables
  custom error handling, retry logic, and failure monitoring.

  ## Parameters
    - `url` - The URL that failed to crawl
    - `reason` - The error reason (e.g., `{:fetch_failed, :timeout}`)
    - `context` - The current crawl context

  ## Returns
    - `:ok` on success
    - `{:error, reason}` if the callback fails (this won't affect the crawl)

  ## Example

      @impl true
      def on_url_failure(url, reason, _context) do
        Logger.warning("Failed to crawl \#{url}: \#{inspect(reason)}")
        # Could implement retry logic, send alerts, etc.
        :ok
      end
  """
  @callback on_url_failure(url(), any(), crawl_context()) :: :ok | {:error, any()}

  @doc """
  Called when the crawling process is complete.

  This callback receives all the crawled results and can be used for
  post-processing, saving data, or cleanup operations.

  ## Parameters
    - `results` - List of all crawl results (maps returned by `extract_data/2`)

  ## Returns
    - `:ok` on success
    - `{:error, reason}` if post-processing fails
  """
  @callback on_complete([crawl_result()]) :: :ok | {:error, any()}

  @optional_callbacks on_complete: 1, on_url_success: 3, on_url_failure: 3
end
