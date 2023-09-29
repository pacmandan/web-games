defmodule WebGamesWeb.PlayController do
  use WebGamesWeb, :controller

  import Phoenix.LiveView.Controller

  def connect_to_game(conn, %{"game_id" => game_id}) do
    # TODO: Check if game exists
    if GamePlatform.Game.game_exists?(game_id) do
            # TODO: Check if player on game exists

      IO.inspect("PLAY CONTROLLER")
      IO.inspect("SESSION PLAYER ID: #{get_session(conn, "player_id")}")
      IO.inspect("SESSION GAME ID: #{get_session(conn, "game_id")}")
      IO.inspect("PARAM GAME ID: #{game_id}")

      if get_session(conn, "player_id") |> is_nil() do
        IO.inspect("PUTTING SESSION!")
        player_id = GamePlatform.Player.generate_id()
        GamePlatform.Game.add_player(player_id, game_id)

        conn
        |> put_session("player_id", player_id)
        |> put_session("game_id", game_id)
      else
        # Game already exists
        conn
      end
      |> live_render(WebGamesWeb.Minesweeper.Play)
    else
      conn
      |> redirect(to: "/select-game")
    end
  end
end
