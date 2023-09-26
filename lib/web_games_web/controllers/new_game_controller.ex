defmodule WebGamesWeb.NewGameController do
  use WebGamesWeb, :controller

  def start_minesweeper(conn, _params) do
    {game_id, player_id, _} = GamePlatform.new_game(:minesweeper, WebGames.Minesweeper.Config.beginner())

    conn
    |> clear_session()
    |> put_session("game_id", game_id)
    |> put_session("player_id", player_id)
    |> redirect(to: "/play/#{game_id}")
  end
end
