defmodule WebGamesWeb.SelectGameController do
  use WebGamesWeb, :controller

  def select_game(conn, _params) do
    conn
    |> render(:select_game, layout: false)
  end
end
