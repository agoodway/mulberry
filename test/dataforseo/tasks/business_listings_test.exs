defmodule DataForSEO.Tasks.BusinessListingsTest do
  use ExUnit.Case, async: true

  alias DataForSEO.Tasks.BusinessListings
  alias DataForSEO.Schemas.BusinessListingsResult

  describe "task_type/0" do
    test "returns the correct task type" do
      assert BusinessListings.task_type() == "business_data/business_listings/search"
    end
  end

  describe "build_task_payload/1" do
    test "builds payload with all parameters" do
      params = %{
        categories: ["pizza_restaurant"],
        location_coordinate: "53.476,-2.243,10",
        title: "Joe's Pizza",
        description: "Best pizza in town",
        is_claimed: true,
        filters: [["rating.value", ">", 3]],
        order_by: [["rating.value", "desc"]],
        limit: 50,
        offset: 10,
        offset_token: "token123",
        tag: "test_tag"
      }

      [payload] = BusinessListings.build_task_payload(params)

      assert payload["categories"] == ["pizza_restaurant"]
      assert payload["location_coordinate"] == "53.476,-2.243,10"
      assert payload["title"] == "Joe's Pizza"
      assert payload["description"] == "Best pizza in town"
      assert payload["is_claimed"] == true
      assert payload["filters"] == [["rating.value", ">", 3]]
      assert payload["order_by"] == [["rating.value", "desc"]]
      assert payload["limit"] == 50
      assert payload["offset"] == 10
      assert payload["offset_token"] == "token123"
      assert payload["tag"] == "test_tag"
    end

    test "builds payload with minimal parameters" do
      params = %{
        categories: ["restaurant"]
      }

      [payload] = BusinessListings.build_task_payload(params)

      assert payload["categories"] == ["restaurant"]
      assert payload["limit"] == 100
    end

    test "uses default limit when not specified" do
      params = %{
        categories: ["restaurant"],
        location_coordinate: "40.7128,-74.0060,5"
      }

      [payload] = BusinessListings.build_task_payload(params)

      assert payload["limit"] == 100
    end

    test "omits nil values from payload" do
      params = %{
        categories: ["restaurant"],
        location_coordinate: "40.7128,-74.0060,5",
        tag: nil,
        description: nil
      }

      [payload] = BusinessListings.build_task_payload(params)

      refute Map.has_key?(payload, "tag")
      refute Map.has_key?(payload, "description")
    end

    test "handles string keys in params" do
      params = %{
        "categories" => ["pizza_restaurant"],
        "location_coordinate" => "53.476,-2.243,10"
      }

      [payload] = BusinessListings.build_task_payload(params)

      assert payload["categories"] == ["pizza_restaurant"]
      assert payload["location_coordinate"] == "53.476,-2.243,10"
    end

    test "handles multiple categories" do
      params = %{
        categories: ["restaurant", "pizza_restaurant", "italian_restaurant"]
      }

      [payload] = BusinessListings.build_task_payload(params)

      assert payload["categories"] == ["restaurant", "pizza_restaurant", "italian_restaurant"]
    end

    test "handles multiple filters" do
      params = %{
        categories: ["restaurant"],
        filters: [
          ["rating.value", ">", 4],
          ["rating.votes_count", ">", 50],
          ["is_claimed", "=", true]
        ]
      }

      [payload] = BusinessListings.build_task_payload(params)

      assert length(payload["filters"]) == 3
    end

    test "handles multiple order_by rules" do
      params = %{
        categories: ["restaurant"],
        order_by: [
          ["rating.value", "desc"],
          ["rating.votes_count", "desc"]
        ]
      }

      [payload] = BusinessListings.build_task_payload(params)

      assert length(payload["order_by"]) == 2
    end
  end

  describe "parse_task_response/1" do
    test "parses successful task creation response" do
      response = %{
        "tasks" => [
          %{
            "id" => "task123",
            "status_code" => 20_100,
            "status_message" => "Ok."
          }
        ]
      }

      assert {:ok, ["task123"]} = BusinessListings.parse_task_response(response)
    end

    test "parses multiple task IDs" do
      response = %{
        "tasks" => [
          %{"id" => "task1", "status_code" => 20_100},
          %{"id" => "task2", "status_code" => 20_100}
        ]
      }

      assert {:ok, ["task1", "task2"]} = BusinessListings.parse_task_response(response)
    end

    test "filters out failed tasks" do
      response = %{
        "tasks" => [
          %{"id" => "task1", "status_code" => 20_100},
          %{"id" => "task2", "status_code" => 40_100, "status_message" => "Error"},
          %{"id" => "task3", "status_code" => 20_100}
        ]
      }

      assert {:ok, ["task1", "task3"]} = BusinessListings.parse_task_response(response)
    end

    test "returns error when no successful tasks" do
      response = %{
        "tasks" => [
          %{"status_code" => 40_100, "status_message" => "Invalid categories"}
        ]
      }

      assert {:error, {:task_creation_failed, "Invalid categories"}} =
               BusinessListings.parse_task_response(response)
    end

    test "returns error for invalid response format" do
      response = %{"invalid" => "format"}

      assert {:error, {:invalid_response, "Expected tasks array in response"}} =
               BusinessListings.parse_task_response(response)
    end
  end

  describe "parse_ready_tasks/1" do
    test "parses ready tasks from response" do
      response = %{
        "tasks" => [
          %{
            "result_count" => 1,
            "result" => [
              %{"id" => "task123"}
            ]
          }
        ]
      }

      assert ["task123"] = BusinessListings.parse_ready_tasks(response)
    end

    test "parses multiple ready tasks" do
      response = %{
        "tasks" => [
          %{
            "result_count" => 2,
            "result" => [
              %{"id" => "task1"},
              %{"id" => "task2"}
            ]
          }
        ]
      }

      assert ["task1", "task2"] = BusinessListings.parse_ready_tasks(response)
    end

    test "filters out tasks with no results" do
      response = %{
        "tasks" => [
          %{"result_count" => 0, "result" => []},
          %{"result_count" => 1, "result" => [%{"id" => "task123"}]}
        ]
      }

      assert ["task123"] = BusinessListings.parse_ready_tasks(response)
    end

    test "returns empty list for no ready tasks" do
      response = %{
        "tasks" => [
          %{"result_count" => 0}
        ]
      }

      assert [] = BusinessListings.parse_ready_tasks(response)
    end

    test "handles invalid response format" do
      response = %{"invalid" => "format"}

      assert [] = BusinessListings.parse_ready_tasks(response)
    end
  end

  describe "parse_task_results/1" do
    test "parses complete business listing results" do
      response = %{
        "tasks" => [
          %{
            "result" => [
              %{
                "total_count" => 36,
                "items" => [
                  %{
                    "type" => "business_listing",
                    "title" => "Joe's Pizza",
                    "description" => "Best pizza in town",
                    "category" => "Pizza restaurant",
                    "category_ids" => ["pizza_restaurant"],
                    "address" => "123 Main St, New York, NY 10001",
                    "address_info" => %{
                      "street" => "123 Main St",
                      "city" => "New York",
                      "zip" => "10001"
                    },
                    "phone" => "+1-555-0123",
                    "url" => "https://maps.google.com/place/123",
                    "domain" => "joespizza.com",
                    "latitude" => 40.7128,
                    "longitude" => -74.006,
                    "place_id" => "ChIJOwg_06VPwokRYv534QaPC8g",
                    "cid" => "12345678901234567890",
                    "is_claimed" => true,
                    "rating" => %{
                      "value" => 4.5,
                      "votes_count" => 150
                    },
                    "rating_distribution" => %{
                      "1" => 5,
                      "2" => 3,
                      "3" => 10,
                      "4" => 30,
                      "5" => 102
                    },
                    "work_time" => %{
                      "Monday" => "09:00-22:00",
                      "Tuesday" => "09:00-22:00"
                    },
                    "popular_times" => %{
                      "Monday" => [0, 0, 0, 0, 0, 0, 0, 20, 40]
                    },
                    "logo" => "https://example.com/logo.jpg",
                    "main_image" => "https://example.com/main.jpg",
                    "total_photos" => 42,
                    "attributes" => %{
                      "dine_in" => true,
                      "takeout" => true,
                      "delivery" => true
                    },
                    "last_updated_time" => "2024-11-07 12:00:00 +00:00",
                    "first_seen" => "2023-01-15 10:30:00 +00:00"
                  }
                ]
              }
            ]
          }
        ]
      }

      assert {:ok, %BusinessListingsResult{} = result} =
               BusinessListings.parse_task_results(response)

      assert result.total_count == 36
      assert length(result.items) == 1

      listing = List.first(result.items)
      assert listing.type == "business_listing"
      assert listing.title == "Joe's Pizza"
      assert listing.description == "Best pizza in town"
      assert listing.category == "Pizza restaurant"
      assert listing.category_ids == ["pizza_restaurant"]
      assert listing.address == "123 Main St, New York, NY 10001"
      assert listing.phone == "+1-555-0123"
      assert listing.url == "https://maps.google.com/place/123"
      assert listing.domain == "joespizza.com"
      assert listing.latitude == 40.7128
      assert listing.longitude == -74.006
      assert listing.place_id == "ChIJOwg_06VPwokRYv534QaPC8g"
      assert listing.cid == "12345678901234567890"
      assert listing.is_claimed == true
      assert listing.rating["value"] == 4.5
      assert listing.rating["votes_count"] == 150
      assert listing.logo == "https://example.com/logo.jpg"
      assert listing.total_photos == 42
    end

    test "parses multiple business listings" do
      response = %{
        "tasks" => [
          %{
            "result" => [
              %{
                "total_count" => 2,
                "items" => [
                  %{"type" => "business_listing", "title" => "Pizza Place 1"},
                  %{"type" => "business_listing", "title" => "Pizza Place 2"}
                ]
              }
            ]
          }
        ]
      }

      assert {:ok, result} = BusinessListings.parse_task_results(response)
      assert length(result.items) == 2
      assert result.total_count == 2
    end

    test "handles empty results" do
      response = %{
        "tasks" => [
          %{
            "result" => [
              %{"total_count" => 0, "items" => []}
            ]
          }
        ]
      }

      assert {:ok, result} = BusinessListings.parse_task_results(response)
      assert result.items == []
      assert result.total_count == 0
    end

    test "handles minimal listing data" do
      response = %{
        "tasks" => [
          %{
            "result" => [
              %{
                "items" => [
                  %{"title" => "Minimal Listing"}
                ]
              }
            ]
          }
        ]
      }

      assert {:ok, result} = BusinessListings.parse_task_results(response)
      listing = List.first(result.items)
      assert listing.title == "Minimal Listing"
      assert is_nil(listing.rating)
      assert is_nil(listing.address)
    end

    test "returns error when task failed" do
      response = %{
        "tasks" => [
          %{
            "status_code" => 40_100,
            "status_message" => "Invalid parameters"
          }
        ]
      }

      assert {:error, {:task_failed, "Invalid parameters"}} =
               BusinessListings.parse_task_results(response)
    end

    test "returns error when no results" do
      response = %{
        "tasks" => [
          %{"result" => []}
        ]
      }

      assert {:error, {:no_results, "Task completed but no results found"}} =
               BusinessListings.parse_task_results(response)
    end

    test "returns error for invalid response format" do
      response = %{"invalid" => "format"}

      assert {:error, {:invalid_response, "Expected tasks array in response"}} =
               BusinessListings.parse_task_results(response)
    end
  end

  describe "validate_params/1" do
    test "validates with minimal valid params" do
      params = %{categories: ["restaurant"]}

      assert :ok = BusinessListings.validate_params(params)
    end

    test "validates with all parameters" do
      params = %{
        categories: ["pizza_restaurant"],
        location_coordinate: "40.7128,-74.0060,5",
        title: "Joe's Pizza",
        description: "Best pizza",
        filters: [["rating.value", ">", 3]],
        order_by: [["rating.value", "desc"]],
        limit: 100,
        tag: "test"
      }

      assert :ok = BusinessListings.validate_params(params)
    end

    test "returns error when categories exceed maximum" do
      params = %{
        categories: Enum.map(1..11, fn i -> "category_#{i}" end)
      }

      assert {:error, {:invalid_params, "categories must not exceed 10 items"}} =
               BusinessListings.validate_params(params)
    end

    test "returns error when categories is not a list" do
      params = %{categories: "restaurant"}

      assert {:error, {:invalid_params, "categories must be a list of strings"}} =
               BusinessListings.validate_params(params)
    end

    test "returns error when category is not a string" do
      params = %{categories: [123, "restaurant"]}

      assert {:error, {:invalid_params, "all categories must be strings"}} =
               BusinessListings.validate_params(params)
    end

    test "returns error for invalid location_coordinate format" do
      params = %{
        categories: ["restaurant"],
        location_coordinate: "invalid"
      }

      assert {:error,
              {:invalid_params,
               "location_coordinate must be in format 'latitude,longitude,radius'"}} =
               BusinessListings.validate_params(params)
    end

    test "returns error for non-numeric location_coordinate values" do
      params = %{
        categories: ["restaurant"],
        location_coordinate: "abc,def,ghi"
      }

      assert {:error,
              {:invalid_params,
               "location_coordinate must be in format 'latitude,longitude,radius'"}} =
               BusinessListings.validate_params(params)
    end

    test "validates proper location_coordinate format" do
      params = %{
        categories: ["restaurant"],
        location_coordinate: "40.7128,-74.0060,5.5"
      }

      assert :ok = BusinessListings.validate_params(params)
    end

    test "returns error when title exceeds maximum length" do
      params = %{
        categories: ["restaurant"],
        title: String.duplicate("a", 201)
      }

      assert {:error, {:invalid_params, "title must not exceed 200 characters"}} =
               BusinessListings.validate_params(params)
    end

    test "returns error when description exceeds maximum length" do
      params = %{
        categories: ["restaurant"],
        description: String.duplicate("a", 201)
      }

      assert {:error, {:invalid_params, "description must not exceed 200 characters"}} =
               BusinessListings.validate_params(params)
    end

    test "returns error when filters exceed maximum" do
      params = %{
        categories: ["restaurant"],
        filters: Enum.map(1..9, fn i -> ["field_#{i}", ">", i] end)
      }

      assert {:error, {:invalid_params, "filters must not exceed 8 items"}} =
               BusinessListings.validate_params(params)
    end

    test "returns error for invalid filter format" do
      params = %{
        categories: ["restaurant"],
        filters: [["field", "invalid_op", 3]]
      }

      assert {:error,
              {:invalid_params,
               "each filter must be a list [field, operator, value] with valid operator"}} =
               BusinessListings.validate_params(params)
    end

    test "validates all valid filter operators" do
      operators = ["<", "<=", ">", ">=", "=", "!=", "like", "not_like", "regex", "not_regex"]

      for op <- operators do
        params = %{
          categories: ["restaurant"],
          filters: [["rating.value", op, 3]]
        }

        assert :ok = BusinessListings.validate_params(params)
      end
    end

    test "returns error when order_by exceed maximum" do
      params = %{
        categories: ["restaurant"],
        order_by: [
          ["field1", "desc"],
          ["field2", "asc"],
          ["field3", "desc"],
          ["field4", "asc"]
        ]
      }

      assert {:error, {:invalid_params, "order_by must not exceed 3 items"}} =
               BusinessListings.validate_params(params)
    end

    test "returns error for invalid order_by direction" do
      params = %{
        categories: ["restaurant"],
        order_by: [["rating.value", "invalid"]]
      }

      assert {:error,
              {:invalid_params,
               "each order_by must be [field, direction] where direction is asc/desc"}} =
               BusinessListings.validate_params(params)
    end

    test "validates order_by with asc and desc" do
      params = %{
        categories: ["restaurant"],
        order_by: [["rating.value", "desc"], ["name", "asc"]]
      }

      assert :ok = BusinessListings.validate_params(params)
    end

    test "returns error when limit exceeds maximum" do
      params = %{
        categories: ["restaurant"],
        limit: 1001
      }

      assert {:error, {:invalid_params, "limit must not exceed 1000"}} =
               BusinessListings.validate_params(params)
    end

    test "returns error when tag exceeds maximum length" do
      params = %{
        categories: ["restaurant"],
        tag: String.duplicate("a", 256)
      }

      assert {:error, {:invalid_params, "tag must not exceed 255 characters"}} =
               BusinessListings.validate_params(params)
    end

    test "returns error when params is not a map" do
      assert {:error, {:invalid_params, "params must be a map"}} =
               BusinessListings.validate_params("not a map")
    end

    test "handles string keys in params" do
      params = %{
        "categories" => ["restaurant"],
        "location_coordinate" => "40.7128,-74.0060,5"
      }

      assert :ok = BusinessListings.validate_params(params)
    end

    test "allows optional parameters to be nil" do
      params = %{
        categories: ["restaurant"],
        title: nil,
        description: nil,
        filters: nil,
        order_by: nil
      }

      assert :ok = BusinessListings.validate_params(params)
    end
  end
end
