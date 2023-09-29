defmodule GamePlatform.GameState do
  @callback handle_event(event :: term(), state :: term()) ::
    {:ok, notifications :: list(term()), state :: term()}

  @callback player_connected(state :: term(), player_id :: String.t()) ::
    {:ok, notifications :: list(term()), state :: term()}

  @callback add_player(state :: term(), player_id :: String.t()) ::
    {:ok, notifications :: list(term()), state :: term()}

  @callback init(term()) :: term()

  defmacro __using__(_opts) do
    quote do
      @behaviour GamePlatform.GameState

      def add_player(state, _), do: {:ok, [], state}
      def player_connected(_, state), do: {:ok, [], state}
      def handle_event(_, state), do: {:ok, [], state}
      defoverridable GamePlatform.GameState
    end
  end
end
