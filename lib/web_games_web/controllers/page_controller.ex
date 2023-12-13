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

  # def join_game(conn, _params) do
  #   render(conn, :join_game)
  # end

  def minesweeper_form(conn, _params) do
    render(conn, :minesweeper_form)
  end

  def join_game(conn, %{"game_id" => ""}) do
    conn
    |> put_flash(:error, "No Game ID")
    |> redirect(to: "/")
  end

  def join_game(conn, %{"game_id" => game_id}) do
    if String.match?(game_id, ~r"^[a-zA-Z]+$") do
      # The path itself looks to see if this game exists.
      # If it doesn't, it'll redirect the same way an invalid ID does.
      conn
      |> redirect(to: "/play/#{String.upcase(game_id)}")
    else
      conn
      |> put_flash(:error, "Invalid Game ID")
      |> redirect(to: "/")
    end


  end
end
