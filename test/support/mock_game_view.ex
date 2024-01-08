defmodule GamePlatform.MockGameView do
  use GamePlatform.PlayerComponent

  def handle_game_event(socket, _payload) do
    {:ok, socket}
  end

  def handle_sync(socket, _payload) do
    {:ok, socket}
  end

  def handle_display_event(socket, _payload) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div>MOCK!</div>
    """
  end
end
