defmodule GamePlatform.Game do
  alias GamePlatform.GameServer

  @registry :game_registry

  def join_game(player_id, game_id) do
    GenServer.call(GameServer.via_tuple(game_id), {:join_game, player_id})
  end

  def send_event(event, from, game_id) do
    GenServer.cast(GameServer.via_tuple(game_id), {:game_event, from, event})
  end

  def player_connected(player_id, game_id, pid) do
    GenServer.cast(GameServer.via_tuple(game_id), {:player_connected, player_id, pid})
  end

  def send_event_after(event, time) do
    Process.send_after(self(), {:game_event, event}, time)
  end

  def send_event_after(event, game_id, time) do
    case Registry.lookup(@registry, game_id) do
      [] -> {:error, :not_found}
      [{pid, _}] -> {:ok, Process.send_after(pid, {:game_event, event}, time)}
      _ -> {:error, :unknown_error}
    end
  end

  def game_exists?(game_id) do
    Registry.lookup(@registry, game_id) |> Enum.count() > 0
  end
end
