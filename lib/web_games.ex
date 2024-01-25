defmodule WebGames do
  @moduledoc """
  WebGames keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  alias GamePlatform.GameServer.GameSpec
  alias WebGames.Minesweeper.GameState, as: MinesweeperState
  alias WebGames.LightCycles.GameState, as: LightCyclesState

  def start_minesweeper(player_id, minesweeper_config) do
    server_config = %{
      pubsub: WebGames.PubSub,
      player_disconnect_timeout_length: :timer.seconds(15),
    }

    GameSpec.make(MinesweeperState, player_id, minesweeper_config)
    |> GamePlatform.GameSupervisor.start_game(server_config)
  end

  def start_lightcycles(player_id, lightcycles_config) do
    server_config = %{
      pubsub: WebGames.PubSub,
    }
    GameSpec.make(LightCyclesState, player_id, lightcycles_config)
    |> GamePlatform.GameSupervisor.start_game(server_config)
  end

  # TODO: Wrap this in a ":dev" check
  # def start_observer() do
  #   Mix.ensure_application!(:wx)
  #   Mix.ensure_application!(:runtime_tools)
  #   Mix.ensure_application!(:observer)
  #   :observer.start()
  # end
end
