defmodule GamePlatform.View do
  @moduledoc """
  UNFINISHED DOCS
  This should be the "generic LiveView" that game views should build on top of.

  - game_id, player_id, and topics should already be in session
  - If the game does not exist, redirect away.
  - If the socket is not connected, do nothing.
  - Once the socket is connected
    - Monitor the game server
    - Subscribe to each topic in session
    - Initialize assigns
    - Set the assigns to wait for :sync
    - Start a timeout to wait for sync
    - Tell the game that the player is connected
      - TODO: Maybe instead of waiting for a proper "game_event", we could do a direct "recieve()"?
    - Initialize game-specific assigns (PASS TO IMPLEMENTATION)
      - Ensure we can set temporary assigns from the implementation
  - When an event comes in,
    - Look for a :sync message (Need to standardize this in the GameServer/Notifications somehow)
      - Process that message first, and remove it from the list.
      - Remove sync timeout
      - Use the normal event processing? A dedicated sync() function?
      - Mark the state as :synced
    - If the state is not :synced, ignore the rest of the messages.
    - Pre-process messages (PASS TO IMPLEMENTATION)
    - Process each message (PASS TO IMPLEMENTATION)
    - Post-process assigns (PASS TO IMPLEMENTATION)
  - On sync timeout
    - If we've tried too many times, fail completely
    - Tell the game that a player is connected
    - Start a longer timeout to wait for :sync
  - On game server crash
    - Set assigns to show crash (PASS TO IMPLEMENTATION?)
    - ...what should we do here? Redirect out? Wait for messages on existing topics?
      Ping the server until we get a response, then join_game(), unsubscribe/subscribe topics, connected()?
      (Exponential back-off on pinging the server?)
  """

  @callback init_game_state(socket :: term()) :: {:ok, socket :: term()}
  @callback synchronize_state(socket :: term(), sync_msgs :: term()) :: socket :: term()
  @callback process_message(msg :: term(), socket :: term()) :: socket :: term()
  @callback pre_process_messages(msgs :: list(term()), socket :: term()) :: {msgs :: list(term()), socket :: term()}
  @callback post_game_event(socket :: term()) :: socket :: term()
  @callback handle_game_crash(socket :: term(), reason :: atom()) :: socket :: term()

  import Phoenix.Component
  import Phoenix.LiveView

  alias GamePlatform.Game

  defmacro __using__(_) do
    quote do
      # TODO: Make this configurable?
      use WebGamesWeb, :live_view

      import GamePlatform.View, only: [send_event: 2]

      # @view_module opts[:module]

      @behaviour GamePlatform.View

      # FIXME: This is too much inside of a __using__ macro.
      # Find some way to reduce this but maintain the behavior.
      # Maybe we don't use __using__ at all.

      def mount(_params, %{"game_id" => game_id, "player_id" => player_id, "topics" => topics}, socket) do
        if GamePlatform.Game.game_exists?(game_id) do
          if connected?(socket) do
            GamePlatform.View.subscribe_to_pubsub(topics)

            socket
            |> GamePlatform.View.store_ids_in_assigns(game_id, player_id, topics)
            |> GamePlatform.View.connect_player()
            |> GamePlatform.View.schedule_reconnect_attempt()
            |> GamePlatform.View.monitor_game()
            |> init_game_state()
          else
            {:ok, socket}
          end
        else
          socket = socket
          |> put_flash(:error, "Game with id #{game_id} does not exist")
          |> redirect(socket, to: "/select-game")
          {:ok, socket}
        end
      end

      def mount(_params, _session, socket) do
        # Invalid session state, somehow. We don't need to continue, just redirect out.
        socket = socket
        |> put_flash(:error, "Invalid sessions state, cannot connect to game")
        |> redirect(to: "/select-game")

        {:ok, socket}
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
          |> GamePlatform.View.monitor_game(socket)
          |> GamePlatform.View.connect_player()
          |> GamePlatform.View.schedule_reconnect_attempt(attempts)
        else
          socket
          |> put_flash(:error, "Game server has crashed")
          |> assign(socket, :connection_state, :server_down)
          |> GamePlatform.View.schedule_reconnect_attempt(attempts)
        end
        {:noreply, socket}
      end

      def handle_info({:DOWN, ref, :process, _object, _reason}, socket) when socket.assigns.game_monitor == ref do
        socket = socket
        |> assign(socket, :connection_state, :server_down)
        |> GamePlatform.View.schedule_reconnect_attempt(attempts)

        {:noreply, socket}
      end

      def handle_info({:DOWN, _ref, :process, _object, _reason}, socket) do
        # Unknown monitor somehow? Ignore it.
        {:noreply, socket}
      end

      def handle_info({:game_event, _game_id, msgs}, socket) when socket.assigns.connection_state == :synced do
        with {msgs, socket} <- pre_process_messages(msg, socket),
          socket <- Enum.reduce(msgs, socket, &process_message/2),
          socket <- post_game_event(socket)
        do
          {:noreply, socket}
        else
          _ ->
            {:noreply, socket}
        end
      end

      def handle_info({:game_event, _, _}, socket) do
        # Ignore all messages until we've synced.
        {:noreply, socket}
      end

      def handle_info({:sync, _game_id, msgs}, socket) do
        socket = socket
        |> GamePlatform.View.handle_sync()
        |> synchronize_state(socket, msgs)

        {:noreply, socket}
      end

      def pre_process_messages(msgs, socket), do: {msgs, socket}
      def post_game_event(socket), do: socket

      defoverridable GamePlatform.View
      defoverridable Phoenix.LiveView
    end
  end

  def send_event(event, socket) do
    Game.send_event(event, socket.assigns.player_id, socket.assigns.game_id)
    socket
  end

  def subscribe_to_pubsub(topics) do
    # TODO: Make which PubSub is used configurable
    unsubscribe_from_pubsub(topics)
    Enum.each(topics, fn topic -> Phoenix.PubSub.subscribe(WebGames.PubSub, topic) end)
  end

  def unsubscribe_from_pubsub(topics) do
    # Does this need to be a separate function?
    Enum.each(topics, fn topic -> Phoenix.PubSub.unsubscribe(WebGames.PubSub, topic) end)
  end

  def monitor_game(socket) when not (socket.assigns.game_id |> is_nil()) do
    unless socket.assigns.game_monitor |> is_nil() do
      Process.demonitor(socket.assigns.game_monitor)
    end
    assign(socket, :game_monitor, Game.monitor(socket.assigns.game_id))
  end

  def store_ids_in_assigns(socket, game_id, player_id, topics) do
    socket
    |> assign(:game_id, game_id)
    |> assign(:player_id, player_id)
    |> assign(:topics, topics)
  end

  def cancel_reconnect_timer(socket) do
    # Have to guard in case the game state sends :sync twice.
    unless socket.assigns.reconnect_timer |> is_nil() do
      Process.cancel_timer(socket.assigns.reconnect_timer)
    end

    assign(socket, :reconnect_timer, nil)
  end

  def schedule_reconnect_attempt(socket, attempt \\ 1) do
    reconnect_timer = Process.send_after(self(), {:try_reconnect, attempt + 1}, :timer.seconds(attempt * 5))
    assign(socket, :reconnect_timer, reconnect_timer)
  end

  def connect_player(%{assigns: %{game_id: game_id, player_id: player_id}} = socket) do
    Game.player_connected(player_id, game_id, self())
    assign(socket, :connection_state, :waiting_for_sync)
  end

  def handle_sync(socket) do
    socket
    |> cancel_reconnect_timer()
    |> assign(:connection_state, :synced)
  end
end
