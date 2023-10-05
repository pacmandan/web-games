defmodule GamePlatform.GameState do
  @moduledoc """
  Behavior that a module defining game logic should implement.
  """

  @type game_state :: term()

  @type notifications :: list(term())

  @type player_id :: String.t()

  @type pubsub_topic :: term()
  @type player_opts :: term()
  @type player_join_spec :: {list(pubsub_topic()), term()}

  @doc """
  Initializes the game state based on provided config.

  Called by the game server during initialization. (In a :continue)
  """
  @callback init(game_config :: term()) :: game_state()

  @doc """
  Tells the state that the provided player is attempting to join the game.

  If the player joins successfully, return instructions for how that player should connect.

  `topics` is a list of PubSub topics the caller should subscribe to in order to join as this player.
  `opts` is a list of player options associated with the given player ID. On first join, these will be
  defaults that the state provides. On subsequent joins, they should be things specific to the player's view,
  such as name, text scaling, display colors, etc. (Nothing related to actual _game_ state.)

  If trying to add a player that already exists, return successfully as if they were just added.
  """
  @callback join_game(game_state(), player_id()) ::
    {:ok, player_join_spec(), notifications(), game_state()}

  @doc """
  Removes a player from the state. Typically called by the server whenever a player has disconnected and timed out.
  """
  @callback leave_game(game_state(), player_id()) ::
    {:ok, notifications(), game_state()}

  @doc """
  Tells the state that a particular player is connected and ready to recieve events.

  This should return a notification to that player to allow them to initialize their state.
  """
  @callback player_connected(game_state(), player_id()) ::
    {:ok, notifications(), game_state()}

  @doc """
  Called whenever a player socket process stops, crashes, or is otherwise refreshed.

  On the server, this will start a timer. If the player does not reconnect within a certain time frame,
  then `leave_game` will be called.
  """
  @callback player_disconnected(game_state(), player_id()) ::
    {:ok, notifications(), game_state()}

  @doc """
  The primary workhorse of the game state logic. Players will send events to the server,
  and this modifies the game state and sends notifications to connected players about those changes.
  """
  @callback handle_event(game_state(), from :: player_id() | :game, event :: term()) ::
  {:ok, notifications(), game_state()}

  defmacro __using__(_opts) do
    quote do
      @behaviour GamePlatform.GameState

      def join_game(state, _), do: {:ok, [], state}
      def leave_game(state, _), do: {:ok, [], state}
      def player_connected(_, state), do: {:ok, [], state}
      def player_disconnected(state, _), do: {:ok, [], state}
      def handle_event(_, _, state), do: {:ok, [], state}
      defoverridable GamePlatform.GameState
    end
  end
end
