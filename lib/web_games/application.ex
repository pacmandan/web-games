defmodule WebGames.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    :opentelemetry_cowboy.setup()
    OpentelemetryPhoenix.setup(adapter: :cowboy2)

    children = [
      # Start the Telemetry supervisor
      WebGamesWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: WebGames.PubSub},
      # Start the Endpoint (http/https)
      WebGamesWeb.Endpoint,
      # Start a worker by calling: WebGames.Worker.start_link(arg)
      # {WebGames.Worker, arg}

      # Game platform stuff
      # TODO: Move to it's own application? Maybe need to do an umbrella project?
      # {Phoenix.PubSub, name: GamePlatform.PubSub},
      # GameSupervisor
      {GamePlatform.GameSupervisor, []},
      # Registry
      {Registry, [keys: :unique, name: GamePlatform.GameRegistry.registry_name()]},
      # {Task.Supervisor, name: WebGames.TaskSupervisor}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: WebGames.Supervisor]
    Supervisor.start_link(children, opts)
  after
    # Task.Supervisor.start_child(WebGames.TaskSupervisor, fn ->
    #   Sibyl.Handlers.attach_all_events(Sibyl.Handlers.OpenTelemetry)
    # end)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    WebGamesWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
