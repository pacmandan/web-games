defmodule GamePlatform.GameSupervisor do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def start_game(game_module, config) do
    id = generate_game_id()
    child_spec = {GamePlatform.Game, %{id: id, state_module: game_module, config: config}}

    {id, DynamicSupervisor.start_child(__MODULE__, child_spec)}
  end

  defp generate_game_id() do
    for _ <- 1..4, into: "", do: <<Enum.random(?A..?Z)>>
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
