defmodule Mulberry.Crawler.Stats do
  @moduledoc """
  Tracks detailed crawl statistics including HTTP status codes,
  error categorization, and per-domain metrics.

  This module provides a pure functional interface for recording and
  aggregating crawl statistics. Stats are stored in the Orchestrator state
  and updated as crawling progresses.

  ## Usage

      # Create new stats
      stats = Stats.new()

      # Record a successful crawl
      stats = Stats.record_success(stats, "example.com", 200, 150)

      # Record a failure
      stats = Stats.record_failure(stats, "example.com", :timeout, "Connection timed out")

      # Get formatted summary
      IO.puts(Stats.format_summary(stats))

  ## Statistics Tracked

  - URLs crawled, failed, discovered, filtered, robots-blocked
  - HTTP status code breakdown
  - Error categorization (timeout, DNS, connection, parse, etc.)
  - Per-domain metrics including average response time
  - Crawl duration
  """

  @type error_category ::
          :timeout
          | :dns
          | :connection
          | :parse
          | :rate_limited
          | :robots_blocked
          | :http_error
          | :unknown

  @type domain_stats :: %{
          urls_crawled: non_neg_integer(),
          urls_failed: non_neg_integer(),
          total_response_time_ms: non_neg_integer(),
          avg_response_time_ms: float()
        }

  @type t :: %{
          urls_crawled: non_neg_integer(),
          urls_failed: non_neg_integer(),
          urls_discovered: non_neg_integer(),
          urls_filtered: non_neg_integer(),
          urls_robots_blocked: non_neg_integer(),
          start_time: integer() | nil,
          end_time: integer() | nil,
          status_codes: %{optional(integer()) => non_neg_integer()},
          errors_by_category: %{optional(error_category()) => non_neg_integer()},
          per_domain: %{optional(String.t()) => domain_stats()}
        }

  @doc """
  Creates a new stats structure with all counters initialized to zero.
  """
  @spec new() :: t()
  def new do
    %{
      urls_crawled: 0,
      urls_failed: 0,
      urls_discovered: 0,
      urls_filtered: 0,
      urls_robots_blocked: 0,
      start_time: nil,
      end_time: nil,
      status_codes: %{},
      errors_by_category: %{},
      per_domain: %{}
    }
  end

  @doc """
  Records the start time of the crawl.
  """
  @spec start(t()) :: t()
  def start(stats) do
    %{stats | start_time: System.monotonic_time(:millisecond)}
  end

  @doc """
  Records a successful crawl for a URL.

  ## Parameters
    - `stats` - Current stats structure
    - `domain` - Domain that was crawled
    - `status_code` - HTTP status code received
    - `response_time_ms` - Time taken to fetch the page in milliseconds
  """
  @spec record_success(t(), String.t(), integer(), non_neg_integer()) :: t()
  def record_success(stats, domain, status_code, response_time_ms) do
    stats
    |> Map.update!(:urls_crawled, &(&1 + 1))
    |> update_status_codes(status_code)
    |> update_domain_stats(domain, :success, response_time_ms)
  end

  @doc """
  Records a failed crawl for a URL.

  ## Parameters
    - `stats` - Current stats structure
    - `domain` - Domain that failed
    - `category` - Error category (e.g., :timeout, :dns, :connection)
    - `_reason` - Detailed error reason (for logging, not stored)
  """
  @spec record_failure(t(), String.t(), error_category(), any()) :: t()
  def record_failure(stats, domain, category, _reason) do
    stats
    |> Map.update!(:urls_failed, &(&1 + 1))
    |> update_error_category(category)
    |> update_domain_stats(domain, :failure, 0)
  end

  @doc """
  Records discovered URLs count.
  """
  @spec record_discovered(t(), non_neg_integer()) :: t()
  def record_discovered(stats, count) do
    Map.update!(stats, :urls_discovered, &(&1 + count))
  end

  @doc """
  Records filtered URLs count.
  """
  @spec record_filtered(t(), non_neg_integer()) :: t()
  def record_filtered(stats, count) do
    Map.update!(stats, :urls_filtered, &(&1 + count))
  end

  @doc """
  Records URLs blocked by robots.txt count.
  """
  @spec record_robots_blocked(t(), non_neg_integer()) :: t()
  def record_robots_blocked(stats, count) do
    Map.update!(stats, :urls_robots_blocked, &(&1 + count))
  end

  @doc """
  Finalizes stats by recording end time and calculating duration.
  """
  @spec finalize(t()) :: t()
  def finalize(stats) do
    %{stats | end_time: System.monotonic_time(:millisecond)}
  end

  @doc """
  Returns the duration of the crawl in milliseconds.
  Returns nil if crawl hasn't started or finished.
  """
  @spec duration_ms(t()) :: non_neg_integer() | nil
  def duration_ms(%{start_time: nil}), do: nil
  def duration_ms(%{end_time: nil}), do: nil
  def duration_ms(%{start_time: start_time, end_time: end_time}), do: end_time - start_time

  @doc """
  Categorizes an error based on its type and content.

  ## Examples

      iex> Stats.categorize_error(%Req.TransportError{reason: :timeout})
      :timeout

      iex> Stats.categorize_error(%Req.TransportError{reason: :nxdomain})
      :dns

      iex> Stats.categorize_error({:http_error, 404})
      :http_error
  """
  @spec categorize_error(any()) :: error_category()
  def categorize_error(error) do
    cond do
      timeout_error?(error) -> :timeout
      dns_error?(error) -> :dns
      connection_error?(error) -> :connection
      parse_error?(error) -> :parse
      rate_limited_error?(error) -> :rate_limited
      http_error?(error) -> :http_error
      true -> :unknown
    end
  end

  @doc """
  Formats a human-readable summary of the crawl statistics.
  """
  @spec format_summary(t()) :: String.t()
  def format_summary(stats) do
    duration = duration_ms(stats)

    duration_str =
      if duration do
        format_duration(duration)
      else
        "N/A"
      end

    urls_per_sec =
      if duration && duration > 0 do
        Float.round(stats.urls_crawled / (duration / 1000), 2)
      else
        0.0
      end

    """
    ═══════════════════════════════════════════════════════════════════
    CRAWL SUMMARY
    ═══════════════════════════════════════════════════════════════════

    Duration: #{duration_str}
    URLs/second: #{urls_per_sec}

    URL Statistics:
      Crawled:        #{stats.urls_crawled}
      Failed:         #{stats.urls_failed}
      Discovered:     #{stats.urls_discovered}
      Filtered:       #{stats.urls_filtered}
      Robots Blocked: #{stats.urls_robots_blocked}

    #{format_status_codes(stats.status_codes)}
    #{format_errors(stats.errors_by_category)}
    #{format_top_domains(stats.per_domain)}
    ═══════════════════════════════════════════════════════════════════
    """
  end

  @doc """
  Converts stats to a simple map for serialization.
  """
  @spec to_map(t()) :: map()
  def to_map(stats) do
    stats
    |> Map.put(:duration_ms, duration_ms(stats))
  end

  # Private functions

  defp update_status_codes(stats, status_code) do
    status_codes = Map.update(stats.status_codes, status_code, 1, &(&1 + 1))
    %{stats | status_codes: status_codes}
  end

  defp update_error_category(stats, category) do
    errors = Map.update(stats.errors_by_category, category, 1, &(&1 + 1))
    %{stats | errors_by_category: errors}
  end

  defp update_domain_stats(stats, domain, result, response_time_ms) do
    domain_stats =
      Map.get(stats.per_domain, domain, %{
        urls_crawled: 0,
        urls_failed: 0,
        total_response_time_ms: 0,
        avg_response_time_ms: 0.0
      })

    domain_stats =
      case result do
        :success ->
          new_crawled = domain_stats.urls_crawled + 1
          new_total_time = domain_stats.total_response_time_ms + response_time_ms
          new_avg = new_total_time / new_crawled

          %{
            domain_stats
            | urls_crawled: new_crawled,
              total_response_time_ms: new_total_time,
              avg_response_time_ms: Float.round(new_avg, 2)
          }

        :failure ->
          %{domain_stats | urls_failed: domain_stats.urls_failed + 1}
      end

    %{stats | per_domain: Map.put(stats.per_domain, domain, domain_stats)}
  end

  # Error type detection

  defp timeout_error?(%{reason: :timeout}), do: true
  defp timeout_error?(%{reason: :connect_timeout}), do: true
  defp timeout_error?({:timeout, _}), do: true
  defp timeout_error?(:timeout), do: true
  defp timeout_error?(_), do: false

  defp dns_error?(%{reason: :nxdomain}), do: true
  defp dns_error?(%{reason: :dns_error}), do: true
  defp dns_error?({:dns, _}), do: true
  defp dns_error?(:nxdomain), do: true
  defp dns_error?(_), do: false

  defp connection_error?(%{reason: :econnrefused}), do: true
  defp connection_error?(%{reason: :econnreset}), do: true
  defp connection_error?(%{reason: :closed}), do: true
  defp connection_error?(%{reason: :connection_refused}), do: true
  defp connection_error?({:connection, _}), do: true
  defp connection_error?(:econnrefused), do: true
  defp connection_error?(_), do: false

  defp parse_error?({:parse, _}), do: true
  defp parse_error?(%Jason.DecodeError{}), do: true
  defp parse_error?(:parse_error), do: true
  defp parse_error?(_), do: false

  defp rate_limited_error?(:rate_limited), do: true
  defp rate_limited_error?({:rate_limited, _}), do: true
  defp rate_limited_error?(_), do: false

  defp http_error?({:http_error, _}), do: true
  defp http_error?({:status, code}) when code >= 400, do: true
  defp http_error?(_), do: false

  # Formatting helpers

  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"

  defp format_duration(ms) do
    seconds = div(ms, 1000)
    remaining_ms = rem(ms, 1000)

    if seconds < 60 do
      "#{seconds}.#{div(remaining_ms, 100)}s"
    else
      minutes = div(seconds, 60)
      remaining_seconds = rem(seconds, 60)
      "#{minutes}m #{remaining_seconds}s"
    end
  end

  defp format_status_codes(status_codes) when map_size(status_codes) == 0 do
    "HTTP Status Codes: None"
  end

  defp format_status_codes(status_codes) do
    codes =
      status_codes
      |> Enum.sort_by(fn {code, _} -> code end)
      |> Enum.map_join("\n", fn {code, count} -> "    #{code}: #{count}" end)

    """
    HTTP Status Codes:
    #{codes}
    """
  end

  defp format_errors(errors) when map_size(errors) == 0 do
    "Errors by Category: None"
  end

  defp format_errors(errors) do
    error_lines =
      errors
      |> Enum.sort_by(fn {_, count} -> -count end)
      |> Enum.map_join("\n", fn {category, count} -> "    #{category}: #{count}" end)

    """
    Errors by Category:
    #{error_lines}
    """
  end

  defp format_top_domains(domains) when map_size(domains) == 0 do
    "Top Domains: None"
  end

  defp format_top_domains(domains) do
    top_domains =
      domains
      |> Enum.sort_by(fn {_, stats} -> -(stats.urls_crawled + stats.urls_failed) end)
      |> Enum.take(5)
      |> Enum.map_join("\n", fn {domain, stats} ->
        "    #{domain}: #{stats.urls_crawled} crawled, #{stats.urls_failed} failed, #{stats.avg_response_time_ms}ms avg"
      end)

    """
    Top Domains (by activity):
    #{top_domains}
    """
  end
end
