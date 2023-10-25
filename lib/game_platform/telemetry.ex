defmodule GamePlatform.Telemetry do
  @prefix [:game_platform]

  import Telemetry.Metrics

  def metrics() do
    [
      summary("game_platform.server.start.system_time",
        unit: {:native, :millisecond},
        tags: [:game_id, :game_type]
      ),
      summary("game_platform.server.stop.duration",
        unit: {:native, :millisecond},
        tags: [:game_id, :game_type, :status]
      ),
      last_value("game_platform.server.active.count"),
    ]
  end

  def emit_player_join(game_id, player_id) do
    :telemetry.execute(
      @prefix ++ [:server, :player, :joined],
      %{system_time: System.system_time()},
      %{game_id: game_id, player_id: player_id}
    )
  end

  def emit_player_connected(game_id, player_id) do
    :telemetry.execute(
      @prefix ++ [:server, :player, :connected],
      %{system_time: System.system_time()},
      %{game_id: game_id, player_id: player_id}
    )
  end

  def emit_player_disconnected(game_id, player_id) do
    :telemetry.execute(
      @prefix ++ [:server, :player, :disconnected],
      %{system_time: System.system_time()},
      %{game_id: game_id, player_id: player_id}
    )
  end

  def emit_player_left(game_id, player_id) do
    :telemetry.execute(
      @prefix ++ [:server, :player, :left],
      %{system_time: System.system_time()},
      %{game_id: game_id, player_id: player_id}
    )
  end

  def count_active_games() do
    if Process.whereis(GamePlatform.GameRegistry.registry_name()) |> is_nil() do
      # Periodic telemetry processes fire off before the registry has a chance to start.
      # If we can't find it, then no games exist yet.
      # (Should this even run :telemetry.execute() here?)
      :telemetry.execute(
        [:game_platform, :server, :active],
        %{count: 0},
        %{}
      )
    else
      count = Registry.count(GamePlatform.GameRegistry.registry_name())
      :telemetry.execute(
        [:game_platform, :server, :active],
        %{count: count},
        %{}
      )
    end
  end
end
