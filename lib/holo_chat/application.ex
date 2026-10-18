defmodule HoloChat.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      HoloChatWeb.Telemetry,
      HoloChat.Repo,
      {DNSCluster, query: Application.get_env(:holo_chat, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: HoloChat.PubSub},
      # Start a worker by calling: HoloChat.Worker.start_link(arg)
      # {HoloChat.Worker, arg},
      # Start to serve requests, typically the last entry
      HoloChatWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: HoloChat.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    HoloChatWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
