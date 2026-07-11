defmodule MovimentoApi.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MovimentoApiWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:movimento_api, :dns_cluster_query) || :ignore},
      MovimentoApi.Repo,
      {Phoenix.PubSub, name: MovimentoApi.PubSub},
      # Start a worker by calling: MovimentoApi.Worker.start_link(arg)
      # {MovimentoApi.Worker, arg},
      # Start to serve requests, typically the last entry
      MovimentoApiWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MovimentoApi.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MovimentoApiWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
