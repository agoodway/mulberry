defmodule Mix.Tasks.GoogleJobs do
  @moduledoc """
  Fetch Google Jobs SERP results from DataForSEO API and save to JSON file.

  Retrieves job listings from Google Jobs search results for a specific keyword,
  location, and language.

  ## Usage

      mix google_jobs [options]

  ## Options

    * `--keyword`, `-k` - Job title or search term (required, max 700 chars)
    * `--location-name`, `-l` - Full location name (e.g., "United States")
    * `--location-code` - Numeric location code (e.g., 2840 for USA)
    * `--language`, `-g` - Language code (default: en)
    * `--depth`, `-d` - Number of results to fetch (default: 10, max: 200)
    * `--employment-type`, `-e` - Employment types (comma-separated: fulltime,partime,contractor,intern)
    * `--location-radius`, `-r` - Search radius in kilometers (max: 300)
    * `--priority`, `-p` - Task priority: 1 (normal) or 2 (high, extra cost)
    * `--tag`, `-t` - User identifier (max 255 chars)
    * `--output`, `-o` - Output JSON file (default: google_jobs.json)

  ## Examples

      # Basic job search
      mix google_jobs -k "elixir developer" -l "San Francisco,California,United States" -d 50

      # Search with employment type filters
      mix google_jobs -k ".net developer" --location-code 2840 -e fulltime,contractor

      # Search with location radius
      mix google_jobs -k "software engineer" -l "New York,NY,United States" -r 50 -d 100

      # High priority task
      mix google_jobs -k "data scientist" -l "United States" -p 2 -o data_scientist_jobs.json

  ## Billing Note

  Your DataForSEO account will be billed per task set, not per result retrieved.
  Results are billed per 10-result increment based on the depth parameter.
  """

  use Mix.Task

  alias DataForSEO.Schemas.GoogleJobsResult

  @shortdoc "Fetch Google Jobs SERP results from DataForSEO and save to JSON"

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
          employment_type: :string,
          location_radius: :float,
          priority: :integer,
          tag: :string,
          output: :string
        ],
        aliases: [
          k: :keyword,
          l: :location_name,
          g: :language,
          d: :depth,
          e: :employment_type,
          r: :location_radius,
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

    output_path = opts[:output] || "google_jobs.json"
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
    |> maybe_put(:employment_type, parse_employment_type(opts[:employment_type]))
    |> maybe_put(:location_radius, opts[:location_radius])
    |> maybe_put(:priority, opts[:priority])
    |> maybe_put(:tag, opts[:tag])
  end

  @doc """
  Executes the jobs search and waits for results.
  """
  @spec execute_search(map(), integer()) :: GoogleJobsResult.t()
  def execute_search(task_params, start_time) do
    Mix.shell().info("🔍 Fetching Google Jobs results...")

    ref = make_ref()
    parent = self()
    callback = fn result -> send(parent, {ref, result}) end

    case DataForSEO.Supervisor.start_task(
           DataForSEO.Tasks.GoogleJobs,
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
  Saves jobs results to JSON file.
  """
  @spec save_results(GoogleJobsResult.t(), map(), String.t(), integer()) :: :ok
  def save_results(result, search_params, output_path, elapsed_ms) do
    Mix.shell().info("💾 Saving to #{output_path}...")

    data = %{
      keyword: result.keyword,
      location_code: result.location_code,
      language_code: result.language_code,
      se_domain: result.se_domain,
      total_jobs: GoogleJobsResult.job_count(result),
      fetched_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      elapsed_ms: elapsed_ms,
      search_params: search_params,
      check_url: result.check_url,
      jobs: Enum.map(result.jobs, &struct_to_map/1)
    }

    json = Jason.encode!(data, pretty: true)
    File.write!(output_path, json)

    total = GoogleJobsResult.job_count(result)
    Mix.shell().info("✓ Successfully saved #{total} jobs")
  end

  # Private functions

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp parse_employment_type(nil), do: nil

  defp parse_employment_type(type_string) when is_binary(type_string) do
    type_string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

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

    if params[:employment_type] do
      Mix.shell().info("Employment Types: #{Enum.join(params[:employment_type], ", ")}")
    end

    if params[:location_radius] do
      Mix.shell().info("Location Radius: #{params[:location_radius]} km")
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
    Mix.shell().info("Total jobs: #{GoogleJobsResult.job_count(result)}")

    # Show contract type breakdown
    display_contract_breakdown(result)

    # Show employer breakdown (top 5)
    display_employer_breakdown(result)

    Mix.shell().info("Time elapsed: #{format_elapsed(elapsed_ms)}")
    Mix.shell().info("Output file: #{output_path}")

    # Show recent jobs summary
    if GoogleJobsResult.job_count(result) > 0 do
      display_recent_jobs(result)
    end

    Mix.shell().info("===============\n")
  end

  defp display_contract_breakdown(result) do
    contract_types =
      result.jobs
      |> Enum.map(& &1.contract_type)
      |> Enum.reject(&is_nil/1)
      |> Enum.frequencies()

    if map_size(contract_types) > 0 do
      Mix.shell().info("\nContract Types:")

      contract_types
      |> Enum.sort_by(fn {_type, count} -> -count end)
      |> Enum.each(fn {type, count} ->
        Mix.shell().info("  • #{type}: #{count}")
      end)
    end
  end

  defp display_employer_breakdown(result) do
    employers =
      result.jobs
      |> Enum.map(& &1.employer_name)
      |> Enum.reject(&is_nil/1)
      |> Enum.frequencies()

    if map_size(employers) > 0 do
      Mix.shell().info("\nTop Employers:")

      employers
      |> Enum.sort_by(fn {_employer, count} -> -count end)
      |> Enum.take(5)
      |> Enum.each(fn {employer, count} ->
        Mix.shell().info("  • #{employer}: #{count} job(s)")
      end)
    end
  end

  defp display_recent_jobs(result) do
    Mix.shell().info("\n=== Recent Job Listings ===")

    result.jobs
    |> Enum.take(5)
    |> Enum.each(&display_job/1)
  end

  defp display_job(job) do
    Mix.shell().info("  💼 #{job.title}")

    if job.employer_name do
      Mix.shell().info("     Company: #{job.employer_name}")
    end

    if job.location do
      Mix.shell().info("     Location: #{job.location}")
    end

    if job.contract_type do
      Mix.shell().info("     Type: #{job.contract_type}")
    end

    if job.salary do
      Mix.shell().info("     Salary: #{job.salary}")
    end

    Mix.shell().info("")
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
