defmodule WebGames.Minesweeper.GameState do
  defstruct [
    w: 0,
    h: 0,
    num_mines: 10,
    grid: %{},
    state: :init,
    notifications: [],
    player: nil,
  ]

  use GamePlatform.GameState

  alias WebGames.Minesweeper.Config
  alias WebGames.Minesweeper.Display
  alias WebGames.Minesweeper.Cell
  alias GamePlatform.Notification

  @type notification_t :: {String.t() | atom(), any()}
  @type coord_t :: {integer(), integer()}
  @type grid_t :: %{coord_t() => Cell.t()}

  @type t :: %__MODULE__{
    w: integer(),
    h: integer(),
    num_mines: integer(),
    grid: grid_t(),
    state: :init | :play | :win | :lose,
  }

  @impl true
  def init(config) do
    if Config.valid?(config) do
      game = %__MODULE__{w: config.width, h: config.height, num_mines: config.num_mines, grid: create_blank_grid(config)}
      Display.display_grid(game)
      {:ok, game}
    else
      # TODO: Return WHICH error caused the config to not be valid
      {:error, :invalid_config}
    end
  end

  @spec all_coords(integer(), integer()) :: list(coord_t())
  def all_coords(width, height) do
    for x <- 0..(width - 1), y <- 0..(height - 1), do: {x, y}
  end

  defp create_blank_grid(config) do
    all_coords(config.width, config.height)
    |> Stream.map(fn coord -> {coord, %Cell{}} end)
    |> Enum.into(%{})
  end

  defp get_adjacent_coords({x, y}) do
    for dx <- -1..1, dy <- -1..1 do
      {x + dx, y + dy}
    end
  end

  defp begin_game(game, start_space) do
    # Get all the spaces where we _can_ put a mine...
    prepared_grid = possible_mine_spaces(game.grid, game.num_mines, start_space)
    # ...shuffle that list...
    |> Enum.shuffle()
    # ...then take however many we need to place mines.
    # This should make it so that, for full grids, we aren't
    # randomly trying to land on the last open space forever.
    |> Enum.take(game.num_mines)
    # Loop through each space we need to mine..
    |> Enum.reduce(game.grid, fn mined_coord, grid ->
      # Put a mine in the space we picked.
      # mined_grid = Map.replace(mined_grid, mined_space, %{mined_grid[mined_space] | has_mine?: true})
      grid = Map.replace(grid, mined_coord, Cell.place_mine(grid[mined_coord]))

      get_adjacent_coords(mined_coord)
      # Get all adjacent cells
      |> Enum.map(fn adj_coord -> {adj_coord, Map.get(grid, adj_coord)} end)
      |> Enum.reject(fn {_, cell} -> is_nil(cell) end)
      # Increment all their values by 1
      |> Enum.map(fn {adj_coord, cell} -> {adj_coord, Cell.increment_value(cell)} end)
      # Put the incremented cells back in the grid
      |> Enum.reduce(grid, fn {adj_coord, cell}, grid -> Map.replace(grid, adj_coord, cell) end)
    end)

    %__MODULE__{game | grid: prepared_grid, state: :play}
  end

  defp possible_mine_spaces(grid, num_mines, start_space) do
    if map_size(grid) - num_mines >= 9 do
      # Ensure the start space is 0 by making the start space
      # and all adjacent spaces un-mineable.
      Map.keys(grid) -- get_adjacent_coords(start_space)
    else
      # We either have too many mines to make the start space 0,
      # or more mines than grid spaces.
      # Either way, the only space where a mine CANNOT go
      # is the start space.
      Map.keys(grid) -- [start_space]
    end
  end

  @impl true
  def player_connected(game, player_id, pid) do
    # Pre-calculate this so we don't do it inside the loop a bunch of times.
    show_mines? = game.state not in [:win, :lose]

    display_grid = Enum.map(game.grid, fn {coord, cell} ->
      {coord, Cell.display(cell, show_mines?)}
    end)
    |> Enum.into(%{})

    sync_data = %{grid: display_grid, width: game.w, height: game.h, num_mines: game.num_mines}

    {n, g} = game
    |> add_notification({:player, player_id}, {:sync, sync_data})
    |> take_notifications()

    # Process.monitor(pid)

    {:ok, n, g}
  end

  # If a game is over, do nothing.
  @impl true
  def handle_event(%__MODULE__{state: :win} = game, _), do: {:ok, [], game}
  @impl true
  def handle_event(%__MODULE__{state: :lose} = game, _), do: {:ok, [], game}

  @impl true
  def handle_event(%__MODULE__{state: :init} = game, {:open, space}) do
    {n, g} = begin_game(game, space)
    |> then(&(click_cell(space, &1)))
    |> then(&(try_open(space, &1)))
    |> update_state()
    |> take_notifications()

    Display.display_grid(g, true)

    {:ok, n, g}
  end

  @impl true
  def handle_event(%__MODULE__{state: :play} = game, {:open, space}) do
    {n, g} = click_cell(space, game)
    |> then(&(try_open(space, &1)))
    |> update_state()
    |> take_notifications()

    Display.display_grid(g, true)

    {:ok, n, g}
  end

  @impl true
  def handle_event(%__MODULE__{} = game, {:flag, space}) do
    {n, g} = toggle_flag(space, game)
    |> take_notifications()

    Display.display_grid(g, true)

    {:ok, n, g}
  end

  defp click_cell(coord, game) do
    case Cell.click(game.grid[coord]) do
      {:error, _} -> game
      {:noop, _} -> game
      {:ok, cell} ->
        %__MODULE__{game | grid: Map.replace(game.grid, coord, cell)}
        |> add_notification(:all, {:click, %{coord => cell.clicked?}})
    end
  end

  defp try_open(coord, game) do
    {opened_cells, game} = open(coord, game)

    if Enum.empty?(opened_cells) do
      game
    else
      game |> add_notification(:all, {:open, opened_cells |> Enum.into(%{})})
    end
  end

  defp open(coord, game, opened_cells \\ []) do
    case Cell.open(game.grid[coord]) do
      {:error, _} -> {opened_cells, game}
      {:noop, _} -> {opened_cells, game}
      {:ok, cell} ->
        {[{coord, cell.value} | opened_cells], %__MODULE__{game | grid: Map.replace(game.grid, coord, cell)}}
      {:cascade, cell} ->
        game = %__MODULE__{game | grid: Map.replace(game.grid, coord, cell)}
        opened_cells = [{coord, cell.value} | opened_cells]

        get_adjacent_coords(coord)
        |> Enum.reduce({opened_cells, game}, fn adj_coord, {opened_cells, game} -> open(adj_coord, game, opened_cells) end)
      {:boom, cell} ->
        game = %__MODULE__{game | state: :lose, grid: Map.replace(game.grid, coord, cell)}
        |> add_notification(:all, {:show_mines, get_mine_locations(game.grid)})
        |> add_notification(:all, {:game_over, :lose})

        {[{coord, cell.value} | opened_cells], game}
    end
  end

  defp toggle_flag(coord, game) do
    case Cell.toggle_flag(game.grid[coord]) do
      {:error, _} -> game
      {:ok, cell} ->
        %__MODULE__{game | grid: Map.replace(game.grid, coord, cell)}
        |> add_notification(:all, {:flag, %{coord => cell.flagged?}})
    end
  end

  defp get_mine_locations(grid) do
    grid
    |> Enum.filter(fn {_, cell} -> cell.has_mine? end)
    |> Enum.map(fn {coord, _} -> coord end)
  end

  defp update_state(%__MODULE__{state: :lose} = game), do: game
  defp update_state(%__MODULE__{state: :win} = game), do: game
  defp update_state(%__MODULE__{state: _state} = game) do
    if has_won?(game) do
      %__MODULE__{game | state: :win}
      |> add_notification(:all, {:game_over, :win})
    else
      %__MODULE__{game | state: :play}
    end
  end

  # We win if all cells that don't have mines are open
  defp has_won?(game) do
    Enum.count(game.grid, fn {_, cell} ->
      !cell.has_mine? && !cell.opened?
    end) == 0
  end

  @impl true
  def take_notifications(game) do
    {Notification.collate_notifications(game.notifications), struct(game, notifications: [])}
  end

  defp add_notification(game, to, msg) do
    %__MODULE__{game | notifications: [Notification.build(to, msg) | game.notifications]}
  end

  @impl true
  def add_player(%__MODULE__{player: nil} = game, player) do
    {n, g} = %__MODULE__{game | player: player}
    |> add_notification(:all, {:added, player})
    |> take_notifications()

    {:ok, n, g}
  end

  @impl true
  def add_player(%__MODULE__{player: player} = game, player) do
    IO.inspect("CANNOT ADD PLAYER #{inspect(player)}")
    {:ok, [], game}
  end
end
