defmodule Mulberry.Crawler.Orchestrator do
  @moduledoc """
  GenServer that orchestrates the crawling process.

  The orchestrator manages:
  - URL queue and visited tracking
  - Worker pool management
  - Rate limiting coordination
  - Crawl progress and statistics
  - Result collection and callbacks
  """

  use GenServer
  require Logger

  alias Mulberry.Crawler.{RateLimiter, RobotsTxt, Stats, URLManager, Worker}

  defmodule State do
    @moduledoc false
    @type t :: %__MODULE__{
      crawler_impl: module(),
      supervisor: pid(),
      mode: :url_list | :website,
      start_url: String.t() | nil,
      max_depth: non_neg_integer(),
      max_workers: non_neg_integer(),
      retriever: module() | [module()],
      respect_robots_txt: boolean(),
      include_patterns: [Regex.t()],
      exclude_patterns: [Regex.t()],
      options: keyword(),
      url_queue: :queue.queue(),
      visited_urls: MapSet.t(),
      active_workers: map(),
      results: list(),
      stats: Stats.t(),
      waiting_callers: [GenServer.from()]
    }

    defstruct [
      :crawler_impl,
      :supervisor,
      :mode,
      :start_url,
      :max_depth,
      :max_workers,
      :retriever,
      :options,
      :stats,
      respect_robots_txt: true,
      include_patterns: [],
      exclude_patterns: [],
      url_queue: :queue.new(),
      visited_urls: MapSet.new(),
      active_workers: %{},
      results: [],
      waiting_callers: []
    ]
  end

  # Client API

  @doc """
  Starts the crawler orchestrator.

  ## Options
    - `:crawler_impl` - Module implementing Mulberry.Crawler.Behaviour (required)
    - `:supervisor` - PID of the crawler supervisor (required)
    - `:mode` - Either `:url_list` or `:website` (required)
    - `:max_workers` - Maximum concurrent workers (default: 5)
    - `:max_depth` - Maximum crawl depth for website mode (default: 3)
    - `:retriever` - Retriever module(s) to use (default: Mulberry.Retriever.Req)
    - `:respect_robots_txt` - Whether to check robots.txt before crawling (default: true)
    - `:include_patterns` - List of regex pattern strings. URLs must match at least one pattern to be crawled.
    - `:exclude_patterns` - List of regex pattern strings. URLs matching any pattern will be skipped.
    - Additional options passed to workers and callbacks
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Starts crawling a list of URLs.
  """
  @spec crawl_urls(pid(), [String.t()]) :: :ok
  def crawl_urls(orchestrator, urls) do
    GenServer.cast(orchestrator, {:crawl_urls, urls})
  end

  @doc """
  Starts crawling a website from the given URL.
  """
  @spec crawl_website(pid(), String.t()) :: :ok
  def crawl_website(orchestrator, start_url) do
    GenServer.cast(orchestrator, {:crawl_website, start_url})
  end

  @doc """
  Gets the current crawl statistics.
  """
  @spec get_stats(pid()) :: map()
  def get_stats(orchestrator) do
    GenServer.call(orchestrator, :get_stats)
  end

  @doc """
  Waits for the crawl to complete and returns the results.
  """
  @spec await_completion(pid(), timeout()) :: {:ok, [map()]} | {:error, :timeout}
  def await_completion(orchestrator, timeout \\ :infinity) do
    GenServer.call(orchestrator, :await_completion, timeout)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    crawler_impl = Keyword.fetch!(opts, :crawler_impl)
    supervisor = Keyword.fetch!(opts, :supervisor)
    mode = Keyword.fetch!(opts, :mode)

    # Compile URL patterns
    include_patterns = compile_url_patterns(Keyword.get(opts, :include_patterns, []))
    exclude_patterns = compile_url_patterns(Keyword.get(opts, :exclude_patterns, []))

    state = %State{
      crawler_impl: crawler_impl,
      supervisor: supervisor,
      mode: mode,
      max_workers: Keyword.get(opts, :max_workers, 5),
      max_depth: Keyword.get(opts, :max_depth, 3),
      retriever: Keyword.get(opts, :retriever, Mulberry.Retriever.Req),
      respect_robots_txt: Keyword.get(opts, :respect_robots_txt, true),
      include_patterns: include_patterns,
      exclude_patterns: exclude_patterns,
      stats: Stats.new(),
      options:
        Keyword.drop(opts, [
          :crawler_impl,
          :supervisor,
          :mode,
          :max_workers,
          :max_depth,
          :retriever,
          :respect_robots_txt,
          :include_patterns,
          :exclude_patterns
        ])
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:crawl_urls, urls}, state) do
    Logger.info("Starting URL list crawl with #{length(urls)} URLs")

    state = %{state | stats: Stats.start(state.stats)}

    # Add URLs to queue
    state = Enum.reduce(urls, state, fn url, acc ->
      add_url_to_queue(url, acc, 0)
    end)

    # Start crawling
    state = spawn_workers(state)

    {:noreply, state}
  end

  @impl true
  def handle_cast({:crawl_website, start_url}, state) do
    Logger.info("Starting website crawl from #{start_url}")

    state = %{state | start_url: start_url, stats: Stats.start(state.stats)}

    # Add start URL to queue
    state = add_url_to_queue(start_url, state, 0)

    # Start crawling
    state = spawn_workers(state)

    {:noreply, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats =
      state.stats
      |> Stats.to_map()
      |> Map.merge(%{
        queue_size: :queue.len(state.url_queue),
        active_workers: map_size(state.active_workers),
        visited_urls: MapSet.size(state.visited_urls),
        results_count: length(state.results)
      })

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:await_completion, from, state) do
    if crawl_complete?(state) do
      {:reply, {:ok, state.results}, state}
    else
      # Store the caller to reply when complete
      state = %{state | waiting_callers: [from | state.waiting_callers]}
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:crawl_result, worker_pid, url, result}, state) do
    # Get worker info before removing
    worker_info = Map.get(state.active_workers, worker_pid, %{depth: 0})

    # Remove worker from active workers
    state = %{state | active_workers: Map.delete(state.active_workers, worker_pid)}

    # Extract domain for stats
    domain = extract_domain_for_stats(url)

    # Process the result
    state =
      case result do
        {:ok, %{data: data, urls: urls, status_code: status_code, response_time_ms: response_time}} ->
          Logger.debug("Successfully crawled #{url}")

          # Update stats with detailed info
          stats = Stats.record_success(state.stats, domain, status_code, response_time)
          stats = Stats.record_discovered(stats, length(urls))

          # Add result
          state = %{state | results: [data | state.results], stats: stats}

          # Add discovered URLs if in website mode
          maybe_add_discovered_urls(state, urls, worker_info[:depth] || 0)

        {:ok, %{data: data, urls: urls}} ->
          # Fallback for workers that don't report status_code/response_time
          Logger.debug("Successfully crawled #{url}")

          stats = Stats.record_success(state.stats, domain, 200, 0)
          stats = Stats.record_discovered(stats, length(urls))

          state = %{state | results: [data | state.results], stats: stats}
          maybe_add_discovered_urls(state, urls, worker_info[:depth] || 0)

        {:error, reason} ->
          Logger.warning("Failed to crawl #{url}: #{inspect(reason)}")
          category = Stats.categorize_error(reason)
          stats = Stats.record_failure(state.stats, domain, category, reason)
          %{state | stats: stats}
      end

    # Check if crawl is complete
    state =
      if crawl_complete?(state) do
        finalize_crawl(state)
      else
        # Spawn more workers if needed
        spawn_workers(state)
      end

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, worker_pid, reason}, state) do
    Logger.warning("Worker #{inspect(worker_pid)} died: #{inspect(reason)}")
    
    # Remove worker from active workers
    state = %{state | active_workers: Map.delete(state.active_workers, worker_pid)}
    
    # Spawn a new worker if needed
    state = spawn_workers(state)
    
    {:noreply, state}
  end

  @impl true
  def handle_info(:retry_spawn, state) do
    # Try to spawn more workers after rate limit delay
    state = spawn_workers(state)
    {:noreply, state}
  end

  # Private functions

  defp add_url_to_queue(url, state, depth) do
    with {:ok, normalized_url} <- URLManager.normalize_url(url),
         false <- MapSet.member?(state.visited_urls, normalized_url),
         true <- should_crawl_url?(normalized_url, state, depth),
         true <- robots_txt_allowed?(normalized_url, state) do
      %{
        state
        | url_queue: :queue.in({normalized_url, depth}, state.url_queue),
          visited_urls: MapSet.put(state.visited_urls, normalized_url)
      }
    else
      :robots_blocked ->
        Logger.debug("URL blocked by robots.txt: #{url}")
        stats = Stats.record_robots_blocked(state.stats, 1)
        %{state | stats: stats}

      :filtered ->
        stats = Stats.record_filtered(state.stats, 1)
        %{state | stats: stats}

      _ ->
        state
    end
  end

  defp robots_txt_allowed?(url, state) do
    if state.respect_robots_txt do
      case RobotsTxt.allowed?(url) do
        {:ok, true} -> true
        {:ok, false} -> :robots_blocked
        {:error, _} -> true
      end
    else
      true
    end
  end

  defp should_crawl_url?(url, state, depth) do
    context = %{
      start_url: state.start_url || "",
      max_depth: state.max_depth,
      current_depth: depth,
      visited_urls: state.visited_urls,
      mode: state.mode,
      options: state.options
    }

    # Check depth limit, URL patterns, and crawler filter
    cond do
      depth > state.max_depth ->
        :filtered

      not passes_url_patterns?(url, state) ->
        :filtered

      not state.crawler_impl.should_crawl?(url, context) ->
        :filtered

      true ->
        true
    end
  end

  defp passes_url_patterns?(url, state) do
    # If include_patterns is not empty, URL must match at least one
    include_passes =
      if state.include_patterns == [] do
        true
      else
        URLManager.matches_patterns?(url, state.include_patterns)
      end

    # URL must not match any exclude pattern
    exclude_passes = not URLManager.matches_patterns?(url, state.exclude_patterns)

    include_passes && exclude_passes
  end

  defp filter_urls_for_crawling(urls, state, current_depth) do
    urls
    |> Enum.filter(fn url ->
      with {:ok, normalized} <- URLManager.normalize_url(url),
           false <- MapSet.member?(state.visited_urls, normalized),
           true <- should_crawl_url?(normalized, state, current_depth + 1) do
        true
      else
        _ -> false
      end
    end)
  end

  defp spawn_workers(state) do
    active_count = map_size(state.active_workers)
    needed = min(
      state.max_workers - active_count,
      :queue.len(state.url_queue)
    )
    
    if needed > 0 do
      Enum.reduce(1..needed, state, fn _, acc ->
        spawn_worker(acc)
      end)
    else
      state
    end
  end

  defp spawn_worker(state) do
    case :queue.out(state.url_queue) do
      {{:value, {url, depth}}, new_queue} ->
        # Get domain for rate limiting
        {:ok, domain} = URLManager.extract_domain(url)
        
        # Wait for rate limit
        case RateLimiter.consume_token(domain) do
          :ok ->
            # Spawn worker
            {:ok, worker_pid} = DynamicSupervisor.start_child(
              state.supervisor,
              {Worker, [
                orchestrator: self(),
                crawler_impl: state.crawler_impl,
                retriever: state.retriever
              ] ++ state.options}
            )
            
            # Monitor the worker
            Process.monitor(worker_pid)
            
            # Create crawl context
            context = %{
              start_url: state.start_url || url,
              max_depth: state.max_depth,
              current_depth: depth,
              visited_urls: state.visited_urls,
              mode: state.mode,
              options: state.options
            }
            
            # Start crawling
            Worker.crawl(worker_pid, url, context)
            
            %{state | 
              url_queue: new_queue,
              active_workers: Map.put(state.active_workers, worker_pid, %{url: url, depth: depth})
            }
            
          {:error, :rate_limited} ->
            # Put URL back in queue and wait
            Process.send_after(self(), :retry_spawn, 100)
            state
        end
        
      {:empty, _} ->
        state
    end
  end

  defp crawl_complete?(state) do
    :queue.is_empty(state.url_queue) && map_size(state.active_workers) == 0
  end

  defp maybe_add_discovered_urls(state, urls, current_depth) do
    if state.mode == :website do
      urls
      |> filter_urls_for_crawling(state, current_depth)
      |> Enum.reduce(state, fn url, acc ->
        add_url_to_queue(url, acc, current_depth + 1)
      end)
    else
      state
    end
  end

  defp finalize_crawl(state) do
    # Finalize stats
    stats = Stats.finalize(state.stats)
    state = %{state | stats: stats}

    Logger.info("Crawl complete. Crawled #{stats.urls_crawled} URLs")
    Logger.info(Stats.format_summary(stats))

    # Call on_complete callback if defined
    if function_exported?(state.crawler_impl, :on_complete, 1) do
      case state.crawler_impl.on_complete(state.results) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.error("on_complete callback failed: #{inspect(reason)}")
      end
    end

    # Reply to any waiting callers
    Enum.each(state.waiting_callers, fn from ->
      GenServer.reply(from, {:ok, state.results})
    end)

    %{state | waiting_callers: []}
  end

  defp extract_domain_for_stats(url) do
    case URLManager.extract_domain(url) do
      {:ok, domain} -> domain
      _ -> "unknown"
    end
  end

  defp compile_url_patterns(patterns) when is_list(patterns) do
    case URLManager.compile_patterns(patterns) do
      {:ok, compiled} ->
        compiled

      {:error, {:invalid_pattern, pattern, _}} ->
        Logger.warning("Invalid URL pattern '#{pattern}', ignoring")
        []
    end
  end

  defp compile_url_patterns(_), do: []
end