defmodule DataForSEO.Schemas.BusinessListingTest do
  use ExUnit.Case, async: true

  alias DataForSEO.Schemas.BusinessListing

  describe "new/1" do
    test "creates a BusinessListing struct from a map" do
      attrs = %{
        "title" => "Joe's Pizza",
        "category" => "Pizza restaurant",
        "cid" => "12345",
        "place_id" => "ChIJ123",
        "rating" => %{"value" => 4.5, "votes_count" => 150}
      }

      listing = BusinessListing.new(attrs)

      assert %BusinessListing{} = listing
      assert listing.title == "Joe's Pizza"
      assert listing.category == "Pizza restaurant"
      assert listing.cid == "12345"
      assert listing.place_id == "ChIJ123"
      assert listing.rating == %{"value" => 4.5, "votes_count" => 150}
    end

    test "handles missing optional fields" do
      attrs = %{"title" => "Minimal Listing"}

      listing = BusinessListing.new(attrs)

      assert listing.title == "Minimal Listing"
      assert is_nil(listing.cid)
      assert is_nil(listing.rating)
    end
  end

  describe "generate_id/2 with :cid strategy" do
    test "generates ID from CID by default" do
      listing = %BusinessListing{cid: "10614836463326137470"}

      assert BusinessListing.generate_id(listing) == "10614836463326137470"
    end

    test "returns nil when CID is missing" do
      listing = %BusinessListing{cid: nil}

      assert BusinessListing.generate_id(listing) == nil
    end

    test "returns nil when CID is empty string" do
      listing = %BusinessListing{cid: ""}

      assert BusinessListing.generate_id(listing) == nil
    end

    test "applies prefix when configured" do
      listing = %BusinessListing{cid: "12345"}

      assert BusinessListing.generate_id(listing, prefix: "bl_") == "bl_12345"
    end
  end

  describe "generate_id/2 with :place_id strategy" do
    test "generates ID from Place ID" do
      listing = %BusinessListing{place_id: "ChIJwX3JRSAS54gRfgxrCYZ5T5M"}

      assert BusinessListing.generate_id(listing, strategy: :place_id) ==
               "ChIJwX3JRSAS54gRfgxrCYZ5T5M"
    end

    test "returns nil when Place ID is missing" do
      listing = %BusinessListing{place_id: nil}

      assert BusinessListing.generate_id(listing, strategy: :place_id) == nil
    end

    test "applies prefix" do
      listing = %BusinessListing{place_id: "ChIJ123"}

      assert BusinessListing.generate_id(listing, strategy: :place_id, prefix: "place_") ==
               "place_ChIJ123"
    end
  end

  describe "generate_id/2 with :composite_hash strategy" do
    test "generates hash from default fields (cid + place_id)" do
      listing = %BusinessListing{
        cid: "12345",
        place_id: "ChIJ123"
      }

      id = BusinessListing.generate_id(listing, strategy: :composite_hash)

      assert is_binary(id)
      assert String.length(id) == 32
      # Verify it's a valid hex string
      assert String.match?(id, ~r/^[0-9a-f]{32}$/)
    end

    test "generates consistent hash for same inputs" do
      listing = %BusinessListing{cid: "12345", place_id: "ChIJ123"}

      id1 = BusinessListing.generate_id(listing, strategy: :composite_hash)
      id2 = BusinessListing.generate_id(listing, strategy: :composite_hash)

      assert id1 == id2
    end

    test "generates different hashes for different inputs" do
      listing1 = %BusinessListing{cid: "12345", place_id: "ChIJ123"}
      listing2 = %BusinessListing{cid: "67890", place_id: "ChIJ456"}

      id1 = BusinessListing.generate_id(listing1, strategy: :composite_hash)
      id2 = BusinessListing.generate_id(listing2, strategy: :composite_hash)

      assert id1 != id2
    end

    test "uses custom fields for composite hash" do
      listing = %BusinessListing{
        cid: "12345",
        place_id: "ChIJ123",
        latitude: 40.7128,
        longitude: -74.006
      }

      id = BusinessListing.generate_id(listing,
        strategy: :composite_hash,
        composite_fields: [:cid, :place_id, :latitude, :longitude]
      )

      assert is_binary(id)
      assert String.length(id) == 32
    end

    test "returns nil when all fields are missing" do
      listing = %BusinessListing{cid: nil, place_id: nil}

      id = BusinessListing.generate_id(listing, strategy: :composite_hash)

      assert is_nil(id)
    end

    test "handles partial field availability" do
      listing = %BusinessListing{cid: "12345", place_id: nil}

      id = BusinessListing.generate_id(listing, strategy: :composite_hash)

      # Should still generate hash with available fields
      assert is_binary(id)
      assert String.length(id) == 32
    end

    test "applies prefix to composite hash" do
      listing = %BusinessListing{cid: "12345", place_id: "ChIJ123"}

      id = BusinessListing.generate_id(listing,
        strategy: :composite_hash,
        prefix: "bl_"
      )

      assert String.starts_with?(id, "bl_")
      assert String.length(id) == 35
    end
  end

  describe "generate_id/2 with :custom strategy" do
    test "uses custom hash function" do
      listing = %BusinessListing{cid: "12345", title: "Joe's Pizza"}

      custom_fn = fn l -> "custom_#{l.cid}_#{l.title}" end

      assert BusinessListing.generate_id(listing, strategy: :custom, hash_fn: custom_fn) ==
               "custom_12345_Joe's Pizza"
    end

    test "returns nil when hash_fn not provided" do
      listing = %BusinessListing{cid: "12345"}

      assert BusinessListing.generate_id(listing, strategy: :custom) == nil
    end

    test "applies prefix to custom hash" do
      listing = %BusinessListing{cid: "12345"}

      custom_fn = fn l -> l.cid end

      assert BusinessListing.generate_id(listing,
               strategy: :custom,
               hash_fn: custom_fn,
               prefix: "custom_"
             ) == "custom_12345"
    end
  end

  describe "generate_id!/2" do
    test "returns ID when successful" do
      listing = %BusinessListing{cid: "12345"}

      assert BusinessListing.generate_id!(listing) == "12345"
    end

    test "raises when ID cannot be generated" do
      listing = %BusinessListing{cid: nil}

      assert_raise RuntimeError, "Cannot generate ID: required field is missing", fn ->
        BusinessListing.generate_id!(listing)
      end
    end

    test "raises with place_id strategy when field missing" do
      listing = %BusinessListing{place_id: nil}

      assert_raise RuntimeError, fn ->
        BusinessListing.generate_id!(listing, strategy: :place_id)
      end
    end
  end

  describe "with_id/2" do
    test "adds unique_id field to listing" do
      listing = %BusinessListing{cid: "12345", title: "Joe's Pizza"}

      result = BusinessListing.with_id(listing)

      assert result.unique_id == "12345"
      assert result.cid == "12345"
      assert result.title == "Joe's Pizza"
    end

    test "sets unique_id to nil when ID cannot be generated" do
      listing = %BusinessListing{cid: nil}

      result = BusinessListing.with_id(listing)

      assert result.unique_id == nil
    end

    test "respects strategy option" do
      listing = %BusinessListing{cid: "12345", place_id: "ChIJ123"}

      result = BusinessListing.with_id(listing, strategy: :place_id)

      assert result.unique_id == "ChIJ123"
    end

    test "applies prefix" do
      listing = %BusinessListing{cid: "12345"}

      result = BusinessListing.with_id(listing, prefix: "bl_")

      assert result.unique_id == "bl_12345"
    end
  end

  describe "configuration" do
    setup do
      # Save original config
      original_config = Application.get_env(:mulberry, DataForSEO.Schemas.BusinessListing)

      on_exit(fn ->
        # Restore original config
        if original_config do
          Application.put_env(:mulberry, DataForSEO.Schemas.BusinessListing, original_config)
        else
          Application.delete_env(:mulberry, DataForSEO.Schemas.BusinessListing)
        end
      end)

      :ok
    end

    test "uses configured strategy from application config" do
      Application.put_env(:mulberry, DataForSEO.Schemas.BusinessListing, id_strategy: :place_id)

      listing = %BusinessListing{cid: "12345", place_id: "ChIJ123"}

      # Should use :place_id from config
      assert BusinessListing.generate_id(listing) == "ChIJ123"
    end

    test "uses configured prefix from application config" do
      Application.put_env(:mulberry, DataForSEO.Schemas.BusinessListing, id_prefix: "bl_")

      listing = %BusinessListing{cid: "12345"}

      assert BusinessListing.generate_id(listing) == "bl_12345"
    end

    test "per-request options override config" do
      Application.put_env(:mulberry, DataForSEO.Schemas.BusinessListing,
        id_strategy: :cid,
        id_prefix: "bl_"
      )

      listing = %BusinessListing{cid: "12345", place_id: "ChIJ123"}

      # Override both strategy and prefix
      assert BusinessListing.generate_id(listing, strategy: :place_id, prefix: nil) == "ChIJ123"
    end

    test "uses defaults when config not set" do
      Application.delete_env(:mulberry, DataForSEO.Schemas.BusinessListing)

      listing = %BusinessListing{cid: "12345"}

      # Should use :cid strategy as default
      assert BusinessListing.generate_id(listing) == "12345"
    end
  end
end
