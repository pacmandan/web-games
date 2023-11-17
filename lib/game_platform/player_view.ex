defmodule GamePlatform.PlayerView do
  # TODO: Figure out a way to do this without WebGamesWeb?
  use WebGamesWeb, :live_view

  alias GamePlatform.Game

  def mount(_params, session, socket) do
    if connected?(socket) do
      connected_mount(socket, session)
    else
      {:ok, assign(socket, connection_state: :loading)}
    end
  end

  defp connected_mount(socket, %{"game_id" => game_id, "player_id" => player_id, "topics" => topics}) do
    if Game.game_exists?(game_id) do
      subscribe_to_pubsub(topics)

      socket
      |> store_ids_in_assigns(game_id, player_id, topics)
      |> fetch_game_type()
      |> connect_player()
      |> schedule_reconnect_attempt()
      |> monitor_game()
      |> init_view_module()
      # init/1 will return the LiveView mount return type ({:ok, socket, opts})
    else
      socket = socket
      |> put_flash(:error, "Game with id #{game_id} does not exist")
      |> redirect(to: "/select-game")
      {:ok, socket}
    end
  end

  defp connected_mount(socket, _session) do
    socket = socket
    |> put_flash(:error, "Invalid session state, cannot connect to game")
    |> redirect(to: "/select-game")

    {:ok, socket}
  end

  defp init_view_module(socket) do
    socket.assigns.game_view_module.init(socket)
  end

  defp fetch_game_type(socket) do
    if socket.assigns[:game_view_module] |> is_nil() do
      {:ok, _state_module, game_view_module} = Game.get_game_type(socket.assigns.game_id)

      assign(socket, :game_view_module, game_view_module)
    else
      socket
    end
  end

  def handle_info({:try_reconnect, attempts}, socket) when attempts >= 30 do
    socket = socket
    |> put_flash(:error, "Could not reconnect to server")
    |> redirect(to: "/select-game")

    {:noreply, socket}
  end

  def handle_info({:try_reconnect, attempts}, socket) do
    socket = if Game.is_game_alive?(socket.assigns.game_id) do
      socket
      |> monitor_game()
      |> connect_player()
      |> schedule_reconnect_attempt(attempts)
    else
      socket
      |> put_flash(:error, "Game server has crashed")
      |> assign(:connection_state, :server_down)
      |> schedule_reconnect_attempt(attempts)
    end
    {:noreply, socket}
  end

  def handle_info({:DOWN, ref, :process, _object, _reason}, socket) when socket.assigns.game_monitor == ref do
    socket = socket
    |> assign(:connection_state, :server_down)
    |> schedule_reconnect_attempt()
    |> socket.assigns.game_view_module.handle_game_crash()

    {:noreply, socket}
  end

  def handle_info({:DOWN, _ref, :process, _object, _reason}, socket) do
    # Unknown monitor somehow? Ignore it.
    {:noreply, socket}
  end

  def handle_info({:game_event, _game_id, msgs}, socket) when socket.assigns.connection_state == :synced do
    socket = socket.assigns.game_view_module.handle_game_event(socket, msgs)
    {:noreply, socket}
  end

  def handle_info({:game_event, _, _}, socket) do
    # Ignore all messages until we've synced.
    {:noreply, socket}
  end

  def handle_info({:sync, _game_id, msgs}, socket) do
    socket = socket
    |> handle_sync()
    |> socket.assigns.game_view_module.handle_sync(msgs)

    {:noreply, socket}
  end

  def handle_info(payload, socket) do
    # Delegate all other "handle_info"s to the implementation module.
    socket.assigns.game_view_module.handle_info(payload, socket)
  end

  def handle_event(event, unsigned_params, socket) do
    # Delegate handle_event to the implementation module
    socket.assigns.game_view_module.handle_event(event, unsigned_params, socket)
  end

  def render(%{connection_state: :loading} = assigns) do
    # This is necessary since "mount" is called twice.
    # Which means "render" is called twice - once before the WS connection,
    # and once after.
    # On the one prior to connection, we haven't initialized anything in the
    # game yet, so we need a temporary loading state.
    # I don't want to do game initialization twice, so our options are do it
    # all after connection (and display a "loading" page before connection), or
    # do it all before connection and check for some kind of flag afterward.
    # The problem with doing it afterward is that the implementations can set
    # "temporary_assigns", so we _need_ to call init() after connection anyway.

    # TODO: Make this look good, or make it customizable.
    # In order to make it customizable, I need to move game_exists?() and
    # fetch_game_type(game_id) to before connection.
    ~H"""
    <div>Loading...</div>
    """
  end

  def render(assigns) do
    # Delegate render to the implementation module
    assigns.game_view_module.render(assigns)
  end

  defp subscribe_to_pubsub(topics) do
    # TODO: Make which PubSub is used configurable
    unsubscribe_from_pubsub(topics)
    Enum.each(topics, fn topic -> Phoenix.PubSub.subscribe(WebGames.PubSub, topic) end)
  end

  defp unsubscribe_from_pubsub(topics) do
    # Does this need to be a separate function?
    Enum.each(topics, fn topic -> Phoenix.PubSub.unsubscribe(WebGames.PubSub, topic) end)
  end

  defp monitor_game(socket) when not (socket.assigns.game_id |> is_nil()) do
    unless socket.assigns[:game_monitor] |> is_nil() do
      Process.demonitor(socket.assigns[:game_monitor])
    end
    assign(socket, :game_monitor, Game.monitor(socket.assigns.game_id))
  end

  defp store_ids_in_assigns(socket, game_id, player_id, topics) do
    socket
    |> assign(:game_id, game_id)
    |> assign(:player_id, player_id)
    |> assign(:topics, topics)
  end

  defp connect_player(%{assigns: %{game_id: game_id, player_id: player_id}} = socket) do
    Game.player_connected(player_id, game_id, self())
    assign(socket, :connection_state, :waiting_for_sync)
  end

  defp handle_sync(socket) do
    socket
    |> cancel_reconnect_timer()
    |> assign(:connection_state, :synced)
  end

  defp cancel_reconnect_timer(socket) do
    # Have to guard in case the game state sends :sync twice.
    unless socket.assigns.reconnect_timer |> is_nil() do
      Process.cancel_timer(socket.assigns.reconnect_timer)
    end

    assign(socket, :reconnect_timer, nil)
  end

  defp schedule_reconnect_attempt(socket, attempt \\ 1) do
    reconnect_timer = Process.send_after(self(), {:try_reconnect, attempt + 1}, :timer.seconds(attempt * 5))
    assign(socket, :reconnect_timer, reconnect_timer)
  end
end
