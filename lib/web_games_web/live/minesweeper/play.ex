defmodule WebGamesWeb.Minesweeper.Play do
  alias GamePlatform.Game
  use WebGamesWeb, :live_view

  @assigns_keys [
    :grid,
    :events,
    :player_id,
    :game_id,
    :status,
    :height,
    :width,
    :num_mines,
    :clicks_enabled?,
    :display_grid,
  ]

  @impl true
  def mount(_params, %{"game_id" => game_id, "player_id" => player_id, "topics" => topics}, socket) do
    if Game.game_exists?(game_id) do
      if connected?(socket) do
        Enum.each(topics, fn topic -> Phoenix.PubSub.subscribe(WebGames.PubSub, topic) end)

        Game.player_connected(player_id, game_id, self())
      end
      {:ok, assign(socket, init_assigns(game_id, player_id)), temporary_assigns: [display_grid: %{}]}
    else
      {:ok, redirect(socket, to: "/select-game")}
    end
  end

  # If we don't have the proper session for some reason.
  @impl true
  def mount(_params, _session, socket) do
    {:ok, redirect(socket, to: "/select-game")}
  end

  defp init_assigns(game_id, player_id) do
    %{
      game_id: game_id,
      player_id: player_id,
      events: [],
      grid: nil,
      display_grid: %{},
      status: :play,
      clicks_enabled?: true,
    }
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

  @impl true
  def handle_info({:game_event, _game_id, msgs}, socket) do
    new_assigns = Enum.reduce(msgs, Map.take(socket.assigns, @assigns_keys), fn msg, acc ->
      process_event(msg, acc)
    end)

    {:noreply, assign(socket, new_assigns)}
  end

  def process_event({:click, cells}, %{grid: grid} = assigns) do
    new_grid = Enum.into(cells, grid, fn {coord, clicked?} ->
      {coord, %{grid[coord] | clicked?: clicked?}}
    end)

    assigns
    |> Map.put(:grid, new_grid)
    |> render_cells(Map.keys(cells))
  end

  def process_event({:open, cells}, %{grid: grid} = assigns) do
    new_grid = Enum.into(cells, grid, fn {coord, value} ->
      {coord, %{grid[coord] | value: value, opened?: true}}
    end)

    assigns
    |> Map.put(:grid, new_grid)
    |> render_cells(Map.keys(cells))
  end

  def process_event({:flag, cells}, %{grid: grid} = assigns) do
    new_grid = Enum.into(cells, grid, fn {coord, flagged?} ->
      {coord, %{grid[coord] | flagged?: flagged?}}
    end)

    assigns
    |> Map.put(:grid, new_grid)
    |> render_cells(Map.keys(cells))
  end

  def process_event({:game_over, :lose}, assigns) do
    assigns
    |> Map.put(:status, :lose)
    |> Map.put(:clicks_enabled?, false)
    |> render_full_grid()
  end

  def process_event({:game_over, :win}, assigns) do
    assigns
    |> Map.put(:status, :win)
    |> Map.put(:clicks_enabled?, false)
    |> render_full_grid()
  end

  def process_event({:sync, %{grid: grid, height: h, width: w, num_mines: n, status: status}}, assigns) do
    Map.merge(assigns, %{grid: grid, height: h, width: w, num_mines: n, status: status})
    |> render_full_grid()
  end

  def process_event({:show_mines, coord_list}, %{grid: grid} = assigns) do
    new_grid = Enum.into(coord_list, grid, fn coord ->
      {coord, %{grid[coord] | has_mine?: true}}
    end)

    assigns
    |> Map.put(:grid, new_grid)
    |> render_cells(coord_list)
  end

  defp render_cells(assigns, coords) do
    Enum.map(coords, fn coord ->
      {coord, render_cell(assigns.grid[coord], assigns)}
    end)
    |> Enum.into(%{})
    |> then(fn new_display -> Map.merge(assigns.display_grid, new_display) end)
    |> then(fn new_display -> Map.put(assigns, :display_grid, new_display) end)
  end

  defp render_full_grid(assigns) do
    render_cells(assigns, Map.keys(assigns.grid))
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

  defp display_value(%{has_mine?: true}, :win), do: "+"
  defp display_value(%{has_mine?: true, flagged?: true}, _), do: "O"
  defp display_value(%{has_mine?: true}, _), do: "X"
  defp display_value(%{flagged?: true}, _), do: "F"
  defp display_value(%{value: 0}, _), do: nil
  defp display_value(%{value: "0"}, _), do: nil
  defp display_value(%{value: v}, _), do: v
  defp display_value(_, _), do: nil
end
