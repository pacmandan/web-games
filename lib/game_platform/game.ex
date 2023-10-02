defmodule GamePlatform.Game do
  @registry :game_registry

  def add_player(player_id, game_id) do
    GenServer.cast(via_tuple(game_id), {:add_player, player_id})
  end

  def send_event(event, from, game_id) do
    GenServer.cast(via_tuple(game_id), {:game_event, from, event})
  end

  def player_connected(player_id, game_id, pid) do
    GenServer.cast(via_tuple(game_id), {:player_connected, player_id, pid})
  end

  def schedule_event(event, time) do
    Process.send_after(self(), {:game_event, event}, time)
  end

  def game_exists?(game_id) do
    Registry.lookup(@registry, game_id) |> Enum.count() > 0
  end

  defp via_tuple(id) do
    {:via, Registry, {@registry, id}}
  end
end
