defmodule GamePlatform.PlayerComponent do
  @callback handle_game_event(
    socket :: Phoenix.LiveView.Socket.t(),
    payload :: term()
  ) :: {:ok, Phoenix.LiveView.Socket.t()}

  @callback handle_sync(
    socket :: Phoenix.LiveView.Socket.t(),
    payload :: term()
  ) :: {:ok, Phoenix.LiveView.Socket.t()}

  defmacro __using__(_) do
    quote do
      use Phoenix.LiveComponent
      @behaviour GamePlatform.PlayerComponent

      def update(%{type: :game_event, payload: payload}, socket) do
        handle_game_event(socket, payload)
      end

      def update(%{type: :sync, payload: payload}, socket) do
        handle_sync(socket, payload)
      end

      def update(assigns, socket) do
        {:ok, assign(socket, assigns)}
      end

      defoverridable Phoenix.LiveComponent
    end
  end
end
