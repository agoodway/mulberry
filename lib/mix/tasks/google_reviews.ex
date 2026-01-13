defmodule Mix.Tasks.GoogleReviews do
  @moduledoc """
  Fetch Google reviews from DataForSEO API and save to JSON file.

  Supports both regular Google reviews and extended reviews (multi-platform).

  ## Usage

      mix google_reviews [options]

  ## Options

    * `--keyword`, `-k` - Business name to search (requires --location)
    * `--cid`, `-c` - Google Customer ID (preferred, from business_listings)
    * `--place-id`, `-p` - Google Place ID
    * `--location`, `-l` - Location for keyword search (name, code, or coordinate)
    * `--depth`, `-n` - Number of reviews to fetch (default: 10, max: 4490 regular / 1000 extended)
    * `--sort-by`, `-s` - Sort order: newest, highest_rating, lowest_rating, relevant (default)
    * `--language`, `-g` - Language code (default: en)
    * `--type`, `-t` - Review type: regular (default) or extended
    * `--output`, `-o` - Output JSON file (default: google_reviews.json)

  ## Examples

      # Fetch reviews using CID from business listing
      mix google_reviews --cid "10179360708466590899" --depth 100 --sort-by newest

      # Fetch reviews by business name
      mix google_reviews -k "Joe's Pizza" -l "New York" -n 50

      # Fetch extended reviews (multi-platform)
      mix google_reviews --cid "12345" --type extended --depth 100 -o extended_reviews.json

      # Fetch reviews using place_id
      mix google_reviews --place-id "ChIJOwg_06VPwokRYv534QaPC8g" --depth 200
  """

  use Mix.Task

  @shortdoc "Fetch Google reviews from DataForSEO and save to JSON"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _remaining, invalid} =
      OptionParser.parse(args,
        switches: [
          keyword: :string,
          cid: :string,
          place_id: :string,
          location: :string,
          depth: :integer,
          sort_by: :string,
          language: :string,
          type: :string,
          output: :string
        ],
        aliases: [
          k: :keyword,
          c: :cid,
          p: :place_id,
          l: :location,
          n: :depth,
          s: :sort_by,
          g: :language,
          t: :type,
          o: :output
        ]
      )

    if length(invalid) > 0 do
      Mix.raise("Invalid options: #{inspect(invalid)}")
    end

    task_params = build_task_params(opts)
    validate_params!(task_params)

    task_module = get_task_module(opts[:type])
    display_search_info(task_params, opts)

    start_time = System.monotonic_time(:millisecond)
    result = execute_search(task_module, task_params, start_time)
    elapsed_ms = System.monotonic_time(:millisecond) - start_time

    output_path = opts[:output] || "google_reviews.json"
    save_results(result, task_params, output_path, elapsed_ms)
    display_summary(result, output_path, elapsed_ms)
  end

  @doc """
  Builds task parameters from CLI options.
  """
  @spec build_task_params(keyword()) :: map()
  def build_task_params(opts) do
    params =
      %{}
      |> maybe_put(:keyword, opts[:keyword])
      |> maybe_put(:cid, opts[:cid])
      |> maybe_put(:place_id, opts[:place_id])
      |> maybe_put(:depth, opts[:depth])
      |> maybe_put(:sort_by, opts[:sort_by])
      |> maybe_put(:language_code, opts[:language])

    # Add location if provided, or use default for CID/place_id
    cond do
      opts[:location] ->
        Map.put(params, :location_name, opts[:location])

      opts[:cid] || opts[:place_id] ->
        # CID and place_id still require a location parameter per DataForSEO API
        # Use a default location code that covers United States
        Map.put(params, :location_code, 2840)

      true ->
        params
    end
  end

  @doc """
  Executes the reviews search and waits for results.
  """
  @spec execute_search(module(), map(), integer()) :: DataForSEO.Schemas.GoogleReviewsResult.t()
  def execute_search(task_module, task_params, start_time) do
    Mix.shell().info("🔍 Fetching Google reviews...")

    ref = make_ref()
    parent = self()
    callback = fn result -> send(parent, {ref, result}) end

    case DataForSEO.Supervisor.start_task(task_module, task_params, callback: callback) do
      {:ok, pid} ->
        Mix.shell().info("⏳ Task created (PID: #{inspect(pid)}), polling for results...")
        wait_for_results(ref, pid, start_time)

      {:error, reason} ->
        Mix.shell().error("✗ Failed to start task: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  @doc """
  Saves reviews results to JSON file.
  """
  @spec save_results(DataForSEO.Schemas.GoogleReviewsResult.t(), map(), String.t(), integer()) ::
          :ok
  def save_results(result, search_params, output_path, elapsed_ms) do
    Mix.shell().info("💾 Saving to #{output_path}...")

    data = %{
      keyword: result.keyword,
      cid: result.cid,
      place_id: result.place_id,
      title: result.title,
      rating: result.rating,
      reviews_count: result.reviews_count,
      fetched_count: length(result.reviews),
      fetched_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      elapsed_ms: elapsed_ms,
      search_params: search_params,
      reviews: Enum.map(result.reviews, &struct_to_map/1)
    }

    json = Jason.encode!(data, pretty: true)
    File.write!(output_path, json)

    Mix.shell().info("✓ Successfully saved #{length(result.reviews)} reviews")
  end

  # Private functions

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp get_task_module(type) do
    case type do
      "extended" -> DataForSEO.Tasks.ExtendedGoogleReviews
      _ -> DataForSEO.Tasks.GoogleReviews
    end
  end

  defp validate_params!(params) do
    has_identifier = params[:keyword] || params[:cid] || params[:place_id]

    unless has_identifier do
      Mix.raise("At least one business identifier required (--keyword, --cid, or --place-id)")
    end

    # Keyword requires explicit location
    if params[:keyword] && !params[:location_name] && !params[:location_code] &&
         !params[:location_coordinate] do
      Mix.raise("--location required when using --keyword")
    end

    :ok
  end

  defp display_search_info(params, opts) do
    Mix.shell().info("\n=== Search Parameters ===")

    display_identifier(params)
    display_location(params)

    depth = opts[:depth] || default_depth(opts[:type])
    Mix.shell().info("Depth: #{depth}")

    if params[:sort_by], do: Mix.shell().info("Sort by: #{params[:sort_by]}")

    type = if opts[:type] == "extended", do: "Extended (multi-platform)", else: "Regular"
    Mix.shell().info("Type: #{type}")

    Mix.shell().info("========================\n")
  end

  defp display_identifier(params) do
    cond do
      params[:cid] -> Mix.shell().info("CID: #{params[:cid]}")
      params[:place_id] -> Mix.shell().info("Place ID: #{params[:place_id]}")
      params[:keyword] -> Mix.shell().info("Keyword: #{params[:keyword]}")
    end
  end

  defp display_location(params) do
    cond do
      params[:location_name] ->
        Mix.shell().info("Location: #{params[:location_name]}")

      params[:location_code] ->
        Mix.shell().info("Location Code: #{params[:location_code]}")

      params[:location_coordinate] ->
        Mix.shell().info("Location Coordinate: #{params[:location_coordinate]}")

      true ->
        nil
    end
  end

  defp default_depth("extended"), do: 20
  defp default_depth(_), do: 10

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
    Mix.shell().info("Business: #{result.title}")

    if result.rating do
      rating_val = result.rating["value"]
      votes = result.rating["votes_count"]
      Mix.shell().info("Overall Rating: #{rating_val}/5 (#{votes} total reviews)")
    end

    Mix.shell().info("Total reviews available: #{result.reviews_count}")
    Mix.shell().info("Fetched: #{length(result.reviews)}")
    Mix.shell().info("Time elapsed: #{format_elapsed(elapsed_ms)}")
    Mix.shell().info("Output file: #{output_path}")

    # Show recent reviews summary
    if length(result.reviews) > 0 do
      display_recent_reviews(result.reviews)
    end

    Mix.shell().info("===============\n")
  end

  defp display_recent_reviews(reviews) do
    Mix.shell().info("\n=== Recent Reviews ===")

    reviews
    |> Enum.take(3)
    |> Enum.each(fn review ->
      rating = review.rating["value"] || "N/A"
      name = review.profile_name || "Anonymous"
      text = String.slice(review.review_text || "", 0..80)
      text = if String.length(review.review_text || "") > 80, do: "#{text}...", else: text

      Mix.shell().info("  ⭐ #{rating}/5 - #{name}")
      Mix.shell().info("     \"#{text}\"")
    end)
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
