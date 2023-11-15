defmodule GamePlatform.Game do
  alias GamePlatform.GameRegistry
  alias GamePlatform.GameServer

  def join_game(player_id, game_id) do
    GenServer.call(GameServer.via_tuple(game_id), {:join_game, player_id})
  end

  def send_event(event, from, game_id) do
    # TODO: Add span context
    GenServer.cast(GameServer.via_tuple(game_id), {:game_event, from, event})
  end

  def player_connected(player_id, game_id, pid) do
    GenServer.cast(GameServer.via_tuple(game_id), {:player_connected, player_id, pid})
  end

  def get_game_type(game_id) do
    GenServer.call(GameServer.via_tuple(game_id), :game_type)
  end

  # TODO: Move some of these Registry.lookup() functions into GameRegistry

  def monitor(game_id) do
    {:ok, pid} = GameRegistry.lookup(game_id)
    Process.monitor(pid)
  end

  def game_exists?(game_id) do
    Registry.lookup(GameRegistry.registry_name(), game_id) |> Enum.count() > 0
  end

  def is_game_alive?(game_id) do
    case Registry.lookup(GameRegistry.registry_name(), game_id) do
      [] -> false
      [{pid, _}] -> Process.alive?(pid)
    end
  end
end
