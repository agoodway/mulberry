defmodule DataForSEO.Tasks.GoogleEventsTest do
  use ExUnit.Case, async: true

  alias DataForSEO.Tasks.GoogleEvents
  alias DataForSEO.Schemas.GoogleEventsResult

  describe "task_type/0" do
    test "returns the correct task type" do
      assert GoogleEvents.task_type() == "serp/google/events"
    end
  end

  describe "build_task_payload/1" do
    test "builds payload with all parameters" do
      params = %{
        keyword: "concerts",
        location_name: "New York",
        language_code: "en",
        date_range: "next_week",
        depth: 20,
        priority: 2,
        tag: "test_tag"
      }

      [payload] = GoogleEvents.build_task_payload(params)

      assert payload["keyword"] == "concerts"
      assert payload["location"] == "New York"
      assert payload["language_code"] == "en"
      assert payload["date_range"] == "next_week"
      assert payload["depth"] == 20
      assert payload["priority"] == 2
      assert payload["tag"] == "test_tag"
    end

    test "builds payload with location_code" do
      params = %{
        keyword: "concerts",
        location_code: 2840
      }

      [payload] = GoogleEvents.build_task_payload(params)

      assert payload["keyword"] == "concerts"
      assert payload["location_code"] == 2840
      refute Map.has_key?(payload, "location")
    end

    test "builds payload with location_coordinate" do
      params = %{
        keyword: "concerts",
        location_coordinate: "40.7128,-74.0060"
      }

      [payload] = GoogleEvents.build_task_payload(params)

      assert payload["keyword"] == "concerts"
      assert payload["location_coordinate"] == "40.7128,-74.0060"
    end

    test "uses default values for optional parameters" do
      params = %{
        keyword: "concerts",
        location_name: "New York"
      }

      [payload] = GoogleEvents.build_task_payload(params)

      assert payload["language_code"] == "en"
      assert payload["depth"] == 10
      assert payload["priority"] == 1
    end

    test "omits nil values from payload" do
      params = %{
        keyword: "concerts",
        location_name: "New York",
        tag: nil
      }

      [payload] = GoogleEvents.build_task_payload(params)

      refute Map.has_key?(payload, "tag")
    end

    test "handles string keys in params" do
      params = %{
        "keyword" => "concerts",
        "location_name" => "New York"
      }

      [payload] = GoogleEvents.build_task_payload(params)

      assert payload["keyword"] == "concerts"
      assert payload["location"] == "New York"
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

      assert {:ok, ["task123"]} = GoogleEvents.parse_task_response(response)
    end

    test "parses multiple task IDs" do
      response = %{
        "tasks" => [
          %{"id" => "task1", "status_code" => 20_100},
          %{"id" => "task2", "status_code" => 20_100}
        ]
      }

      assert {:ok, ["task1", "task2"]} = GoogleEvents.parse_task_response(response)
    end

    test "filters out failed tasks" do
      response = %{
        "tasks" => [
          %{"id" => "task1", "status_code" => 20_100},
          %{"id" => "task2", "status_code" => 40_100, "status_message" => "Error"},
          %{"id" => "task3", "status_code" => 20_100}
        ]
      }

      assert {:ok, ["task1", "task3"]} = GoogleEvents.parse_task_response(response)
    end

    test "returns error when no successful tasks" do
      response = %{
        "tasks" => [
          %{"status_code" => 40_100, "status_message" => "Invalid keyword"}
        ]
      }

      assert {:error, {:task_creation_failed, "Invalid keyword"}} =
               GoogleEvents.parse_task_response(response)
    end

    test "returns error for invalid response format" do
      response = %{"invalid" => "format"}

      assert {:error, {:invalid_response, "Expected tasks array in response"}} =
               GoogleEvents.parse_task_response(response)
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

      assert ["task123"] = GoogleEvents.parse_ready_tasks(response)
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

      assert ["task1", "task2"] = GoogleEvents.parse_ready_tasks(response)
    end

    test "filters out tasks with no results" do
      response = %{
        "tasks" => [
          %{"result_count" => 0, "result" => []},
          %{"result_count" => 1, "result" => [%{"id" => "task123"}]}
        ]
      }

      assert ["task123"] = GoogleEvents.parse_ready_tasks(response)
    end

    test "returns empty list for no ready tasks" do
      response = %{
        "tasks" => [
          %{"result_count" => 0}
        ]
      }

      assert [] = GoogleEvents.parse_ready_tasks(response)
    end

    test "handles invalid response format" do
      response = %{"invalid" => "format"}

      assert [] = GoogleEvents.parse_ready_tasks(response)
    end
  end

  describe "parse_task_results/1" do
    test "parses complete event results" do
      response = %{
        "tasks" => [
          %{
            "result" => [
              %{
                "keyword" => "concerts nyc",
                "location" => "New York",
                "language_code" => "en",
                "check_url" => "https://www.google.com/search?q=concerts+nyc",
                "datetime" => "2024-11-07 12:00:00 +00:00",
                "total_count" => 1,
                "items_count" => 1,
                "items" => [
                  %{
                    "type" => "event_item",
                    "title" => "Summer Concert",
                    "description" => "A great concert",
                    "url" => "https://example.com/concert",
                    "image_url" => "https://example.com/image.jpg",
                    "position" => 1,
                    "xpath" => "/html/body/div",
                    "event_dates" => %{
                      "start_datetime" => "2024-08-15T19:00:00",
                      "end_datetime" => "2024-08-15T22:00:00",
                      "displayed_dates" => "Aug 15"
                    },
                    "location_info" => %{
                      "name" => "Madison Square Garden",
                      "address" => "4 Pennsylvania Plaza, New York, NY 10001",
                      "url" => "https://www.msg.com",
                      "cid" => "12345",
                      "feature_id" => "0x89c25"
                    },
                    "information_and_tickets" => [
                      %{
                        "type" => "tickets",
                        "title" => "Ticketmaster",
                        "description" => "Buy tickets",
                        "url" => "https://www.ticketmaster.com/event/123",
                        "domain" => "www.ticketmaster.com"
                      }
                    ]
                  }
                ]
              }
            ]
          }
        ]
      }

      assert {:ok, %GoogleEventsResult{} = result} = GoogleEvents.parse_task_results(response)
      assert length(result.events) == 1

      event = List.first(result.events)
      assert event.type == "event"
      assert event.title == "Summer Concert"
      assert event.description == "A great concert"
      assert event.url == "https://example.com/concert"
      assert event.date == "Aug 15"
      assert event.event_dates.start_datetime == "2024-08-15T19:00:00"
      assert event.location.name == "Madison Square Garden"
      assert length(event.information_and_tickets) == 1

      assert result.metadata.keyword == "concerts nyc"
      assert result.metadata.location == "New York"
      assert result.metadata.total_count == 1
    end

    test "filters out non-event items" do
      response = %{
        "tasks" => [
          %{
            "result" => [
              %{
                "items" => [
                  %{"type" => "event_item", "title" => "Concert 1"},
                  %{"type" => "organic", "title" => "Some webpage"},
                  %{"type" => "event_item", "title" => "Concert 2"}
                ]
              }
            ]
          }
        ]
      }

      assert {:ok, result} = GoogleEvents.parse_task_results(response)
      assert length(result.events) == 2
    end

    test "handles empty results" do
      response = %{
        "tasks" => [
          %{
            "result" => [
              %{"items" => []}
            ]
          }
        ]
      }

      assert {:ok, result} = GoogleEvents.parse_task_results(response)
      assert result.events == []
    end

    test "handles missing event_dates" do
      response = %{
        "tasks" => [
          %{
            "result" => [
              %{
                "items" => [
                  %{"type" => "event_item", "title" => "Concert"}
                ]
              }
            ]
          }
        ]
      }

      assert {:ok, result} = GoogleEvents.parse_task_results(response)
      event = List.first(result.events)
      assert is_nil(event.date)
      assert is_nil(event.event_dates)
    end

    test "handles missing location_info" do
      response = %{
        "tasks" => [
          %{
            "result" => [
              %{
                "items" => [
                  %{"type" => "event_item", "title" => "Concert"}
                ]
              }
            ]
          }
        ]
      }

      assert {:ok, result} = GoogleEvents.parse_task_results(response)
      event = List.first(result.events)
      assert is_nil(event.location)
    end

    test "handles missing information_and_tickets" do
      response = %{
        "tasks" => [
          %{
            "result" => [
              %{
                "items" => [
                  %{"type" => "event_item", "title" => "Concert"}
                ]
              }
            ]
          }
        ]
      }

      assert {:ok, result} = GoogleEvents.parse_task_results(response)
      event = List.first(result.events)
      assert event.information_and_tickets == []
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
               GoogleEvents.parse_task_results(response)
    end

    test "returns error when no results" do
      response = %{
        "tasks" => [
          %{"result" => []}
        ]
      }

      assert {:error, {:no_results, "Task completed but no results found"}} =
               GoogleEvents.parse_task_results(response)
    end

    test "returns error for invalid response format" do
      response = %{"invalid" => "format"}

      assert {:error, {:invalid_response, "Expected tasks array in response"}} =
               GoogleEvents.parse_task_results(response)
    end
  end

  describe "validate_params/1" do
    test "validates with keyword and location_name" do
      params = %{keyword: "concerts", location_name: "New York"}

      assert :ok = GoogleEvents.validate_params(params)
    end

    test "validates with keyword and location_code" do
      params = %{keyword: "concerts", location_code: 2840}

      assert :ok = GoogleEvents.validate_params(params)
    end

    test "validates with keyword and location_coordinate" do
      params = %{keyword: "concerts", location_coordinate: "40.7128,-74.0060"}

      assert :ok = GoogleEvents.validate_params(params)
    end

    test "returns error when keyword is missing" do
      params = %{location_name: "New York"}

      assert {:error, {:invalid_params, "keyword is required and must be non-empty"}} =
               GoogleEvents.validate_params(params)
    end

    test "returns error when keyword is empty string" do
      params = %{keyword: "", location_name: "New York"}

      assert {:error, {:invalid_params, "keyword is required and must be non-empty"}} =
               GoogleEvents.validate_params(params)
    end

    test "returns error when keyword is not a string" do
      params = %{keyword: 123, location_name: "New York"}

      assert {:error, {:invalid_params, "keyword is required and must be non-empty"}} =
               GoogleEvents.validate_params(params)
    end

    test "returns error when all location params are missing" do
      params = %{keyword: "concerts"}

      assert {:error,
              {:invalid_params,
               "One of location_name, location_code, or location_coordinate is required"}} =
               GoogleEvents.validate_params(params)
    end

    test "returns error when params is not a map" do
      assert {:error, {:invalid_params, "params must be a map"}} =
               GoogleEvents.validate_params("not a map")
    end

    test "handles string keys in params" do
      params = %{"keyword" => "concerts", "location_name" => "New York"}

      assert :ok = GoogleEvents.validate_params(params)
    end
  end
end
