defmodule Listex.DataForSEO.TaskManager do
  @moduledoc """
  Generic GenServer that manages the lifecycle of DataForSEO tasks.

  This GenServer handles the three-stage process:
  1. Creating tasks
  2. Monitoring task status
  3. Fetching results

  It uses a behaviour module to handle task-specific logic.
  """

  use GenServer
  require Logger

  alias Listex.DataForSEO.Client

  defmodule State do
    @moduledoc """
    Internal state for the task manager.
    """
    @type t :: %__MODULE__{
            task_module: module(),
            task_params: map(),
            task_ids: list(String.t()),
            status: atom(),
            results: list(map()),
            error: term() | nil,
            retry_count: non_neg_integer(),
            poll_timer: reference() | nil,
            created_at: DateTime.t(),
            updated_at: DateTime.t(),
            callback: function() | nil
          }

    defstruct [
      :task_module,
      :task_params,
      :callback,
      task_ids: [],
      status: :initializing,
      results: [],
      error: nil,
      retry_count: 0,
      poll_timer: nil,
      created_at: nil,
      updated_at: nil
    ]
  end

  # Configuration
  @default_poll_interval_ms 5_000
  # 5 minutes
  @default_timeout_ms 300_000
  @max_retries 3

  # Client API

  @doc """
  Starts a task manager for a specific task type.

  ## Options
    - `:task_module` - Module implementing ClientBehaviour (required)
    - `:task_params` - Parameters for the task (required)
    - `:callback` - Function to call when results are ready (optional)
    - `:poll_interval_ms` - Polling interval in milliseconds
    - `:timeout_ms` - Total timeout for the task
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Gets the current status and results of the task.
  """
  @spec get_status(pid()) :: {:ok, map()}
  def get_status(pid) do
    GenServer.call(pid, :get_status)
  end

  @doc """
  Cancels the task and stops the GenServer.
  """
  @spec cancel(pid()) :: :ok
  def cancel(pid) do
    GenServer.stop(pid, :normal)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    task_module = Keyword.fetch!(opts, :task_module)
    task_params = Keyword.fetch!(opts, :task_params)
    callback = Keyword.get(opts, :callback)

    state = %State{
      task_module: task_module,
      task_params: task_params,
      callback: callback,
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }

    # Validate params if the callback is implemented
    case validate_params(task_module, task_params) do
      :ok ->
        # Start the task creation process
        send(self(), :create_task)
        {:ok, state}

      {:error, reason} ->
        {:stop, {:invalid_params, reason}}
    end
  end

  @impl true
  def handle_info(:create_task, state) do
    Logger.info("Creating DataForSEO task with module: #{state.task_module}")

    case create_task(state) do
      {:ok, task_ids} ->
        Logger.info("Successfully created #{length(task_ids)} task(s): #{inspect(task_ids)}")

        new_state = %{
          state
          | task_ids: task_ids,
            status: :monitoring,
            updated_at: DateTime.utc_now()
        }

        schedule_poll()
        {:noreply, new_state}

      {:error, reason} ->
        handle_error(reason, state)
    end
  end

  @impl true
  def handle_info(:check_status, %{status: :monitoring} = state) do
    case check_ready_tasks(state) do
      {:ok, ready_ids} when ready_ids != [] ->
        Logger.info("Tasks ready: #{inspect(ready_ids)}")
        # Fetch results for ready tasks
        send(self(), :fetch_results)
        {:noreply, %{state | status: :fetching, updated_at: DateTime.utc_now()}}

      {:ok, []} ->
        # No tasks ready yet, continue polling
        if task_timeout?(state) do
          handle_error({:timeout, "Task timeout exceeded"}, state)
        else
          schedule_poll()
          {:noreply, state}
        end

      {:error, reason} ->
        handle_error(reason, state)
    end
  end

  @impl true
  def handle_info(:fetch_results, %{status: :fetching} = state) do
    case fetch_all_results(state) do
      {:ok, results} ->
        Logger.info("Successfully fetched results for #{length(results)} task(s)")

        new_state = %{
          state
          | results: results,
            status: :completed,
            updated_at: DateTime.utc_now()
        }

        # Call callback if provided
        if state.callback do
          callback_results = unwrap_single_result(results)
          # Log the structure for debugging
          Logger.debug("Callback results structure: #{inspect(callback_results)}")
          state.callback.({:ok, callback_results})
        end

        {:noreply, new_state}

      {:error, reason} ->
        handle_error(reason, state)
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    response = %{
      status: state.status,
      task_ids: state.task_ids,
      results: state.results,
      error: state.error,
      created_at: state.created_at,
      updated_at: state.updated_at
    }

    {:reply, {:ok, response}, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Cancel any pending timers
    if state.poll_timer do
      Process.cancel_timer(state.poll_timer)
    end

    :ok
  end

  # Private functions

  defp validate_params(task_module, params) do
    if function_exported?(task_module, :validate_params, 1) do
      task_module.validate_params(params)
    else
      :ok
    end
  end

  defp create_task(state) do
    payload = state.task_module.build_task_payload(state.task_params)
    task_type = state.task_module.task_type()

    case Client.create_task(task_type, payload) do
      {:ok, response} ->
        state.task_module.parse_task_response(response)

      error ->
        error
    end
  end

  defp check_ready_tasks(state) do
    task_type = state.task_module.task_type()

    case Client.check_ready_tasks(task_type) do
      {:ok, response} ->
        ready_ids = state.task_module.parse_ready_tasks(response)
        # Filter to only our task IDs
        our_ready_ids = Enum.filter(ready_ids, &(&1 in state.task_ids))
        {:ok, our_ready_ids}

      error ->
        error
    end
  end

  defp fetch_all_results(state) do
    task_type = state.task_module.task_type()

    results =
      state.task_ids
      |> Enum.map(&fetch_single_result(&1, task_type, state.task_module))

    # Check if all fetches were successful
    errors =
      Enum.filter(results, fn
        {:error, _} -> true
        _ -> false
      end)

    if errors == [] do
      # All successful, extract results
      parsed_results = Enum.map(results, fn {:ok, {_id, result}} -> result end)
      {:ok, parsed_results}
    else
      # Return first error
      List.first(errors)
    end
  end

  defp schedule_poll do
    interval = get_config(:poll_interval_ms, @default_poll_interval_ms)
    timer = Process.send_after(self(), :check_status, interval)
    timer
  end

  defp handle_error(reason, state) do
    Logger.error("Task manager error: #{inspect(reason)}")

    if state.retry_count < @max_retries do
      # Retry the current operation
      new_state = %{state | retry_count: state.retry_count + 1, updated_at: DateTime.utc_now()}

      # Reschedule based on current status
      case state.status do
        :initializing ->
          send(self(), :create_task)

        :monitoring ->
          schedule_poll()

        :fetching ->
          send(self(), :fetch_results)

        _ ->
          nil
      end

      {:noreply, new_state}
    else
      # Max retries exceeded
      final_state = %{state | status: :failed, error: reason, updated_at: DateTime.utc_now()}

      if state.callback do
        state.callback.({:error, reason})
      end

      {:noreply, final_state}
    end
  end

  defp task_timeout?(state) do
    timeout = get_config(:timeout_ms, @default_timeout_ms)
    elapsed = DateTime.diff(DateTime.utc_now(), state.created_at, :millisecond)
    elapsed > timeout
  end

  defp fetch_single_result(task_id, task_type, task_module) do
    case Client.fetch_task_results(task_type, task_id) do
      {:ok, response} ->
        case task_module.parse_task_results(response) do
          {:ok, parsed} -> {:ok, {task_id, parsed}}
          error -> error
        end

      error ->
        error
    end
  end

  defp get_config(key, default) do
    case Application.get_env(:listex, :dataforseo) do
      nil -> default
      config -> config[key] || default
    end
  end

  # For single task results, unwrap the list for convenience
  defp unwrap_single_result([single_result]), do: single_result
  defp unwrap_single_result(multiple), do: multiple
end
