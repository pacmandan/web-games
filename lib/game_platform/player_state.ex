defmodule GamePlatform.PlayerState do
  @callback init(socket :: term()) :: {:ok, socket :: term()} | {:ok, socket :: term(), opts :: keyword()}
  @callback handle_sync(socket :: term(), sync_msgs :: term()) :: socket :: term()
  @callback handle_game_event(socket :: term(), msgs :: list(term())) :: socket :: term()
  @callback handle_event(event :: binary(), params :: map(), socket :: Phoenix.LiveView.Socket.t()) ::
    {:noreply, Phoenix.LiveView.Socket.t()}
    | {:reply, map(), Phoenix.LiveView.Socket.t()}
  @callback handle_game_crash(socket :: term(), reason :: atom()) :: socket :: term()
  # @callback render(assigns :: Phoenix.LiveView.Socket.assigns()) :: Phoenix.LiveView.Rendered.t()

  defmacro __using__(_) do
    quote do
      # Including these so we can still use the "render" behavior
      # of LiveView where it looks for .heex files.
      import Phoenix.LiveView
      @before_compile Phoenix.LiveView.Renderer
      use Phoenix.Component

      @behaviour GamePlatform.PlayerState

      def handle_game_crash(socket, _), do: socket
      def handle_event(socket, _), do: {:noreply, socket}
      defoverridable GamePlatform.PlayerState
    end
  end
end
