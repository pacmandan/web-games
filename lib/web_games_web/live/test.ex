defmodule WebGamesWeb.Test do
  use WebGamesWeb, :live_view

  def mount(_params, _session, socket) do
    socket = socket
    |> assign(:height, 100)
    |> assign(:width, 100)
    |> assign(:grid, create_blank_grid(100, 100))
    {:ok, socket}
  end

  defp all_coords(width, height) do
    for x <- 0..(width - 1), y <- 0..(height - 1), do: {x, y}
  end

  defp create_blank_grid(width, height) do
    all_coords(width, height)
    |> Stream.map(fn {x, y} = coord -> {coord, "#{x},#{y}"} end)
    |> Enum.into(%{})
  end

  def render(assigns) do
    ~H"""
    TESTING!!!
    <div style={"display:grid; grid-template-columns:repeat(#{@width},1fr); grid-template-rows:repeat(#{@height},1fr);"}>
      <%= for {{x,y}, value} <- @grid do %>
        <div id={"p#{x}_#{y}"} style={"grid-column-start:#{x};grid-row-start:#{y}"}>
          <%= value %>
        </div>
      <% end %>
    </div>
    """
  end
end
