defmodule Mulberry.Crawler.RateLimiter do
  @moduledoc """
  Token bucket rate limiter for controlling crawl request rates.

  This module implements a token bucket algorithm to limit the rate of requests
  made by the crawler. It supports:
  - Global rate limiting
  - Per-domain rate limiting
  - Configurable refill rates
  - Burst capacity

  The rate limiter is implemented as a GenServer that manages token buckets
  for different domains.
  """

  use GenServer
  require Logger

  @type domain :: String.t()
  @type tokens :: non_neg_integer()
  @type bucket :: %{
          tokens: tokens(),
          max_tokens: tokens(),
          last_refill: integer(),
          refill_rate: float()
        }

  defmodule State do
    @moduledoc false
    @type t :: %__MODULE__{
            buckets: map(),
            default_max_tokens: non_neg_integer(),
            default_refill_rate: float(),
            per_domain_limits: map()
          }

    defstruct buckets: %{},
              default_max_tokens: 10,
              default_refill_rate: 1.0,
              per_domain_limits: %{}
  end

  # Client API

  @doc """
  Starts the rate limiter GenServer.

  ## Options
    - `:default_max_tokens` - Default maximum tokens in a bucket (default: 10)
    - `:default_refill_rate` - Default tokens refilled per second (default: 1.0)
    - `:per_domain_limits` - Map of domain-specific limits

  ## Example

      Mulberry.Crawler.RateLimiter.start_link(
        default_max_tokens: 10,
        default_refill_rate: 1.0,
        per_domain_limits: %{
          "example.com" => %{max_tokens: 5, refill_rate: 0.5}
        }
      )
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Attempts to consume a token for the given domain.

  Returns `:ok` if a token was available and consumed, or `{:error, :rate_limited}`
  if no tokens are available.

  ## Examples

      iex> Mulberry.Crawler.RateLimiter.consume_token("example.com")
      :ok

      iex> Mulberry.Crawler.RateLimiter.consume_token("example.com")
      {:error, :rate_limited}
  """
  @spec consume_token(domain()) :: :ok | {:error, :rate_limited}
  def consume_token(domain) do
    GenServer.call(__MODULE__, {:consume_token, domain})
  end

  @doc """
  Waits until a token is available and then consumes it.

  This function will block until a token becomes available for the domain.
  Use with caution as it can block indefinitely if tokens are consumed
  faster than they are refilled.

  ## Options
    - `:timeout` - Maximum time to wait in milliseconds (default: 60_000)

  ## Examples

      iex> Mulberry.Crawler.RateLimiter.wait_and_consume_token("example.com", timeout: 5_000)
      :ok

      iex> Mulberry.Crawler.RateLimiter.wait_and_consume_token("example.com", timeout: 100)
      {:error, :timeout}
  """
  @spec wait_and_consume_token(domain(), keyword()) :: :ok | {:error, :timeout}
  def wait_and_consume_token(domain, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 60_000)
    wait_and_consume_token_loop(domain, timeout, System.monotonic_time(:millisecond))
  end

  @doc """
  Gets the current token count for a domain.

  Returns the number of tokens currently available for the given domain.
  """
  @spec get_token_count(domain()) :: tokens()
  def get_token_count(domain) do
    GenServer.call(__MODULE__, {:get_token_count, domain})
  end

  @doc """
  Resets the rate limiter for a specific domain.

  This will recreate the bucket with full tokens.
  """
  @spec reset_domain(domain()) :: :ok
  def reset_domain(domain) do
    GenServer.cast(__MODULE__, {:reset_domain, domain})
  end

  # Server callbacks

  @impl true
  def init(opts) do
    state = %State{
      default_max_tokens: Keyword.get(opts, :default_max_tokens, 10),
      default_refill_rate: Keyword.get(opts, :default_refill_rate, 1.0),
      per_domain_limits: Keyword.get(opts, :per_domain_limits, %{})
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:consume_token, domain}, _from, state) do
    {bucket, state} = get_or_create_bucket(domain, state)
    bucket = refill_bucket(bucket)

    if bucket.tokens >= 1 do
      bucket = %{bucket | tokens: bucket.tokens - 1}
      state = put_bucket(state, domain, bucket)
      {:reply, :ok, state}
    else
      state = put_bucket(state, domain, bucket)
      {:reply, {:error, :rate_limited}, state}
    end
  end

  @impl true
  def handle_call({:get_token_count, domain}, _from, state) do
    {bucket, state} = get_or_create_bucket(domain, state)
    bucket = refill_bucket(bucket)
    state = put_bucket(state, domain, bucket)
    {:reply, trunc(bucket.tokens), state}
  end

  @impl true
  def handle_cast({:reset_domain, domain}, state) do
    state = %{state | buckets: Map.delete(state.buckets, domain)}
    {:noreply, state}
  end

  # Private functions

  defp get_or_create_bucket(domain, state) do
    case Map.get(state.buckets, domain) do
      nil ->
        limits = Map.get(state.per_domain_limits, domain, %{})
        max_tokens = Map.get(limits, :max_tokens, state.default_max_tokens)
        refill_rate = Map.get(limits, :refill_rate, state.default_refill_rate)

        bucket = %{
          tokens: max_tokens,
          max_tokens: max_tokens,
          last_refill: System.monotonic_time(:millisecond),
          refill_rate: refill_rate
        }

        {bucket, state}

      bucket ->
        {bucket, state}
    end
  end

  defp refill_bucket(bucket) do
    now = System.monotonic_time(:millisecond)
    time_passed = (now - bucket.last_refill) / 1000.0
    tokens_to_add = time_passed * bucket.refill_rate

    new_tokens = min(bucket.tokens + tokens_to_add, bucket.max_tokens)

    %{bucket | tokens: new_tokens, last_refill: now}
  end

  defp put_bucket(state, domain, bucket) do
    %{state | buckets: Map.put(state.buckets, domain, bucket)}
  end

  defp wait_and_consume_token_loop(domain, timeout, start_time) do
    case consume_token(domain) do
      :ok ->
        :ok

      {:error, :rate_limited} ->
        elapsed = System.monotonic_time(:millisecond) - start_time

        if elapsed >= timeout do
          {:error, :timeout}
        else
          # Sleep for a short time before retrying
          Process.sleep(100)
          wait_and_consume_token_loop(domain, timeout, start_time)
        end
    end
  end
end
