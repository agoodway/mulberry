defmodule DataForSEO.Supervisor do
  @moduledoc """
  Supervisor for the DataForSEO system.

  Manages the registry and dynamic supervisor for task managers.
  """

  use Supervisor

  alias DataForSEO.{TaskRegistry, TaskManager}

  @doc """
  Starts the DataForSEO supervisor.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts a new task manager.

  ## Parameters
    - `task_module` - Module implementing ClientBehaviour
    - `task_params` - Parameters for the task
    - `opts` - Additional options for the task manager

  ## Options
    - `:callback` - Function to call when results are ready
    - `:credentials` - DataForSEO API credentials for this request (optional).
      Supports tuple `{username, password}`, atom map `%{username: u, password: p}`,
      or string map `%{"username" => u, "password" => p}`. Falls back to application
      config if not provided.
    - `:poll_interval_ms` - Polling interval in milliseconds
    - `:timeout_ms` - Total timeout for the task
    - `:task_id` - Custom task ID (auto-generated if not provided)

  ## Returns
    - `{:ok, pid}` - PID of the started task manager
    - `{:error, reason}` - Error if starting failed

  ## Examples

      # Using application config credentials (default)
      DataForSEO.Supervisor.start_task(GoogleReviews, %{cid: "123"})

      # Using per-request credentials for parallel calls with different accounts
      DataForSEO.Supervisor.start_task(GoogleReviews, %{cid: "123"},
        credentials: %{username: "account1", password: "pass1"},
        callback: fn result -> handle(result) end
      )
  """
  @spec start_task(module(), map(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_task(task_module, task_params, opts \\ []) do
    task_id = Keyword.get(opts, :task_id, generate_task_id())

    spec = %{
      id: task_id,
      start:
        {TaskManager, :start_link,
         [
           [
             task_module: task_module,
             task_params: task_params
           ] ++ opts
         ]},
      restart: :temporary
    }

    case DynamicSupervisor.start_child(__MODULE__.TaskSupervisor, spec) do
      {:ok, pid} ->
        # Register with the registry
        metadata = %{
          task_module: task_module,
          started_at: DateTime.utc_now()
        }

        TaskRegistry.register_task(task_id, pid, metadata)
        {:ok, pid}

      error ->
        error
    end
  end

  @doc """
  Stops a task manager.

  ## Parameters
    - `task_id` - ID of the task to stop
  """
  @spec stop_task(String.t()) :: :ok | {:error, :not_found}
  def stop_task(task_id) do
    case TaskRegistry.lookup_task(task_id) do
      {:ok, pid} ->
        DynamicSupervisor.terminate_child(__MODULE__.TaskSupervisor, pid)
        TaskRegistry.unregister_task(task_id)
        :ok

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Lists all active tasks with their status.
  """
  @spec list_tasks() :: list(map())
  def list_tasks do
    TaskRegistry.list_tasks()
    |> Enum.map(&add_task_status/1)
  end

  @doc """
  Gets statistics about the DataForSEO system.
  """
  @spec get_stats() :: map()
  def get_stats do
    TaskRegistry.get_stats()
  end

  @impl true
  def init(_opts) do
    children = [
      # Registry for tracking tasks
      {TaskRegistry, []},

      # Dynamic supervisor for task managers
      {DynamicSupervisor, strategy: :one_for_one, name: __MODULE__.TaskSupervisor}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # Private functions

  defp add_task_status(task) do
    status =
      case task.alive do
        true ->
          case TaskManager.get_status(task.pid) do
            {:ok, status} -> status
            _ -> %{status: :unknown}
          end

        false ->
          %{status: :dead}
      end

    Map.merge(task, status)
  end

  defp generate_task_id do
    "dfs_" <> Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
  end
end
