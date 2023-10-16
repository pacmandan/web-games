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
        # TODO: Set timer, if we don't get a sync before it runs out, try again.
        # Also set a "back-off" for attempts.
        # Maybe better to do a "receive" loop directly instead of waiting on handle_info?
        # That way we don't have to mess with Process.send_after(), and the whole thing can
        # be self-contained.
        # Game.player_connected(player_id, game_id, self())
        wait_for_sync(player_id, game_id, socket)
      end
      {:ok, assign(socket, init_assigns(game_id, player_id))}
    else
      {:ok, redirect(socket, to: "/select-game")}
    end
  end

  # If we don't have the proper session for some reason.
  @impl true
  def mount(_params, _session, socket) do
    {:ok, redirect(socket, to: "/select-game")}
  end

  defp wait_for_sync(player_id, game_id, socket, attempts \\ 5)
  defp wait_for_sync(_player_id, _game_id, _socket, 0) do
    {:error, :cannot_connect_to_game}
  end
  defp wait_for_sync(player_id, game_id, socket, attempts) do
    Game.player_connected(player_id, game_id, self())
    receive do
      # TODO: Maybe make "sync" messages into a different structure?
      {:game_event, _, [{:sync, _data}]} ->
        :ok
    after
      30_000 -> wait_for_sync(player_id, game_id, socket, attempts - 1)
    end
  end

  def init_assigns(game_id, player_id) do
    %{
      game_id: game_id,
      player_id: player_id,
      events: [],
      grid: nil,
      display_grid: nil,
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
    |> Map.put(:events, [msgs |> inspect() | socket.assigns[:events]])

    display_grid = render_grid(new_assigns.grid, new_assigns)

    new_assigns = Map.put(new_assigns, :display_grid, display_grid)

    {:noreply, assign(socket, new_assigns)}
  end

  def process_event({:click, cells}, %{grid: grid} = assigns) do
    new_grid = Enum.into(cells, grid, fn {coord, clicked?} ->
      {coord, %{grid[coord] | clicked?: clicked?}}
    end)

    %{assigns | grid: new_grid}
  end

  def process_event({:open, cells}, %{grid: grid} = assigns) do
    new_grid = Enum.into(cells, grid, fn {coord, value} ->
      {coord, %{grid[coord] | value: value, opened?: true}}
    end)

    %{assigns | grid: new_grid}
  end

  def process_event({:flag, cells}, %{grid: grid} = assigns) do
    new_grid = Enum.into(cells, grid, fn {coord, flagged?} ->
      {coord, %{grid[coord] | flagged?: flagged?}}
    end)

    %{assigns | grid: new_grid}
  end

  def process_event({:game_over, :lose}, assigns) do
    %{assigns | status: :lose, clicks_enabled?: false}
  end

  def process_event({:game_over, :win}, assigns) do
    %{assigns | status: :win, clicks_enabled?: false}
  end

  def process_event({:sync, %{grid: grid, height: h, width: w, num_mines: n, status: status}}, assigns) do
    Map.merge(assigns, %{grid: grid, height: h, width: w, num_mines: n, status: status})
  end

  def process_event({:show_mines, coord_list}, %{grid: grid} = assigns) do
    new_grid = Enum.into(coord_list, grid, fn coord ->
      {coord, %{grid[coord] | has_mine?: true}}
    end)

    %{assigns | grid: new_grid}
  end

  def render_grid(grid, assigns) do
    Enum.map(grid, fn {coord, cell} ->
      {coord, render_cell(cell, assigns)}
    end)
    |> Enum.into(%{})
  end

  def render_cell(cell, assigns) do
    %{
      background_color: background_color(cell),
      text_color: text_color(cell),
      value: display_value(cell, assigns.status),
      clickable?: assigns.clicks_enabled? && not (cell.opened?),
      border_color: "border-black",
    }
  end

  def background_color(%{opened?: true, has_mine?: true}), do: "bg-red-400"
  def background_color(%{opened?: true}), do: "bg-gray-300"
  def background_color(_), do: "bg-gray-500"

  def text_color(%{has_mine?: true}), do: "text-black"
  def text_color(%{value: value}) when value in [0, "0"], do: "text-black"
  def text_color(%{value: value}) when value in [1, "1"], do: "text-blue-500"
  def text_color(%{value: value}) when value in [2, "2"], do: "text-green-500"
  def text_color(%{value: value}) when value in [3, "3"], do: "text-red-500"
  def text_color(%{value: value}) when value in [4, "4"], do: "text-blue-800"
  def text_color(%{value: value}) when value in [5, "5"], do: "text-amber-800"
  def text_color(%{value: value}) when value in [6, "6"], do: "text-sky-500"
  def text_color(%{value: value}) when value in [7, "7"], do: "text-black"
  def text_color(%{value: value}) when value in [8, "8"], do: "text-gray-700"
  def text_color(_), do: "text-black"

  def display_value(%{has_mine?: true}, :win), do: "+"
  def display_value(%{has_mine?: true, flagged?: true}, _), do: "O"
  def display_value(%{has_mine?: true}, _), do: "X"
  def display_value(%{flagged?: true}, _), do: "F"
  def display_value(%{value: 0}, _), do: nil
  def display_value(%{value: "0"}, _), do: nil
  def display_value(%{value: v}, _), do: v
  def display_value(_, _), do: nil
end
