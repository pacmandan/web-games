defmodule GamePlatform.Plugs.PlayerIdPlug do
  import Plug.Conn

  alias GamePlatform.Player

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_session(conn)

    if get_session(conn, "player_id") |> is_nil() do
      put_session(conn, "player_id", Player.generate_id())
    else
      conn
    end
  end
end
