defmodule GamePlatform do
  def new_game(:minesweeper, config) do
    GamePlatform.GameSupervisor.start_game(WebGames.Minesweeper.GameState, config)
  end
  def new_game(_game_type, _config), do: {:error, :unknown_game}
end
