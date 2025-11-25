defmodule DataForSEO.TaskManagerTest do
  use ExUnit.Case, async: false
  use Mimic

  import ExUnit.CaptureLog

  alias DataForSEO.{TaskManager, Client}
  alias DataForSEO.Tasks.GoogleEvents

  setup :set_mimic_global

  setup do
    # Set shorter timeouts for testing
    Application.put_env(:mulberry, :dataforseo,
      poll_interval_ms: 100,
      timeout_ms: 1000
    )

    on_exit(fn ->
      Application.delete_env(:mulberry, :dataforseo)
    end)

    :ok
  end

  describe "start_link/1" do
    test "starts task manager successfully with valid params" do
      params = %{keyword: "concerts", location_name: "New York"}

      assert {:ok, pid} =
               TaskManager.start_link(task_module: GoogleEvents, task_params: params)

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "fails to start with invalid params" do
      params = %{location_name: "New York"}

      Process.flag(:trap_exit, true)

      result = TaskManager.start_link(task_module: GoogleEvents, task_params: params)

      case result do
        {:ok, pid} ->
          assert_receive {:EXIT, ^pid, {:invalid_params, _}}, 100

        {:error, {:invalid_params, _}} ->
          assert true
      end
    end

    test "fails to start without required options" do
      Process.flag(:trap_exit, true)

      result = TaskManager.start_link([])

      case result do
        {:ok, pid} ->
          assert_receive {:EXIT, ^pid, {%KeyError{key: :task_module}, _}}, 100

        {:error, _} ->
          assert true
      end
    end
  end

  describe "task creation flow" do
    test "creates task successfully and transitions to monitoring" do
      params = %{keyword: "concerts", location_name: "New York"}

      expect(Client, :create_task, fn _task_type, _payload ->
        {:ok, %{"tasks" => [%{"id" => "task123", "status_code" => 20_100}]}}
      end)

      {:ok, pid} = TaskManager.start_link(task_module: GoogleEvents, task_params: params)

      # Wait for task creation
      :timer.sleep(50)

      assert {:ok, status} = TaskManager.get_status(pid)
      assert status.status == :monitoring
      assert status.task_ids == ["task123"]

      GenServer.stop(pid)
    end

    test "handles task creation error and retries" do
      params = %{keyword: "concerts", location_name: "New York"}

      expect(Client, :create_task, 2, fn _task_type, _payload ->
        case Process.get(:attempt, 0) do
          0 ->
            Process.put(:attempt, 1)
            {:error, {:api_error, 500, "Server Error"}}

          1 ->
            {:ok, %{"tasks" => [%{"id" => "task123", "status_code" => 20_100}]}}
        end
      end)

      {:ok, pid} = TaskManager.start_link(task_module: GoogleEvents, task_params: params)

      # Wait for retries
      :timer.sleep(100)

      assert {:ok, status} = TaskManager.get_status(pid)
      assert status.status == :monitoring
      assert status.task_ids == ["task123"]

      GenServer.stop(pid)
    end

    test "fails after max retries on task creation" do
      params = %{keyword: "concerts", location_name: "New York"}

      expect(Client, :create_task, 4, fn _task_type, _payload ->
        {:error, {:api_error, 500, "Server Error"}}
      end)

      log =
        capture_log(fn ->
          {:ok, pid} = TaskManager.start_link(task_module: GoogleEvents, task_params: params)

          # Wait for all retries
          :timer.sleep(200)

          assert {:ok, status} = TaskManager.get_status(pid)
          assert status.status == :failed
          assert status.error == {:api_error, 500, "Server Error"}

          GenServer.stop(pid)
        end)

      assert log =~ "Task manager error"
    end
  end

  describe "status monitoring flow" do
    test "polls for ready tasks and fetches results" do
      params = %{keyword: "concerts", location_name: "New York"}

      expect(Client, :create_task, fn _task_type, _payload ->
        {:ok, %{"tasks" => [%{"id" => "task123", "status_code" => 20_100}]}}
      end)

      expect(Client, :check_ready_tasks, fn _task_type ->
        {:ok,
         %{
           "tasks" => [
             %{"result_count" => 1, "result" => [%{"id" => "task123"}]}
           ]
         }}
      end)

      expect(Client, :fetch_task_results, fn _task_type, "task123" ->
        {:ok,
         %{
           "tasks" => [
             %{
               "result" => [
                 %{
                   "items" => [
                     %{
                       "type" => "event_item",
                       "title" => "Summer Concert"
                     }
                   ]
                 }
               ]
             }
           ]
         }}
      end)

      {:ok, pid} = TaskManager.start_link(task_module: GoogleEvents, task_params: params)

      # Wait for task creation, monitoring, and result fetching
      :timer.sleep(300)

      assert {:ok, status} = TaskManager.get_status(pid)
      assert status.status == :completed
      assert length(status.results) == 1

      GenServer.stop(pid)
    end

    test "continues polling when tasks not ready" do
      params = %{keyword: "concerts", location_name: "New York"}

      expect(Client, :create_task, fn _task_type, _payload ->
        {:ok, %{"tasks" => [%{"id" => "task123", "status_code" => 20_100}]}}
      end)

      expect(Client, :check_ready_tasks, 2, fn _task_type ->
        case Process.get(:check_count, 0) do
          0 ->
            Process.put(:check_count, 1)
            {:ok, %{"tasks" => []}}

          1 ->
            {:ok,
             %{
               "tasks" => [
                 %{"result_count" => 1, "result" => [%{"id" => "task123"}]}
               ]
             }}
        end
      end)

      expect(Client, :fetch_task_results, fn _task_type, "task123" ->
        {:ok,
         %{
           "tasks" => [
             %{"result" => [%{"items" => [%{"type" => "event_item", "title" => "Concert"}]}]}
           ]
         }}
      end)

      {:ok, pid} = TaskManager.start_link(task_module: GoogleEvents, task_params: params)

      # Wait for multiple polling attempts
      :timer.sleep(400)

      assert {:ok, status} = TaskManager.get_status(pid)
      assert status.status == :completed

      GenServer.stop(pid)
    end

    test "handles timeout when tasks never ready" do
      params = %{keyword: "concerts", location_name: "New York"}

      expect(Client, :create_task, fn _task_type, _payload ->
        {:ok, %{"tasks" => [%{"id" => "task123", "status_code" => 20_100}]}}
      end)

      # Always return empty ready tasks
      stub(Client, :check_ready_tasks, fn _task_type ->
        {:ok, %{"tasks" => []}}
      end)

      {:ok, pid} = TaskManager.start_link(task_module: GoogleEvents, task_params: params)

      # Wait for timeout
      :timer.sleep(1200)

      assert {:ok, status} = TaskManager.get_status(pid)
      assert status.status == :failed
      assert {:timeout, _} = status.error

      GenServer.stop(pid)
    end
  end

  describe "result fetching" do
    test "fetches results for multiple tasks" do
      params = %{keyword: "concerts", location_name: "New York"}

      expect(Client, :create_task, fn _task_type, _payload ->
        {:ok,
         %{
           "tasks" => [
             %{"id" => "task1", "status_code" => 20_100},
             %{"id" => "task2", "status_code" => 20_100}
           ]
         }}
      end)

      expect(Client, :check_ready_tasks, fn _task_type ->
        {:ok,
         %{
           "tasks" => [
             %{
               "result_count" => 2,
               "result" => [%{"id" => "task1"}, %{"id" => "task2"}]
             }
           ]
         }}
      end)

      expect(Client, :fetch_task_results, 2, fn _task_type, task_id ->
        {:ok,
         %{
           "tasks" => [
             %{
               "result" => [
                 %{
                   "items" => [
                     %{"type" => "event_item", "title" => "Concert #{task_id}"}
                   ]
                 }
               ]
             }
           ]
         }}
      end)

      {:ok, pid} = TaskManager.start_link(task_module: GoogleEvents, task_params: params)

      :timer.sleep(300)

      assert {:ok, status} = TaskManager.get_status(pid)
      assert status.status == :completed
      assert length(status.results) == 2

      GenServer.stop(pid)
    end

    test "handles fetch error and retries" do
      params = %{keyword: "concerts", location_name: "New York"}

      expect(Client, :create_task, fn _task_type, _payload ->
        {:ok, %{"tasks" => [%{"id" => "task123", "status_code" => 20_100}]}}
      end)

      expect(Client, :check_ready_tasks, fn _task_type ->
        {:ok,
         %{
           "tasks" => [
             %{"result_count" => 1, "result" => [%{"id" => "task123"}]}
           ]
         }}
      end)

      expect(Client, :fetch_task_results, 2, fn _task_type, "task123" ->
        case Process.get(:fetch_attempt, 0) do
          0 ->
            Process.put(:fetch_attempt, 1)
            {:error, {:api_error, 500, "Server Error"}}

          1 ->
            {:ok,
             %{
               "tasks" => [
                 %{"result" => [%{"items" => [%{"type" => "event_item", "title" => "Concert"}]}]}
               ]
             }}
        end
      end)

      {:ok, pid} = TaskManager.start_link(task_module: GoogleEvents, task_params: params)

      :timer.sleep(400)

      assert {:ok, status} = TaskManager.get_status(pid)
      assert status.status == :completed

      GenServer.stop(pid)
    end
  end

  describe "callbacks" do
    test "invokes callback on success with single result" do
      test_pid = self()
      params = %{keyword: "concerts", location_name: "New York"}

      callback = fn result ->
        send(test_pid, {:callback_called, result})
      end

      expect(Client, :create_task, fn _task_type, _payload ->
        {:ok, %{"tasks" => [%{"id" => "task123", "status_code" => 20_100}]}}
      end)

      expect(Client, :check_ready_tasks, fn _task_type ->
        {:ok,
         %{
           "tasks" => [
             %{"result_count" => 1, "result" => [%{"id" => "task123"}]}
           ]
         }}
      end)

      expect(Client, :fetch_task_results, fn _task_type, "task123" ->
        {:ok,
         %{
           "tasks" => [
             %{"result" => [%{"items" => [%{"type" => "event_item", "title" => "Concert"}]}]}
           ]
         }}
      end)

      {:ok, pid} =
        TaskManager.start_link(
          task_module: GoogleEvents,
          task_params: params,
          callback: callback
        )

      assert_receive {:callback_called, {:ok, result}}, 500
      assert result.events != []

      GenServer.stop(pid)
    end

    test "invokes callback with multiple results as list" do
      test_pid = self()
      params = %{keyword: "concerts", location_name: "New York"}

      callback = fn result ->
        send(test_pid, {:callback_called, result})
      end

      expect(Client, :create_task, fn _task_type, _payload ->
        {:ok,
         %{
           "tasks" => [
             %{"id" => "task1", "status_code" => 20_100},
             %{"id" => "task2", "status_code" => 20_100}
           ]
         }}
      end)

      expect(Client, :check_ready_tasks, fn _task_type ->
        {:ok,
         %{
           "tasks" => [
             %{
               "result_count" => 2,
               "result" => [%{"id" => "task1"}, %{"id" => "task2"}]
             }
           ]
         }}
      end)

      expect(Client, :fetch_task_results, 2, fn _task_type, _task_id ->
        {:ok,
         %{
           "tasks" => [
             %{"result" => [%{"items" => [%{"type" => "event_item", "title" => "Concert"}]}]}
           ]
         }}
      end)

      {:ok, pid} =
        TaskManager.start_link(
          task_module: GoogleEvents,
          task_params: params,
          callback: callback
        )

      assert_receive {:callback_called, {:ok, results}}, 500
      assert is_list(results)
      assert length(results) == 2

      GenServer.stop(pid)
    end

    test "invokes callback on failure" do
      test_pid = self()
      params = %{keyword: "concerts", location_name: "New York"}

      callback = fn result ->
        send(test_pid, {:callback_called, result})
      end

      expect(Client, :create_task, 4, fn _task_type, _payload ->
        {:error, {:api_error, 500, "Server Error"}}
      end)

      {:ok, pid} =
        TaskManager.start_link(
          task_module: GoogleEvents,
          task_params: params,
          callback: callback
        )

      assert_receive {:callback_called, {:error, {:api_error, 500, "Server Error"}}}, 500

      GenServer.stop(pid)
    end
  end

  describe "get_status/1" do
    test "returns current status" do
      params = %{keyword: "concerts", location_name: "New York"}

      stub(Client, :create_task, fn _task_type, _payload ->
        {:ok, %{"tasks" => [%{"id" => "task123", "status_code" => 20_100}]}}
      end)

      stub(Client, :check_ready_tasks, fn _task_type ->
        {:ok, %{"tasks" => []}}
      end)

      {:ok, pid} = TaskManager.start_link(task_module: GoogleEvents, task_params: params)

      :timer.sleep(50)

      assert {:ok, status} = TaskManager.get_status(pid)
      assert is_atom(status.status)
      assert is_list(status.task_ids)
      assert %DateTime{} = status.created_at
      assert %DateTime{} = status.updated_at

      GenServer.stop(pid)
    end
  end

  describe "cancel/1" do
    test "stops the task manager" do
      params = %{keyword: "concerts", location_name: "New York"}

      stub(Client, :create_task, fn _task_type, _payload ->
        {:ok, %{"tasks" => [%{"id" => "task123", "status_code" => 20_100}]}}
      end)

      stub(Client, :check_ready_tasks, fn _task_type ->
        {:ok, %{"tasks" => []}}
      end)

      {:ok, pid} = TaskManager.start_link(task_module: GoogleEvents, task_params: params)

      assert Process.alive?(pid)

      TaskManager.cancel(pid)

      # Wait for process to stop
      :timer.sleep(50)

      refute Process.alive?(pid)
    end
  end
end
