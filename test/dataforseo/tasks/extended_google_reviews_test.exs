defmodule DataForSEO.Tasks.ExtendedGoogleReviewsTest do
  use ExUnit.Case, async: true

  alias DataForSEO.Tasks.ExtendedGoogleReviews
  alias DataForSEO.Schemas.GoogleReviewsResult

  describe "task_type/0" do
    test "returns the correct task type" do
      assert ExtendedGoogleReviews.task_type() == "business_data/google/extended_reviews"
    end
  end

  describe "build_task_payload/1" do
    test "uses default depth of 20" do
      params = %{cid: "12345"}
      [payload] = ExtendedGoogleReviews.build_task_payload(params)
      assert payload["depth"] == 20
    end

    test "validates max depth of 1000" do
      params = %{cid: "12345", depth: 1001}
      assert {:error, {:invalid_params, msg}} = ExtendedGoogleReviews.validate_params(params)
      assert msg =~ "between 1 and 1000"
    end
  end

  describe "validate_params/1" do
    test "validates with CID" do
      assert :ok = ExtendedGoogleReviews.validate_params(%{cid: "12345"})
    end
  end
end
