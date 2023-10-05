defmodule WebGamesWeb.PlayController do
  use WebGamesWeb, :controller

  alias GamePlatform.Game
  alias GamePlatform.Player

  import Phoenix.LiveView.Controller

  def connect_to_game(conn, %{"game_id" => game_id}) do
    if Game.game_exists?(game_id) do
      {player_id, conn} = get_player_id(conn)
      {:ok, topics, opts} = Game.join_game(player_id, game_id)

      conn
      |> put_session("game_id", game_id)
      |> put_session("player_opts", opts)
      |> put_session("topics", topics)
      # TODO: Make which game to render generic somehow
      |> live_render(WebGamesWeb.Minesweeper.Play)
    else
      conn
      |> clear_session()
      |> redirect(to: "/select-game")
    end
  end

  def get_player_id(conn) do
    player_id = get_session(conn, "player_id")
    if player_id |> is_nil() do
      player_id = Player.generate_id()
      {player_id, conn |> put_session("player_id", player_id)}
    else
      {player_id, conn}
    end
  end
end
