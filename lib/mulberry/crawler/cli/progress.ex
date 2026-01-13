defmodule Mulberry.Crawler.CLI.Progress do
  @moduledoc """
  CLI progress reporting for the crawler.

  Provides formatted output for crawl progress and statistics,
  including progress bars, status summaries, and detailed reports.

  ## Verbosity Levels

  - `:quiet` - No output except errors
  - `:normal` - Progress updates and summary (default)
  - `:verbose` - Detailed per-URL output
  - `:debug` - Full debug information

  ## Usage

      # Start progress tracking
      progress = Progress.new(total_urls: 100, verbosity: :normal)

      # Update progress
      progress = Progress.update(progress, %{
        urls_crawled: 45,
        urls_failed: 2,
        active_workers: 5
      })

      # Render progress bar
      Progress.render(progress)

      # Format final summary
      Progress.format_summary(stats)
  """

  # Stats is a plain map, not a struct

  @type verbosity :: :quiet | :normal | :verbose | :debug

  @type t :: %__MODULE__{
          total_urls: non_neg_integer() | nil,
          urls_crawled: non_neg_integer(),
          urls_failed: non_neg_integer(),
          active_workers: non_neg_integer(),
          queue_size: non_neg_integer(),
          verbosity: verbosity(),
          start_time: integer(),
          shell: module()
        }

  defstruct total_urls: nil,
            urls_crawled: 0,
            urls_failed: 0,
            active_workers: 0,
            queue_size: 0,
            verbosity: :normal,
            start_time: 0,
            shell: Mix.shell()

  @doc """
  Creates a new progress tracker.

  ## Options
    - `:total_urls` - Total number of URLs to crawl (nil if unknown)
    - `:verbosity` - Output verbosity level (default: :normal)
    - `:shell` - Shell module for output (default: Mix.shell())
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      total_urls: Keyword.get(opts, :total_urls),
      verbosity: Keyword.get(opts, :verbosity, :normal),
      shell: Keyword.get(opts, :shell, Mix.shell()),
      start_time: System.monotonic_time(:millisecond)
    }
  end

  @doc """
  Updates progress with new stats.
  """
  @spec update(t(), map()) :: t()
  def update(progress, stats) do
    %{
      progress
      | urls_crawled: Map.get(stats, :urls_crawled, progress.urls_crawled),
        urls_failed: Map.get(stats, :urls_failed, progress.urls_failed),
        active_workers: Map.get(stats, :active_workers, progress.active_workers),
        queue_size: Map.get(stats, :queue_size, progress.queue_size)
    }
  end

  @doc """
  Renders the current progress to the console.
  """
  @spec render(t()) :: :ok
  def render(%__MODULE__{verbosity: :quiet}), do: :ok

  def render(%__MODULE__{} = progress) do
    line = format_progress_line(progress)
    # Use carriage return to overwrite the line
    progress.shell.info(["\r", line])
    :ok
  end

  @doc """
  Renders a completed URL (for verbose mode).
  """
  @spec render_url(t(), String.t(), :ok | :error) :: :ok
  def render_url(%__MODULE__{verbosity: verbosity}, _url, _status)
      when verbosity in [:quiet, :normal] do
    :ok
  end

  def render_url(%__MODULE__{} = progress, url, status) do
    status_str = if status == :ok, do: "[OK]", else: "[FAIL]"
    progress.shell.info("  #{status_str} #{truncate_url(url, 70)}")
    :ok
  end

  @doc """
  Formats a detailed summary of the crawl statistics.
  """
  @spec format_summary(map()) :: String.t()
  def format_summary(%{} = stats) do
    lines = [
      "",
      String.duplicate("=", 60),
      "CRAWL SUMMARY",
      String.duplicate("=", 60),
      "",
      format_main_stats(stats),
      "",
      format_timing_stats(stats),
      "",
      format_status_codes(stats),
      "",
      format_error_breakdown(stats),
      "",
      format_top_domains(stats),
      String.duplicate("=", 60)
    ]

    Enum.join(lines, "\n")
  end

  @doc """
  Formats a brief summary (one-liner).
  """
  @spec format_brief_summary(map()) :: String.t()
  def format_brief_summary(%{} = stats) do
    success_rate = calculate_success_rate(stats)

    "Crawled #{stats.urls_crawled} URLs | " <>
      "#{stats.urls_failed} failed | " <>
      "#{format_float(success_rate)}% success | " <>
      "#{format_duration(stats.duration_ms)}"
  end

  # Private functions

  defp format_progress_line(progress) do
    bar = format_progress_bar(progress)
    stats = format_inline_stats(progress)
    elapsed = format_elapsed(progress)

    "#{bar} | #{stats} | #{elapsed}"
  end

  defp format_progress_bar(%{total_urls: nil, urls_crawled: crawled}) do
    # Spinner for unknown total
    spinner = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    idx = rem(crawled, length(spinner))
    "[#{Enum.at(spinner, idx)}] #{crawled} URLs"
  end

  defp format_progress_bar(%{total_urls: total, urls_crawled: crawled}) when total > 0 do
    percentage = min(100, div(crawled * 100, total))
    bar_width = 20
    filled = div(percentage * bar_width, 100)
    empty = bar_width - filled

    bar =
      String.duplicate("=", max(0, filled - 1)) <>
        if(filled > 0, do: ">", else: "") <>
        String.duplicate(" ", empty)

    "[#{bar}] #{percentage}% (#{crawled}/#{total})"
  end

  defp format_progress_bar(_), do: "[          ] 0%"

  defp format_inline_stats(progress) do
    "#{progress.urls_failed} failed | #{progress.active_workers} active | #{progress.queue_size} queued"
  end

  defp format_elapsed(progress) do
    elapsed = System.monotonic_time(:millisecond) - progress.start_time
    format_duration(elapsed)
  end

  defp format_main_stats(stats) do
    success_rate = calculate_success_rate(stats)

    """
    URLs Crawled:     #{stats.urls_crawled}
    URLs Failed:      #{stats.urls_failed}
    URLs Discovered:  #{stats.urls_discovered}
    URLs Filtered:    #{stats.urls_filtered}
    Robots Blocked:   #{stats.urls_robots_blocked}
    Success Rate:     #{format_float(success_rate)}%
    """
    |> String.trim()
  end

  defp format_timing_stats(stats) do
    """
    TIMING
    ------
    Duration:         #{format_duration(stats.duration_ms)}
    Avg Response:     #{format_avg_response_time(stats)}
    """
    |> String.trim()
  end

  defp format_status_codes(stats) do
    if stats.status_codes == %{} do
      "STATUS CODES\n------\n  (none recorded)"
    else
      codes =
        stats.status_codes
        |> Enum.sort_by(fn {code, _} -> code end)
        |> Enum.map_join("\n", fn {code, count} -> "  #{code}: #{count}" end)

      "STATUS CODES\n------\n#{codes}"
    end
  end

  defp format_error_breakdown(stats) do
    if stats.errors_by_category == %{} do
      "ERRORS\n------\n  (none)"
    else
      errors =
        stats.errors_by_category
        |> Enum.sort_by(fn {_, count} -> -count end)
        |> Enum.map_join("\n", fn {category, count} -> "  #{category}: #{count}" end)

      "ERRORS\n------\n#{errors}"
    end
  end

  defp format_top_domains(stats) do
    if stats.per_domain == %{} do
      "TOP DOMAINS\n------\n  (none)"
    else
      domains =
        stats.per_domain
        |> Enum.sort_by(fn {_, domain_stats} ->
          -(domain_stats.urls_crawled + domain_stats.urls_failed)
        end)
        |> Enum.take(5)
        |> Enum.map_join("\n", fn {domain, domain_stats} ->
          total = domain_stats.urls_crawled + domain_stats.urls_failed

          "  #{truncate_domain(domain, 30)}: #{total} (#{domain_stats.urls_crawled} ok, #{domain_stats.urls_failed} fail)"
        end)

      "TOP DOMAINS (by requests)\n------\n#{domains}"
    end
  end

  defp calculate_success_rate(%{urls_crawled: 0}), do: 0.0

  defp calculate_success_rate(%{urls_crawled: crawled, urls_failed: failed}) do
    total = crawled + failed
    if total > 0, do: crawled / total * 100, else: 0.0
  end

  defp format_avg_response_time(%{per_domain: domains}) when domains == %{}, do: "N/A"

  defp format_avg_response_time(%{per_domain: domains}) do
    {total_time, total_count} =
      Enum.reduce(domains, {0, 0}, fn {_, stats}, {time_acc, count_acc} ->
        {time_acc + stats.total_response_time_ms, count_acc + stats.urls_crawled}
      end)

    if total_count > 0 do
      avg = div(total_time, total_count)
      "#{avg}ms"
    else
      "N/A"
    end
  end

  defp format_duration(nil), do: "N/A"
  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms) when ms < 60_000, do: "#{format_float(ms / 1000)}s"

  defp format_duration(ms) do
    minutes = div(ms, 60_000)
    seconds = rem(ms, 60_000) / 1000
    "#{minutes}m #{format_float(seconds)}s"
  end

  defp format_float(value) when is_float(value) do
    :erlang.float_to_binary(value, decimals: 1)
  end

  defp format_float(value), do: to_string(value)

  defp truncate_url(url, max_len) when byte_size(url) > max_len do
    String.slice(url, 0, max_len - 3) <> "..."
  end

  defp truncate_url(url, _), do: url

  defp truncate_domain(domain, max_len) when byte_size(domain) > max_len do
    String.slice(domain, 0, max_len - 3) <> "..."
  end

  defp truncate_domain(domain, _), do: domain
end
