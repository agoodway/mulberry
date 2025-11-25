defmodule Mulberry.Application do
  @moduledoc """
  The Mulberry Application module.

  This module defines the OTP application callback and supervision tree for Mulberry.
  It ensures that essential services like the DataForSEO.Supervisor are started and
  monitored when the application starts.

  ## Supervision Tree

  The application starts the following children under a `:one_for_one` supervision strategy:

    * `DataForSEO.Supervisor` - Manages DataForSEO task lifecycle and provides API
      for starting business listings searches, Google events searches, and other
      DataForSEO API operations.

  ## Configuration

  The application is configured in `mix.exs` with:

      def application do
        [
          mod: {Mulberry.Application, []},
          extra_applications: [:logger]
        ]
      end

  """

  use Application

  require Logger

  @impl true
  @spec start(Application.start_type(), term()) :: {:ok, pid()} | {:error, term()}
  def start(_type, _args) do
    Logger.info("Starting Mulberry application")

    children = [
      # DataForSEO Supervisor for managing API tasks
      DataForSEO.Supervisor
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Mulberry.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
