defmodule DataForSEO.Tasks.GoogleJobs do
  @moduledoc """
  DataForSEO task implementation for Google Jobs SERP results.

  Fetches job listings from Google Jobs search results for a specific keyword,
  location, and language. This is an async task-based endpoint that requires
  polling for results.

  ## Usage

      {:ok, pid} = DataForSEO.Supervisor.start_task(
        DataForSEO.Tasks.GoogleJobs,
        %{
          keyword: "elixir developer",
          location_name: "San Francisco,California,United States",
          language_code: "en",
          depth: 50
        },
        callback: fn {:ok, results} -> IO.inspect(results) end
      )

  With employment type filters:

      {:ok, pid} = DataForSEO.Supervisor.start_task(
        DataForSEO.Tasks.GoogleJobs,
        %{
          keyword: ".net developer",
          location_code: 2840,
          language_code: "en",
          employment_type: ["fulltime", "contractor"],
          depth: 100
        },
        callback: fn {:ok, results} -> IO.inspect(results) end
      )

  ## Parameters

  Required:
  - `:keyword` - Job title or search term (max 700 chars)

  Location (choose one):
  - `:location_name` - Full location name (e.g., "United States")
  - `:location_code` - Numeric location code (e.g., 2840)

  Language (choose one):
  - `:language_name` - Full language name
  - `:language_code` - Language code (default: "en")

  Optional:
  - `:depth` - Number of results to fetch (default: 10, max: 200)
  - `:employment_type` - List of employment types: ["fulltime", "partime", "contractor", "intern"]
  - `:location_radius` - Search radius in kilometers (max: 300)
  - `:priority` - 1 (normal) or 2 (high priority, additional cost)
  - `:tag` - User identifier (max 255 chars)

  ## Billing

  Your account will be billed per task set, not per result retrieved.
  Results are billed per 10-result increment based on depth parameter.

  ## API Documentation

  https://docs.dataforseo.com/v3/serp/google/jobs/task_post/
  """

  @behaviour DataForSEO.ClientBehaviour

  alias DataForSEO.Schemas.GoogleJobsResult

  @max_depth 200
  @max_location_radius 300.0
  @valid_employment_types ["fulltime", "partime", "contractor", "intern"]

  # Private helper functions

  defp get_param(params, key) when is_atom(key) do
    Map.get(params, key) || Map.get(params, Atom.to_string(key))
  end

  defp has_location?(params) do
    location_name = get_param(params, :location_name)
    location_code = get_param(params, :location_code)

    not is_nil(location_name) or not is_nil(location_code)
  end

  defp extract_task_ids(task) do
    case task["result"] do
      results when is_list(results) ->
        Enum.map(results, & &1["id"])

      _ ->
        []
    end
  end

  # Public functions (behaviour callbacks)

  @impl true
  def task_type, do: "serp/google/jobs"

  @impl true
  def result_endpoint, do: "advanced"

  @impl true
  def build_task_payload(params) do
    [
      %{
        "keyword" => get_param(params, :keyword),
        "location_name" => get_param(params, :location_name),
        "location_code" => get_param(params, :location_code),
        "language_name" => get_param(params, :language_name),
        "language_code" => get_param(params, :language_code) || "en",
        "depth" => get_param(params, :depth) || 10,
        "employment_type" => get_param(params, :employment_type),
        "location_radius" => get_param(params, :location_radius),
        "priority" => get_param(params, :priority) || 1,
        "tag" => get_param(params, :tag)
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()
    ]
  end

  @impl true
  def parse_task_response(response) do
    case response do
      %{"tasks" => tasks} when is_list(tasks) ->
        task_ids =
          tasks
          |> Enum.filter(&(&1["status_code"] == 20_100))
          |> Enum.map(& &1["id"])

        if length(task_ids) > 0 do
          {:ok, task_ids}
        else
          errors =
            tasks
            |> Enum.map(& &1["status_message"])
            |> Enum.reject(&is_nil/1)
            |> Enum.join(", ")

          {:error, {:task_creation_failed, errors}}
        end

      _ ->
        {:error, {:invalid_response, "Expected tasks array in response"}}
    end
  end

  @impl true
  def parse_ready_tasks(response) do
    case response do
      %{"tasks" => tasks} when is_list(tasks) ->
        tasks
        |> Enum.filter(&(&1["result_count"] > 0))
        |> Enum.flat_map(&extract_task_ids/1)

      _ ->
        []
    end
  end

  @impl true
  @spec parse_task_results(map()) :: {:ok, GoogleJobsResult.t()} | {:error, term()}
  def parse_task_results(response) do
    require Logger
    Logger.debug("GoogleJobs parse_task_results response: #{inspect(response)}")

    case response do
      %{"tasks" => [task | _]} ->
        Logger.debug("Task structure: #{inspect(task)}")

        case task do
          %{"result" => [result | _]} ->
            Logger.debug("Result structure: #{inspect(result)}")
            {:ok, GoogleJobsResult.new(result)}

          %{"status_message" => message} ->
            {:error, {:task_failed, message}}

          _ ->
            {:error, {:no_results, "Task completed but no results found"}}
        end

      _ ->
        {:error, {:invalid_response, "Expected tasks array in response"}}
    end
  end

  @impl true
  def validate_params(params) when is_map(params) do
    cond do
      is_nil(get_param(params, :keyword)) ->
        {:error, {:invalid_params, "keyword is required"}}

      not has_location?(params) ->
        {:error,
         {:invalid_params, "Location parameter required (location_name or location_code)"}}

      not valid_depth?(params) ->
        {:error, {:invalid_params, "depth must be between 1 and #{@max_depth}"}}

      not valid_employment_type?(params) ->
        {:error,
         {:invalid_params,
          "employment_type must be a list containing only: #{Enum.join(@valid_employment_types, ", ")}"}}

      not valid_location_radius?(params) ->
        {:error, {:invalid_params, "location_radius must be a number <= #{@max_location_radius} km"}}

      true ->
        :ok
    end
  end

  def validate_params(_) do
    {:error, {:invalid_params, "params must be a map"}}
  end

  # Private validation helpers

  defp valid_depth?(params) do
    case get_param(params, :depth) do
      nil -> true
      depth when is_integer(depth) -> depth >= 1 and depth <= @max_depth
      _ -> false
    end
  end

  defp valid_employment_type?(params) do
    case get_param(params, :employment_type) do
      nil ->
        true

      types when is_list(types) ->
        Enum.all?(types, fn type -> type in @valid_employment_types end)

      _ ->
        false
    end
  end

  defp valid_location_radius?(params) do
    case get_param(params, :location_radius) do
      nil ->
        true

      radius when is_number(radius) ->
        radius > 0 and radius <= @max_location_radius

      _ ->
        false
    end
  end
end
