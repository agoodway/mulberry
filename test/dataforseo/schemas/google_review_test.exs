defmodule DataForSEO.Schemas.GoogleReviewTest do
  use ExUnit.Case, async: true

  alias DataForSEO.Schemas.GoogleReview

  describe "new/1" do
    test "creates struct from map" do
      attrs = %{
        "review_id" => "abc123",
        "review_text" => "Great place!",
        "rating" => %{"value" => 5},
        "profile_name" => "John Doe"
      }

      review = GoogleReview.new(attrs)

      assert review.review_id == "abc123"
      assert review.review_text == "Great place!"
      assert review.profile_name == "John Doe"
    end
  end
end
