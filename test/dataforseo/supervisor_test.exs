defmodule DataForSEO.SupervisorTest do
  use ExUnit.Case, async: false
  use Mimic

  alias DataForSEO.{Supervisor, TaskRegistry, Client}
  alias DataForSEO.Tasks.GoogleEvents

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
    stub(Client, :create_task, fn _task_type, _payload ->
      {:ok, %{"tasks" => [%{"id" => "task123", "status_code" => 20_100}]}}
    end)

    stub(Client, :check_ready_tasks, fn _task_type ->
      {:ok, %{"tasks" => []}}
    end)

    {:ok, supervisor: sup_pid}
  end

  describe "start_link/1" do
    test "starts supervisor successfully" do
      # Already started in setup, just verify it's running
      assert Process.whereis(Supervisor) != nil
      assert Process.alive?(Process.whereis(Supervisor))
    end

    test "starts with TaskRegistry and TaskSupervisor children" do
      # Verify the registry is available
      assert Process.whereis(TaskRegistry) != nil

      # Verify dynamic supervisor is available
      assert Process.whereis(:"Elixir.DataForSEO.Supervisor.TaskSupervisor") != nil
    end
  end

  describe "start_task/3" do
    test "starts a task manager successfully" do
      task_params = %{keyword: "concerts", location_name: "New York"}

      assert {:ok, pid} = Supervisor.start_task(GoogleEvents, task_params)
      assert Process.alive?(pid)

      # Verify task is registered
      tasks = Supervisor.list_tasks()
      assert length(tasks) > 0
    end

    test "starts task with custom options" do
      task_params = %{keyword: "concerts", location_name: "New York"}

      callback = fn _result -> :ok end

      assert {:ok, pid} =
               Supervisor.start_task(GoogleEvents, task_params,
                 callback: callback,
                 poll_interval_ms: 200
               )

      assert Process.alive?(pid)
    end

    test "starts task with custom task_id" do
      task_params = %{keyword: "concerts", location_name: "New York"}
      custom_id = "my_custom_task_id"

      assert {:ok, pid} = Supervisor.start_task(GoogleEvents, task_params, task_id: custom_id)

      # Verify task is registered with custom ID
      assert {:ok, ^pid} = TaskRegistry.lookup_task(custom_id)
    end

    test "generates unique task_id when not provided" do
      task_params = %{keyword: "concerts", location_name: "New York"}

      {:ok, _pid1} = Supervisor.start_task(GoogleEvents, task_params)
      {:ok, _pid2} = Supervisor.start_task(GoogleEvents, task_params)

      tasks = Supervisor.list_tasks()
      task_ids = Enum.map(tasks, & &1.task_id)

      # All task IDs should be unique
      assert length(task_ids) == length(Enum.uniq(task_ids))

      # All should start with "dfs_"
      assert Enum.all?(task_ids, &String.starts_with?(&1, "dfs_"))
    end

    test "registers task with metadata" do
      task_params = %{keyword: "concerts", location_name: "New York"}

      {:ok, _pid} = Supervisor.start_task(GoogleEvents, task_params)

      tasks = Supervisor.list_tasks()
      task = List.first(tasks)

      assert task.metadata.task_module == GoogleEvents
      assert %DateTime{} = task.metadata.started_at
    end

    test "returns error when task validation fails" do
      invalid_params = %{location_name: "New York"}

      assert {:error, {:invalid_params, _}} =
               Supervisor.start_task(GoogleEvents, invalid_params)
    end
  end

  describe "stop_task/1" do
    test "stops a running task" do
      task_params = %{keyword: "concerts", location_name: "New York"}
      {:ok, pid} = Supervisor.start_task(GoogleEvents, task_params, task_id: "test_task")

      assert Process.alive?(pid)

      assert :ok = Supervisor.stop_task("test_task")

      # Wait for shutdown
      :timer.sleep(50)

      # Verify task is no longer registered
      assert {:error, :not_found} = TaskRegistry.lookup_task("test_task")
    end

    test "returns error when stopping non-existent task" do
      assert {:error, :not_found} = Supervisor.stop_task("non_existent_task")
    end
  end

  describe "list_tasks/0" do
    test "lists all active tasks" do
      task_params1 = %{keyword: "concerts", location_name: "New York"}
      task_params2 = %{keyword: "sports", location_name: "Boston"}

      {:ok, _pid1} = Supervisor.start_task(GoogleEvents, task_params1)
      {:ok, _pid2} = Supervisor.start_task(GoogleEvents, task_params2)

      tasks = Supervisor.list_tasks()

      assert length(tasks) == 2
      assert Enum.all?(tasks, fn task -> task.alive == true end)
    end

    test "returns empty list when no tasks" do
      # Start with clean state
      tasks = Supervisor.list_tasks()

      # Stop any existing tasks
      Enum.each(tasks, fn task -> Supervisor.stop_task(task.task_id) end)
      :timer.sleep(50)

      assert Supervisor.list_tasks() == []
    end

    test "includes task status in listing" do
      task_params = %{keyword: "concerts", location_name: "New York"}

      {:ok, _pid} = Supervisor.start_task(GoogleEvents, task_params)

      # Wait for task to initialize
      :timer.sleep(100)

      tasks = Supervisor.list_tasks()
      task = List.first(tasks)

      assert Map.has_key?(task, :status)
      assert is_atom(task.status)
    end
  end

  describe "get_stats/0" do
    test "returns statistics about active tasks" do
      task_params = %{keyword: "concerts", location_name: "New York"}

      {:ok, _pid1} = Supervisor.start_task(GoogleEvents, task_params)
      {:ok, _pid2} = Supervisor.start_task(GoogleEvents, task_params)

      stats = Supervisor.get_stats()

      assert stats.total_tasks == 2
      assert stats.alive_tasks == 2
      assert stats.dead_tasks == 0
      assert is_map(stats.by_module)
    end

    test "returns zero stats when no tasks" do
      # Clean up any existing tasks
      tasks = Supervisor.list_tasks()
      Enum.each(tasks, fn task -> Supervisor.stop_task(task.task_id) end)
      :timer.sleep(50)

      stats = Supervisor.get_stats()

      assert stats.total_tasks == 0
      assert stats.alive_tasks == 0
      assert stats.dead_tasks == 0
    end

    test "groups tasks by module" do
      task_params = %{keyword: "concerts", location_name: "New York"}

      {:ok, _pid1} = Supervisor.start_task(GoogleEvents, task_params)
      {:ok, _pid2} = Supervisor.start_task(GoogleEvents, task_params)

      stats = Supervisor.get_stats()

      assert stats.by_module[GoogleEvents] == 2
    end
  end

  describe "task lifecycle" do
    test "task is automatically removed when it crashes" do
      task_params = %{keyword: "concerts", location_name: "New York"}

      {:ok, pid} = Supervisor.start_task(GoogleEvents, task_params, task_id: "crash_task")

      # Verify task is running
      tasks = Supervisor.list_tasks()
      assert Enum.any?(tasks, fn task -> task.task_id == "crash_task" end)

      # Kill the task manager
      Process.exit(pid, :kill)

      # Wait for cleanup
      :timer.sleep(100)

      # Task should be removed from registry
      assert {:error, :not_found} = TaskRegistry.lookup_task("crash_task")
    end

    test "supervisor restarts registry if it crashes" do
      # Get the original registry PID
      original_pid = Process.whereis(TaskRegistry)

      # Kill the registry
      Process.exit(original_pid, :kill)

      # Wait for supervisor to restart it
      :timer.sleep(100)

      # Verify registry is running again with new PID
      new_pid = Process.whereis(TaskRegistry)
      assert new_pid != nil
      assert new_pid != original_pid
      assert Process.alive?(new_pid)
    end
  end

  describe "concurrent task management" do
    test "can start multiple tasks concurrently" do
      tasks =
        Enum.map(1..5, fn i ->
          task_params = %{keyword: "event#{i}", location_name: "City#{i}"}
          Task.async(fn -> Supervisor.start_task(GoogleEvents, task_params) end)
        end)

      results = Enum.map(tasks, &Task.await/1)

      # All should succeed
      assert Enum.all?(results, fn
               {:ok, pid} -> Process.alive?(pid)
               _ -> false
             end)

      # All should be registered
      registered_tasks = Supervisor.list_tasks()
      assert length(registered_tasks) >= 5
    end

    test "can stop multiple tasks concurrently" do
      # Start multiple tasks
      task_ids =
        Enum.map(1..5, fn i ->
          task_params = %{keyword: "event#{i}", location_name: "City#{i}"}
          task_id = "task_#{i}"
          {:ok, _pid} = Supervisor.start_task(GoogleEvents, task_params, task_id: task_id)
          task_id
        end)

      # Stop them all concurrently
      stop_tasks =
        Enum.map(task_ids, fn task_id ->
          Task.async(fn -> Supervisor.stop_task(task_id) end)
        end)

      results = Enum.map(stop_tasks, &Task.await/1)

      # All should succeed
      assert Enum.all?(results, &(&1 == :ok))

      # Wait for cleanup
      :timer.sleep(50)

      # None should be registered
      Enum.each(task_ids, fn task_id ->
        assert {:error, :not_found} = TaskRegistry.lookup_task(task_id)
      end)
    end
  end
end
