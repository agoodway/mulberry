defmodule DataForSEO.Schemas.BusinessListingsResultTest do
  use ExUnit.Case, async: true

  alias DataForSEO.Schemas.{BusinessListingsResult, BusinessListing}

  describe "new/1" do
    test "creates a BusinessListingsResult with items and IDs" do
      attrs = %{
        "total_count" => 2,
        "items" => [
          %{
            "title" => "Joe's Pizza",
            "cid" => "12345",
            "place_id" => "ChIJ123"
          },
          %{
            "title" => "Tony's Pizza",
            "cid" => "67890",
            "place_id" => "ChIJ456"
          }
        ]
      }

      result = BusinessListingsResult.new(attrs)

      assert result.total_count == 2
      assert length(result.items) == 2

      # Verify unique_id is added to each item
      first_item = Enum.at(result.items, 0)
      assert first_item.unique_id == "12345"
      assert first_item.cid == "12345"

      second_item = Enum.at(result.items, 1)
      assert second_item.unique_id == "67890"
      assert second_item.cid == "67890"
    end

    test "handles items with missing CID" do
      attrs = %{
        "total_count" => 1,
        "items" => [
          %{"title" => "No CID Business", "cid" => nil}
        ]
      }

      result = BusinessListingsResult.new(attrs)

      assert length(result.items) == 1
      first_item = Enum.at(result.items, 0)
      assert first_item.unique_id == nil
    end

    test "handles empty items list" do
      attrs = %{
        "total_count" => 0,
        "items" => []
      }

      result = BusinessListingsResult.new(attrs)

      assert result.total_count == 0
      assert result.items == []
    end

    test "uses configured ID strategy" do
      # Configure to use place_id
      Application.put_env(:mulberry, DataForSEO.Schemas.BusinessListing, id_strategy: :place_id)

      on_exit(fn ->
        Application.delete_env(:mulberry, DataForSEO.Schemas.BusinessListing)
      end)

      attrs = %{
        "total_count" => 1,
        "items" => [
          %{"cid" => "12345", "place_id" => "ChIJ123"}
        ]
      }

      result = BusinessListingsResult.new(attrs)

      first_item = Enum.at(result.items, 0)
      assert first_item.unique_id == "ChIJ123"
    end

    test "preserves all other fields while adding unique_id" do
      attrs = %{
        "total_count" => 1,
        "items" => [
          %{
            "title" => "Full Business",
            "cid" => "12345",
            "category" => "Restaurant",
            "address" => "123 Main St",
            "phone" => "+1-555-0100",
            "rating" => %{"value" => 4.5, "votes_count" => 100}
          }
        ]
      }

      result = BusinessListingsResult.new(attrs)

      first_item = Enum.at(result.items, 0)
      assert first_item.unique_id == "12345"
      assert first_item.title == "Full Business"
      assert first_item.category == "Restaurant"
      assert first_item.address == "123 Main St"
      assert first_item.phone == "+1-555-0100"
      assert first_item.rating == %{"value" => 4.5, "votes_count" => 100}
    end
  end
end
