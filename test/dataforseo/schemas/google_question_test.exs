defmodule DataForSEO.Schemas.GoogleQuestionTest do
  use ExUnit.Case, async: true

  alias DataForSEO.Schemas.{GoogleQuestion, GoogleAnswer}

  describe "new/1" do
    test "creates question with answers" do
      attrs = %{
        "type" => "google_business_question_item",
        "question_id" => "123",
        "question_text" => "Are you open on weekends?",
        "original_question_text" => "Are you open on weekends?",
        "profile_name" => "John Doe",
        "time_ago" => "2 days ago",
        "timestamp" => "2023-01-15 10:30:00",
        "items" => [
          %{
            "type" => "google_business_answer_element",
            "answer_id" => "456",
            "answer_text" => "Yes, we are open on weekends"
          }
        ]
      }

      question = GoogleQuestion.new(attrs)

      assert question.type == "google_business_question_item"
      assert question.question_id == "123"
      assert question.question_text == "Are you open on weekends?"
      assert question.original_question_text == "Are you open on weekends?"
      assert question.profile_name == "John Doe"
      assert question.time_ago == "2 days ago"
      assert question.timestamp == "2023-01-15 10:30:00"
      assert length(question.answers) == 1
      assert %GoogleAnswer{} = hd(question.answers)
      assert hd(question.answers).answer_id == "456"
    end

    test "creates question without answers" do
      attrs = %{
        "question_id" => "789",
        "question_text" => "Do you deliver?",
        "items" => []
      }

      question = GoogleQuestion.new(attrs)

      assert question.question_id == "789"
      assert question.question_text == "Do you deliver?"
      assert question.answers == []
    end

    test "handles missing items field" do
      attrs = %{
        "question_id" => "999",
        "question_text" => "What are your hours?"
      }

      question = GoogleQuestion.new(attrs)

      assert question.question_id == "999"
      assert question.answers == []
    end
  end

  describe "answer_count/1" do
    test "returns correct count of answers" do
      question = %GoogleQuestion{
        answers: [
          %GoogleAnswer{answer_id: "1"},
          %GoogleAnswer{answer_id: "2"}
        ]
      }

      assert GoogleQuestion.answer_count(question) == 2
    end

    test "returns zero for question without answers" do
      question = %GoogleQuestion{answers: []}

      assert GoogleQuestion.answer_count(question) == 0
    end
  end

  describe "has_answers?/1" do
    test "returns true when question has answers" do
      question = %GoogleQuestion{
        answers: [%GoogleAnswer{answer_id: "1"}]
      }

      assert GoogleQuestion.has_answers?(question) == true
    end

    test "returns false when question has no answers" do
      question = %GoogleQuestion{answers: []}

      assert GoogleQuestion.has_answers?(question) == false
    end
  end
end
