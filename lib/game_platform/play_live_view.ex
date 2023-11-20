defmodule GamePlatform.PlayLiveView do
  # TODO: Figure out a way to do this without WebGamesWeb?
  use WebGamesWeb, :live_view

  alias GamePlatform.Game

  def mount(%{"game_id" => game_id} = _params, %{"player_id" => player_id} = _session, socket) do
    socket = socket
    |> assign(:game_id, game_id)
    |> assign(:player_id, player_id)

    if connected?(socket) do
      # Socket is connected, try connecting to the game.

      socket = socket
      |> join_game()
      |> fetch_game_type()
      |> monitor_game()
      |> connect_player()
      # |> schedule_reconnect_attempt()
      |> assign(:connection_state, :syncing)

      # Render "loading..."

      {:ok, socket}
    else
      # We aren't connected yet, render the "connecting..." screen.
      {:ok, assign(socket, :connection_state, :loading)}
    end

    {:ok, socket}
  end

  # def handle_info({:try_reconnect, attempts}, socket) when attempts >= 30 do
  #   socket = socket
  #   |> put_flash(:error, "Could not reconnect to server")
  #   |> redirect(to: "/select-game")

  #   {:noreply, socket}
  # end

  # def handle_info({:try_reconnect, attempts}, socket) do
  #   socket = if Game.is_game_alive?(socket.assigns.game_id) do
  #     socket
  #     |> monitor_game()
  #     |> connect_player()
  #   else
  #     socket
  #     |> put_flash(:error, "Game server has crashed")
  #     |> assign(:connection_state, :server_down)
  #   end
  #   |> schedule_reconnect_attempt(attempts + 1)
  #   {:noreply, socket}
  # end

  def handle_info({:sync, _game_id, data}, socket) do
    send_update(socket.assigns.play_component_module, [id: "game_view"] ++ to_keyword_list(data))

    socket = socket
    # |> cancel_reconnect_timer()
    |> assign(:connection_state, :synced)

    {:noreply, socket}
  end

  defp to_keyword_list(map) do
    map |> Enum.into([], &{elem(&1, 0), elem(&1, 1)})
  end

  def render(assigns) do
    ~H"""
    <.live_component module={@game_component_module} id={@game_id} player_id={@player_id} state={%{}}/>
    """
  end

  defp connect_player(%{assigns: %{game_id: game_id, player_id: player_id}} = socket) do
    Game.player_connected(player_id, game_id, self())
    assign(socket, :connection_state, :waiting_for_sync)
  end

  defp fetch_game_type(socket) do
    # Don't try and call the game if we already know.
    if socket.assigns[:game_view_module] |> is_nil() do
      {:ok, _state_module, game_view_module} = Game.get_game_type(socket.assigns.game_id)

      assign(socket, :game_view_module, game_view_module)
    else
      socket
    end
  end

  defp join_game(%{assigns: %{player_id: player_id, game_id: game_id}} = socket) do
    {:ok, topics} = Game.join_game(player_id, game_id)

    Enum.each(topics, fn topic ->
      # Ensure we don't double-subscribe to topics.
      Phoenix.PubSub.unsubscribe(WebGames.PubSub, topic)
      Phoenix.PubSub.subscribe(WebGames.PubSub, topic)
    end)

    assign(socket, :topics, topics)
  end

  defp monitor_game(socket) when not (socket.assigns.game_id |> is_nil()) do
    unless socket.assigns[:game_monitor] |> is_nil() do
      Process.demonitor(socket.assigns[:game_monitor])
    end

    assign(socket, :game_monitor, Game.monitor(socket.assigns.game_id))
  end

  # defp cancel_reconnect_timer(socket) do
  #   # Have to guard in case the game state sends :sync twice.
  #   unless socket.assigns.reconnect_timer |> is_nil() do
  #     Process.cancel_timer(socket.assigns.reconnect_timer)
  #   end

  #   assign(socket, :reconnect_timer, nil)
  # end

  # defp schedule_reconnect_attempt(socket, attempt \\ 1) do
  #   reconnect_timer = Process.send_after(self(), {:try_reconnect, attempt + 1}, :timer.seconds(attempt * 5))
  #   assign(socket, :reconnect_timer, reconnect_timer)
  # end
end
