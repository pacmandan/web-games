defmodule WebGamesWeb.Minesweeper.Play do
  alias GamePlatform.Game
  use WebGamesWeb, :live_view

  def mount(_params, %{"game_id" => game_id, "player_id" => player_id}, socket) do
    IO.inspect("LIVE VIEW -- GAME ID: #{game_id} -- PLAYER ID: #{player_id}")
    if connected?(socket) do
      Phoenix.PubSub.subscribe(WebGames.PubSub, "game:#{game_id}")
      Phoenix.PubSub.subscribe(WebGames.PubSub, "game:#{game_id}:player:#{player_id}")
      IO.inspect("SENDING PLAYER CONNECTED")
      Game.player_connected(player_id, game_id)
    end
    {:ok, assign(socket, %{game_id: game_id, player_id: player_id, events: []})}
  end

  def handle_event("inc", _unsigned_params, socket) do
    %{assigns: %{count: count}} = socket
    {:noreply, assign(socket, %{count: count + 1})}
  end

  def handle_event("dec", _unsigned_params, socket) do
    %{assigns: %{count: count}} = socket
    {:noreply, assign(socket, %{count: count - 1})}
  end

  def handle_info({:game_event, game_id, event}, socket) do
    IO.inspect("GOT AN EVENT!!!")
    IO.inspect(event)
    {:noreply, assign(socket, %{events: [event |> inspect() | socket.assigns[:events]]})}
  end
end
