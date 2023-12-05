defmodule WebGamesWeb.Minesweeper.PlayerComponent do
  use GamePlatform.PlayerComponent

  require OpenTelemetry.Tracer
  alias GamePlatform.Game

  @impl true
  def mount(socket) do
    {:ok, assign(socket, init_assigns()), temporary_assigns: [display_grid: %{}]}
  end

  defp init_assigns() do
    %{
      events: [],
      grid: nil,
      display_grid: %{},
      status: :play,
      clicks_enabled?: true,
      start_time: nil,
      end_time: nil,
    }
  end

  @impl true
  def handle_sync(socket, payload) do
    OpenTelemetry.Tracer.with_span :minesweeper_handle_sync, %{} do
      {:ok, process_payload(socket, payload)}
    end
  end

  @impl true
  def handle_game_event(socket, payload) do
    OpenTelemetry.Tracer.with_span :minesweeper_handle_game_event, %{} do
      {:ok, process_payload(socket, payload)}
    end
  end

  defp process_payload(socket, payload) do
    payload
    |> List.wrap()
    |> Enum.reduce(socket, &process_msg/2)
  end

  defp process_msg({:click, cells}, %{assigns: %{grid: grid}} = socket) do
    new_grid = Enum.into(cells, grid, fn {coord, clicked?} ->
      {coord, %{grid[coord] | clicked?: clicked?}}
    end)

    socket
    |> assign(:grid, new_grid)
    |> render_cells(Map.keys(cells))
  end

  defp process_msg({:open, cells}, %{assigns: %{grid: grid}} = socket) do
    new_grid = Enum.into(cells, grid, fn {coord, value} ->
      {coord, %{grid[coord] | value: value, opened?: true}}
    end)

    socket
    |> assign(:grid, new_grid)
    |> render_cells(Map.keys(cells))
  end

  defp process_msg({:flag, cells}, %{assigns: %{grid: grid}} = socket) do
    new_grid = Enum.into(cells, grid, fn {coord, flagged?} ->
      {coord, %{grid[coord] | flagged?: flagged?}}
    end)

    socket
    |> assign(:grid, new_grid)
    |> render_cells(Map.keys(cells))
  end

  defp process_msg({:game_over, %{status: :lose, end_time: time}}, socket) do
    socket
    # |> push_event("end_game", %{end_time: time})
    |> assign(:status, :lose)
    |> assign(:end_time, time)
    |> assign(:clicks_enabled?, false)
    |> update_timer()
    |> render_full_grid()
  end

  defp process_msg({:game_over, %{status: :win, end_time: time}}, socket) do
    socket
    # |> push_event("end_game", %{end_time: time})
    |> assign(:status, :win)
    |> assign(:end_time, time)
    |> assign(:clicks_enabled?, false)
    |> update_timer()
    |> render_full_grid()
  end

  defp process_msg({:sync, %{grid: grid, height: h, width: w, num_mines: n, status: status, start_time: start_time, end_time: end_time}}, socket) do
    socket
    |> assign(%{grid: grid, height: h, width: w, num_mines: n, status: status, start_time: start_time, end_time: end_time})
    |> update_timer()
    |> render_full_grid()
  end

  defp process_msg({:show_mines, coord_list}, %{assigns: %{grid: grid}} = socket) do
    new_grid = Enum.into(coord_list, grid, fn coord ->
      {coord, %{grid[coord] | has_mine?: true}}
    end)

    socket
    |> assign(:grid, new_grid)
    |> render_cells(coord_list)
  end

  defp update_timer(%{assigns: %{end_time: nil}} = socket) do
    socket
  end

  defp update_timer(%{assigns: %{end_time: time}} = socket) do
    socket
    |> push_event("end_game", %{end_time: time})
  end

  @impl true
  def handle_event("click", %{"x" => x, "y" => y}, socket) do
    x = String.to_integer(x)
    y = String.to_integer(y)
    Game.send_event({:open, {x, y}}, socket.assigns[:player_id], socket.assigns[:game_id])
    {:noreply, socket}
  end

  @impl true
  def handle_event("flag", %{"x" => x, "y" => y}, socket) do
    x = String.to_integer(x)
    y = String.to_integer(y)
    Game.send_event({:flag, {x, y}}, socket.assigns[:player_id], socket.assigns[:game_id])
    {:noreply, socket}
  end

  defp render_cells(socket, coords) do
    new_display = Enum.map(coords, fn coord ->
      {coord, render_cell(socket.assigns.grid[coord], socket.assigns)}
    end)
    |> Enum.into(%{})
    |> then(fn new_display -> Map.merge(socket.assigns.display_grid, new_display) end)

    assign(socket, :display_grid, new_display)
  end

  defp render_full_grid(socket) do
    render_cells(socket, Map.keys(socket.assigns.grid))
  end

  defp render_cell(cell, assigns) do
    %{
      background_color: background_color(cell),
      text_color: text_color(cell),
      value: display_value(cell, assigns.status),
      clickable?: assigns.clicks_enabled? && not (cell.opened?),
      border_color: "border-black",
    }
  end

  defp background_color(%{has_mine?: true, flagged?: true}), do: "bg-green-400"
  defp background_color(%{opened?: true, has_mine?: true}), do: "bg-red-400"
  defp background_color(%{opened?: true}), do: "bg-gray-300"
  defp background_color(_), do: "bg-gray-500"

  defp text_color(%{has_mine?: true}), do: "text-black"
  defp text_color(%{value: value}) when value in [0, "0"], do: "text-black"
  defp text_color(%{value: value}) when value in [1, "1"], do: "text-blue-500"
  defp text_color(%{value: value}) when value in [2, "2"], do: "text-green-500"
  defp text_color(%{value: value}) when value in [3, "3"], do: "text-red-500"
  defp text_color(%{value: value}) when value in [4, "4"], do: "text-blue-800"
  defp text_color(%{value: value}) when value in [5, "5"], do: "text-amber-800"
  defp text_color(%{value: value}) when value in [6, "6"], do: "text-sky-500"
  defp text_color(%{value: value}) when value in [7, "7"], do: "text-black"
  defp text_color(%{value: value}) when value in [8, "8"], do: "text-gray-700"
  defp text_color(_), do: "text-black"

  defp display_value(%{has_mine?: true}, :win), do: "F" # "+"
  defp display_value(%{has_mine?: true, flagged?: true}, _), do: "F" # "O"
  defp display_value(%{has_mine?: true}, _), do: "X"
  defp display_value(%{flagged?: true}, _), do: "F"
  defp display_value(%{value: 0}, _), do: nil
  defp display_value(%{value: "0"}, _), do: nil
  defp display_value(%{value: v}, _), do: v
  defp display_value(_, _), do: nil
end
