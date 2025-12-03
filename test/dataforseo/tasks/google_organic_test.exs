defmodule DataForSEO.Tasks.GoogleOrganicTest do
  use ExUnit.Case, async: true

  alias DataForSEO.Tasks.GoogleOrganic
  alias DataForSEO.Schemas.GoogleOrganicResult

  describe "task_type/0" do
    test "returns the correct task type" do
      assert GoogleOrganic.task_type() == "serp/google/organic"
    end
  end

  describe "result_endpoint/0" do
    test "returns advanced endpoint" do
      assert GoogleOrganic.result_endpoint() == "advanced"
    end
  end

  describe "build_task_payload/1" do
    test "builds payload with keyword and location_name" do
      params = %{
        keyword: "elixir programming",
        location_name: "United States",
        language_code: "en",
        depth: 50
      }

      [payload] = GoogleOrganic.build_task_payload(params)

      assert payload["keyword"] == "elixir programming"
      assert payload["location_name"] == "United States"
      assert payload["language_code"] == "en"
      assert payload["depth"] == 50
    end

    test "builds payload with location_code" do
      params = %{
        keyword: "functional programming",
        location_code: 2840,
        language_code: "en"
      }

      [payload] = GoogleOrganic.build_task_payload(params)

      assert payload["keyword"] == "functional programming"
      assert payload["location_code"] == 2840
    end

    test "builds payload with device parameter" do
      params = %{
        keyword: "web development",
        location_code: 2840,
        device: "mobile"
      }

      [payload] = GoogleOrganic.build_task_payload(params)

      assert payload["device"] == "mobile"
    end

    test "builds payload with os parameter" do
      params = %{
        keyword: "best smartphones",
        location_code: 2840,
        device: "mobile",
        os: "android"
      }

      [payload] = GoogleOrganic.build_task_payload(params)

      assert payload["os"] == "android"
    end

    test "uses default values" do
      params = %{keyword: "search query", location_code: 2840}
      [payload] = GoogleOrganic.build_task_payload(params)

      assert payload["language_code"] == "en"
      assert payload["depth"] == 10
      assert payload["priority"] == 1
    end

    test "includes language_name when provided" do
      params = %{
        keyword: "search",
        location_code: 2840,
        language_name: "English"
      }

      [payload] = GoogleOrganic.build_task_payload(params)

      assert payload["language_name"] == "English"
    end

    test "omits nil values" do
      params = %{
        keyword: "search",
        location_code: 2840,
        tag: nil,
        device: nil,
        os: nil
      }

      [payload] = GoogleOrganic.build_task_payload(params)

      refute Map.has_key?(payload, "tag")
      refute Map.has_key?(payload, "device")
      refute Map.has_key?(payload, "os")
    end

    test "includes tag when provided" do
      params = %{
        keyword: "search",
        location_code: 2840,
        tag: "my-task-123"
      }

      [payload] = GoogleOrganic.build_task_payload(params)

      assert payload["tag"] == "my-task-123"
    end

    test "includes priority when provided" do
      params = %{
        keyword: "search",
        location_code: 2840,
        priority: 2
      }

      [payload] = GoogleOrganic.build_task_payload(params)

      assert payload["priority"] == 2
    end
  end

  describe "parse_task_response/1" do
    test "parses successful response" do
      response = %{
        "tasks" => [%{"id" => "task123", "status_code" => 20_100}]
      }

      assert {:ok, ["task123"]} = GoogleOrganic.parse_task_response(response)
    end

    test "parses multiple task IDs" do
      response = %{
        "tasks" => [
          %{"id" => "task1", "status_code" => 20_100},
          %{"id" => "task2", "status_code" => 20_100}
        ]
      }

      assert {:ok, ["task1", "task2"]} = GoogleOrganic.parse_task_response(response)
    end

    test "returns error for failed tasks" do
      response = %{
        "tasks" => [
          %{"status_code" => 40_100, "status_message" => "Invalid keyword"}
        ]
      }

      assert {:error, {:task_creation_failed, "Invalid keyword"}} =
               GoogleOrganic.parse_task_response(response)
    end

    test "filters out non-successful tasks" do
      response = %{
        "tasks" => [
          %{"id" => "task1", "status_code" => 20_100},
          %{"id" => "task2", "status_code" => 40_100, "status_message" => "Error"}
        ]
      }

      assert {:ok, ["task1"]} = GoogleOrganic.parse_task_response(response)
    end

    test "returns error when no successful tasks" do
      response = %{
        "tasks" => [
          %{"status_code" => 40_100, "status_message" => "Error 1"},
          %{"status_code" => 40_200, "status_message" => "Error 2"}
        ]
      }

      assert {:error, {:task_creation_failed, msg}} = GoogleOrganic.parse_task_response(response)
      assert msg =~ "Error 1"
      assert msg =~ "Error 2"
    end

    test "returns error for invalid response structure" do
      response = %{"invalid" => "structure"}

      assert {:error, {:invalid_response, _}} = GoogleOrganic.parse_task_response(response)
    end
  end

  describe "parse_ready_tasks/1" do
    test "parses ready tasks" do
      response = %{
        "tasks" => [
          %{"result_count" => 1, "result" => [%{"id" => "task123"}]}
        ]
      }

      assert ["task123"] = GoogleOrganic.parse_ready_tasks(response)
    end

    test "filters out tasks with no results" do
      response = %{
        "tasks" => [
          %{"result_count" => 0, "result" => []},
          %{"result_count" => 1, "result" => [%{"id" => "task456"}]}
        ]
      }

      assert ["task456"] = GoogleOrganic.parse_ready_tasks(response)
    end

    test "handles multiple ready tasks" do
      response = %{
        "tasks" => [
          %{"result_count" => 1, "result" => [%{"id" => "task1"}]},
          %{"result_count" => 2, "result" => [%{"id" => "task2"}, %{"id" => "task3"}]}
        ]
      }

      assert ["task1", "task2", "task3"] = GoogleOrganic.parse_ready_tasks(response)
    end

    test "returns empty list for invalid response" do
      assert [] = GoogleOrganic.parse_ready_tasks(%{})
    end
  end

  describe "parse_task_results/1" do
    test "parses organic results and people also ask" do
      response = %{
        "tasks" => [
          %{
            "result" => [
              %{
                "keyword" => "elixir programming",
                "location_code" => 2840,
                "language_code" => "en",
                "se_domain" => "google.com",
                "check_url" => "https://google.com/...",
                "datetime" => "2025-01-27 12:00:00",
                "se_results_count" => 1_000_000,
                "items_count" => 50,
                "type" => "organic",
                "items" => [
                  %{
                    "type" => "organic",
                    "title" => "Elixir Programming Language",
                    "url" => "https://elixir-lang.org",
                    "domain" => "elixir-lang.org",
                    "description" => "Official Elixir website",
                    "position" => 1
                  },
                  %{
                    "type" => "people_also_ask",
                    "title" => "What is Elixir?",
                    "url" => "https://example.com",
                    "domain" => "example.com",
                    "description" => "Elixir is a functional language..."
                  }
                ]
              }
            ]
          }
        ]
      }

      assert {:ok, %GoogleOrganicResult{} = result} = GoogleOrganic.parse_task_results(response)
      assert result.keyword == "elixir programming"
      assert result.location_code == 2840
      assert result.language_code == "en"
      assert result.items_count == 50
      assert result.se_results_count == 1_000_000
      assert length(result.organic_items) == 1
      assert length(result.people_also_ask) == 1
      assert hd(result.organic_items).title == "Elixir Programming Language"
      assert hd(result.people_also_ask).question == "What is Elixir?"
    end

    test "returns error for task failure" do
      response = %{
        "tasks" => [
          %{"status_message" => "Task failed due to invalid parameters"}
        ]
      }

      assert {:error, {:task_failed, "Task failed due to invalid parameters"}} =
               GoogleOrganic.parse_task_results(response)
    end

    test "returns error when no results" do
      response = %{
        "tasks" => [%{}]
      }

      assert {:error, {:no_results, _}} = GoogleOrganic.parse_task_results(response)
    end

    test "returns error for invalid response structure" do
      response = %{"invalid" => "structure"}

      assert {:error, {:invalid_response, _}} = GoogleOrganic.parse_task_results(response)
    end
  end

  describe "validate_params/1" do
    test "validates with keyword and location_name" do
      assert :ok =
               GoogleOrganic.validate_params(%{
                 keyword: "search",
                 location_name: "United States"
               })
    end

    test "validates with keyword and location_code" do
      assert :ok =
               GoogleOrganic.validate_params(%{
                 keyword: "search",
                 location_code: 2840
               })
    end

    test "validates with all optional parameters" do
      assert :ok =
               GoogleOrganic.validate_params(%{
                 keyword: "search",
                 location_code: 2840,
                 language_code: "en",
                 depth: 50,
                 device: "desktop",
                 os: "windows",
                 priority: 2,
                 tag: "test-123"
               })
    end

    test "returns error when keyword missing" do
      assert {:error, {:invalid_params, msg}} =
               GoogleOrganic.validate_params(%{location_code: 2840})

      assert msg =~ "keyword is required"
    end

    test "returns error when location missing" do
      assert {:error, {:invalid_params, msg}} = GoogleOrganic.validate_params(%{keyword: "search"})

      assert msg =~ "Location parameter required"
    end

    test "validates depth range - too high" do
      assert {:error, {:invalid_params, msg}} =
               GoogleOrganic.validate_params(%{
                 keyword: "search",
                 location_code: 2840,
                 depth: 800
               })

      assert msg =~ "depth must be between 1 and 700"
    end

    test "validates depth range - too low" do
      assert {:error, {:invalid_params, msg}} =
               GoogleOrganic.validate_params(%{
                 keyword: "search",
                 location_code: 2840,
                 depth: 0
               })

      assert msg =~ "depth must be between 1 and 700"
    end

    test "accepts valid depth values" do
      assert :ok =
               GoogleOrganic.validate_params(%{
                 keyword: "search",
                 location_code: 2840,
                 depth: 1
               })

      assert :ok =
               GoogleOrganic.validate_params(%{
                 keyword: "search",
                 location_code: 2840,
                 depth: 100
               })

      assert :ok =
               GoogleOrganic.validate_params(%{
                 keyword: "search",
                 location_code: 2840,
                 depth: 700
               })
    end

    test "validates device - valid values" do
      assert :ok =
               GoogleOrganic.validate_params(%{
                 keyword: "search",
                 location_code: 2840,
                 device: "desktop"
               })

      assert :ok =
               GoogleOrganic.validate_params(%{
                 keyword: "search",
                 location_code: 2840,
                 device: "mobile"
               })
    end

    test "validates device - invalid value" do
      assert {:error, {:invalid_params, msg}} =
               GoogleOrganic.validate_params(%{
                 keyword: "search",
                 location_code: 2840,
                 device: "tablet"
               })

      assert msg =~ "device must be one of"
    end

    test "validates os for desktop device - valid values" do
      assert :ok =
               GoogleOrganic.validate_params(%{
                 keyword: "search",
                 location_code: 2840,
                 device: "desktop",
                 os: "windows"
               })

      assert :ok =
               GoogleOrganic.validate_params(%{
                 keyword: "search",
                 location_code: 2840,
                 device: "desktop",
                 os: "macos"
               })
    end

    test "validates os for desktop device - invalid value" do
      assert {:error, {:invalid_params, msg}} =
               GoogleOrganic.validate_params(%{
                 keyword: "search",
                 location_code: 2840,
                 device: "desktop",
                 os: "android"
               })

      assert msg =~ "os must be one of"
      assert msg =~ "desktop"
    end

    test "validates os for mobile device - valid values" do
      assert :ok =
               GoogleOrganic.validate_params(%{
                 keyword: "search",
                 location_code: 2840,
                 device: "mobile",
                 os: "android"
               })

      assert :ok =
               GoogleOrganic.validate_params(%{
                 keyword: "search",
                 location_code: 2840,
                 device: "mobile",
                 os: "ios"
               })
    end

    test "validates os for mobile device - invalid value" do
      assert {:error, {:invalid_params, msg}} =
               GoogleOrganic.validate_params(%{
                 keyword: "search",
                 location_code: 2840,
                 device: "mobile",
                 os: "windows"
               })

      assert msg =~ "os must be one of"
      assert msg =~ "mobile"
    end

    test "allows os without device specified" do
      assert :ok =
               GoogleOrganic.validate_params(%{
                 keyword: "search",
                 location_code: 2840,
                 os: "windows"
               })
    end

    test "returns error when params is not a map" do
      assert {:error, {:invalid_params, "params must be a map"}} =
               GoogleOrganic.validate_params("not a map")
    end
  end
end
