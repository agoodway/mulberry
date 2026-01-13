defmodule Mix.Tasks.GoogleNews do
  @moduledoc """
  Fetch Google News SERP results from DataForSEO API and save to JSON file.

  Retrieves news articles from Google News search results for a specific keyword,
  location, and language.

  ## Usage

      mix google_news [options]

  ## Options

    * `--keyword`, `-k` - News search term (required, max 700 chars)
    * `--location-name`, `-l` - Full location name (e.g., "United States")
    * `--location-code` - Numeric location code (e.g., 2840 for USA)
    * `--language`, `-g` - Language code (default: en)
    * `--depth`, `-d` - Number of results (default: 10, max: 700)
    * `--os` - Operating system: windows or macos (default: windows)
    * `--priority`, `-p` - Task priority: 1 (normal) or 2 (high, extra cost)
    * `--tag`, `-t` - User identifier (max 255 chars)
    * `--output`, `-o` - Output JSON file (default: google_news.json)

  ## Examples

      # Basic news search
      mix google_news -k "artificial intelligence" -l "United States" -d 50

      # Search with location code
      mix google_news -k "climate change" --location-code 2840 -d 100

      # macOS user agent
      mix google_news -k "technology news" -l "United States" --os macos

      # High priority task with custom output
      mix google_news -k "breaking news" -l "United States" -p 2 -o breaking_news.json

      # Large result set
      mix google_news -k "politics" --location-code 2840 -d 700

  ## Billing Note

  Your DataForSEO account will be billed per task set, not per result retrieved.
  Default billing accommodates up to 10 results per task cost.
  """

  use Mix.Task

  alias DataForSEO.Schemas.GoogleNewsResult

  @shortdoc "Fetch Google News SERP results from DataForSEO and save to JSON"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _remaining, invalid} =
      OptionParser.parse(args,
        switches: [
          keyword: :string,
          location_name: :string,
          location_code: :integer,
          language: :string,
          depth: :integer,
          os: :string,
          priority: :integer,
          tag: :string,
          output: :string
        ],
        aliases: [
          k: :keyword,
          l: :location_name,
          g: :language,
          d: :depth,
          p: :priority,
          t: :tag,
          o: :output
        ]
      )

    if length(invalid) > 0 do
      Mix.raise("Invalid options: #{inspect(invalid)}")
    end

    task_params = build_task_params(opts)
    validate_params!(task_params)

    display_search_info(task_params, opts)

    start_time = System.monotonic_time(:millisecond)
    result = execute_search(task_params, start_time)
    elapsed_ms = System.monotonic_time(:millisecond) - start_time

    output_path = opts[:output] || "google_news.json"
    save_results(result, task_params, output_path, elapsed_ms)
    display_summary(result, output_path, elapsed_ms)
  end

  @doc """
  Builds task parameters from CLI options.
  """
  @spec build_task_params(keyword()) :: map()
  def build_task_params(opts) do
    %{}
    |> maybe_put(:keyword, opts[:keyword])
    |> maybe_put(:location_name, opts[:location_name])
    |> maybe_put(:location_code, opts[:location_code])
    |> maybe_put(:language_code, opts[:language])
    |> maybe_put(:depth, opts[:depth])
    |> maybe_put(:os, opts[:os])
    |> maybe_put(:priority, opts[:priority])
    |> maybe_put(:tag, opts[:tag])
  end

  @doc """
  Executes the news search and waits for results.
  """
  @spec execute_search(map(), integer()) :: GoogleNewsResult.t()
  def execute_search(task_params, start_time) do
    Mix.shell().info("🔍 Fetching Google News results...")

    ref = make_ref()
    parent = self()
    callback = fn result -> send(parent, {ref, result}) end

    case DataForSEO.Supervisor.start_task(
           DataForSEO.Tasks.GoogleNews,
           task_params,
           callback: callback
         ) do
      {:ok, pid} ->
        Mix.shell().info("⏳ Task created (PID: #{inspect(pid)}), polling for results...")
        wait_for_results(ref, pid, start_time)

      {:error, reason} ->
        Mix.shell().error("✗ Failed to start task: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  @doc """
  Saves news results to JSON file.
  """
  @spec save_results(GoogleNewsResult.t(), map(), String.t(), integer()) :: :ok
  def save_results(result, search_params, output_path, elapsed_ms) do
    Mix.shell().info("💾 Saving to #{output_path}...")

    data = %{
      keyword: result.keyword,
      location_code: result.location_code,
      language_code: result.language_code,
      se_domain: result.se_domain,
      total_news: GoogleNewsResult.news_count(result),
      se_results_count: result.se_results_count,
      fetched_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      elapsed_ms: elapsed_ms,
      search_params: search_params,
      check_url: result.check_url,
      news_items: Enum.map(result.news_items, &struct_to_map/1)
    }

    json = Jason.encode!(data, pretty: true)
    File.write!(output_path, json)

    total = GoogleNewsResult.news_count(result)
    Mix.shell().info("✓ Successfully saved #{total} news articles")
  end

  # Private functions

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp validate_params!(params) do
    unless params[:keyword] do
      Mix.raise("--keyword is required")
    end

    has_location = params[:location_name] || params[:location_code]

    unless has_location do
      Mix.raise("Location required (--location-name or --location-code)")
    end

    :ok
  end

  defp display_search_info(params, opts) do
    Mix.shell().info("\n=== Search Parameters ===")

    Mix.shell().info("Keyword: #{params[:keyword]}")
    display_location(params)

    depth = opts[:depth] || 10
    Mix.shell().info("Depth: #{depth}")
    Mix.shell().info("Language: #{params[:language_code] || "en"}")

    if params[:os] do
      Mix.shell().info("OS: #{params[:os]}")
    end

    if params[:priority] do
      Mix.shell().info("Priority: #{params[:priority]}")
    end

    Mix.shell().info("========================\n")
  end

  defp display_location(params) do
    cond do
      params[:location_name] -> Mix.shell().info("Location: #{params[:location_name]}")
      params[:location_code] -> Mix.shell().info("Location Code: #{params[:location_code]}")
      true -> nil
    end
  end

  defp wait_for_results(ref, pid, start_time) do
    receive do
      {^ref, {:ok, result}} ->
        result

      {^ref, {:error, reason}} ->
        Mix.shell().error("✗ Task failed: #{inspect(reason)}")
        exit({:shutdown, 1})
    after
      5_000 ->
        elapsed_s = div(System.monotonic_time(:millisecond) - start_time, 1000)

        status =
          if Process.alive?(pid) do
            case DataForSEO.TaskManager.get_status(pid) do
              {:ok, state} -> state.status
              _ -> :unknown
            end
          else
            :dead
          end

        Mix.shell().info("⏱️  Elapsed: #{elapsed_s}s, Status: #{status}...")
        wait_for_results(ref, pid, start_time)
    end
  end

  defp display_summary(result, output_path, elapsed_ms) do
    Mix.shell().info("\n=== Summary ===")
    Mix.shell().info("Keyword: #{result.keyword}")
    Mix.shell().info("Total news: #{GoogleNewsResult.news_count(result)}")
    Mix.shell().info("SERP results: #{result.se_results_count || "N/A"}")

    # Show source breakdown
    display_source_breakdown(result)

    # Show recent news
    display_recent_news(result)

    Mix.shell().info("Time elapsed: #{format_elapsed(elapsed_ms)}")
    Mix.shell().info("Output file: #{output_path}")

    # Show sample news items
    if GoogleNewsResult.news_count(result) > 0 do
      display_sample_news(result)
    end

    Mix.shell().info("===============\n")
  end

  defp display_source_breakdown(result) do
    sources =
      result.news_items
      |> Enum.map(&(&1.source || &1.domain))
      |> Enum.reject(&is_nil/1)
      |> Enum.frequencies()

    if map_size(sources) > 0 do
      Mix.shell().info("\nTop Sources:")

      sources
      |> Enum.sort_by(fn {_source, count} -> -count end)
      |> Enum.take(5)
      |> Enum.each(fn {source, count} ->
        Mix.shell().info("  • #{source}: #{count}")
      end)
    end
  end

  defp display_recent_news(result) do
    recent_24h = GoogleNewsResult.recent_news(result, 24)
    recent_count = length(recent_24h)

    if recent_count > 0 do
      Mix.shell().info("\nRecent news (last 24h): #{recent_count}")
    end
  end

  defp display_sample_news(result) do
    Mix.shell().info("\n=== Sample News Articles ===")

    result.news_items
    |> Enum.take(5)
    |> Enum.each(&display_news_item/1)
  end

  defp display_news_item(item) do
    Mix.shell().info("  📰 #{item.title}")

    if item.source || item.domain do
      Mix.shell().info("     Source: #{item.source || item.domain}")
    end

    if item.time_published do
      Mix.shell().info("     Published: #{item.time_published}")
    end

    if item.snippet do
      snippet = truncate_text(item.snippet, 100)
      Mix.shell().info("     #{snippet}")
    end

    Mix.shell().info("")
  end

  defp truncate_text(nil, _max_length), do: ""

  defp truncate_text(text, max_length) do
    if String.length(text) > max_length do
      "#{String.slice(text, 0..max_length)}..."
    else
      text
    end
  end

  defp format_elapsed(ms) when ms < 1_000, do: "#{ms}ms"
  defp format_elapsed(ms), do: "#{Float.round(ms / 1000, 1)}s"

  defp struct_to_map(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> Enum.map(fn {k, v} -> {k, struct_to_map(v)} end)
    |> Map.new()
  end

  defp struct_to_map(value), do: value
end
