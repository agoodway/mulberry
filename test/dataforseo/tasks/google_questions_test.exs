defmodule DataForSEO.Tasks.GoogleQuestionsTest do
  use ExUnit.Case, async: true

  alias DataForSEO.Tasks.GoogleQuestions
  alias DataForSEO.Schemas.GoogleQuestionsResult

  describe "task_type/0" do
    test "returns the correct task type" do
      assert GoogleQuestions.task_type() == "business_data/google/questions_and_answers"
    end
  end

  describe "result_endpoint/0" do
    test "returns empty string for regular endpoint" do
      assert GoogleQuestions.result_endpoint() == ""
    end
  end

  describe "build_task_payload/1" do
    test "builds payload with CID" do
      params = %{cid: "12345", language_code: "en", depth: 50}
      [payload] = GoogleQuestions.build_task_payload(params)

      assert payload["keyword"] == "cid:12345"
      assert payload["language_code"] == "en"
      assert payload["depth"] == 50
    end

    test "builds payload with place_id" do
      params = %{place_id: "ChIJ123", language_code: "en"}
      [payload] = GoogleQuestions.build_task_payload(params)

      assert payload["keyword"] == "place_id:ChIJ123"
      assert payload["language_code"] == "en"
    end

    test "builds payload with keyword and location" do
      params = %{
        keyword: "The Last Bookstore",
        location_name: "Los Angeles,California,United States",
        language_code: "en"
      }

      [payload] = GoogleQuestions.build_task_payload(params)

      assert payload["keyword"] == "The Last Bookstore"
      assert payload["location_name"] == "Los Angeles,California,United States"
    end

    test "builds payload with location_code" do
      params = %{keyword: "Pizza", location_code: 2840, language_code: "en"}
      [payload] = GoogleQuestions.build_task_payload(params)

      assert payload["location_code"] == 2840
    end

    test "builds payload with location_coordinate" do
      params = %{
        keyword: "Pizza",
        location_coordinate: "40.7128,-74.0060,5",
        language_code: "en"
      }

      [payload] = GoogleQuestions.build_task_payload(params)

      assert payload["location_coordinate"] == "40.7128,-74.0060,5"
    end

    test "uses default values" do
      params = %{cid: "12345"}
      [payload] = GoogleQuestions.build_task_payload(params)

      assert payload["language_code"] == "en"
      assert payload["depth"] == 20
      assert payload["priority"] == 1
    end

    test "includes language_name when provided" do
      params = %{cid: "12345", language_name: "English"}
      [payload] = GoogleQuestions.build_task_payload(params)

      assert payload["language_name"] == "English"
    end

    test "omits nil values" do
      params = %{cid: "12345", tag: nil}
      [payload] = GoogleQuestions.build_task_payload(params)

      refute Map.has_key?(payload, "tag")
    end

    test "includes tag when provided" do
      params = %{cid: "12345", tag: "my-task-123"}
      [payload] = GoogleQuestions.build_task_payload(params)

      assert payload["tag"] == "my-task-123"
    end
  end

  describe "parse_task_response/1" do
    test "parses successful response" do
      response = %{
        "tasks" => [%{"id" => "task123", "status_code" => 20_100}]
      }

      assert {:ok, ["task123"]} = GoogleQuestions.parse_task_response(response)
    end

    test "parses multiple task IDs" do
      response = %{
        "tasks" => [
          %{"id" => "task1", "status_code" => 20_100},
          %{"id" => "task2", "status_code" => 20_100}
        ]
      }

      assert {:ok, ["task1", "task2"]} = GoogleQuestions.parse_task_response(response)
    end

    test "returns error for failed tasks" do
      response = %{
        "tasks" => [
          %{"status_code" => 40_100, "status_message" => "Invalid CID"}
        ]
      }

      assert {:error, {:task_creation_failed, "Invalid CID"}} =
               GoogleQuestions.parse_task_response(response)
    end

    test "filters out non-successful tasks" do
      response = %{
        "tasks" => [
          %{"id" => "task1", "status_code" => 20_100},
          %{"id" => "task2", "status_code" => 40_100, "status_message" => "Error"}
        ]
      }

      assert {:ok, ["task1"]} = GoogleQuestions.parse_task_response(response)
    end

    test "returns error when no successful tasks" do
      response = %{
        "tasks" => [
          %{"status_code" => 40_100, "status_message" => "Error 1"},
          %{"status_code" => 40_200, "status_message" => "Error 2"}
        ]
      }

      assert {:error, {:task_creation_failed, msg}} =
               GoogleQuestions.parse_task_response(response)

      assert msg =~ "Error 1"
      assert msg =~ "Error 2"
    end

    test "returns error for invalid response structure" do
      response = %{"invalid" => "structure"}

      assert {:error, {:invalid_response, _}} = GoogleQuestions.parse_task_response(response)
    end
  end

  describe "parse_ready_tasks/1" do
    test "parses ready tasks" do
      response = %{
        "tasks" => [
          %{"result_count" => 1, "result" => [%{"id" => "task123"}]}
        ]
      }

      assert ["task123"] = GoogleQuestions.parse_ready_tasks(response)
    end

    test "filters out tasks with no results" do
      response = %{
        "tasks" => [
          %{"result_count" => 0, "result" => []},
          %{"result_count" => 1, "result" => [%{"id" => "task456"}]}
        ]
      }

      assert ["task456"] = GoogleQuestions.parse_ready_tasks(response)
    end

    test "handles multiple ready tasks" do
      response = %{
        "tasks" => [
          %{"result_count" => 1, "result" => [%{"id" => "task1"}]},
          %{"result_count" => 2, "result" => [%{"id" => "task2"}, %{"id" => "task3"}]}
        ]
      }

      assert ["task1", "task2", "task3"] = GoogleQuestions.parse_ready_tasks(response)
    end

    test "returns empty list for invalid response" do
      assert [] = GoogleQuestions.parse_ready_tasks(%{})
    end
  end

  describe "parse_task_results/1" do
    test "parses question results with answers" do
      response = %{
        "tasks" => [
          %{
            "result" => [
              %{
                "keyword" => "The Last Bookstore",
                "cid" => "12345",
                "items_count" => 2,
                "items" => [
                  %{
                    "question_id" => "q1",
                    "question_text" => "Are you open?",
                    "items" => [
                      %{"answer_id" => "a1", "answer_text" => "Yes"}
                    ]
                  }
                ],
                "items_without_answers" => [
                  %{"question_id" => "q2", "question_text" => "Do you deliver?", "items" => []}
                ]
              }
            ]
          }
        ]
      }

      assert {:ok, %GoogleQuestionsResult{} = result} =
               GoogleQuestions.parse_task_results(response)

      assert result.metadata.keyword == "The Last Bookstore"
      assert result.metadata.cid == "12345"
      assert result.metadata.items_count == 2
      assert length(result.questions_with_answers) == 1
      assert length(result.questions_without_answers) == 1
    end

    test "returns error for task failure" do
      response = %{
        "tasks" => [
          %{"status_message" => "Task failed due to invalid parameters"}
        ]
      }

      assert {:error, {:task_failed, "Task failed due to invalid parameters"}} =
               GoogleQuestions.parse_task_results(response)
    end

    test "returns error when no results" do
      response = %{
        "tasks" => [%{}]
      }

      assert {:error, {:no_results, _}} = GoogleQuestions.parse_task_results(response)
    end

    test "returns error for invalid response structure" do
      response = %{"invalid" => "structure"}

      assert {:error, {:invalid_response, _}} = GoogleQuestions.parse_task_results(response)
    end
  end

  describe "validate_params/1" do
    test "validates with CID only" do
      assert :ok = GoogleQuestions.validate_params(%{cid: "12345"})
    end

    test "validates with CID and language_code" do
      assert :ok = GoogleQuestions.validate_params(%{cid: "12345", language_code: "en"})
    end

    test "validates with place_id and language_name" do
      assert :ok =
               GoogleQuestions.validate_params(%{place_id: "ChIJ123", language_name: "English"})
    end

    test "validates with keyword, location, and language" do
      assert :ok =
               GoogleQuestions.validate_params(%{
                 keyword: "Pizza",
                 location_name: "NYC",
                 language_code: "en"
               })
    end

    test "validates with keyword and location_code" do
      assert :ok =
               GoogleQuestions.validate_params(%{
                 keyword: "Pizza",
                 location_code: 2840,
                 language_code: "en"
               })
    end

    test "validates with keyword and location_coordinate" do
      assert :ok =
               GoogleQuestions.validate_params(%{
                 keyword: "Pizza",
                 location_coordinate: "40.7128,-74.0060,5",
                 language_code: "en"
               })
    end

    test "returns error when no business identifier" do
      assert {:error, {:invalid_params, msg}} =
               GoogleQuestions.validate_params(%{language_code: "en"})

      assert msg =~ "keyword, cid, or place_id"
    end

    test "returns error when keyword without location" do
      assert {:error, {:invalid_params, msg}} =
               GoogleQuestions.validate_params(%{keyword: "Pizza", language_code: "en"})

      assert msg =~ "Location parameter required"
    end

    test "validates depth range" do
      assert {:error, {:invalid_params, msg}} =
               GoogleQuestions.validate_params(%{cid: "123", language_code: "en", depth: 800})

      assert msg =~ "depth must be between"
    end

    test "validates depth minimum" do
      assert {:error, {:invalid_params, msg}} =
               GoogleQuestions.validate_params(%{cid: "123", language_code: "en", depth: 0})

      assert msg =~ "depth must be between"
    end

    test "accepts valid depth values" do
      assert :ok =
               GoogleQuestions.validate_params(%{cid: "123", language_code: "en", depth: 100})

      assert :ok = GoogleQuestions.validate_params(%{cid: "123", language_code: "en", depth: 1})

      assert :ok = GoogleQuestions.validate_params(%{cid: "123", language_code: "en", depth: 700})
    end

    test "returns error when params is not a map" do
      assert {:error, {:invalid_params, "params must be a map"}} =
               GoogleQuestions.validate_params("not a map")
    end
  end
end
