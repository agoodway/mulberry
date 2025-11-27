defmodule DataForSEO.Tasks.GoogleJobsTest do
  use ExUnit.Case, async: true

  alias DataForSEO.Tasks.GoogleJobs
  alias DataForSEO.Schemas.GoogleJobsResult

  describe "task_type/0" do
    test "returns the correct task type" do
      assert GoogleJobs.task_type() == "serp/google/jobs"
    end
  end

  describe "result_endpoint/0" do
    test "returns advanced endpoint" do
      assert GoogleJobs.result_endpoint() == "advanced"
    end
  end

  describe "build_task_payload/1" do
    test "builds payload with keyword and location_name" do
      params = %{
        keyword: "elixir developer",
        location_name: "San Francisco,California,United States",
        language_code: "en",
        depth: 50
      }

      [payload] = GoogleJobs.build_task_payload(params)

      assert payload["keyword"] == "elixir developer"
      assert payload["location_name"] == "San Francisco,California,United States"
      assert payload["language_code"] == "en"
      assert payload["depth"] == 50
    end

    test "builds payload with location_code" do
      params = %{
        keyword: ".net developer",
        location_code: 2840,
        language_code: "en"
      }

      [payload] = GoogleJobs.build_task_payload(params)

      assert payload["keyword"] == ".net developer"
      assert payload["location_code"] == 2840
    end

    test "builds payload with employment_type filter" do
      params = %{
        keyword: "software engineer",
        location_code: 2840,
        employment_type: ["fulltime", "contractor"]
      }

      [payload] = GoogleJobs.build_task_payload(params)

      assert payload["employment_type"] == ["fulltime", "contractor"]
    end

    test "builds payload with location_radius" do
      params = %{
        keyword: "data scientist",
        location_name: "New York,NY,United States",
        location_radius: 50.0
      }

      [payload] = GoogleJobs.build_task_payload(params)

      assert payload["location_radius"] == 50.0
    end

    test "uses default values" do
      params = %{keyword: "developer", location_code: 2840}
      [payload] = GoogleJobs.build_task_payload(params)

      assert payload["language_code"] == "en"
      assert payload["depth"] == 10
      assert payload["priority"] == 1
    end

    test "includes language_name when provided" do
      params = %{
        keyword: "developer",
        location_code: 2840,
        language_name: "English"
      }

      [payload] = GoogleJobs.build_task_payload(params)

      assert payload["language_name"] == "English"
    end

    test "omits nil values" do
      params = %{
        keyword: "developer",
        location_code: 2840,
        tag: nil,
        employment_type: nil
      }

      [payload] = GoogleJobs.build_task_payload(params)

      refute Map.has_key?(payload, "tag")
      refute Map.has_key?(payload, "employment_type")
    end

    test "includes tag when provided" do
      params = %{
        keyword: "developer",
        location_code: 2840,
        tag: "my-task-123"
      }

      [payload] = GoogleJobs.build_task_payload(params)

      assert payload["tag"] == "my-task-123"
    end

    test "includes priority when provided" do
      params = %{
        keyword: "developer",
        location_code: 2840,
        priority: 2
      }

      [payload] = GoogleJobs.build_task_payload(params)

      assert payload["priority"] == 2
    end
  end

  describe "parse_task_response/1" do
    test "parses successful response" do
      response = %{
        "tasks" => [%{"id" => "task123", "status_code" => 20_100}]
      }

      assert {:ok, ["task123"]} = GoogleJobs.parse_task_response(response)
    end

    test "parses multiple task IDs" do
      response = %{
        "tasks" => [
          %{"id" => "task1", "status_code" => 20_100},
          %{"id" => "task2", "status_code" => 20_100}
        ]
      }

      assert {:ok, ["task1", "task2"]} = GoogleJobs.parse_task_response(response)
    end

    test "returns error for failed tasks" do
      response = %{
        "tasks" => [
          %{"status_code" => 40_100, "status_message" => "Invalid keyword"}
        ]
      }

      assert {:error, {:task_creation_failed, "Invalid keyword"}} =
               GoogleJobs.parse_task_response(response)
    end

    test "filters out non-successful tasks" do
      response = %{
        "tasks" => [
          %{"id" => "task1", "status_code" => 20_100},
          %{"id" => "task2", "status_code" => 40_100, "status_message" => "Error"}
        ]
      }

      assert {:ok, ["task1"]} = GoogleJobs.parse_task_response(response)
    end

    test "returns error when no successful tasks" do
      response = %{
        "tasks" => [
          %{"status_code" => 40_100, "status_message" => "Error 1"},
          %{"status_code" => 40_200, "status_message" => "Error 2"}
        ]
      }

      assert {:error, {:task_creation_failed, msg}} = GoogleJobs.parse_task_response(response)
      assert msg =~ "Error 1"
      assert msg =~ "Error 2"
    end

    test "returns error for invalid response structure" do
      response = %{"invalid" => "structure"}

      assert {:error, {:invalid_response, _}} = GoogleJobs.parse_task_response(response)
    end
  end

  describe "parse_ready_tasks/1" do
    test "parses ready tasks" do
      response = %{
        "tasks" => [
          %{"result_count" => 1, "result" => [%{"id" => "task123"}]}
        ]
      }

      assert ["task123"] = GoogleJobs.parse_ready_tasks(response)
    end

    test "filters out tasks with no results" do
      response = %{
        "tasks" => [
          %{"result_count" => 0, "result" => []},
          %{"result_count" => 1, "result" => [%{"id" => "task456"}]}
        ]
      }

      assert ["task456"] = GoogleJobs.parse_ready_tasks(response)
    end

    test "handles multiple ready tasks" do
      response = %{
        "tasks" => [
          %{"result_count" => 1, "result" => [%{"id" => "task1"}]},
          %{"result_count" => 2, "result" => [%{"id" => "task2"}, %{"id" => "task3"}]}
        ]
      }

      assert ["task1", "task2", "task3"] = GoogleJobs.parse_ready_tasks(response)
    end

    test "returns empty list for invalid response" do
      assert [] = GoogleJobs.parse_ready_tasks(%{})
    end
  end

  describe "parse_task_results/1" do
    test "parses job results" do
      response = %{
        "tasks" => [
          %{
            "result" => [
              %{
                "keyword" => "elixir developer",
                "location_code" => 2840,
                "language_code" => "en",
                "se_domain" => "google.com",
                "check_url" => "https://google.com/...",
                "datetime" => "2025-01-27 12:00:00",
                "items_count" => 2,
                "type" => "jobs",
                "items" => [
                  %{
                    "job_id" => "job1",
                    "title" => "Senior Elixir Engineer",
                    "employer_name" => "Tech Corp",
                    "contract_type" => "Full-time",
                    "location" => "San Francisco, CA"
                  },
                  %{
                    "job_id" => "job2",
                    "title" => "Elixir Developer",
                    "employer_name" => "StartupCo",
                    "contract_type" => "Contract",
                    "salary" => "$100,000 - $150,000"
                  }
                ]
              }
            ]
          }
        ]
      }

      assert {:ok, %GoogleJobsResult{} = result} = GoogleJobs.parse_task_results(response)
      assert result.keyword == "elixir developer"
      assert result.location_code == 2840
      assert result.language_code == "en"
      assert result.items_count == 2
      assert length(result.jobs) == 2
      assert hd(result.jobs).title == "Senior Elixir Engineer"
    end

    test "returns error for task failure" do
      response = %{
        "tasks" => [
          %{"status_message" => "Task failed due to invalid parameters"}
        ]
      }

      assert {:error, {:task_failed, "Task failed due to invalid parameters"}} =
               GoogleJobs.parse_task_results(response)
    end

    test "returns error when no results" do
      response = %{
        "tasks" => [%{}]
      }

      assert {:error, {:no_results, _}} = GoogleJobs.parse_task_results(response)
    end

    test "returns error for invalid response structure" do
      response = %{"invalid" => "structure"}

      assert {:error, {:invalid_response, _}} = GoogleJobs.parse_task_results(response)
    end
  end

  describe "validate_params/1" do
    test "validates with keyword and location_name" do
      assert :ok =
               GoogleJobs.validate_params(%{
                 keyword: "developer",
                 location_name: "United States"
               })
    end

    test "validates with keyword and location_code" do
      assert :ok =
               GoogleJobs.validate_params(%{
                 keyword: "developer",
                 location_code: 2840
               })
    end

    test "validates with all optional parameters" do
      assert :ok =
               GoogleJobs.validate_params(%{
                 keyword: "developer",
                 location_code: 2840,
                 language_code: "en",
                 depth: 50,
                 employment_type: ["fulltime", "contractor"],
                 location_radius: 100.0,
                 priority: 2,
                 tag: "test-123"
               })
    end

    test "returns error when keyword missing" do
      assert {:error, {:invalid_params, msg}} =
               GoogleJobs.validate_params(%{location_code: 2840})

      assert msg =~ "keyword is required"
    end

    test "returns error when location missing" do
      assert {:error, {:invalid_params, msg}} =
               GoogleJobs.validate_params(%{keyword: "developer"})

      assert msg =~ "Location parameter required"
    end

    test "validates depth range - too high" do
      assert {:error, {:invalid_params, msg}} =
               GoogleJobs.validate_params(%{
                 keyword: "developer",
                 location_code: 2840,
                 depth: 250
               })

      assert msg =~ "depth must be between 1 and 200"
    end

    test "validates depth range - too low" do
      assert {:error, {:invalid_params, msg}} =
               GoogleJobs.validate_params(%{
                 keyword: "developer",
                 location_code: 2840,
                 depth: 0
               })

      assert msg =~ "depth must be between 1 and 200"
    end

    test "accepts valid depth values" do
      assert :ok =
               GoogleJobs.validate_params(%{
                 keyword: "developer",
                 location_code: 2840,
                 depth: 1
               })

      assert :ok =
               GoogleJobs.validate_params(%{
                 keyword: "developer",
                 location_code: 2840,
                 depth: 100
               })

      assert :ok =
               GoogleJobs.validate_params(%{
                 keyword: "developer",
                 location_code: 2840,
                 depth: 200
               })
    end

    test "validates employment_type - valid values" do
      assert :ok =
               GoogleJobs.validate_params(%{
                 keyword: "developer",
                 location_code: 2840,
                 employment_type: ["fulltime"]
               })

      assert :ok =
               GoogleJobs.validate_params(%{
                 keyword: "developer",
                 location_code: 2840,
                 employment_type: ["fulltime", "partime", "contractor", "intern"]
               })
    end

    test "validates employment_type - invalid values" do
      assert {:error, {:invalid_params, msg}} =
               GoogleJobs.validate_params(%{
                 keyword: "developer",
                 location_code: 2840,
                 employment_type: ["invalid_type"]
               })

      assert msg =~ "employment_type must be a list containing only"
    end

    test "validates employment_type - must be list" do
      assert {:error, {:invalid_params, msg}} =
               GoogleJobs.validate_params(%{
                 keyword: "developer",
                 location_code: 2840,
                 employment_type: "fulltime"
               })

      assert msg =~ "employment_type must be a list"
    end

    test "validates location_radius - valid values" do
      assert :ok =
               GoogleJobs.validate_params(%{
                 keyword: "developer",
                 location_code: 2840,
                 location_radius: 50.0
               })

      assert :ok =
               GoogleJobs.validate_params(%{
                 keyword: "developer",
                 location_code: 2840,
                 location_radius: 300.0
               })

      assert :ok =
               GoogleJobs.validate_params(%{
                 keyword: "developer",
                 location_code: 2840,
                 location_radius: 1
               })
    end

    test "validates location_radius - too high" do
      assert {:error, {:invalid_params, msg}} =
               GoogleJobs.validate_params(%{
                 keyword: "developer",
                 location_code: 2840,
                 location_radius: 400.0
               })

      assert msg =~ "location_radius must be a number <= 300"
    end

    test "validates location_radius - must be positive" do
      assert {:error, {:invalid_params, msg}} =
               GoogleJobs.validate_params(%{
                 keyword: "developer",
                 location_code: 2840,
                 location_radius: 0
               })

      assert msg =~ "location_radius must be a number <= 300"
    end

    test "validates location_radius - must be numeric" do
      assert {:error, {:invalid_params, msg}} =
               GoogleJobs.validate_params(%{
                 keyword: "developer",
                 location_code: 2840,
                 location_radius: "fifty"
               })

      assert msg =~ "location_radius must be a number"
    end

    test "returns error when params is not a map" do
      assert {:error, {:invalid_params, "params must be a map"}} =
               GoogleJobs.validate_params("not a map")
    end
  end
end
