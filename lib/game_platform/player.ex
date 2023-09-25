defmodule GamePlatform.Player do
  use GenServer

  defstruct [
    :id,
    :role,
    :name,
    :game_id,
  ]

  def new_player(game_id, role) do
    %__MODULE__{id: generate_player_id(), role: role, game_id: game_id}
  end

  defp generate_player_id() do
    for _ <- 1..20, into: "", do: <<Enum.random(?a..?z)>>
  end

  def init(player) do
    Phoenix.PubSub.subscribe(WebGames.PubSub, "game:#{player.game_id}")
    {:ok, player}
  end

  def start_link(player) do
    GenServer.start_link(__MODULE__, player, name: via_tuple(player.id))
  end

  defp via_tuple(player_id) do
    {:via, Registry, {:game_registry, player_id}}
  end

  def handle_info({:game_event, _game_id, event}, state) do
    IO.inspect("GOT EVENT!")
    IO.inspect(event)
    {:noreply, state}
  end
end
