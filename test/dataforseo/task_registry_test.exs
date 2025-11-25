defmodule DataForSEO.TaskRegistryTest do
  use ExUnit.Case, async: false

  alias DataForSEO.TaskRegistry

  setup do
    # Registry is already started by Application/Supervisor, just get its PID
    pid = Process.whereis(TaskRegistry)

    # Clean up any registered tasks from previous tests
    TaskRegistry.list_tasks()
    |> Enum.each(fn task ->
      TaskRegistry.unregister_task(task.task_id)
    end)

    {:ok, registry: pid}
  end

  describe "register_task/3" do
    test "registers a task with metadata" do
      task_id = "test_task_123"
      task_pid = spawn(fn -> :timer.sleep(:infinity) end)
      metadata = %{task_module: SomeModule, started_at: DateTime.utc_now()}

      assert :ok = TaskRegistry.register_task(task_id, task_pid, metadata)
    end

    test "returns error when registering duplicate task_id" do
      task_id = "test_task_123"
      task_pid1 = spawn(fn -> :timer.sleep(:infinity) end)
      task_pid2 = spawn(fn -> :timer.sleep(:infinity) end)

      assert :ok = TaskRegistry.register_task(task_id, task_pid1, %{})
      assert {:error, :already_registered} = TaskRegistry.register_task(task_id, task_pid2, %{})
    end
  end

  describe "lookup_task/1" do
    test "finds registered task by ID" do
      task_id = "test_task_123"
      task_pid = spawn(fn -> :timer.sleep(:infinity) end)

      TaskRegistry.register_task(task_id, task_pid, %{})

      assert {:ok, ^task_pid} = TaskRegistry.lookup_task(task_id)
    end

    test "returns error for non-existent task" do
      assert {:error, :not_found} = TaskRegistry.lookup_task("non_existent_task")
    end
  end

  describe "unregister_task/1" do
    test "unregisters a task" do
      task_id = "test_task_123"
      task_pid = spawn(fn -> :timer.sleep(:infinity) end)

      TaskRegistry.register_task(task_id, task_pid, %{})
      assert {:ok, ^task_pid} = TaskRegistry.lookup_task(task_id)

      assert :ok = TaskRegistry.unregister_task(task_id)
      assert {:error, :not_found} = TaskRegistry.lookup_task(task_id)
    end

    test "unregistering non-existent task returns ok" do
      assert :ok = TaskRegistry.unregister_task("non_existent_task")
    end
  end

  describe "list_tasks/0" do
    test "lists all registered tasks" do
      task_id1 = "task_1"
      task_id2 = "task_2"
      task_pid1 = spawn(fn -> :timer.sleep(:infinity) end)
      task_pid2 = spawn(fn -> :timer.sleep(:infinity) end)

      TaskRegistry.register_task(task_id1, task_pid1, %{module: Module1})
      TaskRegistry.register_task(task_id2, task_pid2, %{module: Module2})

      tasks = TaskRegistry.list_tasks()

      assert length(tasks) == 2
      assert Enum.any?(tasks, fn task -> task.task_id == task_id1 end)
      assert Enum.any?(tasks, fn task -> task.task_id == task_id2 end)
    end

    test "returns empty list when no tasks registered" do
      assert TaskRegistry.list_tasks() == []
    end

    test "includes alive status for each task" do
      task_id = "test_task"
      task_pid = spawn(fn -> :timer.sleep(:infinity) end)

      TaskRegistry.register_task(task_id, task_pid, %{})

      tasks = TaskRegistry.list_tasks()
      task = List.first(tasks)

      assert task.alive == true
    end

    test "marks dead processes as not alive" do
      task_id = "test_task"
      # Create a process that dies immediately
      task_pid = spawn(fn -> :ok end)
      :timer.sleep(50)

      TaskRegistry.register_task(task_id, task_pid, %{})

      tasks = TaskRegistry.list_tasks()
      task = List.first(tasks)

      assert task.alive == false
    end
  end

  describe "get_stats/0" do
    test "returns statistics about registered tasks" do
      alive_pid1 = spawn(fn -> :timer.sleep(:infinity) end)
      alive_pid2 = spawn(fn -> :timer.sleep(:infinity) end)

      TaskRegistry.register_task("alive_1", alive_pid1, %{task_module: Module1})
      TaskRegistry.register_task("alive_2", alive_pid2, %{task_module: Module1})

      stats = TaskRegistry.get_stats()

      # Note: Dead tasks are automatically removed by the monitor,
      # so we only count alive tasks
      assert stats.total_tasks == 2
      assert stats.alive_tasks == 2
      assert stats.dead_tasks == 0
      assert stats.by_module[Module1] == 2
    end

    test "returns zero stats when no tasks" do
      stats = TaskRegistry.get_stats()

      assert stats.total_tasks == 0
      assert stats.alive_tasks == 0
      assert stats.dead_tasks == 0
      assert stats.by_module == %{}
    end
  end

  describe "process monitoring" do
    test "automatically removes task when process dies" do
      task_id = "test_task"
      task_pid = spawn(fn -> :timer.sleep(50) end)

      TaskRegistry.register_task(task_id, task_pid, %{})
      assert {:ok, ^task_pid} = TaskRegistry.lookup_task(task_id)

      # Wait for process to die
      :timer.sleep(100)

      # Give the registry time to process the DOWN message
      :timer.sleep(50)

      assert {:error, :not_found} = TaskRegistry.lookup_task(task_id)
    end
  end

  describe "cleanup" do
    test "periodic cleanup removes dead processes" do
      # Register a dead process
      dead_pid = spawn(fn -> :ok end)
      :timer.sleep(50)

      TaskRegistry.register_task("dead_task", dead_pid, %{})

      # Verify it's registered
      assert {:ok, ^dead_pid} = TaskRegistry.lookup_task("dead_task")

      # Trigger cleanup manually by sending the message
      send(Process.whereis(TaskRegistry), :cleanup)

      # Wait for cleanup to process
      :timer.sleep(50)

      # Task should be removed
      assert {:error, :not_found} = TaskRegistry.lookup_task("dead_task")
    end
  end
end
