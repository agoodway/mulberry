defmodule DataForSEO.Schemas.GoogleReviewsResultTest do
  use ExUnit.Case, async: true

  alias DataForSEO.Schemas.{GoogleReviewsResult, GoogleReview}

  describe "new/1" do
    test "creates result with reviews" do
      attrs = %{
        "keyword" => "Joe's Pizza",
        "reviews_count" => 150,
        "items" => [
          %{"review_text" => "Great!", "rating" => %{"value" => 5}}
        ]
      }

      result = GoogleReviewsResult.new(attrs)

      assert result.keyword == "Joe's Pizza"
      assert result.reviews_count == 150
      assert length(result.reviews) == 1
      assert %GoogleReview{} = hd(result.reviews)
    end
  end
end
