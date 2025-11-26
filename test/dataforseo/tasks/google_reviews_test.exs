defmodule DataForSEO.Tasks.GoogleReviewsTest do
  use ExUnit.Case, async: true

  alias DataForSEO.Tasks.GoogleReviews
  alias DataForSEO.Schemas.GoogleReviewsResult

  describe "task_type/0" do
    test "returns the correct task type" do
      assert GoogleReviews.task_type() == "business_data/google/reviews"
    end
  end

  describe "build_task_payload/1" do
    test "builds payload with CID" do
      params = %{cid: "12345", language_code: "en", depth: 100}
      [payload] = GoogleReviews.build_task_payload(params)

      assert payload["cid"] == "12345"
      assert payload["language_code"] == "en"
      assert payload["depth"] == 100
    end

    test "builds payload with place_id" do
      params = %{place_id: "ChIJ123", language_code: "en"}
      [payload] = GoogleReviews.build_task_payload(params)

      assert payload["place_id"] == "ChIJ123"
      assert payload["language_code"] == "en"
    end

    test "builds payload with keyword and location" do
      params = %{keyword: "Joe's Pizza", location_name: "New York", language_code: "en"}
      [payload] = GoogleReviews.build_task_payload(params)

      assert payload["keyword"] == "Joe's Pizza"
      assert payload["location_name"] == "New York"
    end

    test "uses default values" do
      params = %{cid: "12345"}
      [payload] = GoogleReviews.build_task_payload(params)

      assert payload["language_code"] == "en"
      assert payload["depth"] == 10
      assert payload["priority"] == 1
    end

    test "includes sort_by when provided" do
      params = %{cid: "12345", sort_by: "newest"}
      [payload] = GoogleReviews.build_task_payload(params)

      assert payload["sort_by"] == "newest"
    end

    test "omits nil values" do
      params = %{cid: "12345", sort_by: nil}
      [payload] = GoogleReviews.build_task_payload(params)

      refute Map.has_key?(payload, "sort_by")
    end
  end

  describe "parse_task_response/1" do
    test "parses successful response" do
      response = %{
        "tasks" => [%{"id" => "task123", "status_code" => 20_100}]
      }

      assert {:ok, ["task123"]} = GoogleReviews.parse_task_response(response)
    end

    test "returns error for failed tasks" do
      response = %{
        "tasks" => [%{"status_code" => 40_100, "status_message" => "Invalid CID"}]
      }

      assert {:error, {:task_creation_failed, "Invalid CID"}} =
               GoogleReviews.parse_task_response(response)
    end
  end

  describe "parse_ready_tasks/1" do
    test "parses ready tasks" do
      response = %{
        "tasks" => [
          %{"result_count" => 1, "result" => [%{"id" => "task123"}]}
        ]
      }

      assert ["task123"] = GoogleReviews.parse_ready_tasks(response)
    end
  end

  describe "parse_task_results/1" do
    test "parses review results" do
      response = %{
        "tasks" => [
          %{
            "result" => [
              %{
                "keyword" => "Joe's Pizza",
                "cid" => "12345",
                "reviews_count" => 150,
                "items" => [
                  %{"review_text" => "Great!", "rating" => %{"value" => 5}}
                ]
              }
            ]
          }
        ]
      }

      assert {:ok, %GoogleReviewsResult{} = result} = GoogleReviews.parse_task_results(response)
      assert result.keyword == "Joe's Pizza"
      assert result.reviews_count == 150
      assert length(result.reviews) == 1
    end
  end

  describe "validate_params/1" do
    test "validates with CID" do
      assert :ok = GoogleReviews.validate_params(%{cid: "12345"})
    end

    test "validates with place_id" do
      assert :ok = GoogleReviews.validate_params(%{place_id: "ChIJ123"})
    end

    test "validates with keyword and location" do
      assert :ok = GoogleReviews.validate_params(%{keyword: "Pizza", location_name: "NYC"})
    end

    test "returns error when no identifier" do
      assert {:error, {:invalid_params, msg}} = GoogleReviews.validate_params(%{})
      assert msg =~ "keyword, cid, or place_id"
    end

    test "returns error when keyword without location" do
      assert {:error, {:invalid_params, msg}} =
               GoogleReviews.validate_params(%{keyword: "Pizza"})

      assert msg =~ "Location parameter required"
    end

    test "validates depth range" do
      assert {:error, {:invalid_params, msg}} =
               GoogleReviews.validate_params(%{cid: "123", depth: 5000})

      assert msg =~ "depth must be between"
    end

    test "validates sort_by values" do
      assert {:error, {:invalid_params, msg}} =
               GoogleReviews.validate_params(%{cid: "123", sort_by: "invalid"})

      assert msg =~ "sort_by must be one of"
    end
  end
end
