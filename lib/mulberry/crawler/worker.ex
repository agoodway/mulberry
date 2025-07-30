defmodule Mulberry.Crawler.Worker do
  @moduledoc """
  GenServer that performs the actual crawling of individual URLs.

  Each worker is responsible for:
  - Fetching a URL using Mulberry.Retriever
  - Loading and processing the document
  - Extracting data using the crawler behaviour callbacks
  - Extracting new URLs to crawl
  - Reporting results back to the orchestrator
  """

  use GenServer
  require Logger

  alias Mulberry.Crawler.URLManager
  alias Mulberry.Document
  alias Mulberry.Document.WebPage

  defmodule State do
    @moduledoc false
    @type t :: %__MODULE__{
      orchestrator: pid(),
      crawler_impl: module(),
      retriever: module() | [module()],
      options: keyword()
    }
    
    defstruct [:orchestrator, :crawler_impl, :retriever, :options]
  end

  # Client API

  @doc """
  Starts a crawler worker linked to the calling process.

  ## Options
    - `:orchestrator` - PID of the orchestrator GenServer (required)
    - `:crawler_impl` - Module implementing Mulberry.Crawler.Behaviour (required)
    - `:retriever` - Retriever module(s) to use (default: Mulberry.Retriever.Req)
    - Additional options passed to retriever and crawler callbacks
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Instructs the worker to crawl a specific URL.

  The worker will fetch the URL, process it, and report results back to the orchestrator.
  """
  @spec crawl(pid(), String.t(), map()) :: :ok
  def crawl(worker, url, context) do
    GenServer.cast(worker, {:crawl, url, context})
  end

  # Server callbacks

  @impl true
  def init(opts) do
    orchestrator = Keyword.fetch!(opts, :orchestrator)
    crawler_impl = Keyword.fetch!(opts, :crawler_impl)
    retriever = Keyword.get(opts, :retriever, Mulberry.Retriever.Req)

    state = %State{
      orchestrator: orchestrator,
      crawler_impl: crawler_impl,
      retriever: retriever,
      options: Keyword.drop(opts, [:orchestrator, :crawler_impl, :retriever])
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:crawl, url, context}, state) do
    Logger.debug("Worker starting crawl of #{url}")

    result = do_crawl(url, context, state)
    
    # Invoke success/failure callbacks
    case result do
      {:ok, _} = success ->
        invoke_callback(:on_url_success, [url, elem(success, 1), context], state)
      {:error, reason} ->
        invoke_callback(:on_url_failure, [url, reason, context], state)
    end
    
    send(state.orchestrator, {:crawl_result, self(), url, result})

    {:noreply, state}
  end

  # Private functions

  defp do_crawl(url, _context, state) do
    with {:ok, normalized_url} <- URLManager.normalize_url(url),
         {:ok, document} <- fetch_document(normalized_url, state),
         {:ok, data} <- extract_data(document, normalized_url, state),
         {:ok, urls} <- extract_urls(document, normalized_url, state) do
      {:ok, %{data: data, urls: urls}}
    else
      {:error, reason} = error ->
        Logger.warning("Failed to crawl #{url}: #{inspect(reason)}")
        error
    end
  end

  defp fetch_document(url, state) do
    web_page = WebPage.new(%{url: url})

    case Document.load(web_page, retriever: state.retriever) do
      {:ok, loaded_page} ->
        {:ok, loaded_page}

      {:error, reason, _page} ->
        {:error, {:fetch_failed, reason}}

      {:error, reason} ->
        {:error, {:fetch_failed, reason}}
    end
  end

  defp extract_data(document, url, state) do
    try do
      state.crawler_impl.extract_data(document, url)
    rescue
      error ->
        Logger.error("Error in extract_data callback: #{inspect(error)}")
        {:error, {:extract_data_failed, error}}
    end
  end

  defp extract_urls(document, url, state) do
    try do
      case state.crawler_impl.extract_urls(document, url) do
        {:ok, urls} ->
          normalized_urls =
            urls
            |> Enum.map(fn u ->
              case URLManager.resolve_url(u, url) do
                {:ok, resolved} -> resolved
                _ -> nil
              end
            end)
            |> Enum.reject(&is_nil/1)
            |> Enum.uniq()

          {:ok, normalized_urls}

        error ->
          error
      end
    rescue
      error ->
        Logger.error("Error in extract_urls callback: #{inspect(error)}")
        {:error, {:extract_urls_failed, error}}
    end
  end

  defp invoke_callback(callback_name, args, state) do
    if function_exported?(state.crawler_impl, callback_name, length(args)) do
      try do
        apply(state.crawler_impl, callback_name, args)
      rescue
        error ->
          Logger.error("Error in #{callback_name} callback: #{inspect(error)}")
          {:error, error}
      end
    else
      :ok
    end
  end
end