defmodule WebGames do
  @moduledoc """
  WebGames keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  alias WebGames.Minesweeper.GameState, as: MinesweeperState

  def start_minesweeper(player_id, minesweeper_config) do

    server_config = %{
      pubsub: WebGames.PubSub,
    }

    GamePlatform.GameSupervisor.start_game({MinesweeperState, minesweeper_config}, server_config)
  end

  # TODO: Wrap this in a ":dev" check
  def start_observer() do
    Mix.ensure_application!(:wx)
    Mix.ensure_application!(:runtime_tools)
    Mix.ensure_application!(:observer)
    :observer.start()
  end
end
