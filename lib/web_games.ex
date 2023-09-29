defmodule WebGames do
  @moduledoc """
  WebGames keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  alias GamePlatform.GameServerConfig
  alias WebGames.Minesweeper.GameState, as: MinesweeperState

  def start_minesweeper(player_id, minesweeper_config) do
    config = default_server_config()
    |> GameServerConfig.set_start_player_id(player_id)
    |> GameServerConfig.set_game_state(MinesweeperState, minesweeper_config)

    GamePlatform.GameSupervisor.start_game(config)
  end

  defp default_server_config() do
    GameServerConfig.new_config()
    |> GameServerConfig.set_pubsub(WebGames.PubSub)
    |> GameServerConfig.set_max_length(:timer.seconds(120))
  end
end
