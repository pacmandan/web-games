defmodule WebGamesWeb.Test do
  use WebGamesWeb, :live_view

  def mount(_params, _session, socket) do
    socket = socket
    |> assign(:height, 10)
    |> assign(:width, 10)
    |> assign(:grid, create_blank_grid(10, 10))
    {:ok, socket}
  end

  def handle_params(_unsigned_params, _uri, socket) do
    {:noreply, socket}
  end

  defp all_coords(width, height) do
    for x <- 1..width, y <- 1..height, do: {x, y}
  end

  defp create_blank_grid(width, height) do
    all_coords(width, height)
    |> Stream.map(fn {x, y} = coord -> {coord, "#{x},#{y}"} end)
    |> Enum.into(%{})
  end

  # defp create_filled_grid() do
  #   %{
  #     {1, 1} => %{value: "F"}, {2, 1} => %{value: "1"}, {3, 1} => %{value: "0"},
  #     {1, 2} => %{value: "X"}, {2, 2} => %{value: "1"}, {3, 2} => %{value: "0"},
  #     {1, 3} => %{value: "1"}, {2, 3} => %{value: "1"}, {3, 3} => %{value: "0"}
  #   }
  # end

  def render(assigns) do
    ~H"""
    TESTING!!!
    <div style={"display:grid; grid-template-columns:repeat(#{@width},1fr); grid-template-rows:repeat(#{@height},1fr);"}>
      <img src={~p"/images/ms-flag.svg"} width="30" height="30" />
      <%= for {{x,y}, value} <- @grid do %>
        <div id={"p#{x}_#{y}"} style={"grid-column-start:#{x};grid-row-start:#{y}"}>
          <%= value %>
        </div>
      <% end %>
    </div>
    """
  end
end
