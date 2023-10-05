defmodule GamePlatform.GameState do
  @doc """
  Initializes the game state based on provided config.

  Called by the game server during initialization. (In a :continue)
  """
  @callback init(game_config :: term()) :: state :: term()

  @doc """
  Tells the state that the provided player is attempting to join the game.

  If the player joins successfully, return instructions for how that player should connect.

  `topics` is a list of PubSub topics the caller should subscribe to in order to join as this player.
  `opts` is a list of player options associated with the given player ID. On first join, these will be
  defaults that the state provides. On subsequent joins, they should be things specific to the player's view,
  such as name, text scaling, display colors, etc. (Nothing related to actual _game_ state.)

  If trying to add a player that already exists, return successfully as if they were just added.
  """
  @callback join_game(state :: term(), player_id :: String.t()) ::
    {:ok, {topics :: list(term()), opts :: term()}, notifications :: list(term()), state :: term()}

  @doc """
  Removes a player from the state. Typically called by the server whenever a player has disconnected and timed out.
  """
  @callback remove_player(state :: term(), player_id :: String.t()) ::
    {:ok, notifications :: list(term()), state :: term()}

  @doc """
  Tells the state that a particular player is connected and ready to recieve events.

  This should return a notification to that player to allow them to initialize their state.
  """
  @callback player_connected(state :: term(), player_id :: String.t(), pid :: term()) ::
  {:ok, notifications :: list(term()), state :: term()}

  @doc """
  Called whenever a player socket process stops, crashes, or is otherwise refreshed.

  On the server, this will start a timer. If the player does not reconnect within a certain time frame,
  then `remove_player` will be called.
  """
  @callback player_disconnected(state :: term(), player_id :: String.t()) ::
  {:ok, notifications :: list(term()), state :: term()}

  @doc """
  The primary workhorse of the game state logic. Players will send events to the server,
  and this modifies the game state and sends notifications to connected players about those changes.
  """
  @callback handle_event(state :: term(), from :: String.t(), event :: term()) ::
    {:ok, notifications :: list(term()), state :: term()}

  defmacro __using__(_opts) do
    quote do
      @behaviour GamePlatform.GameState

      def join_game(state, _), do: {:ok, [], state}
      def remove_player(state, _), do: {:ok, [], state}
      def player_connected(_, state), do: {:ok, [], state}
      def player_disconnected(state, _), do: {:ok, [], state}
      def handle_event(_, state), do: {:ok, [], state}
      defoverridable GamePlatform.GameState
    end
  end
end
