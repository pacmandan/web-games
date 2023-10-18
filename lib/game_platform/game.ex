defmodule GamePlatform.Game do
  alias GamePlatform.GameRegistry
  alias GamePlatform.GameServer

  def join_game(player_id, game_id) do
    GenServer.call(GameServer.via_tuple(game_id), {:join_game, player_id})
  end

  def send_event(event, from, game_id) do
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
    {pid, _} = Registry.lookup(GameRegistry.registry_name(), game_id) |> hd()
    Process.monitor(pid)
  end

  def send_event_after(event, game_id, time) do
    case Registry.lookup(GameRegistry.registry_name(), game_id) do
      [] -> {:error, :not_found}
      [{pid, _}] -> {:ok, Process.send_after(pid, {:game_event, event}, time)}
      _ -> {:error, :unknown_error}
    end
  end

  def game_exists?(game_id) do
    Registry.lookup(GameRegistry.registry_name(), game_id) |> Enum.count() > 0
  end
end
