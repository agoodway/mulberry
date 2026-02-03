# Mulberry Code Review Recommendations

Generated: January 12, 2026
Review Scope: Crawler system, document processing, HTTP retrieval, and DataForSEO integration

## Summary

| Severity | Count | Key Areas |
|----------|--------|-----------|
| 🔴 Critical | 3 | SSRF, Unbounded recursion, Memory leaks |
| 🟠 High | 5 | Auth validation, Timeouts, Race conditions, Pattern limits |
| 🟡 Medium | 4 | Mix config, Code style, Error handling |
| 🟢 Low/Suggestions | 3 | Documentation, Telemetry |

**Total Issues Found**: 15

---

## 🔴 Critical Issues

### 1. SSRF Vulnerability in RobotsTxt URL Construction

**File**: `lib/mulberry/crawler/robots_txt.ex`
**Lines**: 329-330

**Current Code**:
```elixir
defp fetch_robots_txt(domain, retriever) do
  url = "https://#{domain}/robots.txt"
  # ...
end
```

**Issue**:
The `domain` parameter is not validated before constructing a URL, which could lead to:
- Internal network access via `127.0.0.1` or `localhost`
- Access to cloud metadata endpoints (`169.254.169.254`)
- Redirect attacks via malicious domains

**Recommendation**:
```elixir
defp fetch_robots_txt(domain, retriever) do
  # Validate domain format before making request
  case validate_domain(domain) do
    :ok ->
      url = "https://#{domain}/robots.txt"
      # ... rest of function

    {:error, reason} ->
      Logger.debug("Invalid domain for robots.txt: #{domain} - #{reason}")
      {:error, {:invalid_domain, reason}}
  end
end

defp validate_domain(domain) do
  # Block private/internal IPs and localhosts
  cond do
    domain == nil or domain == "" ->
      {:error, :empty_domain}

    String.starts_with?(domain, "127.") ->
      {:error, :private_ip}

    domain in ["localhost", "localhost.localdomain", "ip6-localhost", "ip6-loopback"] ->
      {:error, :private_ip}

    String.match?(domain, ~r/^169\.254\./) ->
      {:error, :private_ip}

    String.match?(domain, ~r/^192\.168\./) ->
      {:error, :private_ip}

    String.match?(domain, ~r/^10\./) ->
      {:error, :private_ip}

    String.match?(domain, ~r/^172\.(1[6-9]|2\d|3[01])\./) ->
      {:error, :private_ip}

    # Ensure domain looks like a valid hostname
    String.match?(domain, ~r/^[a-zA-Z0-9][a-zA-Z0-9\.-]*[a-zA-Z0-9]$/) ->
      :ok

    true ->
      {:error, :invalid_format}
  end
end
```

**Priority**: P0 - Security vulnerability

**Testing**:
- Add unit tests for `validate_domain/1`
- Test with localhost variants
- Test with private IP ranges
- Test with valid domain names
- Test with invalid formats

---

### 2. Unbounded Sitemap Recursion and Resource Exhaustion

**File**: `lib/mulberry/crawler/sitemap.ex`
**Lines**: 193-204

**Current Code**:
```elixir
defp fetch_index_entries(index_entries, retriever, max_depth, follow_indexes, current_depth) do
  index_entries
  |> Task.async_stream(
    &fetch_sitemap_entry(&1, retriever, max_depth, follow_indexes, current_depth),
    max_concurrency: 3,
    timeout: 30_000
  )
  |> Enum.flat_map(fn
    {:ok, sub_entries} -> sub_entries
    {:exit, _} -> []
  end)
end
```

**Issue**:
While there's a `max_depth` parameter, the `Task.async_stream` for fetching index entries could lead to:
- Resource exhaustion if sitemap index contains thousands of entries
- Network flooding with concurrent requests
- Potential infinite loops with circular sitemap references
- No limit on total number of sitemap entries processed

**Recommendation**:
```elixir
# Add module attributes for limits
@max_sitemap_index_entries 100
@max_sitemap_depth 3
@max_total_sitemap_entries 10_000
@max_sitemap_concurrency 3

defp fetch_index_entries(index_entries, retriever, max_depth, follow_indexes, current_depth, total_count \\ 0) do
  # Limit total entries processed
  if total_count >= @max_total_sitemap_entries do
    Logger.warning("Max sitemap entries limit reached: #{@max_total_sitemap_entries}")
    []
  else
    # Limit concurrency based on available entries
    max_concurrency = min(@max_sitemap_concurrency, length(index_entries))
    remaining_budget = @max_total_sitemap_entries - total_count

    index_entries
    |> Enum.take(remaining_budget)  # Don't exceed budget
    |> Task.async_stream(
      &fetch_sitemap_entry(&1, retriever, max_depth, follow_indexes, current_depth, total_count),
      max_concurrency: max_concurrency,
      timeout: 30_000,
      on_timeout: :kill_task  # Don't keep running tasks alive
    )
    |> Stream.take(@max_sitemap_index_entries)  # Limit per index
    |> Enum.flat_map(fn
      {:ok, sub_entries} ->
        # Track total count
        length(sub_entries)
        sub_entries

      {:exit, reason} ->
        Logger.debug("Sitemap entry fetch failed: #{inspect(reason)}")
        []

      {:timeout, _} ->
        Logger.debug("Sitemap entry fetch timed out")
        []
    end)
  end
end

# Update fetch_sitemap_entry to return count
defp fetch_sitemap_entry(entry, retriever, max_depth, follow_indexes, current_depth, total_count) do
  current_total = total_count  # Track position in fetch stream

  case do_fetch_and_parse(entry.loc, retriever, max_depth, follow_indexes, current_depth + 1) do
    {:ok, sub_entries} ->
      # Check if we've exceeded budget
      if current_total + length(sub_entries) > @max_total_sitemap_entries do
        Logger.warning("Sitemap budget exceeded, truncating results")
        Enum.take(sub_entries, @max_total_sitemap_entries - current_total)
      else
        sub_entries
      end

    {:error, _} ->
      []
  end
end
```

**Priority**: P0 - Resource exhaustion vulnerability

**Testing**:
- Test with sitemap indexes containing many entries
- Test circular sitemap references
- Test timeout behavior
- Verify entry limits are respected

---

### 3. Memory Leak in Orchestrator Results Accumulation

**File**: `lib/mulberry/crawler/orchestrator.ex`
**Lines**: 236-237, 49

**Current Code**:
```elixir
# In handle_info
state = %{state | results: [data | state.results], stats: stats}

# In State struct
defstruct [
  # ...
  results: [],  # Grows without bound
  # ...
]
```

**Issue**:
Results are prepended to a list that grows without bound during long crawls. With thousands of URLs, this could cause:
- Significant memory usage (potentially GBs with large pages)
- Potential OOM errors on memory-constrained systems
- Inefficient data access for large result sets

**Recommendation**:

**Option A: Configurable Result Limit**
```elixir
defmodule Mulberry.Crawler.Orchestrator do
  @default_max_results 10_000

  defmodule State do
    @moduledoc false
    @type t :: %__MODULE__{
            # ...
            results: list(),
            results_count: non_neg_integer(),
            max_results: non_neg_integer(),
            # ...
          }

    defstruct [
      # ...
      results: [],
      results_count: 0,
      max_results: @default_max_results,
      # ...
    ]
  end

  # In init/1
  def init(opts) do
    # ...
    max_results = Keyword.get(opts, :max_results, @default_max_results)

    state = %State{
      # ...
      max_results: max_results,
      # ...
    }

    {:ok, state}
  end

  # In handle_info - modify result handling
  def handle_info({:crawl_result, worker_pid, url, result}, state) do
    # ... existing worker info extraction ...

    state =
      case result do
        {:ok, %{data: data, urls: urls, status_code: status_code, response_time_ms: response_time}} ->
          Logger.debug("Successfully crawled #{url}")

          stats = Stats.record_success(state.stats, domain, status_code, response_time)
          stats = Stats.record_discovered(stats, length(urls))

          # Check result limit
          if state.results_count < state.max_results do
            %{state |
              results: [data | state.results],
              results_count: state.results_count + 1,
              stats: stats
            }
          else
            Logger.warning("Max results limit (#{state.max_results}) reached, discarding data for #{url}")
            %{state |
              results_count: state.results_count + 1,
              stats: stats
            }
          end

        # ... other cases ...
      end

    # ... rest of function
  end

  # In finalize_crawl/1 - add to stats
  defp finalize_crawl(state) do
    stats = Stats.finalize(state.stats)
    state = %{state | stats: stats}

    if state.results_count > state.max_results do
      discarded = state.results_count - state.max_results
      Logger.warning("Crawl complete. Discarded #{discarded} results due to limit (max: #{state.max_results})")
    end

    Logger.info("Crawl complete. Crawled #{stats.urls_crawled} URLs, collected #{length(state.results)} results")
    # ... rest of function
  end
end
```

**Option B: Stream Results to Temporary Storage**
```elixir
defmodule Mulberry.Crawler.Orchestrator do
  @use_temp_storage_threshold 1_000  # Switch to temp storage after N results

  defmodule State do
    @moduledoc false
    @type t :: %__MODULE__{
            # ...
            results: list() | {:file, String.t()},  # Either in-memory or file-based
            results_count: non_neg_integer(),
            temp_file: String.t() | nil,
            # ...
          }

    defstruct [
      # ...
      results: [],
      results_count: 0,
      temp_file: nil,
      # ...
    ]
  end

  # Add result to storage (memory or file)
  defp add_result(state, data) do
    new_count = state.results_count + 1

    case state.results do
      {:file, file_path} ->
        # Append to file
        :ok = File.write!(file_path, :erlang.term_to_binary(data), [:append])
        %{state | results_count: new_count}

      list when new_count > @use_temp_storage_threshold ->
        # Switch to file-based storage
        file_path = create_temp_file()
        # Write existing results
        Enum.each(list, fn item ->
          File.write!(file_path, :erlang.term_to_binary(item), [:append])
        end)
        # Write new result
        File.write!(file_path, :erlang.term_to_binary(data), [:append])

        %{state |
          results: {:file, file_path},
          results_count: new_count,
          temp_file: file_path
        }

      list ->
        %{state | results: [data | list], results_count: new_count}
    end
  end

  defp create_temp_file do
    path = Path.join(System.tmp_dir!, "mulberry_crawl_#{:erlang.unique_integer([:positive])}.dat")
    File.write!(path, "")
    path
  end

  # Load results from storage in finalize_crawl
  defp finalize_crawl(state) do
    results = load_results(state.results)

    # ... rest of finalize logic
  end

  defp load_results({:file, file_path}) do
    file_path
    |> File.stream!([:read, :raw])
    |> Enum.map(fn <<data::binary>> -> :erlang.binary_to_term(data) end)
  end

  defp load_results(list), do: Enum.reverse(list)

  # Cleanup in terminate/2
  def terminate(_reason, %{temp_file: file_path}) when is_binary(file_path) do
    File.rm(file_path)
  end

  def terminate(_reason, _state), do: :ok
end
```

**Priority**: P0 - Memory exhaustion vulnerability

**Testing**:
- Test crawls with 10,000+ URLs
- Monitor memory usage during large crawls
- Test temporary file cleanup
- Verify result limit is respected

---

## 🟠 High Priority Issues

### 4. Hardcoded Auth Format in DataForSEO Client

**File**: `lib/dataforseo/client.ex`
**Lines**: 179-188

**Current Code**:
```elixir
defp build_req_options({username, password}) do
  [
    auth: {:basic, username <> ":" <> password},
    headers: [
      {"content-type", "application/json"},
      {"accept", "application/json"}
    ],
    retry: false
  ]
end
```

**Issue**:
Basic auth concatenation without proper format validation. While Req likely handles encoding, the code assumes a specific tuple format without validation, which could lead to:
- Type errors if credentials aren't strings
- Silent failures with invalid auth format
- Difficult debugging if auth format changes

**Recommendation**:
```elixir
@type credentials :: {String.t(), String.t()}

@spec build_req_options(credentials()) :: keyword() | {:error, :invalid_credentials}
defp build_req_options({username, password}) when is_binary(username) and is_binary(password) do
  if String.trim(username) == "" or String.trim(password) == "" do
    {:error, :invalid_credentials}
  else
    [
      # Use tuple format as expected by Req's basic auth
      auth: {:basic, {username, password}},
      headers: [
        {"content-type", "application/json"},
        {"accept", "application/json"}
      ],
      # We handle retries manually with exponential backoff
      retry: false,
      # Add reasonable timeout
      receive_timeout: 30_000
    ]
  end
end

defp build_req_options(_) do
  {:error, :invalid_credentials}
end

# Update get_auth to validate
@spec get_auth() :: {:ok, credentials()} | {:error, :missing_credentials}
defp get_auth do
  case get_config() do
    %{username: username, password: password}
    when is_binary(username) and is_binary(password) and
         username != "" and password != "" ->
      {:ok, {username, password}}

    _ ->
      {:error, :missing_credentials}
  end
end

# Update create_task/create_live_task to handle auth errors
@spec create_task(String.t(), list(map())) :: {:ok, map()} | {:error, term()}
def create_task(task_type, payload) do
  url = "#{@base_url}/#{task_type}/task_post"

  with {:ok, auth} <- get_auth(),
       {:ok, req_options} <- build_req_options(auth) do
    post_with_retry(url, payload, req_options)
  end
end
```

**Priority**: P1 - Reliability issue

**Testing**:
- Test with valid credentials
- Test with empty credentials
- Test with non-string credentials
- Verify auth format works with Req

---

### 5. No Timeout on DynamicSupervisor Worker Spawn

**File**: `lib/mulberry/crawler/orchestrator.ex`
**Lines**: 412-421

**Current Code**:
```elixir
{:ok, worker_pid} =
  DynamicSupervisor.start_child(
    state.supervisor,
    {Worker,
     [
       orchestrator: self(),
       crawler_impl: state.crawler_impl,
       retriever: state.retriever
     ] ++ state.options}
  )
```

**Issue**:
`DynamicSupervisor.start_child` doesn't have a built-in timeout, meaning a hanging worker initialization could block the orchestrator indefinitely. This could happen if:
- The worker's `init/1` callback blocks
- Dependencies take too long to initialize
- Database/network issues in worker setup

**Recommendation**:
```elixir
# Add timeout constant
@worker_start_timeout 5_000  # 5 seconds

defp spawn_worker(state) do
  case :queue.out(state.url_queue) do
    {{:value, {url, depth}}, new_queue} ->
      # Get domain for rate limiting
      {:ok, domain} = URLManager.extract_domain(url)

      # Wait for rate limit
      case RateLimiter.consume_token(domain) do
        :ok ->
          # Spawn worker with timeout protection
          worker_start_task =
            Task.async(fn ->
              DynamicSupervisor.start_child(
                state.supervisor,
                {Worker,
                 [
                   orchestrator: self(),
                   crawler_impl: state.crawler_impl,
                   retriever: state.retriever
                 ] ++ state.options}
              )
            end)

          case Task.await(worker_start_task, @worker_start_timeout) do
            {:ok, worker_pid} ->
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

              %{
                state
                | url_queue: new_queue,
                  active_workers:
                    Map.put(state.active_workers, worker_pid, %{url: url, depth: depth})
              }

            {:exit, {:timeout, _}} ->
              Logger.warning("Worker start timeout for #{url}")
              # Put URL back in queue for retry
              :queue.in({url, depth}, new_queue)
              state

            {:exit, reason} ->
              Logger.error("Worker start failed for #{url}: #{inspect(reason)}")
              state
          end

        {:error, :rate_limited} ->
          # Put URL back in queue and wait
          Process.send_after(self(), :retry_spawn, 100)
          %{state | url_queue: :queue.in({url, depth}, new_queue)}
      end

    {:empty, _} ->
      state
  end
end
```

**Priority**: P1 - Reliability issue (potential deadlock)

**Testing**:
- Test with workers that have blocking init
- Verify timeout prevents deadlock
- Test that failed worker starts don't lose URLs

---

### 6. Rate Limiter Thundering Herd Race Condition

**File**: `lib/mulberry/crawler/rate_limiter.ex`
**Lines**: 210-226

**Current Code**:
```elixir
defp wait_and_consume_token_loop(domain, timeout, start_time) do
  case consume_token(domain) do
    :ok ->
      :ok

    {:error, :rate_limited} ->
      elapsed = System.monotonic_time(:millisecond) - start_time

      if elapsed >= timeout do
        {:error, :timeout}
      else
        # Sleep for a short time before retrying
        Process.sleep(100)
        wait_and_consume_token_loop(domain, timeout, start_time)
      end
  end
end
```

**Issue**:
Multiple workers calling `wait_and_consume_token` for the same domain could all sleep 100ms and retry simultaneously when tokens become available, creating a thundering herd problem. This results in:
- All workers hitting the rate limit again
- Wasted CPU cycles from repeated checks
- Increased latency for all workers

**Recommendation**:
```elixir
# Add configuration for backoff behavior
@initial_backoff_ms 100
@max_backoff_ms 2_000
@backoff_multiplier 1.5

@spec wait_and_consume_token(domain(), keyword()) :: :ok | {:error, :timeout}
def wait_and_consume_token(domain, opts \\ []) do
  timeout = Keyword.get(opts, :timeout, 60_000)
  wait_and_consume_token_loop(domain, timeout, System.monotonic_time(:millisecond), 0)
end

defp wait_and_consume_token_loop(domain, timeout, start_time, attempt) do
  case consume_token(domain) do
    :ok ->
      :ok

    {:error, :rate_limited} ->
      elapsed = System.monotonic_time(:millisecond) - start_time

      if elapsed >= timeout do
        {:error, :timeout}

      else
        # Calculate exponential backoff with jitter
        base_backoff = :math.pow(@backoff_multiplier, attempt) * @initial_backoff_ms
        capped_backoff = min(base_backoff, @max_backoff_ms)

        # Add jitter to prevent synchronized retries
        jitter = :rand.uniform() * 100  # 0-100ms jitter
        backoff = round(capped_backoff + jitter)

        Logger.debug("Rate limited for #{domain}, waiting #{backoff}ms (attempt #{attempt})")

        Process.sleep(backoff)
        wait_and_consume_token_loop(domain, timeout, start_time, attempt + 1)
      end
  end
end
```

**Priority**: P1 - Performance/efficiency issue

**Testing**:
- Test with multiple workers competing for same domain
- Verify backoff prevents thundering herd
- Measure latency improvements
- Test timeout behavior

---

### 7. Unbounded Regex Pattern Compilation in RobotsTxt

**File**: `lib/mulberry/crawler/robots_txt.ex`
**Lines**: 552-574

**Current Code**:
```elixir
defp compile_pattern(pattern) when is_binary(pattern) do
  regex_str =
    pattern
    |> Regex.escape()
    |> String.replace("\\*", ".*?")
    |> String.replace("\\$", "$")

  regex_str = "^" <> regex_str

  case Regex.compile(regex_str) do
    {:ok, regex} ->
      %{pattern: pattern, regex: regex}

    {:error, _} ->
      Logger.debug("Invalid robots.txt pattern: #{pattern}")
      %{pattern: pattern, regex: nil}
  end
end
```

**Issue**:
While non-greedy quantifiers (`.*?`) help prevent ReDoS, there's no limit on pattern length or complexity. A malicious or malformed robots.txt could contain extremely long patterns that consume significant memory and CPU during compilation:
- Memory exhaustion from large patterns
- CPU spikes during regex compilation
- Potential denial of service

**Recommendation**:
```elixir
# Add size limits for robots.txt patterns
@max_pattern_length 1_000
@max_pattern_complexity 100  # Approximate limit based on special chars

@spec compile_pattern(String.t()) :: compiled_pattern()
defp compile_pattern(pattern) when is_binary(pattern) do
  # Validate pattern length
  pattern_length = String.length(pattern)

  if pattern_length > @max_pattern_length do
    Logger.warning(
      "Robots.txt pattern too long (#{pattern_length} chars, max: #{@max_pattern_length}), ignoring: #{String.slice(pattern, 0, 50)}..."
    )
    %{pattern: pattern, regex: nil}
  else
    # Estimate pattern complexity (rough heuristic)
    complexity = estimate_pattern_complexity(pattern)

    if complexity > @max_pattern_complexity do
      Logger.warning(
        "Robots.txt pattern too complex (complexity: #{complexity}, max: #{@max_pattern_complexity}), ignoring: #{String.slice(pattern, 0, 50)}..."
      )
      %{pattern: pattern, regex: nil}
    else
      do_compile_pattern(pattern)
    end
  end
end

defp do_compile_pattern(pattern) do
  regex_str =
    pattern
    |> Regex.escape()
    |> String.replace("\\*", ".*?")
    |> String.replace("\\$", "$")

  regex_str = "^" <> regex_str

  case Regex.compile(regex_str) do
    {:ok, regex} ->
      %{pattern: pattern, regex: regex}

    {:error, reason} ->
      Logger.debug("Invalid robots.txt pattern: #{pattern} - #{inspect(reason)}")
      %{pattern: pattern, regex: nil}
  end
end

# Estimate complexity based on special characters
defp estimate_pattern_complexity(pattern) do
  pattern
  |> String.graphemes()
  |> Enum.count(fn char ->
    char in ["*", "$", ".", "?", "+", "[", "]", "(", ")", "{", "}", "|", "\\"]
  end)
end

# Also add limit to overall robots.txt parsing
defp parse_robots_txt(content) when is_binary(content) do
  # Check overall file size
  max_content_length = Keyword.get(@opts, :max_robots_txt_size, 100_000)  # 100KB default

  if String.length(content) > max_content_length do
    Logger.warning("Robots.txt too large (#{String.length(content)} bytes), using permissive rules")
    default_permissive_rules()
  else
    # ... existing parsing logic
  end
end
```

**Priority**: P1 - DoS vulnerability

**Testing**:
- Test with very long patterns
- Test with complex patterns
- Test with oversized robots.txt files
- Verify memory/CPU usage with malicious files

---

## 🟡 Medium Priority Issues

### 8. Deprecated Mix Configuration

**File**: `mix.exs`
**Lines**: 17-25

**Current Code**:
```elixir
def project do
  [
    app: :mulberry,
    version: @version,
    # ...
    preferred_cli_env: [
      check: :test,
      "check.doctor": :dev,
      coveralls: :test,
      "coveralls.detail": :test,
      "coveralls.post": :test,
      "coveralls.html": :test,
      "coveralls.github": :test
    ],
    # ...
  ]
end
```

**Issue**:
Mix 1.19 warns that `:preferred_cli_env` should be moved to `def cli do` block instead of `def project`. This is a deprecation warning that will become an error in future Mix versions.

**Recommendation**:
```elixir
def project do
  [
    app: :mulberry,
    version: @version,
    elixir: "~> 1.15",
    start_permanent: Mix.env() == :prod,
    package: package(),
    aliases: aliases(),
    deps: deps(),
    docs: docs(),
    # Remove from here:
    # preferred_cli_env: [...]
    test_coverage: [tool: ExCoveralls],
    test_paths: ["test"],
    test_pattern: "*_test.exs"
  ]
end

# Add new function
def cli do
  [
    preferred_envs: [
      check: :test,
      "check.doctor": :dev,
      coveralls: :test,
      "coveralls.detail": :test,
      "coveralls.post": :test,
      "coveralls.html": :test,
      "coveralls.github": :test
    ]
  ]
end
```

**Priority**: P2 - Future compatibility

**Testing**:
- Verify `mix check` still works
- Verify environment variables are set correctly
- Check for deprecation warnings

---

### 9. Verbose Module References in Search Task

**File**: `lib/mix/tasks/search.ex`
**Multiple locations** (20+ instances of fully qualified module references)

**Issue**:
The search task has numerous instances of fully qualified module references throughout the file (lines showing Credo warnings about nested module aliasing). This:
- Reduces readability
- Violates DRY principle
- Makes refactoring difficult
- Increases cognitive load

**Recommendation**:
```elixir
defmodule Mix.Tasks.Search do
  @moduledoc """
  Performs searches using various providers.

  ## Usage

      mix search [TYPE] QUERY [options]
  ...
  """

  alias Mulberry.Search.Brave
  alias Mulberry.Search.Google
  alias Mulberry.Search.Reddit
  alias Mulberry.Search.FacebookAds
  alias Mulberry.Search.FacebookAdCompanies
  alias Mulberry.Search.GoogleAds
  alias Mulberry.Search.YouTube
  alias Mulberry.Search.File

  # Example of simplified usage:
  def perform_search(type, query, opts) do
    case type do
      "brave" ->
        Brave.perform_search(query, opts)

      "google" ->
        Google.perform_search(query, opts)

      "reddit" ->
        Reddit.perform_search(query, opts)

      # ... instead of Mulberry.Search.Brave.perform_search(...) etc.
    end
  end
end
```

**Priority**: P2 - Code quality

**Testing**:
- Verify all search providers work correctly
- Check for any name conflicts
- Run Credo to verify warnings are resolved

---

### 10. Insufficient Error Classification in Retriever

**File**: `lib/mulberry/retriever/req.ex`
**Lines**: 18-26

**Current Code**:
```elixir
case Req.get(url, headers: headers, params: params) do
  {:ok, %Req.Response{status: status, body: body}} when status < 400 ->
    %Mulberry.Retriever.Response{status: :ok, content: body}

  error ->
    Logger.error("Mulberry - Failed to get #{url}: #{inspect(error)}")
    %Mulberry.Retriever.Response{status: :failed, content: nil}
end
```

**Issue**:
The error case doesn't distinguish between different failure types (timeout, DNS error, connection refused, HTTP error, etc.). This:
- Makes debugging difficult
- Prevents appropriate retry strategies
- Treats transient and permanent errors the same
- Loses valuable error context

**Recommendation**:
```elixir
@type request_result :: {:ok, Mulberry.Retriever.Response.t()} | {:error, atom()}

@spec get(String.t(), Keyword.t()) :: request_result()
def get(url, opts \\ []) do
  params = Keyword.get(opts, :params, %{})
  headers = Keyword.get(opts, :headers, %{})
  timeout = Keyword.get(opts, :timeout, 10_000)

  responder =
    Keyword.get(opts, :responder, &Mulberry.Retriever.Response.default_responder/1)

  case Req.get(url, headers: headers, params: params, receive_timeout: timeout) do
    {:ok, %Req.Response{status: status, body: body}} when status < 400 ->
      Logger.debug("Successfully fetched #{url} (status: #{status})")
      %Mulberry.Retriever.Response{status: :ok, content: body}

    {:ok, %Req.Response{status: status, body: body}} when status >= 400 and status < 500 ->
      Logger.warning("HTTP client error for #{url}: #{status}")
      %Mulberry.Retriever.Response{status: {:http_error, status}, content: body}

    {:ok, %Req.Response{status: status, body: body}} when status >= 500 ->
      Logger.warning("HTTP server error for #{url}: #{status} (may retry)")
      %Mulberry.Retriever.Response{status: {:server_error, status}, content: body}

    {:error, %Req.Error{reason: :timeout}} ->
      Logger.debug("Request timeout for #{url}")
      %Mulberry.Retriever.Response{status: :timeout, content: nil}

    {:error, %Req.Error{reason: :closed}} ->
      Logger.warning("Connection closed for #{url}")
      %Mulberry.Retriever.Response{status: :connection_error, content: nil}

    {:error, %Req.Error{reason: :connect_timeout}} ->
      Logger.warning("Connection timeout for #{url}")
      %Mulberry.Retriever.Response{status: :timeout, content: nil}

    {:error, %Req.Error{reason: reason}} ->
      Logger.error("Request failed for #{url}: #{inspect(reason)}")
      %Mulberry.Retriever.Response{status: {:request_error, reason}, content: nil}

    error ->
      Logger.error("Unexpected error for #{url}: #{inspect(error)}")
      %Mulberry.Retriever.Response{status: :unknown_error, content: nil}
  end
  |> responder.()
end
```

**Priority**: P2 - Debuggability/observability

**Testing**:
- Test with HTTP 4xx errors
- Test with HTTP 5xx errors
- Test with network timeouts
- Test with DNS failures
- Verify error types are correctly identified

---

### 11. Silent Pattern Compilation Failures

**File**: `lib/mulberry/crawler/orchestrator.ex`
**Lines**: 507-516

**Current Code**:
```elixir
defp compile_url_patterns(patterns) when is_list(patterns) do
  case URLManager.compile_patterns(patterns) do
    {:ok, compiled} ->
      compiled

    {:error, {:invalid_pattern, pattern, _}} ->
      Logger.warning("Invalid URL pattern '#{pattern}', ignoring")
      []
  end
end
```

**Issue**:
If pattern compilation fails (invalid regex), the function logs a warning but returns an empty list, silently disabling filters. This could lead to:
- Unexpected behavior when filters are misconfigured
- Difficulty debugging filter issues
- Security implications if exclude patterns are silently ignored

**Recommendation**:
```elixir
defp compile_url_patterns(patterns) when is_list(patterns) do
  case URLManager.compile_patterns(patterns) do
    {:ok, compiled} ->
      compiled

    {:error, {:invalid_pattern, pattern, reason}} ->
      Logger.error(
        "Invalid URL pattern '#{pattern}': #{inspect(reason)}. Filter will be disabled."
      )

      # Option A: Fail fast (recommended for production)
      raise ArgumentError,
            "Invalid URL pattern '#{pattern}': #{inspect(reason)}"

      # Option B: Continue with warning (for development/testing)
      # []
  end
end

# Also add validation in init
def init(opts) do
  # ... existing code ...

  # Validate patterns early
  include_patterns = validate_url_patterns(Keyword.get(opts, :include_patterns, []), "include")
  exclude_patterns = validate_url_patterns(Keyword.get(opts, :exclude_patterns, []), "exclude")

  # ... rest of init
end

defp validate_url_patterns(patterns, pattern_type) when is_list(patterns) do
  case URLManager.compile_patterns(patterns) do
    {:ok, compiled} ->
      compiled

    {:error, {:invalid_pattern, pattern, reason}} ->
      raise ArgumentError,
            "Invalid #{pattern_type} URL pattern '#{pattern}': #{inspect(reason)}"
  end
end

defp validate_url_patterns(_, _), do: []
```

**Priority**: P2 - Correctness/safety

**Testing**:
- Test with invalid regex patterns
- Test with valid regex patterns
- Verify errors are raised appropriately
- Test that filtering works with valid patterns

---

## 🟢 Low Priority / Suggestions

### 12. Document Magic Numbers in Rate Limiter

**File**: `lib/mulberry/crawler/rate_limiter.ex`
**Multiple locations**

**Issue**:
Several magic numbers are used without documentation:
- `default_max_tokens: 10` - Why 10 tokens?
- `default_refill_rate: 1.0` - Why 1 req/sec?
- `sleep(100)` in `wait_and_consume_token_loop` - Why 100ms?

**Recommendation**:
```elixir
defmodule Mulberry.Crawler.RateLimiter do
  @moduledoc """
  Token bucket rate limiter for controlling crawl request rates.

  ## Configuration

  The rate limiter uses a token bucket algorithm with the following defaults:
  - `default_max_tokens`: 10 - Allows bursts of up to 10 concurrent requests
  - `default_refill_rate`: 1.0 - Replenishes 1 token per second (1 req/sec sustained)
  - `retry_backoff_ms`: 100 - Initial backoff when rate limited (100ms)

  These defaults provide a balance between respecting server limits and maintaining reasonable crawl speed.
  """

  # Rate limiter constants
  @default_max_tokens 10
  @default_refill_rate 1.0
  @initial_backoff_ms 100

  defmodule State do
    defstruct buckets: %{},
              default_max_tokens: @default_max_tokens,
              default_refill_rate: @default_refill_rate,
              per_domain_limits: %{}
  end

  # ... rest of module
end
```

**Priority**: P3 - Documentation

**Testing**: No changes needed, just documentation improvement

---

### 13. Document Sitemap Path Sources

**File**: `lib/mulberry/crawler/sitemap.ex`
**Lines**: 47-52

**Current Code**:
```elixir
@common_sitemap_paths [
  "/sitemap.xml",
  "/sitemap_index.xml",
  "/sitemap-index.xml",
  "/sitemaps.xml"
]
```

**Issue**:
The list of common sitemap paths is hardcoded without documentation of its source. This makes it difficult to:
- Understand why these specific paths are checked
- Add new paths in the future
- Remove outdated paths

**Recommendation**:
```elixir
@moduledoc """
Parses and discovers sitemap.xml files for crawling.

## Sitemap Discovery

The crawler attempts to discover sitemaps using two methods:

1. **Robots.txt**: Checks for `Sitemap:` directives in the domain's robots.txt file

2. **Common Paths**: If no sitemaps are found in robots.txt, attempts to fetch from
   commonly used sitemap URLs. These paths are based on web server conventions and
   SEO best practices:

   - `/sitemap.xml` - Most common location (recommended by Google)
   - `/sitemap_index.xml` - Sitemap index file naming convention
   - `/sitemap-index.xml` - Alternative index naming
   - `/sitemaps.xml` - Plural form used by some CMS

   ## Customization

   To add additional sitemap paths, modify the `@common_sitemap_paths` module attribute:

       @common_sitemap_paths [
         "/sitemap.xml",
         "/sitemap_index.xml",
         "/sitemap-index.xml",
         "/sitemaps.xml",
         "/custom_sitemap.xml"  # Add custom paths here
       ]
"""

# Common sitemap paths to check when robots.txt doesn't specify any
# Sources:
# - Google Search Central documentation
# - Common web server configurations
# - SEO best practices
@common_sitemap_paths [
  "/sitemap.xml",        # Most common (Google recommended)
  "/sitemap_index.xml",   # Sitemap index files
  "/sitemap-index.xml",   # Alternative index naming
  "/sitemaps.xml"       # Plural form (some CMS)
]
```

**Priority**: P3 - Documentation

**Testing**: No changes needed, just documentation improvement

---

### 14. Add Telemetry for Observability

**Files**: Multiple crawler modules

**Issue**:
The crawler has good logging but no structured observability. This makes it difficult to:
- Aggregate metrics across crawls
- Set up alerts based on metrics
- Monitor performance trends
- Debug production issues

**Recommendation**:
```elixir
# Add to lib/mulberry/crawler/orchestrator.ex

defmodule Mulberry.Crawler.Orchestrator do
  require Logger
  # Add telemetry attachment
  attach_telemetry_handlers()

  # ... existing code ...

  # In handle_info for crawl results
  def handle_info({:crawl_result, worker_pid, url, result}, state) do
    # ... existing processing ...

    state =
      case result do
        {:ok, %{data: data, urls: urls, status_code: status_code, response_time_ms: response_time}} ->
          # Emit telemetry
          :telemetry.execute(
            [:mulberry, :crawler, :url_complete],
            %{duration_ms: response_time, status_code: status_code, discovered_urls: length(urls)},
            %{domain: domain, url: url, orchestrator: inspect(self())}
          )

          # ... rest of processing
      end
  end

  # In handle_info for failures
  def handle_info({:crawl_result, worker_pid, url, {:error, reason}}, state) do
    # ... existing processing ...

    # Emit telemetry for failures
    :telemetry.execute(
      [:mulberry, :crawler, :url_failed],
      %{error_count: 1},
      %{domain: domain, url: url, reason: inspect(reason)}
    )

    # ... rest of processing
  end

  # In finalize_crawl
  defp finalize_crawl(state) do
    # ... existing code ...

    # Emit completion telemetry
    :telemetry.execute(
      [:mulberry, :crawler, :crawl_complete],
      %{
        urls_crawled: stats.urls_crawled,
        urls_failed: stats.urls_failed,
        duration_ms: stats.duration_ms
      },
      %{start_url: state.start_url || "url_list", orchestrator: inspect(self())}
    )

    # ... rest of finalize
  end

  # Add telemetry attachment function
  defp attach_telemetry_handlers do
    :telemetry.attach(
      "mulberry-crawler-logger",
      [:mulberry, :crawler, :crawl_complete],
      &handle_crawl_complete_telemetry/4,
      nil
    )
  end

  defp handle_crawl_complete_telemetry(event, measurements, metadata, _config) do
    Logger.info(
      "Crawl complete: #{measurements.urls_crawled} crawled, #{measurements.urls_failed} failed in #{measurements.duration_ms}ms"
    )
  end
end

# Also add telemetry to RateLimiter
defmodule Mulberry.Crawler.RateLimiter do
  # In consume_token
  def handle_call({:consume_token, domain}, _from, state) do
    # ... existing logic ...

    if bucket.tokens >= 1 do
      # Token consumed successfully
      :telemetry.execute(
        [:mulberry, :rate_limiter, :token_consumed],
        %{tokens_remaining: bucket.tokens - 1},
        %{domain: domain}
      )

      # ... rest of logic
    else
      # Rate limited
      :telemetry.execute(
        [:mulberry, :rate_limiter, :rate_limited],
        %{tokens_remaining: bucket.tokens},
        %{domain: domain}
      )

      # ... rest of logic
    end
  end
end

# Example usage in application.ex or monitoring setup
defmodule MyApp.Telemetry do
  def setup do
    # Set up Datadog handler
    :telemetry.attach(
      "datadog-mulberry",
      [:mulberry, :crawler, :crawl_complete],
      &handle_datadog/4,
      nil
    )
  end

  def handle_datadog(event, measurements, metadata, _config) do
    Datadog.count("crawler.urls_crawled", measurements.urls_crawled, tags: [domain: metadata.domain])
    Datadog.timing("crawler.duration", measurements.duration_ms, tags: [domain: metadata.domain])
  end
end
```

**Priority**: P3 - Observability

**Testing**:
- Verify telemetry events are emitted correctly
- Test with various event types
- Verify metadata is included
- Test in production environment

---

## Implementation Roadmap

### Phase 1: Critical Security Fixes (Week 1)
1. ✅ Implement domain validation in RobotsTxt
2. ✅ Add sitemap recursion and entry limits
3. ✅ Implement result limiting or streaming in Orchestrator

### Phase 2: High Priority Reliability (Week 2)
4. ✅ Fix DataForSEO auth format validation
5. ✅ Add worker spawn timeout protection
6. ✅ Implement exponential backoff in RateLimiter
7. ✅ Add regex pattern size limits

### Phase 3: Medium Priority Improvements (Week 3)
8. ✅ Update Mix configuration for deprecation warning
9. ✅ Refactor Search task with aliases
10. ✅ Improve error classification in Retriever
11. ✅ Fail fast on invalid URL patterns

### Phase 4: Documentation & Observability (Week 4)
12. ✅ Document magic numbers in RateLimiter
13. ✅ Document sitemap path sources
14. ✅ Add telemetry support across crawler

---

## Testing Strategy

### Unit Tests Required
- Domain validation (SSRF prevention)
- Regex pattern limits
- Auth format validation
- Error classification
- Pattern compilation validation

### Integration Tests Required
- Sitemap with circular references
- Large sitemap index handling
- Worker spawn timeout recovery
- Rate limiter backoff behavior
- Result limit enforcement

### Load Tests Required
- Memory usage with 10,000+ results
- CPU usage with malicious robots.txt
- Performance with rate limiter backoff
- Telemetry event overhead

---

## Monitoring & Metrics

After implementing fixes, monitor:

**Security Metrics**
- Attempted SSRF requests (should be 0)
- Invalid domain rejections
- Robots.txt pattern rejections

**Reliability Metrics**
- Worker spawn timeouts
- Rate limit occurrences
- Retry success rate
- Error type distribution

**Performance Metrics**
- Memory usage during large crawls
- Crawl duration
- Rate limiter backoff distribution
- Sitemap processing time

**Quality Metrics**
- Pattern compilation errors
- Auth validation failures
- Result discard rate (when limited)

---

## Additional Considerations

### Security
- Consider implementing a URL whitelist for production environments
- Add rate limiting per IP/client in production
- Implement request signature verification for APIs

### Performance
- Consider using ETS for URL deduplication at scale
- Implement connection pooling for HTTP requests
- Add compression for sitemap fetching

### Operational
- Add circuit breakers for external API calls
- Implement graceful degradation when under heavy load
- Add health check endpoints for monitoring

---

## References

- [OWASP SSRF Prevention](https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html)
- [Sitemap Protocol](https://www.sitemaps.org/protocol.html)
- [Robots.txt Specification](https://developers.google.com/search/docs/crawling-indexing/robots/robots_txt)
- [Elixir Telemetry](https://hexdocs.pm/telemetry/telemetry.html)
- [Mix CLI Deprecation](https://hexdocs.pm/mix/Mix.Config.html)
- [Token Bucket Algorithm](https://en.wikipedia.org/wiki/Token_bucket)

---

## Change History

| Date | Version | Changes |
|-------|---------|---------|
| 2026-01-12 | 1.0 | Initial code review and recommendations |

---

**Generated by**: AI Code Review
**Project**: Mulberry
**Version**: 0.0.1
