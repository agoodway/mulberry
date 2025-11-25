defmodule DataForSEO.TaskRegistry do
  @moduledoc """
  Registry for tracking active DataForSEO task managers.

  Provides a central registry for looking up and managing task managers
  by various identifiers.
  """

  use GenServer
  require Logger

  @table_name :dataforseo_registry

  # Client API

  @doc """
  Starts the registry.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a task manager with the registry.

  ## Parameters
    - `task_id` - Unique identifier for the task
    - `pid` - PID of the task manager
    - `metadata` - Optional metadata about the task
  """
  @spec register_task(String.t(), pid(), map()) :: :ok | {:error, :already_registered}
  def register_task(task_id, pid, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:register, task_id, pid, metadata})
  end

  @doc """
  Unregisters a task manager from the registry.
  """
  @spec unregister_task(String.t()) :: :ok
  def unregister_task(task_id) do
    GenServer.call(__MODULE__, {:unregister, task_id})
  end

  @doc """
  Looks up a task manager by task ID.
  """
  @spec lookup_task(String.t()) :: {:ok, pid()} | {:error, :not_found}
  def lookup_task(task_id) do
    case :ets.lookup(@table_name, task_id) do
      [{^task_id, pid, _metadata}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Lists all active tasks.
  """
  @spec list_tasks() :: list({String.t(), pid(), map()})
  def list_tasks do
    :ets.tab2list(@table_name)
    |> Enum.map(fn {task_id, pid, metadata} ->
      %{
        task_id: task_id,
        pid: pid,
        alive: Process.alive?(pid),
        metadata: metadata
      }
    end)
  end

  @doc """
  Gets statistics about active tasks.
  """
  @spec get_stats() :: map()
  def get_stats do
    tasks = list_tasks()

    %{
      total_tasks: length(tasks),
      alive_tasks: Enum.count(tasks, & &1.alive),
      dead_tasks: Enum.count(tasks, &(not &1.alive)),
      by_module: group_by_module(tasks)
    }
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for fast lookups
    :ets.new(@table_name, [
      :named_table,
      :set,
      :public,
      read_concurrency: true
    ])

    # Schedule periodic cleanup
    schedule_cleanup()

    {:ok, %{}}
  end

  @impl true
  def handle_call({:register, task_id, pid, metadata}, _from, state) do
    case :ets.insert_new(@table_name, {task_id, pid, metadata}) do
      true ->
        # Monitor the process
        Process.monitor(pid)
        Logger.debug("Registered task #{task_id} with pid #{inspect(pid)}")
        {:reply, :ok, state}

      false ->
        {:reply, {:error, :already_registered}, state}
    end
  end

  @impl true
  def handle_call({:unregister, task_id}, _from, state) do
    :ets.delete(@table_name, task_id)
    Logger.debug("Unregistered task #{task_id}")
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    # Process died, remove from registry
    tasks_to_remove = :ets.match_object(@table_name, {:_, pid, :_})

    Enum.each(tasks_to_remove, fn {task_id, _pid, _metadata} ->
      :ets.delete(@table_name, task_id)
      Logger.debug("Removed dead task #{task_id} (reason: #{inspect(reason)})")
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    # Remove entries for dead processes
    dead_tasks =
      list_tasks()
      |> Enum.filter(&(not &1.alive))
      |> Enum.map(& &1.task_id)

    Enum.each(dead_tasks, &unregister_task/1)

    if length(dead_tasks) > 0 do
      Logger.info("Cleaned up #{length(dead_tasks)} dead task(s) from registry")
    end

    # Schedule next cleanup
    schedule_cleanup()

    {:noreply, state}
  end

  # Private functions

  defp schedule_cleanup do
    # Run cleanup every 5 minutes
    Process.send_after(self(), :cleanup, 5 * 60 * 1000)
  end

  defp group_by_module(tasks) do
    tasks
    |> Enum.group_by(& &1.metadata[:task_module])
    |> Enum.map(fn {module, module_tasks} ->
      {module || "unknown", length(module_tasks)}
    end)
    |> Map.new()
  end
end
