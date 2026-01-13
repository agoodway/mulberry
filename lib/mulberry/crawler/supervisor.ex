defmodule Mulberry.Crawler.Supervisor do
  @moduledoc """
  Supervisor for the crawler system.

  This supervisor manages:
  - The rate limiter GenServer
  - A DynamicSupervisor for crawler workers
  - Individual crawler orchestrators

  The supervisor uses a one_for_one strategy, allowing components to fail
  and restart independently.
  """

  use Supervisor

  @doc """
  Starts the crawler supervisor.

  ## Options
    - `:rate_limiter_opts` - Options for the rate limiter (see Mulberry.Crawler.RateLimiter)
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts a new crawler orchestrator under the supervisor.

  ## Options
    See `Mulberry.Crawler.Orchestrator.start_link/1` for available options.
  """
  @spec start_crawler(keyword()) :: DynamicSupervisor.on_start_child()
  def start_crawler(opts) do
    # Add the worker supervisor to the options
    opts = Keyword.put(opts, :supervisor, Mulberry.Crawler.WorkerSupervisor)

    DynamicSupervisor.start_child(
      Mulberry.Crawler.OrchestratorSupervisor,
      {Mulberry.Crawler.Orchestrator, opts}
    )
  end

  @impl true
  def init(opts) do
    rate_limiter_opts = Keyword.get(opts, :rate_limiter_opts, [])
    robots_txt_opts = Keyword.get(opts, :robots_txt_opts, [])

    children = [
      # Rate limiter (singleton)
      {Mulberry.Crawler.RateLimiter, rate_limiter_opts},

      # robots.txt cache (singleton)
      {Mulberry.Crawler.RobotsTxt, robots_txt_opts},

      # DynamicSupervisor for workers
      {DynamicSupervisor, name: Mulberry.Crawler.WorkerSupervisor, strategy: :one_for_one},

      # DynamicSupervisor for orchestrators
      {DynamicSupervisor, name: Mulberry.Crawler.OrchestratorSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
