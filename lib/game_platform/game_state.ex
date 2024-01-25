defmodule GamePlatform.GameState do
  @moduledoc """
  Behavior that a module defining game logic should implement.
  """

  @type game_state :: term()

  @type notifications :: list(term())
  @type msgs :: list(GamePlatform.PubSubMessage.t())

  @type player_id :: String.t()

  @type pubsub_topic :: term()
  @type player_opts :: term()

  @doc """
  Initializes the game state based on provided config.

  Called by the game server during initialization. (In a :continue)
  """
  @callback init(game_config :: term(), init_player :: player_id()) :: {:ok, game_state()} | {:error, term()}

  @doc """
  Tells the state that the provided player is attempting to join the game.

  If the player joins successfully, return instructions for how that player should connect.

  `topics` is a list of PubSub topics the caller should subscribe to in order to join as this player.

  If trying to add a player that already exists, return successfully as if they were just added.
  """
  @callback join_game(game_state(), player_id()) ::
    {:ok, list(pubsub_topic()), msgs(), game_state()} | {:error, term()}

  @doc """
  Removes a player from the state. Typically called by the server whenever a player has disconnected and timed out.
  """
  @callback leave_game(game_state(), player_id(), reason :: atom()) ::
    {:ok, msgs(), game_state()} | {:error, term()}

  @doc """
  Tells the state that a particular player is connected and ready to recieve events.

  This should return a notification to that player to allow them to initialize their state.
  """
  @callback player_connected(game_state(), player_id()) ::
    {:ok, msgs(), game_state()} | {:error, term()}

  @doc """
  Called whenever a player socket process stops, crashes, or is otherwise refreshed.

  On the server, this will start a timer. If the player does not reconnect within a certain time frame,
  then `leave_game` will be called.
  """
  @callback player_disconnected(game_state(), player_id()) ::
    {:ok, msgs(), game_state()} | {:error, term()}

  @doc """
  The primary workhorse of the game state logic. Players will send events to the server,
  and this modifies the game state and sends msgs to connected players about those changes.
  """
  @callback handle_event(game_state(), from :: player_id() | :game, event :: term()) ::
  {:ok, msgs(), game_state()} | {:error, term()}

  @doc """
  The game server is about to shut down. Handle any last minute tasks before this happens.
  """
  @callback handle_game_shutdown(game_state()) :: {:ok, msgs(), game_state()}

  defmodule GameInfo do
    @moduledoc """
    Struct containing information about the game, used for things like
    passing this module into the game view.
    """

    @enforce_keys [:server_module, :view_module, :display_name]
    defstruct [
      :server_module,
      :view_module,
      :display_name,
    ]

    @type t :: %__MODULE__{
      server_module: module(),
      view_module: module(),
      display_name: String.t(),
    }
  end

  defmacro __using__(opts) do
    %{view_module: view_module, display_name: display_name} = Enum.into(opts, %{})
    quote do
      @behaviour GamePlatform.GameState

      def join_game(state, _), do: {:ok, [], state}
      def leave_game(state, _, _), do: {:ok, [], state}
      def player_connected(state, _), do: {:ok, [], state}
      def player_disconnected(state, _), do: {:ok, [], state}
      def handle_event(state, _, _), do: {:ok, [], state}
      def handle_game_shutdown(state), do: {:ok, [], state}
      def game_info() do
        info = %GamePlatform.GameState.GameInfo{
          server_module: __MODULE__,
          view_module: unquote(view_module),
          display_name: unquote(display_name)
        }

        {:ok, info}
      end

      defoverridable GamePlatform.GameState
    end
  end
end
