defmodule GamePlatform.Telemetry do
  import Telemetry.Metrics

  def metrics() do
    [
      last_value("game_platform.server.active.count"),
    ]
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
