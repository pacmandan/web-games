defmodule WebGamesWeb.PageController do
  use WebGamesWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def about(conn, _params) do
    render(conn, :about)
  end

  def games_list(conn, _params) do
    render(conn, :games_list)
  end

  def join_game(conn, _params) do
    render(conn, :join_game)
  end

  def minesweeper_form(conn, _params) do
    render(conn, :minesweeper_form)
  end
end
