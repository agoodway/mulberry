defmodule DataForSEO.ClientBehaviour do
  @moduledoc """
  Behaviour defining the interface for DataForSEO task implementations.

  Each DataForSEO API endpoint should implement this behaviour to define
  how to create tasks, parse responses, and fetch results for that specific endpoint.
  """

  @type task_params :: map()
  @type task_id :: String.t()
  @type task_response :: map()
  @type error :: {:error, term()}

  @doc """
  Returns the task type identifier used in DataForSEO API URLs.

  ## Examples
      
      def task_type, do: "serp/google/events"
  """
  @callback task_type() :: String.t()

  @doc """
  Builds the request payload for creating a new task.

  ## Parameters
    - `params` - Parameters specific to the task type
    
  ## Returns
    - A list of task objects to be sent to the API
  """
  @callback build_task_payload(params :: task_params()) :: list(map())

  @doc """
  Parses the response from task creation.

  ## Parameters
    - `response` - The response body from the task creation endpoint
    
  ## Returns
    - `{:ok, task_ids}` - List of created task IDs
    - `{:error, reason}` - Error if task creation failed
  """
  @callback parse_task_response(response :: map()) :: {:ok, list(task_id())} | error()

  @doc """
  Parses the response from the tasks_ready endpoint.

  ## Parameters
    - `response` - The response body from the tasks_ready endpoint
    
  ## Returns
    - List of ready task IDs
  """
  @callback parse_ready_tasks(response :: map()) :: list(task_id())

  @doc """
  Parses the final task results.

  ## Parameters
    - `response` - The response body from the task_get endpoint
    
  ## Returns
    - `{:ok, results}` - Parsed results specific to the task type
    - `{:error, reason}` - Error if parsing failed
  """
  @callback parse_task_results(response :: map()) :: {:ok, task_response()} | error()

  @doc """
  Optional callback to validate task parameters before creation.

  ## Parameters
    - `params` - Parameters to validate

  ## Returns
    - `:ok` if valid
    - `{:error, reason}` if invalid
  """
  @callback validate_params(params :: task_params()) :: :ok | error()

  @doc """
  Optional callback to indicate if this endpoint uses live (instant) results.

  Live endpoints return results immediately in the response and don't require
  polling. If not implemented, defaults to `false` (async task-based endpoint).

  ## Returns
    - `true` if this is a live endpoint (e.g., Business Listings)
    - `false` if this is an async task endpoint (e.g., Google Events)
  """
  @callback is_live_endpoint?() :: boolean()

  @doc """
  Optional callback to specify the result endpoint type for task_get.

  Different DataForSEO endpoints use different result endpoint formats:
  - Some use task_get/advanced (default)
  - Others just use task_get (e.g., Google Reviews)

  ## Returns
    - The endpoint suffix string (e.g., "advanced", "regular", or "" for none)
  """
  @callback result_endpoint() :: String.t()

  @optional_callbacks validate_params: 1, is_live_endpoint?: 0, result_endpoint: 0
end
