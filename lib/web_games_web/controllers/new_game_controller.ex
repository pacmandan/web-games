defmodule WebGamesWeb.NewGameController do
  alias GamePlatform.Player
  alias WebGames.Minesweeper
  use WebGamesWeb, :controller

  # TODO: Move this controller into GamePlatform?

  def start_minesweeper(conn, %{"width" => width, "height" => height, "num_mines" => num_mines, "type" => "custom"}) do
    player_id = get_player_id(conn)

    # TODO: Handle config validation
    minesweeper_config = Minesweeper.Config.custom(width, height, num_mines)
    {:ok, game_id, _} = WebGames.start_minesweeper(player_id, minesweeper_config)

    conn
    |> put_session("game_id", game_id)
    |> put_session("player_id", player_id)
    |> redirect(to: "/play/#{game_id}")
  end

  def start_minesweeper(conn, %{"type" => type}) do
    player_id = get_player_id(conn)

    minesweeper_config = case type do
      "beginner" -> Minesweeper.Config.beginner()
      "intermediate" -> Minesweeper.Config.intermediate()
      "advanced" -> Minesweeper.Config.advanced()
      # TODO: Return 400 error instead of throwing
      _ -> throw "Invalid config type"
    end
    {:ok, game_id, _} = WebGames.start_minesweeper(player_id, minesweeper_config)

    conn
    |> put_session("game_id", game_id)
    |> put_session("player_id", player_id)
    |> redirect(to: "/play/#{game_id}")
  end

  def start_lightcycles(conn, _params) do
    player_id = get_player_id(conn)

    {:ok, game_id, _} = WebGames.start_lightcycles(player_id, %{width: 100, height: 100})

    conn
    |> put_session("game_id", game_id)
    |> put_session("player_id", player_id)
    |> redirect(to: "/play/#{game_id}")
  end

  defp get_player_id(conn) do
    case get_session(conn, "player_id") do
      # TODO: Generate ID based on something unique to the user
      # OR: Use UUIDs instead of 10 randomly generated characters
      nil -> Player.generate_id()
      id -> id
    end
  end
end
