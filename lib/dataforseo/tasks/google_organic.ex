defmodule DataForSEO.Tasks.GoogleOrganic do
  @moduledoc """
  DataForSEO task implementation for Google Organic SERP results.

  Fetches organic search results and People Also Ask questions from Google search
  for a specific keyword, location, and language. This is an async task-based endpoint
  that requires polling for results.

  ## Usage

      {:ok, pid} = DataForSEO.Supervisor.start_task(
        DataForSEO.Tasks.GoogleOrganic,
        %{
          keyword: "elixir programming",
          location_name: "United States",
          language_code: "en",
          depth: 100
        },
        callback: fn {:ok, results} -> IO.inspect(results) end
      )

  With device and OS specification:

      {:ok, pid} = DataForSEO.Supervisor.start_task(
        DataForSEO.Tasks.GoogleOrganic,
        %{
          keyword: "functional programming",
          location_code: 2840,
          language_code: "en",
          depth: 50,
          device: "mobile",
          os: "android"
        },
        callback: fn {:ok, results} -> IO.inspect(results) end
      )

  ## Parameters

  Required:
  - `:keyword` - Search term (max 700 chars)

  Location (choose one):
  - `:location_name` - Full location name (e.g., "United States")
  - `:location_code` - Numeric location code (e.g., 2840)

  Language (choose one):
  - `:language_name` - Full language name
  - `:language_code` - Language code (default: "en")

  Optional:
  - `:depth` - Number of results to fetch (default: 10, max: 700)
  - `:device` - Device type: "desktop" (default) or "mobile"
  - `:os` - Operating system (depends on device, see validation)
  - `:priority` - 1 (normal) or 2 (high priority, additional cost)
  - `:tag` - User identifier (max 255 chars)

  ## Device and OS Combinations

  - Desktop device: `os` can be "windows" or "macos"
  - Mobile device: `os` can be "android" or "ios"

  ## Billing

  Your account will be billed per task set, not per result retrieved.
  Default billing accommodates up to 10 results per task cost.

  ## API Documentation

  https://docs.dataforseo.com/v3/serp/google/organic/task_post/
  """

  @behaviour DataForSEO.ClientBehaviour

  alias DataForSEO.Schemas.GoogleOrganicResult

  @max_depth 700
  @valid_devices ["desktop", "mobile"]
  @valid_desktop_os ["windows", "macos"]
  @valid_mobile_os ["android", "ios"]

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
  def task_type, do: "serp/google/organic"

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
        "device" => get_param(params, :device),
        "os" => get_param(params, :os),
        "depth" => get_param(params, :depth) || 10,
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
  @spec parse_task_results(map()) :: {:ok, GoogleOrganicResult.t()} | {:error, term()}
  def parse_task_results(response) do
    require Logger
    Logger.debug("GoogleOrganic parse_task_results response: #{inspect(response)}")

    case response do
      %{"tasks" => [task | _]} ->
        Logger.debug("Task structure: #{inspect(task)}")

        case task do
          %{"result" => [result | _]} ->
            Logger.debug("Result structure: #{inspect(result)}")
            {:ok, GoogleOrganicResult.new(result)}

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

      not valid_device?(params) ->
        {:error,
         {:invalid_params, "device must be one of: #{Enum.join(@valid_devices, ", ")}"}}

      not valid_os_for_device?(params) ->
        device = get_param(params, :device) || "desktop"
        os_list = if device == "desktop", do: @valid_desktop_os, else: @valid_mobile_os

        {:error,
         {:invalid_params,
          "os must be one of: #{Enum.join(os_list, ", ")} for #{device} device"}}

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

  defp valid_device?(params) do
    case get_param(params, :device) do
      nil -> true
      device when is_binary(device) -> device in @valid_devices
      _ -> false
    end
  end

  defp valid_os_for_device?(params) do
    device = get_param(params, :device)
    os = get_param(params, :os)

    case {device, os} do
      {nil, nil} -> true
      {nil, _os} -> true
      {_device, nil} -> true
      {"desktop", os} when is_binary(os) -> os in @valid_desktop_os
      {"mobile", os} when is_binary(os) -> os in @valid_mobile_os
      _ -> false
    end
  end
end
