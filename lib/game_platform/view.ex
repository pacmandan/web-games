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

  Behaviors to implement:
  mount()
  - initialize socket state
  - subscribe to topics
  - monitor game process
  - redirect on failure (make this configurable somehow?)

  try_reconnect

  handle game :DOWN

  handle game events?
  (Should "process event" be the thing to implement?)
  (Is there a generic thing we can do per-event?)

  I think I need to rename a few things.
  Instead of "notification" or "event", should it just be "message"?


  assigns:
  player_id,
  game_id,
  topics,
  player_state,

  """

  @callback init_game_state(socket :: term()) :: socket :: term()
  @callback process_message(msg :: term(), socket :: term()) :: socket :: term()
  @callback pre_process_messages(msgs :: list(term()), socket :: term()) :: {msgs :: list(term()), socket :: term()}
  @callback post_game_event(socket :: term()) :: socket :: term()
  @callback handle_game_crash(socket :: term()) :: socket :: term()


  defstruct [
    :game_id,
    :player_id,
    topics: [],
    view_state: %{},
    reconnect_timer: nil,
    game_monitor: nil,
  ]

  import Phoenix.Component
  import Phoenix.LiveView

  defmacro __using__(_) do
    quote do
      # TODO: Make this configurable?
      use WebGamesWeb, :live_view

      # @view_module opts[:module]

      @behaviour GamePlatform.View

      def mount(_params, %{"game_id" => game_id, "player_id" => player_id, "topics" => topics}, socket) do
        if Game.game_exists?(game_id) do
          if connected?(socket) do
            GamePlatform.View.subscribe_to_pubsub(topics)

            socket
            |> GamePlatform.View.try_connect()
            |> GamePlatform.View.store_ids_in_assigns(game_id, player_id, topics)
            |> GamePlatform.View.monitor_game()
            |> init_game_state()
          else
            {:ok, socket}
          end
        else
          {:ok, redirect(socket, to: "/select-game")}
        end
      end

      def mount(_params, _session, socket) do
        {:ok, redirect(socket, to: "/select-game")}
      end

      def handle_info({:try_reconnect, attempts}, socket) do
        # Check if the game is up.
        # If it's not, ":try_reconnect" again after an exponential backoff.
        # (After X number of tries, give up and redirect out.)
        # If the game is found, call join_game(), re-subscribe to topics (unsubscribe + subscribe), and call player_connected()
        {:noreply, socket}
      end

      def handle_info({:DOWN, ref, :process, _object, _reason}, socket) do
        # Display "Game has crashed" message.
        # Set internals to pre :sync state
        # Send self a ":try_reconnect" message after a bit.
        {:noreply, socket}
      end

      def handle_info({:game_event, _game_id, msgs}, socket) do
        # TODO: Handle "sync" message.
        # This might need to be a separate handle_info, and be sent as a separate Notification entirely.
        # Which means a major refactor of Notification...
        with {msgs, socket} <- pre_process_messages(msg, socket),
          socket <- Enum.reduce(msgs, socket, &process_message/2),
          socket <- post_game_event(msgs, socket)
        do
          {:noreply, socket}
        else
          _ ->
            {:noreply, socket}
        end
      end

      def pre_process_messages(msgs, socket), do: {msgs, socket}
      def post_game_event(socket), do: socket

      defoverridable GamePlatform.View
      defoverridable Phoenix.LiveView
    end
  end

  alias GamePlatform.Game

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
    Enum.each(topics, fn topic -> Phoenix.PubSub.unsubscribe(WebGames.PubSub, topic) end)
  end

  def monitor_game(socket) when not (socket.assigns.game_id |> is_nil()) do
    assign(socket, :game_monitor, Game.monitor(socket.assigns.game_id))
  end

  def store_ids_in_assigns(socket, game_id, player_id, topics) do
    socket
    |> assign(:game_id, game_id)
    |> assign(:player_id, player_id)
    |> assign(:topics, topics)
  end

  def cancel_reconnect_timer(socket) do
    Process.cancel_timer(socket.assigns.reconnect_timer)
    assign(socket, :reconnect_timer, nil)
  end

  def try_connect(socket, attempt \\ 1)
  def try_connect(socket, attempt) when attempt >= 5 do
    # We've run out of attempts to reconnect to the game.
    socket
  end

  def try_connect(socket, attempt) do
    connect_player(socket)
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

  def pop_sync_msg(msgs) do
    sync_msg = Enum.find(msgs, fn
      {:sync, _} -> true
      _ -> false
    end)

    {sync_msg, List.delete(msgs, sync_msg)}
  end
end
