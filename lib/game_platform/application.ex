defmodule GamePlatform.Application do
  use Application

  @registry :game_registry

  @impl true
  def start(_type, _args) do
    children = [
      # Start the PubSub system
      {Phoenix.PubSub, name: GamePlatform.PubSub},
      # GameSupervisor
      {GamePlatform.GameSupervisor, []},
      # Registry
      {Registry, [keys: :unique, name: @registry]},
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: GamePlatform.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
