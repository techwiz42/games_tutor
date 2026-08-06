defmodule GamesTutor.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Binbo (the chess engine/board library) expects an explicit start call
    # rather than auto-starting as an included application -- every example
    # in its own docs calls binbo:start() before any other binbo function.
    {:ok, _} = Application.ensure_all_started(:binbo)

    redis_opts = Application.fetch_env!(:games_tutor, :redis)

    children = [
      GamesTutorWeb.Telemetry,
      GamesTutor.Repo,
      {DNSCluster, query: Application.get_env(:games_tutor, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: GamesTutor.PubSub},
      GamesTutor.Accounts.OAuthStateStore,
      {Registry, keys: :unique, name: GamesTutor.Chess.GameRegistry},
      {DynamicSupervisor, name: GamesTutor.Chess.GameSupervisor, strategy: :one_for_one},
      {Task.Supervisor, name: GamesTutor.Chess.AnalysisTaskSupervisor},
      {Redix, host: redis_opts[:host], port: redis_opts[:port], name: GamesTutor.Redis},
      # Start to serve requests, typically the last entry
      GamesTutorWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: GamesTutor.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GamesTutorWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
