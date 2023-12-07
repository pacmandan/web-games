defmodule GamePlatform.Game do
  alias GamePlatform.GameRegistry
  alias GamePlatform.GameServer
  alias GamePlatform.GameServer.GameMessage

  def join_game(player_id, game_id) do
    msg = %GameMessage{
      action: :player_join,
      from: player_id,
      ctx: OpenTelemetry.Tracer.current_span_ctx(),
    }
    GenServer.call(GameServer.via_tuple(game_id), msg)
  end

  def send_event(event, from, game_id) do
    msg = %GameMessage{
      action: :game_event,
      from: from,
      payload: event,
      ctx: OpenTelemetry.Tracer.current_span_ctx(),
    }
    GenServer.cast(GameServer.via_tuple(game_id), msg)
  end

  def player_connected(player_id, game_id, pid) do
    msg = %GameMessage{
      action: :player_connected,
      from: player_id,
      payload: %{
        pid: pid,
      },
      ctx: OpenTelemetry.Tracer.current_span_ctx(),
    }
    GenServer.cast(GameServer.via_tuple(game_id), msg)
  end

  def get_game_info(game_id) do
    GenServer.call(GameServer.via_tuple(game_id), :game_info)
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
