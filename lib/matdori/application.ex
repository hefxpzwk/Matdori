defmodule Matdori.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MatdoriWeb.Telemetry,
      Matdori.Repo,
      {DNSCluster, query: Application.get_env(:matdori, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Matdori.PubSub},
      MatdoriWeb.Presence,
      Matdori.RateLimiter,
      # Start a worker by calling: Matdori.Worker.start_link(arg)
      # {Matdori.Worker, arg},
      # Start to serve requests, typically the last entry
      MatdoriWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Matdori.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MatdoriWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
