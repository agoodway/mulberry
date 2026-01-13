defmodule DataForSEO.Tasks.GoogleNews do
  @moduledoc """
  DataForSEO task implementation for Google News SERP results.

  Fetches news articles from Google News search results for a specific keyword,
  location, and language. This is an async task-based endpoint that requires
  polling for results.

  ## Usage

      {:ok, pid} = DataForSEO.Supervisor.start_task(
        DataForSEO.Tasks.GoogleNews,
        %{
          keyword: "artificial intelligence",
          location_name: "United States",
          language_code: "en",
          depth: 100
        },
        callback: fn {:ok, results} -> IO.inspect(results) end
      )

  With OS specification:

      {:ok, pid} = DataForSEO.Supervisor.start_task(
        DataForSEO.Tasks.GoogleNews,
        %{
          keyword: "climate change",
          location_code: 2840,
          language_code: "en",
          depth: 50,
          os: "macos"
        },
        callback: fn {:ok, results} -> IO.inspect(results) end
      )

  ## Parameters

  Required:
  - `:keyword` - News search term (max 700 chars)

  Location (choose one):
  - `:location_name` - Full location name (e.g., "United States")
  - `:location_code` - Numeric location code (e.g., 2840)

  Language (choose one):
  - `:language_name` - Full language name
  - `:language_code` - Language code (default: "en")

  Optional:
  - `:depth` - Number of results to fetch (default: 10, max: 700)
  - `:os` - Operating system: "windows" (default) or "macos"
  - `:priority` - 1 (normal) or 2 (high priority, additional cost)
  - `:tag` - User identifier (max 255 chars)

  ## Billing

  Your account will be billed per task set, not per result retrieved.
  Default billing accommodates up to 10 results per task cost.

  ## API Documentation

  https://docs.dataforseo.com/v3/serp/google/news/task_post/
  """

  @behaviour DataForSEO.ClientBehaviour

  alias DataForSEO.Schemas.GoogleNewsResult

  @max_depth 700
  @valid_os_values ["windows", "macos"]

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
  def task_type, do: "serp/google/news"

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
        "os" => get_param(params, :os),
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
  @spec parse_task_results(map()) :: {:ok, GoogleNewsResult.t()} | {:error, term()}
  def parse_task_results(response) do
    require Logger
    Logger.debug("GoogleNews parse_task_results response: #{inspect(response)}")

    case response do
      %{"tasks" => [task | _]} ->
        Logger.debug("Task structure: #{inspect(task)}")

        case task do
          %{"result" => [result | _]} ->
            Logger.debug("Result structure: #{inspect(result)}")
            {:ok, GoogleNewsResult.new(result)}

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

      not valid_os?(params) ->
        {:error, {:invalid_params, "os must be one of: #{Enum.join(@valid_os_values, ", ")}"}}

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

  defp valid_os?(params) do
    case get_param(params, :os) do
      nil ->
        true

      os when is_binary(os) ->
        os in @valid_os_values

      _ ->
        false
    end
  end
end
