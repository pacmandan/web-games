defmodule GamePlatform.GameState do
  alias GamePlatform.Notification
  @callback handle_event(event :: term(), state :: term()) ::
    {:ok, notifications :: list(term()), state :: term()}

  @callback player_connected(player_id :: String.t(), state :: term()) ::
    {:ok, notifications :: list(term()), state :: term()}

  @callback init(term()) :: term()

  @state_fields [
    players: [],
    notifications: [],
  ]

  defmacro __using__(fields) do
    fields = @state_fields ++ fields
    quote do
      @behaviour GamePlatform.GameState

      # TODO: Maybe figure out a different way to do this struct thing?
      defstruct unquote(Macro.escape(fields))

      import GamePlatform.GameState
    end
  end

  # TODO: Fix consistency in argument ordering. Sometimes "game" is the last arg, sometimes it's the first.

  def take_notifications(game) do
    {Enum.reverse(game.notifications), struct(game, notifications: [])}
  end

  def add_notification(game, to, event) do
    struct(game, notifications: [Notification.build(to, event) | game.notifications])
  end

  def add_notification(game, notification) do
    struct(game, notifications: [notification | game.notifications])
  end

  def add_player(game, player) do
    struct(game, players: [player | game.players])
  end

  def player_exists?(_game, _player) do
    # TODO: Players
    false
  end

  def remove_player(game, _player_id) do
    # TODO: Players
    game
  end
end
