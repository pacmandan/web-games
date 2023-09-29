defmodule WebGamesWeb.Minesweeper.Play do
  alias GamePlatform.Game
  use WebGamesWeb, :live_view

  def mount(_params, %{"game_id" => game_id, "player_id" => player_id}, socket) do
    IO.inspect("LIVE VIEW -- GAME ID: #{game_id} -- PLAYER ID: #{player_id}")
    if Game.game_exists?(game_id) do
      if connected?(socket) do
        Phoenix.PubSub.subscribe(WebGames.PubSub, "game:#{game_id}")
        Phoenix.PubSub.subscribe(WebGames.PubSub, "game:#{game_id}:player:#{player_id}")
        IO.inspect("SENDING PLAYER CONNECTED")
        Game.player_connected(player_id, game_id)
      end
      {:ok, assign(socket, %{game_id: game_id, player_id: player_id, events: [], grid: nil})}
    else
      {:ok, redirect(socket, to: "/select-game")}
    end
  end

  def handle_event("inc", _unsigned_params, socket) do
    %{assigns: %{count: count}} = socket
    {:noreply, assign(socket, %{count: count + 1})}
  end

  def handle_event("dec", _unsigned_params, socket) do
    %{assigns: %{count: count}} = socket
    {:noreply, assign(socket, %{count: count - 1})}
  end

  def handle_event("click", %{"x" => x, "y" => y}, socket) do
    x = String.to_integer(x)
    y = String.to_integer(y)
    Game.send_event({:open, {x, y}}, socket.assigns[:player_id], socket.assigns[:game_id])
    {:noreply, socket}
  end

  def handle_info({:game_event, _game_id, event}, socket) do
    IO.inspect("GOT AN EVENT!!!")
    IO.inspect(event)
    new_assigns = process_event(event, socket.assigns[:grid])
    |> Map.put(:events, [event |> inspect() | socket.assigns[:events]])
    IO.inspect(new_assigns)
    {:noreply, assign(socket, new_assigns)}
  end

  def process_event({:sync, sync_data}, _) do
    Enum.into(sync_data.grid, %{}, fn %{coord: coord, display: display} ->
      cell = case display do
        "." -> %{opened?: false, value: nil, has_mine?: nil}
        x -> %{opened?: true, value: x, has_mine?: nil}
      end
      {coord, cell}
    end)
    |> then(fn grid -> %{grid: grid, width: sync_data.width, height: sync_data.height, num_mines: sync_data.num_mines} end)
  end

  def process_event({:open, cells}, grid) do
    grid = Enum.into(cells, grid, fn %{coord: coord, value: value} ->
      case grid[coord] do
        %{has_mine?: true} -> {coord, %{grid[coord] | opened?: true}}
        _ -> {coord, %{grid[coord] | opened?: true, value: value}}
      end
    end)

    %{grid: grid}
  end

  def process_event({:lose, cell}, grid) do
    grid = %{grid | cell.coord => %{grid[cell.coord] | has_mine?: true, value: "X"}}
    %{grid: grid, status: :lose}
  end

  def process_event(event, grid) do
    IO.inspect("UNKNOWN EVENT: #{inspect(event)}")
    %{grid: grid}
  end
end
