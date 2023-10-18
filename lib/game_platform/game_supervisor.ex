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
    # TODO: Check if this ID is in use.
    # If it is, roll again, but with 1 more character.
    # Repeat until we get an unused ID, or reach 30 characters. (In which case, return an error because WTF.)
    for _ <- 1..4, into: "", do: <<Enum.random(?A..?Z)>>
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
