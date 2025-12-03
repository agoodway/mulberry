defmodule Listex.DataForSEO.Tasks.GoogleEvents do
  @moduledoc """
  DataForSEO task implementation for Google Events search.

  This module implements the ClientBehaviour to handle Google Events
  search tasks through the DataForSEO API.
  """

  @behaviour Listex.DataForSEO.ClientBehaviour

  alias Listex.DataForSEO.Schemas.GoogleEventsResult

  # Private helper functions (defined first to be available in public functions)

  defp get_param(params, key) when is_atom(key) do
    Map.get(params, key) || Map.get(params, Atom.to_string(key))
  end

  defp has_location?(params) do
    location_name = get_param(params, :location_name)
    location_code = get_param(params, :location_code)
    location_coordinate = get_param(params, :location_coordinate)

    not is_nil(location_name) or not is_nil(location_code) or not is_nil(location_coordinate)
  end

  defp extract_task_ids(task) do
    case task["result"] do
      results when is_list(results) ->
        Enum.map(results, & &1["id"])

      _ ->
        []
    end
  end

  defp parse_event_results(result) do
    require Logger

    events = result["items"] || []
    Logger.debug("Found #{length(events)} items in result")

    parsed_events =
      Enum.map(events, fn item ->
        case item["type"] do
          "event_item" ->
            %{
              type: "event",
              title: item["title"],
              description: item["description"],
              url: item["url"],
              date: parse_event_date(item),
              event_dates: parse_event_dates(item),
              location: parse_event_location(item),
              tickets_url: get_in(item, ["event_dates", "ticket_info", Access.at(0), "url"]),
              more_info_url: get_in(item, ["event_dates", "more_info", Access.at(0), "url"]),
              information_and_tickets: parse_information_and_tickets(item),
              image_url: item["image_url"],
              position: item["position"],
              xpath: item["xpath"]
            }

          _ ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    metadata = %{
      total_count: result["total_count"],
      items_count: result["items_count"],
      keyword: result["keyword"],
      location: result["location"],
      language_code: result["language_code"],
      check_url: result["check_url"],
      datetime: result["datetime"]
    }

    result =
      GoogleEventsResult.new(%{
        events: parsed_events,
        metadata: metadata
      })

    Logger.debug("Parsed result structure: #{inspect(result)}")

    {:ok, result}
  end

  defp parse_event_date(item) do
    case item["event_dates"] do
      %{"displayed_dates" => date} when is_binary(date) ->
        date

      _ ->
        nil
    end
  end

  defp parse_event_dates(item) do
    case item["event_dates"] do
      %{} = dates ->
        %{
          start_datetime: dates["start_datetime"],
          end_datetime: dates["end_datetime"],
          displayed_dates: dates["displayed_dates"]
        }

      _ ->
        nil
    end
  end

  defp parse_event_location(item) do
    case item["location_info"] do
      %{} = location_info ->
        %{
          name: location_info["name"],
          address: location_info["address"],
          url: location_info["url"],
          cid: location_info["cid"],
          feature_id: location_info["feature_id"]
        }

      _ ->
        nil
    end
  end

  defp parse_information_and_tickets(item) do
    case item["information_and_tickets"] do
      tickets when is_list(tickets) ->
        Enum.map(tickets, fn ticket ->
          %{
            type: ticket["type"],
            title: ticket["title"],
            description: ticket["description"],
            url: ticket["url"],
            domain: ticket["domain"]
          }
        end)

      _ ->
        []
    end
  end

  # Public functions (behaviour callbacks)

  @impl true
  def task_type, do: "serp/google/events"

  @impl true
  def build_task_payload(params) do
    # Build the task payload array
    [
      %{
        "keyword" => get_param(params, :keyword),
        "location" => get_param(params, :location_name),
        "location_code" => get_param(params, :location_code),
        "location_coordinate" => get_param(params, :location_coordinate),
        "language_code" => get_param(params, :language_code) || "en",
        "date_range" => get_param(params, :date_range),
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
  @spec parse_task_results(map()) :: {:ok, GoogleEventsResult.t()} | {:error, term()}
  def parse_task_results(response) do
    require Logger
    Logger.debug("GoogleEvents parse_task_results response: #{inspect(response)}")

    case response do
      %{"tasks" => [task | _]} ->
        Logger.debug("Task structure: #{inspect(task)}")

        case task do
          %{"result" => [result | _]} ->
            Logger.debug("Result structure: #{inspect(result)}")
            parse_event_results(result)

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
    keyword = get_param(params, :keyword)

    cond do
      not is_binary(keyword) or keyword == "" ->
        {:error, {:invalid_params, "keyword is required and must be non-empty"}}

      not has_location?(params) ->
        {:error,
         {:invalid_params,
          "One of location_name, location_code, or location_coordinate is required"}}

      true ->
        :ok
    end
  end

  def validate_params(_) do
    {:error, {:invalid_params, "params must be a map"}}
  end
end
