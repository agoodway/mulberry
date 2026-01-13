defmodule Mix.Tasks.BusinessListings do
  @moduledoc """
  Fetch business listings from DataForSEO API and save to JSON file.

  This task allows you to search for businesses on Google Maps using various
  criteria like categories, location, ratings, and more. Results are saved
  as pretty-printed JSON with detailed progress feedback.

  ## Usage

      mix business_listings [options]

  ## Options

    * `--categories`, `-c` - Comma-separated category IDs (e.g., "pizza_restaurant,italian_restaurant")
    * `--location`, `-l` - Location coordinate in format "latitude,longitude,radius_km" (e.g., "40.7128,-74.0060,5")
    * `--title`, `-t` - Business title/name to search for (max 200 chars)
    * `--description`, `-d` - Business description to search for (max 200 chars)
    * `--claimed` - Only include Google Maps verified businesses (flag, no value needed)
    * `--filters`, `-f` - Filter condition in format "field,operator,value" (can be repeated)
    * `--order-by`, `-s` - Sort rule in format "field,direction" (can be repeated, max 3)
    * `--limit`, `-n` - Maximum number of results (default: 100, max: 1000)
    * `--offset` - Pagination offset for results
    * `--output`, `-o` - Output JSON file path (default: business_listings.json)

  ## Examples

      # Search for pizza restaurants in NYC (5km radius)
      mix business_listings -c pizza_restaurant -l "40.7128,-74.0060,5" -o nyc_pizza.json

      # High-rated restaurants in LA with filters
      mix business_listings \\
        -c restaurant \\
        -l "34.0522,-118.2437,10" \\
        -f "rating.value,>,4.5" \\
        -f "rating.votes_count,>,100" \\
        -s "rating.value,desc" \\
        -n 50

      # Search by business name in Seattle
      mix business_listings -t "Starbucks" -l "47.6062,-122.3321,20" --claimed

      # Multiple categories with ordering
      mix business_listings \\
        -c "pizza_restaurant,italian_restaurant" \\
        -l "41.8781,-87.6298,8" \\
        -s "rating.value,desc" \\
        -s "rating.votes_count,desc" \\
        -n 200

  ## Filter Operators

  Valid operators for --filters:
    * `<`, `<=`, `>`, `>=` - Numeric comparisons
    * `=`, `!=` - Equality checks
    * `like`, `not_like` - Pattern matching
    * `regex`, `not_regex` - Regular expression matching

  ## Output Format

  The output JSON file contains:
    * `total_count` - Total number of matching businesses
    * `fetched_count` - Number of businesses in this result
    * `fetched_at` - ISO 8601 timestamp of when data was fetched
    * `search_params` - The search parameters used
    * `items` - Array of business listing objects with full details

  ## Business Listing Fields

  Each business listing includes:
    * Basic info: title, description, category, category_ids
    * Contact: phone, url, domain, address, address_info
    * Location: latitude, longitude, place_id, cid
    * Ratings: rating (value, votes_count), rating_distribution
    * Media: logo, main_image, total_photos
    * Operations: work_time, popular_times
    * Verification: is_claimed
    * Metadata: last_updated_time, first_seen
  """

  use Mix.Task

  @shortdoc "Fetch business listings from DataForSEO and save to JSON"

  @impl Mix.Task
  def run(args) do
    # Start the application to ensure all dependencies are available
    Mix.Task.run("app.start")

    # Parse command-line options
    {opts, _remaining_args, invalid} =
      OptionParser.parse(args,
        switches: [
          categories: :string,
          location: :string,
          title: :string,
          description: :string,
          claimed: :boolean,
          filters: :keep,
          order_by: :keep,
          limit: :integer,
          offset: :integer,
          output: :string
        ],
        aliases: [
          c: :categories,
          l: :location,
          t: :title,
          d: :description,
          f: :filters,
          s: :order_by,
          n: :limit,
          o: :output
        ]
      )

    # Check for invalid options
    if length(invalid) > 0 do
      Mix.raise("Invalid options: #{inspect(invalid)}")
    end

    # Build task parameters from options
    task_params = build_task_params(opts)

    # Validate that we have at least some search criteria
    validate_params!(task_params)

    # Display search info
    display_search_info(task_params, opts)

    # Execute the search
    start_time = System.monotonic_time(:millisecond)
    result = execute_search(task_params, start_time)
    elapsed_ms = System.monotonic_time(:millisecond) - start_time

    # Save results to file
    output_path = opts[:output] || "business_listings.json"
    save_results(result, task_params, output_path, elapsed_ms)

    # Display summary
    display_summary(result, output_path, elapsed_ms)
  end

  @doc """
  Builds DataForSEO task parameters from parsed command-line options.
  """
  @spec build_task_params(keyword()) :: map()
  def build_task_params(opts) do
    params = %{}

    # Handle categories (comma-separated)
    params =
      if opts[:categories] do
        categories =
          opts[:categories]
          |> String.split(",")
          |> Enum.map(&String.trim/1)

        Map.put(params, :categories, categories)
      else
        params
      end

    # Handle location coordinate
    params =
      if opts[:location] do
        Map.put(params, :location_coordinate, opts[:location])
      else
        params
      end

    # Handle simple string fields
    params =
      params
      |> maybe_put(:title, opts[:title])
      |> maybe_put(:description, opts[:description])

    # Handle claimed flag
    params =
      if opts[:claimed] do
        Map.put(params, :is_claimed, true)
      else
        params
      end

    # Handle filters (can be repeated)
    params =
      case Keyword.get_values(opts, :filters) do
        [] ->
          params

        filters ->
          parsed_filters = Enum.map(filters, &parse_filter/1)
          Map.put(params, :filters, parsed_filters)
      end

    # Handle order_by (can be repeated)
    params =
      case Keyword.get_values(opts, :order_by) do
        [] ->
          params

        order_by ->
          parsed_order_by = Enum.map(order_by, &parse_order_by/1)
          Map.put(params, :order_by, parsed_order_by)
      end

    # Handle numeric fields
    params =
      params
      |> maybe_put(:limit, opts[:limit])
      |> maybe_put(:offset, opts[:offset])

    params
  end

  @doc """
  Executes the business listings search and waits for results.
  """
  @spec execute_search(map(), integer()) ::
          DataForSEO.Schemas.BusinessListingsResult.t() | no_return()
  def execute_search(task_params, start_time) do
    Mix.shell().info("🔍 Fetching business listings...")

    # Use a ref to capture callback result
    ref = make_ref()
    parent = self()

    callback = fn result ->
      send(parent, {ref, result})
    end

    # Start the DataForSEO task
    case DataForSEO.Supervisor.start_task(
           DataForSEO.Tasks.BusinessListings,
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
  Saves the business listings results to a JSON file.
  """
  @spec save_results(
          DataForSEO.Schemas.BusinessListingsResult.t(),
          map(),
          String.t(),
          integer()
        ) :: :ok
  def save_results(result, search_params, output_path, elapsed_ms) do
    Mix.shell().info("💾 Saving to #{output_path}...")

    # Build JSON structure
    data = %{
      total_count: result.total_count,
      fetched_count: length(result.items),
      fetched_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      elapsed_ms: elapsed_ms,
      search_params: search_params,
      items: Enum.map(result.items, &struct_to_map/1)
    }

    # Write pretty-printed JSON
    json = Jason.encode!(data, pretty: true)
    File.write!(output_path, json)

    Mix.shell().info("✓ Successfully saved #{length(result.items)} listings")
  end

  # Private functions

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp parse_filter(filter_str) do
    case String.split(filter_str, ",") do
      [field, operator, value] ->
        [String.trim(field), String.trim(operator), parse_value(value)]

      _ ->
        Mix.raise("Invalid filter format: #{filter_str}. Expected format: 'field,operator,value'")
    end
  end

  defp parse_order_by(order_str) do
    case String.split(order_str, ",") do
      [field, direction] ->
        [String.trim(field), String.trim(direction)]

      _ ->
        Mix.raise("Invalid order_by format: #{order_str}. Expected format: 'field,direction'")
    end
  end

  defp parse_value(value_str) do
    trimmed = String.trim(value_str)

    cond do
      trimmed == "true" -> true
      trimmed == "false" -> false
      String.match?(trimmed, ~r/^-?\d+$/) -> String.to_integer(trimmed)
      String.match?(trimmed, ~r/^-?\d+\.\d+$/) -> String.to_float(trimmed)
      true -> trimmed
    end
  end

  defp validate_params!(params) do
    if map_size(params) == 0 do
      Mix.raise(
        "At least one search parameter is required (categories, location, title, or description)"
      )
    end

    :ok
  end

  defp display_search_info(params, opts) do
    Mix.shell().info("\n=== Search Parameters ===")

    if params[:categories] do
      Mix.shell().info("Categories: #{Enum.join(params[:categories], ", ")}")
    end

    if params[:location_coordinate] do
      Mix.shell().info("Location: #{params[:location_coordinate]}")
    end

    if params[:title] do
      Mix.shell().info("Title: #{params[:title]}")
    end

    if params[:filters] do
      Mix.shell().info("Filters: #{length(params[:filters])} condition(s)")
    end

    if params[:order_by] do
      Mix.shell().info("Order by: #{length(params[:order_by])} rule(s)")
    end

    limit = opts[:limit] || 100
    Mix.shell().info("Limit: #{limit}")
    Mix.shell().info("========================\n")
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
        # Show progress update every 5 seconds
        elapsed_s = div(System.monotonic_time(:millisecond) - start_time, 1000)

        status =
          case Process.alive?(pid) do
            true ->
              case DataForSEO.TaskManager.get_status(pid) do
                {:ok, state} -> state.status
                _ -> :unknown
              end

            false ->
              :dead
          end

        Mix.shell().info("⏱️  Elapsed: #{elapsed_s}s, Status: #{status}...")
        wait_for_results(ref, pid, start_time)
    end
  end

  defp display_summary(result, output_path, elapsed_ms) do
    Mix.shell().info("\n=== Summary ===")
    Mix.shell().info("Total matching businesses: #{result.total_count}")
    Mix.shell().info("Fetched: #{length(result.items)}")
    Mix.shell().info("Time elapsed: #{format_elapsed(elapsed_ms)}")
    Mix.shell().info("Output file: #{output_path}")

    # Show top-rated businesses if any
    display_top_rated(result.items)

    Mix.shell().info("===============\n")
  end

  defp display_top_rated([]), do: :ok

  defp display_top_rated(items) do
    top_rated =
      items
      |> Enum.filter(fn item -> item.rating != nil end)
      |> Enum.sort_by(fn item -> item.rating["value"] || 0 end, :desc)
      |> Enum.take(3)

    if length(top_rated) > 0 do
      Mix.shell().info("\n=== Top Rated ===")

      Enum.each(top_rated, fn item ->
        rating = item.rating["value"]
        votes = item.rating["votes_count"]
        Mix.shell().info("  ⭐ #{rating}/5 (#{votes} reviews) - #{item.title}")
      end)
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
