defmodule DataForSEO.Tasks.BusinessListings do
  @moduledoc """
  DataForSEO task implementation for Business Listings search.

  This module implements the ClientBehaviour to handle Business Listings
  search tasks through the DataForSEO API. It allows searching for businesses
  on Google Maps by category, location, filters, and other criteria.

  ## Usage

      # Start a task to search for pizza restaurants near a location
      {:ok, pid} = DataForSEO.Supervisor.start_task(
        DataForSEO.Tasks.BusinessListings,
        %{
          categories: ["pizza_restaurant"],
          location_coordinate: "53.476,-2.243,10",
          filters: [["rating.value", ">", 3]],
          limit: 100
        },
        callback: fn {:ok, results} -> IO.inspect(results) end
      )

  ## Parameters

  The following parameters are supported in the task params map:

  - `:categories` - List of business category IDs (max 10), e.g., ["pizza_restaurant"]
  - `:location_coordinate` - Location string format "latitude,longitude,radius_km" (radius: 1-100000)
  - `:title` - Business name search term (max 200 chars)
  - `:description` - Business description search term (max 200 chars)
  - `:is_claimed` - Boolean to filter for verified Google Maps businesses
  - `:filters` - List of filter conditions, e.g., [["rating.value", ">", 3]] (max 8)
  - `:order_by` - List of sorting rules, e.g., [["rating.value", "desc"]] (max 3)
  - `:limit` - Maximum number of results (default: 100, max: 1000)
  - `:offset` - Pagination offset
  - `:offset_token` - Token for large result sets (>100k items)
  - `:tag` - User-defined identifier (max 255 chars)

  ## Examples

      # Search by category and location
      params = %{
        categories: ["pizza_restaurant"],
        location_coordinate: "53.476,-2.243,10"
      }

      # Search with filters and sorting
      params = %{
        categories: ["restaurant"],
        location_coordinate: "40.7128,-74.0060,5",
        filters: [
          ["rating.value", ">", 4],
          ["rating.votes_count", ">", 50]
        ],
        order_by: [["rating.value", "desc"]],
        limit: 50
      }

  """

  @behaviour DataForSEO.ClientBehaviour

  alias DataForSEO.Schemas.BusinessListingsResult

  # Maximum constraints from API documentation
  @max_categories 10
  @max_filters 8
  @max_order_by 3
  @max_title_length 200
  @max_description_length 200
  @max_tag_length 255
  @max_limit 1000

  # Private helper functions

  defp get_param(params, key) when is_atom(key) do
    Map.get(params, key) || Map.get(params, Atom.to_string(key))
  end

  defp extract_task_ids(task) do
    case task["result"] do
      results when is_list(results) ->
        Enum.map(results, & &1["id"])

      _ ->
        []
    end
  end

  defp parse_business_results(result) do
    require Logger

    items = result["items"] || []
    Logger.debug("Found #{length(items)} business listings in result")

    parsed_result = BusinessListingsResult.new(result)

    Logger.debug("Parsed result structure: #{inspect(parsed_result)}")

    {:ok, parsed_result}
  end

  # Public functions (behaviour callbacks)

  @impl true
  def task_type, do: "business_data/business_listings/search"

  @impl true
  def is_live_endpoint?, do: true

  @impl true
  def build_task_payload(params) do
    # Build the task payload array
    [
      %{
        "categories" => get_param(params, :categories),
        "location_coordinate" => get_param(params, :location_coordinate),
        "title" => get_param(params, :title),
        "description" => get_param(params, :description),
        "is_claimed" => get_param(params, :is_claimed),
        "filters" => get_param(params, :filters),
        "order_by" => get_param(params, :order_by),
        "limit" => get_param(params, :limit) || 100,
        "offset" => get_param(params, :offset),
        "offset_token" => get_param(params, :offset_token),
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
  @spec parse_task_results(map()) :: {:ok, BusinessListingsResult.t()} | {:error, term()}
  def parse_task_results(response) do
    require Logger
    Logger.debug("BusinessListings parse_task_results response: #{inspect(response)}")

    case response do
      %{"tasks" => [task | _]} ->
        Logger.debug("Task structure: #{inspect(task)}")

        case task do
          %{"result" => [result | _]} ->
            Logger.debug("Result structure: #{inspect(result)}")
            parse_business_results(result)

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
    with :ok <- validate_categories(params),
         :ok <- validate_location_coordinate(params),
         :ok <- validate_title(params),
         :ok <- validate_description(params),
         :ok <- validate_filters(params),
         :ok <- validate_order_by(params),
         :ok <- validate_limit(params) do
      validate_tag(params)
    end
  end

  def validate_params(_) do
    {:error, {:invalid_params, "params must be a map"}}
  end

  # Private validation helpers

  defp validate_categories(params) do
    case get_param(params, :categories) do
      nil ->
        :ok

      categories when is_list(categories) ->
        cond do
          length(categories) > @max_categories ->
            {:error, {:invalid_params, "categories must not exceed #{@max_categories} items"}}

          not Enum.all?(categories, &is_binary/1) ->
            {:error, {:invalid_params, "all categories must be strings"}}

          true ->
            :ok
        end

      _ ->
        {:error, {:invalid_params, "categories must be a list of strings"}}
    end
  end

  defp validate_location_coordinate(params) do
    case get_param(params, :location_coordinate) do
      nil ->
        :ok

      coord when is_binary(coord) ->
        validate_coordinate_format(coord)

      _ ->
        {:error, {:invalid_params, "location_coordinate must be a string"}}
    end
  end

  defp validate_coordinate_format(coord) do
    # Format: "latitude,longitude,radius" - validate basic format
    case String.split(coord, ",") do
      [lat, lng, radius] ->
        if valid_number?(lat) and valid_number?(lng) and valid_number?(radius) do
          :ok
        else
          {:error,
           {:invalid_params, "location_coordinate must be in format 'latitude,longitude,radius'"}}
        end

      _ ->
        {:error,
         {:invalid_params, "location_coordinate must be in format 'latitude,longitude,radius'"}}
    end
  end

  defp validate_title(params) do
    case get_param(params, :title) do
      nil ->
        :ok

      title when is_binary(title) ->
        if String.length(title) > @max_title_length do
          {:error, {:invalid_params, "title must not exceed #{@max_title_length} characters"}}
        else
          :ok
        end

      _ ->
        {:error, {:invalid_params, "title must be a string"}}
    end
  end

  defp validate_description(params) do
    case get_param(params, :description) do
      nil ->
        :ok

      description when is_binary(description) ->
        if String.length(description) > @max_description_length do
          {:error,
           {:invalid_params, "description must not exceed #{@max_description_length} characters"}}
        else
          :ok
        end

      _ ->
        {:error, {:invalid_params, "description must be a string"}}
    end
  end

  defp validate_filters(params) do
    case get_param(params, :filters) do
      nil ->
        :ok

      filters when is_list(filters) ->
        cond do
          length(filters) > @max_filters ->
            {:error, {:invalid_params, "filters must not exceed #{@max_filters} items"}}

          not Enum.all?(filters, &valid_filter?/1) ->
            {:error,
             {:invalid_params,
              "each filter must be a list [field, operator, value] with valid operator"}}

          true ->
            :ok
        end

      _ ->
        {:error, {:invalid_params, "filters must be a list"}}
    end
  end

  defp validate_order_by(params) do
    case get_param(params, :order_by) do
      nil ->
        :ok

      order_by when is_list(order_by) ->
        cond do
          length(order_by) > @max_order_by ->
            {:error, {:invalid_params, "order_by must not exceed #{@max_order_by} items"}}

          not Enum.all?(order_by, &valid_order_by?/1) ->
            {:error,
             {:invalid_params,
              "each order_by must be [field, direction] where direction is asc/desc"}}

          true ->
            :ok
        end

      _ ->
        {:error, {:invalid_params, "order_by must be a list"}}
    end
  end

  defp validate_limit(params) do
    case get_param(params, :limit) do
      nil ->
        :ok

      limit when is_integer(limit) ->
        if limit > @max_limit do
          {:error, {:invalid_params, "limit must not exceed #{@max_limit}"}}
        else
          :ok
        end

      _ ->
        {:error, {:invalid_params, "limit must be an integer"}}
    end
  end

  defp validate_tag(params) do
    case get_param(params, :tag) do
      nil ->
        :ok

      tag when is_binary(tag) ->
        if String.length(tag) > @max_tag_length do
          {:error, {:invalid_params, "tag must not exceed #{@max_tag_length} characters"}}
        else
          :ok
        end

      _ ->
        {:error, {:invalid_params, "tag must be a string"}}
    end
  end

  defp valid_filter?([_field, operator, _value]) when is_binary(operator) do
    operator in ["<", "<=", ">", ">=", "=", "!=", "like", "not_like", "regex", "not_regex"]
  end

  defp valid_filter?(_), do: false

  defp valid_order_by?([_field, direction]) when is_binary(direction) do
    direction in ["asc", "desc"]
  end

  defp valid_order_by?(_), do: false

  defp valid_number?(str) when is_binary(str) do
    case Float.parse(str) do
      {_num, ""} -> true
      _ -> false
    end
  end

  defp valid_number?(_), do: false
end
