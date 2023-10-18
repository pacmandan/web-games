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
  player_opts,
  player_state,

  """

  @callback init_game_state(socket :: term()) :: socket :: term()
  @callback process_message(msg :: term(), socket :: term()) :: socket :: term()
  @callback pre_process_messages(msgs :: list(term()), socket :: term()) :: {msgs :: list(term()), socket :: term()}
  @callback post_game_event(socket :: term()) :: socket :: term()


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
      import GamePlatform.View, only: [send_event: 2]

      # TODO: put behavior here that implies implementation functions

      def mount(params, session, socket) do
        GamePlatform.View.mount(params, session, socket)
      end

      def handle_info({:try_reconnect, attempts_left}, socket) do
        # Check if the game is up.
        # If it's not, ":try_reconnect" again after an exponential backoff.
        # (After X number of tries, give up and redirect out.)
        # If the game is found, call join_game(), re-subscribe to topics (unsubscribe + subscribe), and call player_connected()
        {:noreply, socket}
      end

      def handle_info({:DOWN, _ref, :process, _object, _reason}, socket) do
        # Display "Game has crashed" message.
        # Set internals to pre :sync state
        # Send self a ":try_reconnect" message after a bit.
        {:noreply, socket}
      end

      def handle_info({:game_event, _game_id, _msgs}, socket) do
        # new_assigns = Enum.reduce(msgs, Map.take(socket.assigns, @assigns_keys), fn msg, acc ->
          # IO.inspect("MSG: #{inspect(msg)}")
          # process_event(msg, acc)
        # end)

        # socket = socket
        # |> assign(new_assigns)
        # |> draw_grid()

        {:noreply, socket}
      end
    end
  end

  alias GamePlatform.Game

  def mount(_params, %{"game_id" => game_id, "player_id" => player_id, "topics" => topics}, socket) do
    if Game.game_exists?(game_id) do
      {:ok, handle_connection(game_id, player_id, topics, socket)}
    else
      {:ok, redirect(socket, to: "/select-game")}
    end
  end

  def mount(_params, _session, socket) do
    {:ok, redirect(socket, to: "/select-game")}
  end

  def send_event(event, socket) do
    Game.send_event(event, socket.assigns.player_id, socket.assigns.game_id)
    socket
  end

  defp handle_connection(game_id, player_id, topics, socket) do
    if connected?(socket) do
      # TODO: Make which PubSub is used configurable
      Enum.each(topics, fn topic -> Phoenix.PubSub.subscribe(WebGames.PubSub, topic) end)
      Game.player_connected(player_id, game_id, self())

      assign(socket, :game_monitor, Game.monitor(game_id))
    else
      socket
    end
  end

  def cancel_reconnect_timer(socket) do
    Process.cancel_timer(socket.assigns.reconnect_timer)
    assign(socket, :reconnect_timer, nil)
  end

  def try_reconnect(socket, attempt \\ 5)
  def try_reconnect(socket, attempt) when attempt >= 5 do
    # We've run out of attempts to reconnect to the game.
    socket
  end

  def try_reconnect(socket, attempt) do
    connect_player(socket)
    reconnect_timer = Process.send_after(self(), {:try_reconnect, attempt + 1}, :timer.seconds(attempt * 5))
    assign(socket, :reconnect_timer, reconnect_timer)
  end

  def connect_player(%{assigns: %{game_id: game_id, player_id: player_id}}) do
    Game.player_connected(player_id, game_id, self())
  end

  def handle_server_crash(socket) do

  end

  def handle_game_event(event, socket) do
    # new_assigns = Enum.reduce(msgs, Map.take(socket.assigns, @assigns_keys), fn msg, acc ->
    #   process_event(msg, acc)
    # end)

    # {:noreply, assign(socket, new_assigns)}
  end
end
