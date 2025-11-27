defmodule DataForSEO.Tasks.GoogleNewsTest do
  use ExUnit.Case, async: true

  alias DataForSEO.Tasks.GoogleNews
  alias DataForSEO.Schemas.GoogleNewsResult

  describe "task_type/0" do
    test "returns the correct task type" do
      assert GoogleNews.task_type() == "serp/google/news"
    end
  end

  describe "result_endpoint/0" do
    test "returns advanced endpoint" do
      assert GoogleNews.result_endpoint() == "advanced"
    end
  end

  describe "build_task_payload/1" do
    test "builds payload with keyword and location_name" do
      params = %{
        keyword: "artificial intelligence",
        location_name: "United States",
        language_code: "en",
        depth: 50
      }

      [payload] = GoogleNews.build_task_payload(params)

      assert payload["keyword"] == "artificial intelligence"
      assert payload["location_name"] == "United States"
      assert payload["language_code"] == "en"
      assert payload["depth"] == 50
    end

    test "builds payload with location_code" do
      params = %{
        keyword: "climate change",
        location_code: 2840,
        language_code: "en"
      }

      [payload] = GoogleNews.build_task_payload(params)

      assert payload["keyword"] == "climate change"
      assert payload["location_code"] == 2840
    end

    test "builds payload with os parameter" do
      params = %{
        keyword: "technology news",
        location_code: 2840,
        os: "macos"
      }

      [payload] = GoogleNews.build_task_payload(params)

      assert payload["os"] == "macos"
    end

    test "uses default values" do
      params = %{keyword: "news", location_code: 2840}
      [payload] = GoogleNews.build_task_payload(params)

      assert payload["language_code"] == "en"
      assert payload["depth"] == 10
      assert payload["priority"] == 1
    end

    test "includes language_name when provided" do
      params = %{
        keyword: "news",
        location_code: 2840,
        language_name: "English"
      }

      [payload] = GoogleNews.build_task_payload(params)

      assert payload["language_name"] == "English"
    end

    test "omits nil values" do
      params = %{
        keyword: "news",
        location_code: 2840,
        tag: nil,
        os: nil
      }

      [payload] = GoogleNews.build_task_payload(params)

      refute Map.has_key?(payload, "tag")
      refute Map.has_key?(payload, "os")
    end

    test "includes tag when provided" do
      params = %{
        keyword: "news",
        location_code: 2840,
        tag: "my-task-123"
      }

      [payload] = GoogleNews.build_task_payload(params)

      assert payload["tag"] == "my-task-123"
    end

    test "includes priority when provided" do
      params = %{
        keyword: "news",
        location_code: 2840,
        priority: 2
      }

      [payload] = GoogleNews.build_task_payload(params)

      assert payload["priority"] == 2
    end
  end

  describe "parse_task_response/1" do
    test "parses successful response" do
      response = %{
        "tasks" => [%{"id" => "task123", "status_code" => 20_100}]
      }

      assert {:ok, ["task123"]} = GoogleNews.parse_task_response(response)
    end

    test "parses multiple task IDs" do
      response = %{
        "tasks" => [
          %{"id" => "task1", "status_code" => 20_100},
          %{"id" => "task2", "status_code" => 20_100}
        ]
      }

      assert {:ok, ["task1", "task2"]} = GoogleNews.parse_task_response(response)
    end

    test "returns error for failed tasks" do
      response = %{
        "tasks" => [
          %{"status_code" => 40_100, "status_message" => "Invalid keyword"}
        ]
      }

      assert {:error, {:task_creation_failed, "Invalid keyword"}} =
               GoogleNews.parse_task_response(response)
    end

    test "filters out non-successful tasks" do
      response = %{
        "tasks" => [
          %{"id" => "task1", "status_code" => 20_100},
          %{"id" => "task2", "status_code" => 40_100, "status_message" => "Error"}
        ]
      }

      assert {:ok, ["task1"]} = GoogleNews.parse_task_response(response)
    end

    test "returns error when no successful tasks" do
      response = %{
        "tasks" => [
          %{"status_code" => 40_100, "status_message" => "Error 1"},
          %{"status_code" => 40_200, "status_message" => "Error 2"}
        ]
      }

      assert {:error, {:task_creation_failed, msg}} = GoogleNews.parse_task_response(response)
      assert msg =~ "Error 1"
      assert msg =~ "Error 2"
    end

    test "returns error for invalid response structure" do
      response = %{"invalid" => "structure"}

      assert {:error, {:invalid_response, _}} = GoogleNews.parse_task_response(response)
    end
  end

  describe "parse_ready_tasks/1" do
    test "parses ready tasks" do
      response = %{
        "tasks" => [
          %{"result_count" => 1, "result" => [%{"id" => "task123"}]}
        ]
      }

      assert ["task123"] = GoogleNews.parse_ready_tasks(response)
    end

    test "filters out tasks with no results" do
      response = %{
        "tasks" => [
          %{"result_count" => 0, "result" => []},
          %{"result_count" => 1, "result" => [%{"id" => "task456"}]}
        ]
      }

      assert ["task456"] = GoogleNews.parse_ready_tasks(response)
    end

    test "handles multiple ready tasks" do
      response = %{
        "tasks" => [
          %{"result_count" => 1, "result" => [%{"id" => "task1"}]},
          %{"result_count" => 2, "result" => [%{"id" => "task2"}, %{"id" => "task3"}]}
        ]
      }

      assert ["task1", "task2", "task3"] = GoogleNews.parse_ready_tasks(response)
    end

    test "returns empty list for invalid response" do
      assert [] = GoogleNews.parse_ready_tasks(%{})
    end
  end

  describe "parse_task_results/1" do
    test "parses news results" do
      response = %{
        "tasks" => [
          %{
            "result" => [
              %{
                "keyword" => "artificial intelligence",
                "location_code" => 2840,
                "language_code" => "en",
                "se_domain" => "google.com",
                "check_url" => "https://google.com/...",
                "datetime" => "2025-01-27 12:00:00",
                "se_results_count" => 1000,
                "items_count" => 50,
                "type" => "news",
                "items" => [
                  %{
                    "type" => "news_search",
                    "title" => "AI Breakthrough Announced",
                    "source" => "TechCrunch",
                    "domain" => "techcrunch.com",
                    "url" => "https://techcrunch.com/article",
                    "snippet" => "Major AI advancement...",
                    "time_published" => "2 hours ago"
                  },
                  %{
                    "type" => "news_search",
                    "title" => "New AI Regulation",
                    "source" => "CNN",
                    "domain" => "cnn.com",
                    "url" => "https://cnn.com/article",
                    "time_published" => "5 hours ago"
                  }
                ]
              }
            ]
          }
        ]
      }

      assert {:ok, %GoogleNewsResult{} = result} = GoogleNews.parse_task_results(response)
      assert result.keyword == "artificial intelligence"
      assert result.location_code == 2840
      assert result.language_code == "en"
      assert result.items_count == 50
      assert result.se_results_count == 1000
      assert length(result.news_items) == 2
      assert hd(result.news_items).title == "AI Breakthrough Announced"
    end

    test "returns error for task failure" do
      response = %{
        "tasks" => [
          %{"status_message" => "Task failed due to invalid parameters"}
        ]
      }

      assert {:error, {:task_failed, "Task failed due to invalid parameters"}} =
               GoogleNews.parse_task_results(response)
    end

    test "returns error when no results" do
      response = %{
        "tasks" => [%{}]
      }

      assert {:error, {:no_results, _}} = GoogleNews.parse_task_results(response)
    end

    test "returns error for invalid response structure" do
      response = %{"invalid" => "structure"}

      assert {:error, {:invalid_response, _}} = GoogleNews.parse_task_results(response)
    end
  end

  describe "validate_params/1" do
    test "validates with keyword and location_name" do
      assert :ok =
               GoogleNews.validate_params(%{
                 keyword: "news",
                 location_name: "United States"
               })
    end

    test "validates with keyword and location_code" do
      assert :ok =
               GoogleNews.validate_params(%{
                 keyword: "news",
                 location_code: 2840
               })
    end

    test "validates with all optional parameters" do
      assert :ok =
               GoogleNews.validate_params(%{
                 keyword: "news",
                 location_code: 2840,
                 language_code: "en",
                 depth: 50,
                 os: "macos",
                 priority: 2,
                 tag: "test-123"
               })
    end

    test "returns error when keyword missing" do
      assert {:error, {:invalid_params, msg}} =
               GoogleNews.validate_params(%{location_code: 2840})

      assert msg =~ "keyword is required"
    end

    test "returns error when location missing" do
      assert {:error, {:invalid_params, msg}} = GoogleNews.validate_params(%{keyword: "news"})

      assert msg =~ "Location parameter required"
    end

    test "validates depth range - too high" do
      assert {:error, {:invalid_params, msg}} =
               GoogleNews.validate_params(%{
                 keyword: "news",
                 location_code: 2840,
                 depth: 800
               })

      assert msg =~ "depth must be between 1 and 700"
    end

    test "validates depth range - too low" do
      assert {:error, {:invalid_params, msg}} =
               GoogleNews.validate_params(%{
                 keyword: "news",
                 location_code: 2840,
                 depth: 0
               })

      assert msg =~ "depth must be between 1 and 700"
    end

    test "accepts valid depth values" do
      assert :ok =
               GoogleNews.validate_params(%{
                 keyword: "news",
                 location_code: 2840,
                 depth: 1
               })

      assert :ok =
               GoogleNews.validate_params(%{
                 keyword: "news",
                 location_code: 2840,
                 depth: 100
               })

      assert :ok =
               GoogleNews.validate_params(%{
                 keyword: "news",
                 location_code: 2840,
                 depth: 700
               })
    end

    test "validates os - valid values" do
      assert :ok =
               GoogleNews.validate_params(%{
                 keyword: "news",
                 location_code: 2840,
                 os: "windows"
               })

      assert :ok =
               GoogleNews.validate_params(%{
                 keyword: "news",
                 location_code: 2840,
                 os: "macos"
               })
    end

    test "validates os - invalid value" do
      assert {:error, {:invalid_params, msg}} =
               GoogleNews.validate_params(%{
                 keyword: "news",
                 location_code: 2840,
                 os: "linux"
               })

      assert msg =~ "os must be one of"
    end

    test "validates os - must be string" do
      assert {:error, {:invalid_params, msg}} =
               GoogleNews.validate_params(%{
                 keyword: "news",
                 location_code: 2840,
                 os: 123
               })

      assert msg =~ "os must be one of"
    end

    test "returns error when params is not a map" do
      assert {:error, {:invalid_params, "params must be a map"}} =
               GoogleNews.validate_params("not a map")
    end
  end
end
