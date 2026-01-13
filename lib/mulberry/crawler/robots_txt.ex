defmodule Mulberry.Crawler.RobotsTxt do
  @moduledoc """
  Parses and caches robots.txt files for crawler compliance.

  This module provides functionality to:
  - Fetch and parse robots.txt files from websites
  - Cache parsed rules per domain with configurable TTL
  - Check if URLs are allowed for crawling
  - Extract Crawl-delay directives
  - Discover sitemap URLs from robots.txt

  ## Usage

      # Check if a URL is allowed
      {:ok, allowed} = RobotsTxt.allowed?("https://example.com/page")

      # Get crawl delay for a domain
      delay = RobotsTxt.get_crawl_delay("example.com")

      # Get sitemaps declared in robots.txt
      {:ok, sitemaps} = RobotsTxt.get_sitemaps("example.com")

  ## robots.txt Directives Supported

  - `User-agent`: Specifies which crawlers the rules apply to
  - `Disallow`: Paths that should not be crawled
  - `Allow`: Paths that are explicitly allowed (overrides Disallow)
  - `Crawl-delay`: Suggested delay between requests (in seconds)
  - `Sitemap`: URLs of sitemap files

  ## Wildcard Patterns

  Supports standard robots.txt wildcards:
  - `*` matches any sequence of characters
  - `$` matches end of URL
  """

  use GenServer
  require Logger

  @default_user_agent "Mulberry"
  @default_cache_ttl :timer.hours(1)

  @type rules :: %{
          user_agents: %{String.t() => agent_rules()},
          sitemaps: [String.t()],
          crawl_delay: float() | nil
        }

  @type compiled_pattern :: %{
          pattern: String.t(),
          regex: Regex.t() | nil
        }

  @type agent_rules :: %{
          allow: [compiled_pattern()],
          disallow: [compiled_pattern()],
          crawl_delay: float() | nil
        }

  @type cache_entry :: %{
          rules: rules(),
          fetched_at: integer(),
          ttl: integer()
        }

  # Client API

  @doc """
  Starts the RobotsTxt GenServer.

  ## Options
    - `:user_agent` - User agent string to use for matching rules (default: "Mulberry")
    - `:cache_ttl` - Time-to-live for cached entries in milliseconds (default: 1 hour)
    - `:retriever` - Module to use for fetching robots.txt (default: Mulberry.Retriever.Req)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Fetches and caches robots.txt for a domain.

  Returns the parsed rules or an error if fetching fails.
  If already cached and not expired, returns cached rules.
  """
  @spec fetch_and_cache(String.t(), keyword()) :: {:ok, rules()} | {:error, any()}
  def fetch_and_cache(domain, opts \\ []) do
    GenServer.call(__MODULE__, {:fetch_and_cache, domain, opts})
  end

  @doc """
  Checks if a URL is allowed for crawling according to robots.txt.

  Returns `true` if allowed, `false` if disallowed.
  If robots.txt hasn't been fetched yet, fetches it first.
  Returns `true` if robots.txt is unavailable or malformed.
  """
  @spec allowed?(String.t()) :: {:ok, boolean()} | {:error, any()}
  def allowed?(url) do
    GenServer.call(__MODULE__, {:allowed?, url})
  end

  @doc """
  Gets the crawl delay for a domain.

  Returns the delay in seconds, or `nil` if not specified.
  """
  @spec get_crawl_delay(String.t()) :: float() | nil
  def get_crawl_delay(domain) do
    GenServer.call(__MODULE__, {:get_crawl_delay, domain})
  end

  @doc """
  Gets the sitemap URLs declared in robots.txt for a domain.
  """
  @spec get_sitemaps(String.t()) :: {:ok, [String.t()]} | {:error, any()}
  def get_sitemaps(domain) do
    GenServer.call(__MODULE__, {:get_sitemaps, domain})
  end

  @doc """
  Clears the cached robots.txt for a domain.
  """
  @spec clear_cache(String.t()) :: :ok
  def clear_cache(domain) do
    GenServer.cast(__MODULE__, {:clear_cache, domain})
  end

  @doc """
  Clears all cached robots.txt entries.
  """
  @spec clear_all_cache() :: :ok
  def clear_all_cache do
    GenServer.cast(__MODULE__, :clear_all_cache)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    # Create ETS table with read_concurrency for fast concurrent reads
    # Table is public so we can do direct ETS lookups without GenServer calls
    table =
      :ets.new(:robots_txt_cache, [
        :named_table,
        :set,
        :public,
        read_concurrency: true
      ])

    state = %{
      table: table,
      user_agent: Keyword.get(opts, :user_agent, @default_user_agent),
      cache_ttl: Keyword.get(opts, :cache_ttl, @default_cache_ttl),
      retriever: Keyword.get(opts, :retriever, Mulberry.Retriever.Req)
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:fetch_and_cache, domain, opts}, _from, state) do
    domain = normalize_domain(domain)
    force_refresh = Keyword.get(opts, :force, false)

    case get_cached_rules(state, domain, force_refresh) do
      {:ok, rules} ->
        {:reply, {:ok, rules}, state}

      :not_cached ->
        case fetch_robots_txt(domain, state.retriever) do
          {:ok, content} ->
            rules = parse_robots_txt(content)
            new_state = cache_rules(state, domain, rules)
            {:reply, {:ok, rules}, new_state}

          {:error, reason} ->
            # Cache a permissive entry on error
            rules = default_permissive_rules()
            new_state = cache_rules(state, domain, rules)

            Logger.debug(
              "robots.txt unavailable for #{domain}: #{inspect(reason)}, assuming permissive"
            )

            {:reply, {:ok, rules}, new_state}
        end
    end
  end

  @impl true
  def handle_call({:allowed?, url}, _from, state) do
    case URI.parse(url) do
      %URI{host: nil} ->
        {:reply, {:error, :invalid_url}, state}

      %URI{host: host, path: path, query: query} ->
        domain = normalize_domain(host)
        full_path = build_full_path(path, query)
        {result, new_state} = check_url_allowed(domain, full_path, state)
        {:reply, result, new_state}
    end
  end

  @impl true
  def handle_call({:get_crawl_delay, domain}, _from, state) do
    domain = normalize_domain(domain)

    delay =
      case get_cached_rules(state, domain, false) do
        {:ok, rules} ->
          get_delay_from_rules(rules, state.user_agent)

        :not_cached ->
          nil
      end

    {:reply, delay, state}
  end

  @impl true
  def handle_call({:get_sitemaps, domain}, _from, state) do
    domain = normalize_domain(domain)

    case get_cached_rules(state, domain, false) do
      {:ok, rules} ->
        {:reply, {:ok, rules.sitemaps}, state}

      :not_cached ->
        case fetch_robots_txt(domain, state.retriever) do
          {:ok, content} ->
            rules = parse_robots_txt(content)
            new_state = cache_rules(state, domain, rules)
            {:reply, {:ok, rules.sitemaps}, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_cast({:clear_cache, domain}, state) do
    domain = normalize_domain(domain)
    :ets.delete(:robots_txt_cache, domain)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:clear_all_cache, state) do
    :ets.delete_all_objects(:robots_txt_cache)
    {:noreply, state}
  end

  # Private functions

  defp check_url_allowed(domain, full_path, state) do
    case get_cached_rules(state, domain, false) do
      {:ok, rules} ->
        allowed = check_allowed(rules, full_path, state.user_agent)
        {{:ok, allowed}, state}

      :not_cached ->
        fetch_and_check_allowed(domain, full_path, state)
    end
  end

  defp fetch_and_check_allowed(domain, full_path, state) do
    case fetch_robots_txt(domain, state.retriever) do
      {:ok, content} ->
        rules = parse_robots_txt(content)
        new_state = cache_rules(state, domain, rules)
        allowed = check_allowed(rules, full_path, state.user_agent)
        {{:ok, allowed}, new_state}

      {:error, _reason} ->
        rules = default_permissive_rules()
        new_state = cache_rules(state, domain, rules)
        {{:ok, true}, new_state}
    end
  end

  defp normalize_domain(domain) do
    domain
    |> String.downcase()
    |> String.trim()
    |> String.replace_leading("www.", "")
  end

  defp build_full_path(nil, nil), do: "/"
  defp build_full_path(path, nil), do: path || "/"
  defp build_full_path(nil, query), do: "/?" <> query
  defp build_full_path(path, query), do: path <> "?" <> query

  defp get_cached_rules(_state, _domain, true = _force_refresh), do: :not_cached

  defp get_cached_rules(_state, domain, false = _force_refresh) do
    # Direct ETS lookup - no GenServer call needed for reads
    case :ets.lookup(:robots_txt_cache, domain) do
      [] -> :not_cached
      [{^domain, entry}] -> check_cache_entry_validity(entry)
    end
  end

  defp check_cache_entry_validity(%{rules: rules, fetched_at: fetched_at, ttl: ttl}) do
    now = System.monotonic_time(:millisecond)

    if now - fetched_at > ttl do
      :not_cached
    else
      {:ok, rules}
    end
  end

  defp cache_rules(state, domain, rules) do
    entry = %{
      rules: rules,
      fetched_at: System.monotonic_time(:millisecond),
      ttl: state.cache_ttl
    }

    # Write to ETS table
    :ets.insert(:robots_txt_cache, {domain, entry})
    state
  end

  defp fetch_robots_txt(domain, retriever) do
    url = "https://#{domain}/robots.txt"

    case Mulberry.Retriever.get(retriever, url) do
      {:ok, %{status: :ok, content: content}} when is_binary(content) ->
        {:ok, content}

      {:ok, %{status: :failed}} ->
        {:error, :fetch_failed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp default_permissive_rules do
    %{
      user_agents: %{},
      sitemaps: [],
      crawl_delay: nil
    }
  end

  @doc false
  @spec parse_robots_txt(String.t()) :: rules()
  def parse_robots_txt(content) do
    lines =
      content
      |> String.split(~r/\r?\n/)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(String.starts_with?(&1, "#") || &1 == ""))

    {user_agents, sitemaps} = parse_lines(lines)

    %{
      user_agents: user_agents,
      sitemaps: sitemaps,
      crawl_delay: get_global_crawl_delay(user_agents)
    }
  end

  defp parse_lines(lines) do
    initial_state = %{
      user_agents: %{},
      sitemaps: [],
      current_agents: [],
      current_rules: %{allow: [], disallow: [], crawl_delay: nil}
    }

    final_state = Enum.reduce(lines, initial_state, &parse_line/2)

    # Finalize any pending rules
    final_state = finalize_current_agents(final_state)

    {final_state.user_agents, final_state.sitemaps}
  end

  defp parse_line(line, state) do
    directive = parse_directive(line)
    apply_directive(directive, state)
  end

  defp apply_directive({:user_agent, agent}, state) do
    state = maybe_finalize_agents(state)
    %{state | current_agents: [String.downcase(agent) | state.current_agents]}
  end

  defp apply_directive({:allow, path}, state) do
    compiled = compile_pattern(path)
    rules = %{state.current_rules | allow: [compiled | state.current_rules.allow]}
    %{state | current_rules: rules}
  end

  defp apply_directive({:disallow, path}, state) do
    compiled = compile_pattern(path)
    rules = %{state.current_rules | disallow: [compiled | state.current_rules.disallow]}
    %{state | current_rules: rules}
  end

  defp apply_directive({:crawl_delay, delay}, state) do
    rules = %{state.current_rules | crawl_delay: delay}
    %{state | current_rules: rules}
  end

  defp apply_directive({:sitemap, url}, state) do
    %{state | sitemaps: [url | state.sitemaps]}
  end

  defp apply_directive(:unknown, state), do: state

  defp maybe_finalize_agents(state) do
    has_agents = state.current_agents != []
    has_rules = has_pending_rules?(state.current_rules)

    if has_agents && has_rules do
      finalize_current_agents(state)
    else
      state
    end
  end

  defp has_pending_rules?(rules) do
    rules.allow != [] || rules.disallow != [] || rules.crawl_delay != nil
  end

  defp parse_directive(line) do
    # Remove inline comments
    line = String.replace(line, ~r/#.*$/, "") |> String.trim()

    cond do
      String.match?(line, ~r/^user-agent\s*:\s*/i) ->
        value = Regex.replace(~r/^user-agent\s*:\s*/i, line, "") |> String.trim()
        {:user_agent, value}

      String.match?(line, ~r/^allow\s*:\s*/i) ->
        value = Regex.replace(~r/^allow\s*:\s*/i, line, "") |> String.trim()
        {:allow, value}

      String.match?(line, ~r/^disallow\s*:\s*/i) ->
        value = Regex.replace(~r/^disallow\s*:\s*/i, line, "") |> String.trim()
        {:disallow, value}

      String.match?(line, ~r/^crawl-delay\s*:\s*/i) ->
        value = Regex.replace(~r/^crawl-delay\s*:\s*/i, line, "") |> String.trim()

        case Float.parse(value) do
          {delay, _} -> {:crawl_delay, delay}
          :error -> :unknown
        end

      String.match?(line, ~r/^sitemap\s*:\s*/i) ->
        value = Regex.replace(~r/^sitemap\s*:\s*/i, line, "") |> String.trim()
        {:sitemap, value}

      true ->
        :unknown
    end
  end

  defp finalize_current_agents(state) do
    if state.current_agents == [] do
      state
    else
      # Apply rules to all current agents
      new_user_agents =
        Enum.reduce(state.current_agents, state.user_agents, fn agent, acc ->
          Map.put(acc, agent, state.current_rules)
        end)

      %{
        state
        | user_agents: new_user_agents,
          current_agents: [],
          current_rules: %{allow: [], disallow: [], crawl_delay: nil}
      }
    end
  end

  defp get_global_crawl_delay(user_agents) do
    # Check for wildcard user-agent's crawl delay
    case Map.get(user_agents, "*") do
      %{crawl_delay: delay} when delay != nil -> delay
      _ -> nil
    end
  end

  defp check_allowed(rules, path, user_agent) do
    user_agent_lower = String.downcase(user_agent)

    # Find the most specific matching user-agent rules
    agent_rules =
      cond do
        Map.has_key?(rules.user_agents, user_agent_lower) ->
          Map.get(rules.user_agents, user_agent_lower)

        Map.has_key?(rules.user_agents, "*") ->
          Map.get(rules.user_agents, "*")

        true ->
          # No rules found, allow by default
          nil
      end

    if agent_rules == nil do
      true
    else
      check_path_allowed(agent_rules, path)
    end
  end

  defp check_path_allowed(agent_rules, path) do
    # Find the most specific matching rule
    # Allow rules take precedence when path lengths are equal
    allow_match = find_best_match(agent_rules.allow, path)
    disallow_match = find_best_match(agent_rules.disallow, path)

    cond do
      # No disallow rules match
      disallow_match == nil ->
        true

      # Empty disallow means allow all
      disallow_match.pattern == "" ->
        true

      # Allow rule is more specific or equally specific
      allow_match != nil &&
          String.length(allow_match.pattern) >= String.length(disallow_match.pattern) ->
        true

      # Disallow rule applies
      true ->
        false
    end
  end

  defp find_best_match(patterns, path) do
    patterns
    |> Enum.filter(&pattern_matches?(&1, path))
    |> Enum.max_by(fn %{pattern: p} -> String.length(p) end, fn -> nil end)
  end

  # Compile a robots.txt pattern to a regex at parse time
  # Uses non-greedy .*? to prevent ReDoS attacks
  @spec compile_pattern(String.t()) :: compiled_pattern()
  defp compile_pattern(""), do: %{pattern: "", regex: nil}

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
        # Invalid pattern - store nil regex, will never match
        Logger.debug("Invalid robots.txt pattern: #{pattern}")
        %{pattern: pattern, regex: nil}
    end
  end

  # Match a path against a pre-compiled pattern
  defp pattern_matches?(%{pattern: "", regex: nil}, _path), do: false
  defp pattern_matches?(%{pattern: _, regex: nil}, _path), do: false
  defp pattern_matches?(%{pattern: _, regex: regex}, path), do: Regex.match?(regex, path)

  defp get_delay_from_rules(rules, user_agent) do
    user_agent_lower = String.downcase(user_agent)

    cond do
      Map.has_key?(rules.user_agents, user_agent_lower) ->
        Map.get(rules.user_agents, user_agent_lower).crawl_delay

      Map.has_key?(rules.user_agents, "*") ->
        Map.get(rules.user_agents, "*").crawl_delay

      true ->
        nil
    end
  end
end
