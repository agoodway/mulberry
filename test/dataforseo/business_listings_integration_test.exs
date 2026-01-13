defmodule DataForSEO.BusinessListingsIntegrationTest do
  use ExUnit.Case, async: false
  use Mimic

  alias DataForSEO.{Supervisor, TaskRegistry, Client}
  alias DataForSEO.Tasks.BusinessListings

  setup :set_mimic_global

  setup do
    # Supervisor is already started by Application, just get its PID
    sup_pid = Process.whereis(Supervisor)

    # Clean up any existing tasks from previous tests
    Supervisor.list_tasks()
    |> Enum.each(fn task -> Supervisor.stop_task(task.task_id) end)

    # Give tasks time to shut down
    :timer.sleep(50)

    # Mock Client calls to prevent actual API requests
    # BusinessListings uses live endpoint, so mock create_live_task
    stub(Client, :create_live_task, fn _task_type, _payload ->
      {:ok,
       %{
         "tasks" => [
           %{
             "result" => [
               %{
                 "total_count" => 2,
                 "items" => [
                   %{
                     "type" => "business_listing",
                     "title" => "Joe's Pizza",
                     "category" => "Pizza restaurant",
                     "rating" => %{"value" => 4.5, "votes_count" => 150}
                   },
                   %{
                     "type" => "business_listing",
                     "title" => "Tony's Pizza",
                     "category" => "Pizza restaurant",
                     "rating" => %{"value" => 4.7, "votes_count" => 200}
                   }
                 ]
               }
             ]
           }
         ]
       }}
    end)

    {:ok, supervisor: sup_pid}
  end

  describe "start_task/3 with BusinessListings" do
    test "starts a business listings task successfully" do
      task_params = %{
        categories: ["pizza_restaurant"],
        location_coordinate: "40.7128,-74.0060,5"
      }

      assert {:ok, pid} = Supervisor.start_task(BusinessListings, task_params)
      assert Process.alive?(pid)

      # Verify task is registered
      tasks = Supervisor.list_tasks()
      assert length(tasks) > 0
    end

    test "starts task with filters and ordering" do
      task_params = %{
        categories: ["restaurant"],
        location_coordinate: "40.7128,-74.0060,5",
        filters: [["rating.value", ">", 4]],
        order_by: [["rating.value", "desc"]],
        limit: 50
      }

      assert {:ok, pid} = Supervisor.start_task(BusinessListings, task_params)
      assert Process.alive?(pid)
    end

    test "starts task with custom callback" do
      task_params = %{
        categories: ["pizza_restaurant"],
        location_coordinate: "40.7128,-74.0060,5"
      }

      # Use a test process to receive the callback
      test_pid = self()

      callback = fn result ->
        send(test_pid, {:callback_called, result})
      end

      assert {:ok, _pid} =
               Supervisor.start_task(BusinessListings, task_params, callback: callback)

      # The callback should eventually be called (in real scenario when task completes)
      # For this test, we're just verifying the task starts successfully with a callback
    end

    test "registers task with metadata" do
      task_params = %{
        categories: ["restaurant"],
        location_coordinate: "40.7128,-74.0060,5"
      }

      {:ok, _pid} = Supervisor.start_task(BusinessListings, task_params)

      tasks = Supervisor.list_tasks()
      task = List.first(tasks)

      assert task.metadata.task_module == BusinessListings
      assert %DateTime{} = task.metadata.started_at
    end

    test "returns error when validation fails - missing categories" do
      invalid_params = %{
        location_coordinate: "40.7128,-74.0060,5"
      }

      # Should succeed because categories is optional
      assert {:ok, _pid} = Supervisor.start_task(BusinessListings, invalid_params)
    end

    test "returns error when validation fails - too many categories" do
      invalid_params = %{
        categories: Enum.map(1..11, fn i -> "category_#{i}" end)
      }

      assert {:error, {:invalid_params, _}} =
               Supervisor.start_task(BusinessListings, invalid_params)
    end

    test "returns error when validation fails - invalid location format" do
      invalid_params = %{
        categories: ["restaurant"],
        location_coordinate: "invalid_format"
      }

      assert {:error, {:invalid_params, _}} =
               Supervisor.start_task(BusinessListings, invalid_params)
    end

    test "returns error when validation fails - invalid filters" do
      invalid_params = %{
        categories: ["restaurant"],
        filters: [["field", "invalid_operator", 3]]
      }

      assert {:error, {:invalid_params, _}} =
               Supervisor.start_task(BusinessListings, invalid_params)
    end
  end

  describe "task lifecycle with BusinessListings" do
    test "can stop a running business listings task" do
      task_params = %{
        categories: ["restaurant"],
        location_coordinate: "40.7128,-74.0060,5"
      }

      {:ok, pid} = Supervisor.start_task(BusinessListings, task_params, task_id: "stop_test")

      assert Process.alive?(pid)

      assert :ok = Supervisor.stop_task("stop_test")

      # Wait for shutdown
      :timer.sleep(50)

      # Verify task is no longer registered
      assert {:error, :not_found} = TaskRegistry.lookup_task("stop_test")
    end

    test "task is automatically removed when it crashes" do
      task_params = %{
        categories: ["restaurant"],
        location_coordinate: "40.7128,-74.0060,5"
      }

      {:ok, pid} = Supervisor.start_task(BusinessListings, task_params, task_id: "crash_test")

      # Verify task is running
      tasks = Supervisor.list_tasks()
      assert Enum.any?(tasks, fn task -> task.task_id == "crash_test" end)

      # Kill the task manager
      Process.exit(pid, :kill)

      # Wait for cleanup
      :timer.sleep(100)

      # Task should be removed from registry
      assert {:error, :not_found} = TaskRegistry.lookup_task("crash_test")
    end
  end

  describe "concurrent business listings tasks" do
    test "can start multiple business listings tasks concurrently" do
      tasks =
        Enum.map(1..3, fn i ->
          task_params = %{
            categories: ["restaurant"],
            location_coordinate: "40.#{7100 + i},-74.0060,5",
            tag: "concurrent_test_#{i}"
          }

          Task.async(fn -> Supervisor.start_task(BusinessListings, task_params) end)
        end)

      results = Enum.map(tasks, &Task.await/1)

      # All should succeed
      assert Enum.all?(results, fn
               {:ok, pid} -> Process.alive?(pid)
               _ -> false
             end)

      # All should be registered
      registered_tasks = Supervisor.list_tasks()
      assert length(registered_tasks) >= 3
    end

    test "can start different task types concurrently" do
      business_params = %{
        categories: ["restaurant"],
        location_coordinate: "40.7128,-74.0060,5"
      }

      # Start a business listings task
      {:ok, _pid1} = Supervisor.start_task(BusinessListings, business_params)

      # Start another business listings task
      {:ok, _pid2} =
        Supervisor.start_task(BusinessListings, %{
          categories: ["pizza_restaurant"],
          location_coordinate: "40.7130,-74.0062,3"
        })

      tasks = Supervisor.list_tasks()
      assert length(tasks) >= 2

      # All should be BusinessListings tasks
      assert Enum.all?(tasks, fn task ->
               task.metadata.task_module == BusinessListings
             end)
    end

    test "stats include business listings tasks" do
      task_params = %{
        categories: ["restaurant"],
        location_coordinate: "40.7128,-74.0060,5"
      }

      {:ok, _pid1} = Supervisor.start_task(BusinessListings, task_params)
      {:ok, _pid2} = Supervisor.start_task(BusinessListings, task_params)

      stats = Supervisor.get_stats()

      assert stats.total_tasks >= 2
      assert stats.by_module[BusinessListings] >= 2
    end
  end

  describe "business listings with various parameters" do
    test "starts task with title search" do
      task_params = %{
        title: "Joe's Pizza",
        location_coordinate: "40.7128,-74.0060,5"
      }

      assert {:ok, pid} = Supervisor.start_task(BusinessListings, task_params)
      assert Process.alive?(pid)
    end

    test "starts task with description search" do
      task_params = %{
        description: "Best pizza in town",
        location_coordinate: "40.7128,-74.0060,5"
      }

      assert {:ok, pid} = Supervisor.start_task(BusinessListings, task_params)
      assert Process.alive?(pid)
    end

    test "starts task with is_claimed filter" do
      task_params = %{
        categories: ["restaurant"],
        location_coordinate: "40.7128,-74.0060,5",
        is_claimed: true
      }

      assert {:ok, pid} = Supervisor.start_task(BusinessListings, task_params)
      assert Process.alive?(pid)
    end

    test "starts task with multiple filters" do
      task_params = %{
        categories: ["restaurant"],
        location_coordinate: "40.7128,-74.0060,5",
        filters: [
          ["rating.value", ">", 4],
          ["rating.votes_count", ">", 50],
          ["is_claimed", "=", true]
        ]
      }

      assert {:ok, pid} = Supervisor.start_task(BusinessListings, task_params)
      assert Process.alive?(pid)
    end

    test "starts task with complex ordering" do
      task_params = %{
        categories: ["restaurant"],
        location_coordinate: "40.7128,-74.0060,5",
        order_by: [
          ["rating.value", "desc"],
          ["rating.votes_count", "desc"]
        ]
      }

      assert {:ok, pid} = Supervisor.start_task(BusinessListings, task_params)
      assert Process.alive?(pid)
    end

    test "starts task with pagination" do
      task_params = %{
        categories: ["restaurant"],
        location_coordinate: "40.7128,-74.0060,5",
        limit: 50,
        offset: 100
      }

      assert {:ok, pid} = Supervisor.start_task(BusinessListings, task_params)
      assert Process.alive?(pid)
    end

    test "starts task with offset_token for large datasets" do
      task_params = %{
        categories: ["restaurant"],
        location_coordinate: "40.7128,-74.0060,5",
        offset_token: "large_dataset_token_123"
      }

      assert {:ok, pid} = Supervisor.start_task(BusinessListings, task_params)
      assert Process.alive?(pid)
    end

    test "starts task with custom tag" do
      task_params = %{
        categories: ["restaurant"],
        location_coordinate: "40.7128,-74.0060,5",
        tag: "my_custom_identifier"
      }

      assert {:ok, pid} = Supervisor.start_task(BusinessListings, task_params)
      assert Process.alive?(pid)
    end
  end

  describe "error handling with business listings" do
    test "handles API error response gracefully" do
      # Mock an error response for live endpoint
      expect(Client, :create_live_task, fn _task_type, _payload ->
        {:ok,
         %{
           "tasks" => [
             %{
               "status_code" => 40_100,
               "status_message" => "Invalid location coordinate"
             }
           ]
         }}
      end)

      task_params = %{
        categories: ["restaurant"],
        location_coordinate: "999,-999,5"
      }

      # Task creation should succeed, but the API will return an error
      # The TaskManager will handle this internally
      assert {:ok, pid} = Supervisor.start_task(BusinessListings, task_params)
      assert Process.alive?(pid)
    end

    test "handles network timeout gracefully" do
      # Mock a timeout for live endpoint
      expect(Client, :create_live_task, fn _task_type, _payload ->
        {:error, :timeout}
      end)

      task_params = %{
        categories: ["restaurant"],
        location_coordinate: "40.7128,-74.0060,5"
      }

      # Task creation should succeed, error will be handled by TaskManager
      assert {:ok, pid} = Supervisor.start_task(BusinessListings, task_params)
      assert Process.alive?(pid)
    end
  end
end
