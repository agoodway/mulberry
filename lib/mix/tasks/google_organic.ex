defmodule Mix.Tasks.GoogleOrganic do
  @moduledoc """
  Fetch Google Organic SERP results from DataForSEO API and save to JSON file.

  Retrieves organic search results and People Also Ask questions from Google search
  for a specific keyword, location, and language.

  ## Usage

      mix google_organic [options]

  ## Options

    * `--keyword`, `-k` - Search term (required, max 700 chars)
    * `--location-name`, `-l` - Full location name (e.g., "United States")
    * `--location-code` - Numeric location code (e.g., 2840 for USA)
    * `--language`, `-g` - Language code (default: en)
    * `--depth`, `-d` - Number of results (default: 10, max: 700)
    * `--device` - Device type: desktop (default) or mobile
    * `--os` - Operating system (desktop: windows/macos, mobile: android/ios)
    * `--priority`, `-p` - Task priority: 1 (normal) or 2 (high, extra cost)
    * `--tag`, `-t` - User identifier (max 255 chars)
    * `--output`, `-o` - Output JSON file (default: google_organic.json)

  ## Examples

      # Basic organic search
      mix google_organic -k "elixir programming" -l "United States" -d 50

      # Search with location code
      mix google_organic -k "functional programming" --location-code 2840 -d 100

      # Mobile search with Android
      mix google_organic -k "best smartphones" -l "United States" --device mobile --os android

      # Desktop search with macOS
      mix google_organic -k "web development" -l "United States" --device desktop --os macos

      # High priority task with custom output
      mix google_organic -k "breaking news" -l "United States" -p 2 -o search_results.json

      # Large result set
      mix google_organic -k "climate change" --location-code 2840 -d 700

  ## Billing Note

  Your DataForSEO account will be billed per task set, not per result retrieved.
  Default billing accommodates up to 10 results per task cost.
  """

  use Mix.Task

  alias DataForSEO.Schemas.GoogleOrganicResult

  @shortdoc "Fetch Google Organic SERP results from DataForSEO and save to JSON"

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
          device: :string,
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

    output_path = opts[:output] || "google_organic.json"
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
    |> maybe_put(:device, opts[:device])
    |> maybe_put(:os, opts[:os])
    |> maybe_put(:priority, opts[:priority])
    |> maybe_put(:tag, opts[:tag])
  end

  @doc """
  Executes the organic search and waits for results.
  """
  @spec execute_search(map(), integer()) :: GoogleOrganicResult.t()
  def execute_search(task_params, start_time) do
    Mix.shell().info("🔍 Fetching Google Organic SERP results...")

    ref = make_ref()
    parent = self()
    callback = fn result -> send(parent, {ref, result}) end

    case DataForSEO.Supervisor.start_task(
           DataForSEO.Tasks.GoogleOrganic,
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
  Saves organic search results to JSON file.
  """
  @spec save_results(GoogleOrganicResult.t(), map(), String.t(), integer()) :: :ok
  def save_results(result, search_params, output_path, elapsed_ms) do
    Mix.shell().info("💾 Saving to #{output_path}...")

    data = %{
      keyword: result.keyword,
      location_code: result.location_code,
      language_code: result.language_code,
      se_domain: result.se_domain,
      total_organic_results: GoogleOrganicResult.organic_result_count(result),
      total_people_also_ask: GoogleOrganicResult.people_also_ask_count(result),
      se_results_count: result.se_results_count,
      fetched_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      elapsed_ms: elapsed_ms,
      search_params: search_params,
      check_url: result.check_url,
      organic_items: Enum.map(result.organic_items, &struct_to_map/1),
      people_also_ask: result.people_also_ask
    }

    json = Jason.encode!(data, pretty: true)
    File.write!(output_path, json)

    total_organic = GoogleOrganicResult.organic_result_count(result)
    total_paa = GoogleOrganicResult.people_also_ask_count(result)

    Mix.shell().info(
      "✓ Successfully saved #{total_organic} organic results and #{total_paa} PAA questions"
    )
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

    device = params[:device] || "desktop"
    Mix.shell().info("Device: #{device}")

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
    Mix.shell().info("Organic results: #{GoogleOrganicResult.organic_result_count(result)}")
    Mix.shell().info("People Also Ask: #{GoogleOrganicResult.people_also_ask_count(result)}")
    Mix.shell().info("SERP results: #{result.se_results_count || "N/A"}")

    # Show domain breakdown
    display_domain_breakdown(result)

    # Show results with rich features
    display_rich_features(result)

    # Show People Also Ask sample
    display_people_also_ask_sample(result)

    Mix.shell().info("Time elapsed: #{format_elapsed(elapsed_ms)}")
    Mix.shell().info("Output file: #{output_path}")

    # Show sample organic results
    if GoogleOrganicResult.organic_result_count(result) > 0 do
      display_sample_results(result)
    end

    Mix.shell().info("===============\n")
  end

  defp display_domain_breakdown(result) do
    top_domains = GoogleOrganicResult.top_domains(result, 5)

    if length(top_domains) > 0 do
      Mix.shell().info("\nTop Domains:")

      Enum.each(top_domains, fn {domain, count} ->
        Mix.shell().info("  • #{domain}: #{count}")
      end)
    end
  end

  defp display_rich_features(result) do
    with_ratings = GoogleOrganicResult.filter_with_ratings(result)
    with_sitelinks = GoogleOrganicResult.filter_with_sitelinks(result)

    if length(with_ratings) > 0 || length(with_sitelinks) > 0 do
      Mix.shell().info("\nRich Features:")

      if length(with_ratings) > 0 do
        Mix.shell().info("  • Results with ratings: #{length(with_ratings)}")
      end

      if length(with_sitelinks) > 0 do
        Mix.shell().info("  • Results with sitelinks: #{length(with_sitelinks)}")
      end
    end
  end

  defp display_people_also_ask_sample(result) do
    questions = GoogleOrganicResult.extract_people_also_ask_questions(result)

    if length(questions) > 0 do
      Mix.shell().info("\n=== People Also Ask (Sample) ===")

      questions
      |> Enum.take(3)
      |> Enum.each(&display_paa_question/1)
    end
  end

  defp display_paa_question(question) do
    Mix.shell().info("  ❓ #{question.question}")

    if question.answer do
      answer = truncate_text(question.answer, 100)
      Mix.shell().info("     Answer: #{answer}")
    end

    if question.domain do
      Mix.shell().info("     Source: #{question.domain}")
    end

    Mix.shell().info("")
  end

  defp display_sample_results(result) do
    Mix.shell().info("\n=== Sample Organic Results ===")

    result.organic_items
    |> Enum.take(5)
    |> Enum.each(&display_organic_item/1)
  end

  defp display_organic_item(item) do
    position = item.position || item.rank_absolute
    Mix.shell().info("  #{position}. #{item.title}")

    if item.domain do
      Mix.shell().info("     Domain: #{item.domain}")
    end

    if item.description do
      snippet = truncate_text(item.description, 100)
      Mix.shell().info("     #{snippet}")
    end

    if item.rating do
      Mix.shell().info("     ⭐ Rating: #{item.rating.value || "N/A"}")
    end

    if length(item.sitelinks) > 0 do
      Mix.shell().info("     🔗 Sitelinks: #{length(item.sitelinks)}")
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
