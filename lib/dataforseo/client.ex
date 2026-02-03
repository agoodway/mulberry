defmodule DataForSEO.Client do
  @moduledoc """
  HTTP client for DataForSEO API.

  Handles authentication, request building, and response parsing for all
  DataForSEO API endpoints.

  ## Credential Options

  All public functions accept an optional `opts` keyword list that can include
  a `:credentials` option for per-request authentication. This enables parallel
  requests with different accounts.

  Supported credential formats:
  - Tuple: `{username, password}`
  - Atom map: `%{username: "user", password: "pass"}`
  - String map: `%{"username" => "user", "password" => "pass"}`

  If no credentials are provided, falls back to application config:
  `Application.get_env(:mulberry, :dataforseo)`
  """

  require Logger

  @base_url "https://api.dataforseo.com/v3"
  @max_retries 3
  @retry_delay_ms 1000

  @typedoc "Error tuple returned on failure"
  @type error :: {:error, term()}

  @typedoc "Credentials for DataForSEO API authentication"
  @type credentials ::
          {String.t(), String.t()}
          | %{username: String.t(), password: String.t()}
          | %{String.t() => String.t()}

  @typedoc "Options for API calls, including optional credentials"
  @type opts :: [credentials: credentials()]

  @doc """
  Creates a new task in DataForSEO.

  ## Parameters
    - `task_type` - The type of task (e.g., "serp/google/events")
    - `payload` - List of task objects to create
    - `opts` - Optional keyword list with `:credentials` for per-request auth

  ## Returns
    - `{:ok, response}` - Successful response
    - `{:error, reason}` - Error details
  """
  @spec create_task(String.t(), list(map()), opts()) :: {:ok, map()} | error()
  def create_task(task_type, payload, opts \\ []) do
    url = "#{@base_url}/#{task_type}/task_post"

    with {:ok, auth} <- get_auth(opts) do
      post_with_retry(url, payload, auth)
    end
  end

  @doc """
  Creates a live task that returns results immediately.

  Live endpoints return results in the response without requiring polling.
  Used for endpoints like Business Listings that provide instant results.

  ## Parameters
    - `task_type` - The type of task (e.g., "business_data/business_listings/search")
    - `payload` - List of task objects to create
    - `opts` - Optional keyword list with `:credentials` for per-request auth

  ## Returns
    - `{:ok, response}` - Successful response with results
    - `{:error, reason}` - Error details
  """
  @spec create_live_task(String.t(), list(map()), opts()) :: {:ok, map()} | error()
  def create_live_task(task_type, payload, opts \\ []) do
    url = "#{@base_url}/#{task_type}/live"

    with {:ok, auth} <- get_auth(opts) do
      post_with_retry(url, payload, auth)
    end
  end

  @doc """
  Checks for ready tasks.

  ## Parameters
    - `task_type` - The type of task (e.g., "serp/google/events")
    - `opts` - Optional keyword list with `:credentials` for per-request auth

  ## Returns
    - `{:ok, response}` - List of ready tasks
    - `{:error, reason}` - Error details
  """
  @spec check_ready_tasks(String.t(), opts()) :: {:ok, map()} | error()
  def check_ready_tasks(task_type, opts \\ []) do
    url = "#{@base_url}/#{task_type}/tasks_ready"

    with {:ok, auth} <- get_auth(opts) do
      get_with_retry(url, auth)
    end
  end

  @doc """
  Fetches results for a specific task.

  ## Parameters
    - `task_type` - The type of task (e.g., "serp/google/events")
    - `task_id` - The ID of the task to fetch
    - `endpoint` - The result endpoint (e.g., "advanced", "regular", "html", or "" for none)
    - `opts` - Optional keyword list with `:credentials` for per-request auth

  ## Returns
    - `{:ok, response}` - Task results
    - `{:error, reason}` - Error details
  """
  @spec fetch_task_results(String.t(), String.t(), String.t(), opts()) :: {:ok, map()} | error()
  def fetch_task_results(task_type, task_id, endpoint \\ "advanced", opts \\ [])

  def fetch_task_results(task_type, task_id, endpoint, opts) do
    url =
      if endpoint == "" do
        "#{@base_url}/#{task_type}/task_get/#{task_id}"
      else
        "#{@base_url}/#{task_type}/task_get/#{endpoint}/#{task_id}"
      end

    with {:ok, auth} <- get_auth(opts) do
      get_with_retry(url, auth)
    end
  end

  # Private functions

  defp get_auth(opts) do
    case Keyword.get(opts, :credentials) do
      nil ->
        get_credentials_from_config()

      {username, password} when is_binary(username) and is_binary(password) ->
        validate_credentials(username, password)

      %{username: username, password: password}
      when is_binary(username) and is_binary(password) ->
        validate_credentials(username, password)

      %{"username" => username, "password" => password}
      when is_binary(username) and is_binary(password) ->
        validate_credentials(username, password)

      _ ->
        {:error, :invalid_credentials_format}
    end
  end

  defp get_credentials_from_config do
    case Application.get_env(:mulberry, :dataforseo) do
      nil ->
        {:error, :missing_credentials}

      config ->
        username = config[:username]
        password = config[:password]

        if is_binary(username) and is_binary(password) do
          validate_credentials(username, password)
        else
          {:error, :missing_credentials}
        end
    end
  end

  # Validate credentials are non-empty and reasonable length
  @max_credential_length 500

  defp validate_credentials(username, password) do
    cond do
      username == "" or password == "" ->
        {:error, :empty_credentials}

      byte_size(username) > @max_credential_length or byte_size(password) > @max_credential_length ->
        {:error, :credentials_too_long}

      true ->
        {:ok, {username, password}}
    end
  end

  defp post_with_retry(url, body, auth, attempts \\ 0) do
    req_options = build_req_options(auth)

    case Req.post(url, [json: body] ++ req_options) do
      {:ok, %{status: status, body: response_body}} when status in 200..299 ->
        parse_response(response_body)

      {:ok, %{status: status} = _response}
      when status in [429, 500, 502, 503, 504] and attempts < @max_retries ->
        delay = @retry_delay_ms * :math.pow(2, attempts)
        Logger.warning("DataForSEO API returned #{status}, retrying in #{delay}ms...")
        Process.sleep(round(delay))
        post_with_retry(url, body, auth, attempts + 1)

      {:ok, %{status: status, body: body}} ->
        Logger.error("DataForSEO API error: #{status} - #{sanitize_for_log(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.error("DataForSEO request failed: #{sanitize_for_log(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  defp get_with_retry(url, auth, attempts \\ 0) do
    req_options = build_req_options(auth)

    case Req.get(url, req_options) do
      {:ok, %{status: status, body: response_body}} when status in 200..299 ->
        parse_response(response_body)

      {:ok, %{status: status} = _response}
      when status in [429, 500, 502, 503, 504] and attempts < @max_retries ->
        delay = @retry_delay_ms * :math.pow(2, attempts)
        Logger.warning("DataForSEO API returned #{status}, retrying in #{delay}ms...")
        Process.sleep(round(delay))
        get_with_retry(url, auth, attempts + 1)

      {:ok, %{status: status, body: body}} ->
        Logger.error("DataForSEO API error: #{status} - #{sanitize_for_log(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.error("DataForSEO request failed: #{sanitize_for_log(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  defp build_req_options({username, password}) do
    [
      auth: {:basic, username <> ":" <> password},
      headers: [
        {"content-type", "application/json"},
        {"accept", "application/json"}
      ],
      # We handle retries manually
      retry: false
    ]
  end

  defp parse_response(body) when is_map(body) do
    case body do
      %{"status_code" => status, "status_message" => message} when status != 20_000 ->
        {:error, {:api_error, status, message}}

      response ->
        {:ok, response}
    end
  end

  defp parse_response(body) do
    {:error, {:invalid_response, body}}
  end

  # Sanitize response bodies and errors before logging to prevent credential leakage
  defp sanitize_for_log(body) when is_map(body), do: "[response body redacted]"
  defp sanitize_for_log(body) when is_binary(body), do: "[response body redacted]"
  defp sanitize_for_log(_), do: "[redacted]"
end
