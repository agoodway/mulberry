defmodule Mix.Tasks.BusinessListingsTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  import Mimic

  alias Mix.Tasks.BusinessListings
  alias DataForSEO.Schemas.{BusinessListing, BusinessListingsResult}

  setup :set_mimic_global
  setup :verify_on_exit!

  describe "build_task_params/1" do
    test "builds params with categories" do
      opts = [categories: "pizza_restaurant,italian_restaurant"]

      params = BusinessListings.build_task_params(opts)

      assert params[:categories] == ["pizza_restaurant", "italian_restaurant"]
    end

    test "builds params with location coordinate" do
      opts = [location: "40.7128,-74.0060,5"]

      params = BusinessListings.build_task_params(opts)

      assert params[:location_coordinate] == "40.7128,-74.0060,5"
    end

    test "builds params with title and description" do
      opts = [title: "Joe's Pizza", description: "Best pizza"]

      params = BusinessListings.build_task_params(opts)

      assert params[:title] == "Joe's Pizza"
      assert params[:description] == "Best pizza"
    end

    test "builds params with claimed flag" do
      opts = [claimed: true]

      params = BusinessListings.build_task_params(opts)

      assert params[:is_claimed] == true
    end

    test "builds params with single filter" do
      opts = [filters: "rating.value,>,4"]

      params = BusinessListings.build_task_params(opts)

      assert params[:filters] == [["rating.value", ">", 4]]
    end

    test "builds params with multiple filters" do
      # OptionParser with :keep creates multiple keys, not a list value
      opts = [
        filters: "rating.value,>,4.5",
        filters: "rating.votes_count,>,100",
        filters: "is_claimed,=,true"
      ]

      params = BusinessListings.build_task_params(opts)

      assert params[:filters] == [
               ["rating.value", ">", 4.5],
               ["rating.votes_count", ">", 100],
               ["is_claimed", "=", true]
             ]
    end

    test "builds params with order_by" do
      # OptionParser with :keep creates multiple keys, not a list value
      opts = [order_by: "rating.value,desc", order_by: "rating.votes_count,desc"]

      params = BusinessListings.build_task_params(opts)

      assert params[:order_by] == [
               ["rating.value", "desc"],
               ["rating.votes_count", "desc"]
             ]
    end

    test "builds params with limit and offset" do
      opts = [limit: 50, offset: 100]

      params = BusinessListings.build_task_params(opts)

      assert params[:limit] == 50
      assert params[:offset] == 100
    end

    test "builds params with all options" do
      opts = [
        categories: "restaurant",
        location: "40.7128,-74.0060,5",
        title: "Pizza",
        description: "Italian",
        claimed: true,
        filters: "rating.value,>,4",
        order_by: "rating.value,desc",
        limit: 100,
        offset: 0
      ]

      params = BusinessListings.build_task_params(opts)

      assert params[:categories] == ["restaurant"]
      assert params[:location_coordinate] == "40.7128,-74.0060,5"
      assert params[:title] == "Pizza"
      assert params[:description] == "Italian"
      assert params[:is_claimed] == true
      assert params[:filters] == [["rating.value", ">", 4]]
      assert params[:order_by] == [["rating.value", "desc"]]
      assert params[:limit] == 100
      assert params[:offset] == 0
    end

    test "handles empty options" do
      opts = []

      params = BusinessListings.build_task_params(opts)

      assert params == %{}
    end

    test "trims whitespace in categories" do
      opts = [categories: " pizza_restaurant , italian_restaurant "]

      params = BusinessListings.build_task_params(opts)

      assert params[:categories] == ["pizza_restaurant", "italian_restaurant"]
    end

    test "parses integer filter values" do
      opts = [filters: "rating.votes_count,>,100"]

      params = BusinessListings.build_task_params(opts)

      assert params[:filters] == [["rating.votes_count", ">", 100]]
    end

    test "parses float filter values" do
      opts = [filters: "rating.value,>,4.5"]

      params = BusinessListings.build_task_params(opts)

      assert params[:filters] == [["rating.value", ">", 4.5]]
    end

    test "parses boolean filter values" do
      opts = [filters: "is_claimed,=,true"]

      params = BusinessListings.build_task_params(opts)

      assert params[:filters] == [["is_claimed", "=", true]]
    end

    test "parses string filter values" do
      opts = [filters: "category,like,pizza"]

      params = BusinessListings.build_task_params(opts)

      assert params[:filters] == [["category", "like", "pizza"]]
    end
  end

  describe "execute_search/2" do
    setup do
      # Mock successful task execution
      result = %BusinessListingsResult{
        total_count: 2,
        items: [
          %BusinessListing{
            title: "Joe's Pizza",
            category: "Pizza restaurant",
            rating: %{"value" => 4.5, "votes_count" => 150}
          },
          %BusinessListing{
            title: "Tony's Pizza",
            category: "Pizza restaurant",
            rating: %{"value" => 4.7, "votes_count" => 200}
          }
        ]
      }

      {:ok, result: result}
    end

    test "successfully fetches results", %{result: expected_result} do
      params = %{categories: ["pizza_restaurant"], location_coordinate: "40.7128,-74.0060,5"}

      expect(DataForSEO.Supervisor, :start_task, fn _module, ^params, opts ->
        # Simulate async callback
        callback = opts[:callback]
        spawn(fn -> callback.({:ok, expected_result}) end)
        {:ok, self()}
      end)

      start_time = System.monotonic_time(:millisecond)

      output =
        capture_io(fn ->
          result = BusinessListings.execute_search(params, start_time)
          assert result == expected_result
        end)

      assert output =~ "🔍 Fetching business listings..."
      assert output =~ "⏳ Task created"
    end

    test "handles task start failure" do
      params = %{categories: ["pizza_restaurant"]}

      expect(DataForSEO.Supervisor, :start_task, fn _module, _params, _opts ->
        {:error, {:invalid_params, "test error"}}
      end)

      start_time = System.monotonic_time(:millisecond)

      assert catch_exit(
               capture_io(fn ->
                 BusinessListings.execute_search(params, start_time)
               end)
             ) == {:shutdown, 1}
    end

    test "handles task execution error", %{} do
      params = %{categories: ["pizza_restaurant"]}

      expect(DataForSEO.Supervisor, :start_task, fn _module, _params, opts ->
        # Simulate async error callback
        callback = opts[:callback]
        spawn(fn -> callback.({:error, :timeout}) end)
        {:ok, self()}
      end)

      start_time = System.monotonic_time(:millisecond)

      assert catch_exit(
               capture_io(fn ->
                 BusinessListings.execute_search(params, start_time)
               end)
             ) == {:shutdown, 1}
    end
  end

  describe "save_results/4" do
    test "saves results to JSON file" do
      result = %BusinessListingsResult{
        total_count: 2,
        items: [
          %BusinessListing{
            title: "Joe's Pizza",
            category: "Pizza restaurant",
            rating: %{"value" => 4.5, "votes_count" => 150},
            latitude: 40.7128,
            longitude: -74.006
          },
          %BusinessListing{
            title: "Tony's Pizza",
            category: "Pizza restaurant",
            rating: %{"value" => 4.7, "votes_count" => 200}
          }
        ]
      }

      search_params = %{categories: ["pizza_restaurant"]}
      output_path = "test_output.json"
      elapsed_ms = 5432

      # Mock file writing
      expect(File, :write!, fn path, content ->
        assert path == output_path
        assert is_binary(content)

        # Verify JSON structure
        data = Jason.decode!(content)
        assert data["total_count"] == 2
        assert data["fetched_count"] == 2
        assert data["elapsed_ms"] == 5432
        assert is_binary(data["fetched_at"])
        assert data["search_params"]["categories"] == ["pizza_restaurant"]
        assert length(data["items"]) == 2

        # Verify first item
        item = Enum.at(data["items"], 0)
        assert item["title"] == "Joe's Pizza"
        assert item["category"] == "Pizza restaurant"
        assert item["rating"]["value"] == 4.5
        assert item["latitude"] == 40.7128

        :ok
      end)

      output =
        capture_io(fn ->
          BusinessListings.save_results(result, search_params, output_path, elapsed_ms)
        end)

      assert output =~ "💾 Saving to #{output_path}"
      assert output =~ "✓ Successfully saved 2 listings"
    end

    test "handles nested struct conversion" do
      result = %BusinessListingsResult{
        total_count: 1,
        items: [
          %BusinessListing{
            title: "Test",
            rating: %{"value" => 4.5, "votes_count" => 100},
            address_info: %{"street" => "123 Main St", "city" => "NYC"}
          }
        ]
      }

      search_params = %{}
      output_path = "test.json"

      expect(File, :write!, fn _path, content ->
        data = Jason.decode!(content)
        item = Enum.at(data["items"], 0)

        # Verify nested maps are preserved
        assert item["rating"]["value"] == 4.5
        assert item["address_info"]["street"] == "123 Main St"

        :ok
      end)

      capture_io(fn ->
        BusinessListings.save_results(result, search_params, output_path, 1000)
      end)
    end
  end

  describe "run/1 integration" do
    setup do
      result = %BusinessListingsResult{
        total_count: 2,
        items: [
          %BusinessListing{
            title: "Joe's Pizza",
            category: "Pizza restaurant",
            rating: %{"value" => 4.5, "votes_count" => 150}
          },
          %BusinessListing{
            title: "Tony's Pizza",
            category: "Pizza restaurant",
            rating: %{"value" => 4.7, "votes_count" => 200}
          }
        ]
      }

      {:ok, result: result}
    end

    test "runs successfully with minimal args", %{result: result} do
      args = ["-c", "pizza_restaurant", "-l", "40.7128,-74.0060,5"]

      expect(DataForSEO.Supervisor, :start_task, fn _module, _params, opts ->
        callback = opts[:callback]
        spawn(fn -> callback.({:ok, result}) end)
        {:ok, self()}
      end)

      expect(File, :write!, fn _path, _content -> :ok end)

      output =
        capture_io(fn ->
          BusinessListings.run(args)
        end)

      assert output =~ "🔍 Fetching business listings"
      assert output =~ "Categories: pizza_restaurant"
      assert output =~ "Location: 40.7128,-74.0060,5"
      assert output =~ "✓ Successfully saved 2 listings"
      assert output =~ "Total matching businesses: 2"
      assert output =~ "Top Rated"
      assert output =~ "⭐ 4.7/5"
    end

    test "runs with all options", %{result: result} do
      args = [
        "-c",
        "restaurant",
        "-l",
        "40.7128,-74.0060,5",
        "-t",
        "Pizza",
        "-f",
        "rating.value,>,4",
        "-s",
        "rating.value,desc",
        "-n",
        "50",
        "-o",
        "custom.json",
        "--claimed"
      ]

      expect(DataForSEO.Supervisor, :start_task, fn _module, params, opts ->
        assert params[:categories] == ["restaurant"]
        assert params[:location_coordinate] == "40.7128,-74.0060,5"
        assert params[:title] == "Pizza"
        assert params[:is_claimed] == true
        assert params[:filters] == [["rating.value", ">", 4]]
        assert params[:order_by] == [["rating.value", "desc"]]
        assert params[:limit] == 50

        callback = opts[:callback]
        spawn(fn -> callback.({:ok, result}) end)
        {:ok, self()}
      end)

      expect(File, :write!, fn path, _content ->
        assert path == "custom.json"
        :ok
      end)

      output =
        capture_io(fn ->
          BusinessListings.run(args)
        end)

      assert output =~ "Output file: custom.json"
    end

    test "raises error with no search params" do
      args = []

      assert_raise Mix.Error, ~r/at least one search parameter/i, fn ->
        capture_io(fn ->
          BusinessListings.run(args)
        end)
      end
    end

    test "raises error with invalid filter format" do
      args = ["-c", "restaurant", "-f", "invalid_filter"]

      # Error should be raised during param building, before supervisor is called
      assert_raise Mix.Error, ~r/Invalid filter format/i, fn ->
        BusinessListings.run(args)
      end
    end

    test "raises error with invalid order_by format" do
      args = ["-c", "restaurant", "-s", "invalid"]

      # Error should be raised during param building, before supervisor is called
      assert_raise Mix.Error, ~r/Invalid order_by format/i, fn ->
        BusinessListings.run(args)
      end
    end

    test "uses default output filename when not specified", %{result: result} do
      args = ["-c", "restaurant"]

      expect(DataForSEO.Supervisor, :start_task, fn _module, _params, opts ->
        callback = opts[:callback]
        spawn(fn -> callback.({:ok, result}) end)
        {:ok, self()}
      end)

      expect(File, :write!, fn path, _content ->
        assert path == "business_listings.json"
        :ok
      end)

      capture_io(fn ->
        BusinessListings.run(args)
      end)
    end

    test "handles empty results", %{} do
      args = ["-c", "restaurant"]

      empty_result = %BusinessListingsResult{
        total_count: 0,
        items: []
      }

      expect(DataForSEO.Supervisor, :start_task, fn _module, _params, opts ->
        callback = opts[:callback]
        spawn(fn -> callback.({:ok, empty_result}) end)
        {:ok, self()}
      end)

      expect(File, :write!, fn _path, _content -> :ok end)

      output =
        capture_io(fn ->
          BusinessListings.run(args)
        end)

      assert output =~ "Total matching businesses: 0"
      assert output =~ "Fetched: 0"
      refute output =~ "Top Rated"
    end

    test "shows top rated businesses in summary", %{result: result} do
      args = ["-c", "restaurant"]

      expect(DataForSEO.Supervisor, :start_task, fn _module, _params, opts ->
        callback = opts[:callback]
        spawn(fn -> callback.({:ok, result}) end)
        {:ok, self()}
      end)

      expect(File, :write!, fn _path, _content -> :ok end)

      output =
        capture_io(fn ->
          BusinessListings.run(args)
        end)

      assert output =~ "Top Rated"
      assert output =~ "⭐ 4.7/5 (200 reviews) - Tony's Pizza"
      assert output =~ "⭐ 4.5/5 (150 reviews) - Joe's Pizza"
    end
  end
end
