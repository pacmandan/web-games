defmodule GamePlatform.Plugs.GameExistsPlug do
  import Plug.Conn
  alias GamePlatform.Game

  def init(opts), do: opts

  def call(conn, _opts) do
    if Game.game_exists?(conn.path_params["game_id"]) do
      conn
    else
      conn
      |> put_resp_header("location", "/select-game")
      |> resp(Plug.Conn.Status.code(:found), "The game you are trying to connect to does not exist.")
    end
  end
end
