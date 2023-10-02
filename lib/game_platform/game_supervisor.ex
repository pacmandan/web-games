defmodule GamePlatform.GameSupervisor do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def start_game(game_spec, server_config) do
    game_id = generate_game_id()
    child_spec = {GamePlatform.GameServer, {game_id, game_spec, server_config}}

    {game_id, DynamicSupervisor.start_child(__MODULE__, child_spec)}
  end

  defp generate_game_id() do
    for _ <- 1..4, into: "", do: <<Enum.random(?A..?Z)>>
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
