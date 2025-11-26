defmodule DataForSEO.Tasks.GoogleQuestions do
  @moduledoc """
  DataForSEO task implementation for Google Questions and Answers.

  Fetches questions and answers from Google My Business for a specific business.
  This is an async task-based endpoint that requires polling for results.

  ## Usage

      {:ok, pid} = DataForSEO.Supervisor.start_task(
        DataForSEO.Tasks.GoogleQuestions,
        %{
          keyword: "The Last Bookstore",
          location_name: "Los Angeles,California,United States",
          language_code: "en",
          depth: 20
        },
        callback: fn {:ok, results} -> IO.inspect(results) end
      )

  Or using CID (Customer ID):

      {:ok, pid} = DataForSEO.Supervisor.start_task(
        DataForSEO.Tasks.GoogleQuestions,
        %{
          cid: "10179360708466590899",
          language_code: "en"
        },
        callback: fn {:ok, results} -> IO.inspect(results) end
      )

  ## Parameters

  Business identifier (choose one):
  - `:keyword` - Business name (max 700 chars)
  - `:cid` - Google Customer ID (recommended, includes implicit location)
  - `:place_id` - Google Place ID

  Location (required if using keyword):
  - `:location_name` - Full location name
  - `:location_code` - Numeric location code
  - `:location_coordinate` - "latitude,longitude,radius" format

  Language (choose one):
  - `:language_name` - Full language name
  - `:language_code` - Language code (default: "en")

  Optional:
  - `:depth` - Number of questions to fetch (default: 20, max: 700)
  - `:priority` - 1 (normal) or 2 (high priority, additional cost)
  - `:tag` - User identifier (max 255 chars)

  ## Billing

  Your account will be billed for every 20 questions. The maximum number of
  answers returned for each question is 5.

  ## API Documentation

  https://docs.dataforseo.com/v3/business_data/google/questions_and_answers/task_post/
  """

  @behaviour DataForSEO.ClientBehaviour

  alias DataForSEO.Schemas.GoogleQuestionsResult

  @max_depth 700

  # Private helper functions

  defp get_param(params, key) when is_atom(key) do
    Map.get(params, key) || Map.get(params, Atom.to_string(key))
  end

  defp has_business_identifier?(params) do
    keyword = get_param(params, :keyword)
    cid = get_param(params, :cid)
    place_id = get_param(params, :place_id)

    not is_nil(keyword) or not is_nil(cid) or not is_nil(place_id)
  end

  defp has_location?(params) do
    location_name = get_param(params, :location_name)
    location_code = get_param(params, :location_code)
    location_coordinate = get_param(params, :location_coordinate)

    not is_nil(location_name) or not is_nil(location_code) or not is_nil(location_coordinate)
  end

  defp needs_location?(params) do
    # CID and place_id have implicit location, keyword does not
    keyword = get_param(params, :keyword)
    not is_nil(keyword)
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
  def task_type, do: "business_data/google/questions_and_answers"

  @impl true
  def result_endpoint, do: ""

  @impl true
  def build_task_payload(params) do
    # Questions API uses keyword field with cid: or place_id: prefixes
    keyword = build_keyword_param(params)

    [
      %{
        "keyword" => keyword,
        "location_name" => get_param(params, :location_name),
        "location_code" => get_param(params, :location_code),
        "location_coordinate" => get_param(params, :location_coordinate),
        "language_name" => get_param(params, :language_name),
        "language_code" => get_param(params, :language_code) || "en",
        "depth" => get_param(params, :depth) || 20,
        "priority" => get_param(params, :priority) || 1,
        "tag" => get_param(params, :tag)
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()
    ]
  end

  # Build keyword parameter with cid: or place_id: prefix if applicable
  defp build_keyword_param(params) do
    cond do
      cid = get_param(params, :cid) -> "cid:#{cid}"
      place_id = get_param(params, :place_id) -> "place_id:#{place_id}"
      true -> get_param(params, :keyword)
    end
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
  @spec parse_task_results(map()) :: {:ok, GoogleQuestionsResult.t()} | {:error, term()}
  def parse_task_results(response) do
    require Logger
    Logger.debug("GoogleQuestions parse_task_results response: #{inspect(response)}")

    case response do
      %{"tasks" => [task | _]} ->
        Logger.debug("Task structure: #{inspect(task)}")

        case task do
          %{"result" => [result | _]} ->
            Logger.debug("Result structure: #{inspect(result)}")
            {:ok, GoogleQuestionsResult.new(result)}

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
      not has_business_identifier?(params) ->
        {:error, {:invalid_params, "One of keyword, cid, or place_id is required"}}

      needs_location?(params) and not has_location?(params) ->
        {:error,
         {:invalid_params,
          "Location parameter required when using keyword (location_name, location_code, or location_coordinate)"}}

      not valid_depth?(params) ->
        {:error, {:invalid_params, "depth must be between 1 and #{@max_depth}"}}

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
end
