defmodule DataForSEO.Schemas.GoogleQuestionsResultTest do
  use ExUnit.Case, async: true

  alias DataForSEO.Schemas.{GoogleQuestionsResult, GoogleQuestion}

  describe "new/1" do
    test "creates result with questions and metadata" do
      attrs = %{
        "keyword" => "The Last Bookstore",
        "cid" => "123456",
        "location_code" => 2840,
        "language_code" => "en",
        "check_url" => "https://example.com",
        "datetime" => "2023-01-15 10:30:00",
        "feature_id" => "feature123",
        "items_count" => 5,
        "items" => [
          %{
            "question_id" => "1",
            "question_text" => "Are you open?",
            "items" => [
              %{"answer_id" => "a1", "answer_text" => "Yes"}
            ]
          }
        ],
        "items_without_answers" => [
          %{"question_id" => "2", "question_text" => "Do you deliver?", "items" => []}
        ]
      }

      result = GoogleQuestionsResult.new(attrs)

      assert result.metadata.keyword == "The Last Bookstore"
      assert result.metadata.cid == "123456"
      assert result.metadata.location_code == 2840
      assert result.metadata.language_code == "en"
      assert result.metadata.items_count == 5
      assert length(result.questions_with_answers) == 1
      assert length(result.questions_without_answers) == 1
      assert %GoogleQuestion{} = hd(result.questions_with_answers)
      assert %GoogleQuestion{} = hd(result.questions_without_answers)
    end

    test "handles empty questions arrays" do
      attrs = %{
        "keyword" => "Test Business",
        "items" => [],
        "items_without_answers" => []
      }

      result = GoogleQuestionsResult.new(attrs)

      assert result.questions_with_answers == []
      assert result.questions_without_answers == []
      assert result.metadata.keyword == "Test Business"
    end

    test "handles missing items fields" do
      attrs = %{
        "keyword" => "Test Business"
      }

      result = GoogleQuestionsResult.new(attrs)

      assert result.questions_with_answers == []
      assert result.questions_without_answers == []
    end
  end

  describe "total_question_count/1" do
    test "returns sum of answered and unanswered questions" do
      result = %GoogleQuestionsResult{
        questions_with_answers: [
          %GoogleQuestion{question_id: "1"},
          %GoogleQuestion{question_id: "2"}
        ],
        questions_without_answers: [
          %GoogleQuestion{question_id: "3"}
        ]
      }

      assert GoogleQuestionsResult.total_question_count(result) == 3
    end

    test "returns zero when no questions" do
      result = %GoogleQuestionsResult{
        questions_with_answers: [],
        questions_without_answers: []
      }

      assert GoogleQuestionsResult.total_question_count(result) == 0
    end
  end

  describe "all_questions/1" do
    test "returns combined list of all questions" do
      with_answers = %GoogleQuestion{question_id: "1"}
      without_answers = %GoogleQuestion{question_id: "2"}

      result = %GoogleQuestionsResult{
        questions_with_answers: [with_answers],
        questions_without_answers: [without_answers]
      }

      all = GoogleQuestionsResult.all_questions(result)

      assert length(all) == 2
      assert with_answers in all
      assert without_answers in all
    end

    test "returns empty list when no questions" do
      result = %GoogleQuestionsResult{
        questions_with_answers: [],
        questions_without_answers: []
      }

      assert GoogleQuestionsResult.all_questions(result) == []
    end
  end

  describe "answered_question_count/1" do
    test "returns count of questions with answers" do
      result = %GoogleQuestionsResult{
        questions_with_answers: [
          %GoogleQuestion{question_id: "1"},
          %GoogleQuestion{question_id: "2"}
        ],
        questions_without_answers: [%GoogleQuestion{question_id: "3"}]
      }

      assert GoogleQuestionsResult.answered_question_count(result) == 2
    end

    test "returns zero when no answered questions" do
      result = %GoogleQuestionsResult{
        questions_with_answers: [],
        questions_without_answers: [%GoogleQuestion{}]
      }

      assert GoogleQuestionsResult.answered_question_count(result) == 0
    end
  end

  describe "unanswered_question_count/1" do
    test "returns count of questions without answers" do
      result = %GoogleQuestionsResult{
        questions_with_answers: [%GoogleQuestion{question_id: "1"}],
        questions_without_answers: [
          %GoogleQuestion{question_id: "2"},
          %GoogleQuestion{question_id: "3"}
        ]
      }

      assert GoogleQuestionsResult.unanswered_question_count(result) == 2
    end

    test "returns zero when no unanswered questions" do
      result = %GoogleQuestionsResult{
        questions_with_answers: [%GoogleQuestion{}],
        questions_without_answers: []
      }

      assert GoogleQuestionsResult.unanswered_question_count(result) == 0
    end
  end
end
