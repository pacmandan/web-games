defmodule WebGames.Minesweeper.GameState do
  @moduledoc """
  Game implementation module for Minesweeper.
  """

  use GamePlatform.GameState,
    view_module: WebGamesWeb.Minesweeper.PlayerComponent,
    display_name: "Minesweeper"

  alias GamePlatform.PubSubMessage
  alias GamePlatform.GameServer.InternalComms
  alias WebGames.Minesweeper.Config
  # alias WebGames.Minesweeper.Display
  alias WebGames.Minesweeper.Cell

  defstruct [
    w: 0,
    h: 0,
    num_mines: 10,
    grid: %{},
    status: :init,
    notifications: [],
    player: nil,
    audience: MapSet.new(),
    start_time: nil,
    end_time: nil,
    game_type: nil,
    end_game_ref: nil,
  ]

  @type notification_t :: {String.t() | atom(), any()}
  @type coord_t :: {integer(), integer()}
  @type grid_t :: %{coord_t() => Cell.t()}

  @type t :: %__MODULE__{
    w: integer(),
    h: integer(),
    num_mines: integer(),
    grid: grid_t(),
    status: :init | :play | :win | :lose,
    notifications: list(PubSubMessage.t()),
    player: String.t(),
    audience: MapSet.t(String.t()),
    start_time: DateTime.t(),
    end_time: DateTime.t(),
    game_type: String.t(),
    end_game_ref: reference(),
  }

  @post_game_timeout :timer.minutes(2)

  @impl true
  def init(config, init_player) do
    if Config.valid?(config) do
      game = %__MODULE__{
        w: config.width,
        h: config.height,
        num_mines: config.num_mines,
        game_type: config.type,
        grid: create_blank_grid(config.width, config.height),
        player: init_player,
      }

      {:ok, game}
    else
      {:error, :invalid_config}
    end
  end

  defp all_coords(width, height) do
    for x <- 1..width, y <- 1..height, do: {x, y}
  end

  defp create_blank_grid(width, height) do
    all_coords(width, height)
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

    start_time = DateTime.utc_now()

    %__MODULE__{game | grid: prepared_grid, status: :play, start_time: start_time}
    |> add_notification(:all, {:start_game, start_time})
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
  # Player is set during init now, so this is unlikely to happen now.
  def join_game(%__MODULE__{player: nil} = game, player_id) do
    {n, g} = %__MODULE__{game | player: player_id}
    |> add_notification(:all, {:new_active_player, player_id})
    |> take_notifications()

    {:ok, [:players], n, g}
  end

  @impl true
  def join_game(%__MODULE__{player: active_player_id} = game, player_id) when player_id == active_player_id do
    {:ok, [:players], [], game}
  end

  @impl true
  def join_game(%__MODULE__{audience: audience} = game, audience_member_id) do
    if MapSet.size(audience) >= 100 do
      {:error, :game_full}
    else
      {n, g} = add_audience_member(game, audience_member_id)
      |> take_notifications()

      {:ok, [:audience], n, g}
    end
  end

  defp add_audience_member(game, audience_member_id) do
    # Need to check this so we can also add a notification if it's a new audience member.
    unless MapSet.member?(game.audience, audience_member_id) do
      game
      |> Map.put(:audience, MapSet.put(game.audience, audience_member_id))
      |> add_notification(:all, {:audience_join, audience_member_id})
    else
      game
    end
  end

  @impl true
  def leave_game(%__MODULE__{} = game, player_id, _reason) do
    cond do
      player_id == game.player ->
        # If this is the active player, end the game immediately
        InternalComms.schedule_end_game(5000)

        {n, g} = game
        |> add_notification(:all, {:active_player_leave, player_id})
        |> take_notifications()

        {:ok, n, g}
      MapSet.member?(game.audience, player_id) ->
        # If this is an audience member, remove them and send the audience_leave notification
        {n, g} = %__MODULE__{game | audience: MapSet.delete(game.audience, player_id)}
        |> add_notification(:all, {:audience_leave, player_id})
        |> take_notifications()

        {:ok, n, g}
      true ->
        # Otherwise do nothing
        {:ok, [], game}
    end
  end

  @impl true
  def player_connected(game, player_id) do
    cond do
      player_id == game.player ->
        {n, g} = sync_connected_player(game, player_id, :player)
        |> take_notifications()

        {:ok, n, g}

      MapSet.member?(game.audience, player_id) ->
        {n, g} = sync_connected_player(game, player_id, :audience)
        |> take_notifications()

        {:ok, n, g}

      true ->
        {:error, :unknown_player}
    end
  end

  defp sync_connected_player(game, player_id, player_type) do
    sync_data = build_sync_data(game, player_type)

    game
    |> add_sync_notification({:player, player_id}, {:sync, sync_data})
  end

  @impl true
  def handle_game_shutdown(game) do
    # Send a shutdown message to everyone still connected.
    {:ok, [PubSubMessage.build(:all, {:shutdown, :normal}, :shutdown)], game}
  end

  def handle_event(%__MODULE__{player: active_player_id} = game, player_id, _) when player_id != active_player_id do
    # Only accept events from the active player.
    {:ok, [], game}
  end

  @impl true
  def handle_event(%__MODULE__{} = game, _, :restart) do
    unless game.end_game_ref |> is_nil() do
      InternalComms.cancel_scheduled_message(game.end_game_ref)
    end

    game = %__MODULE__{game |
      grid: create_blank_grid(game.w, game.h),
      status: :init,
      start_time: nil,
      end_time: nil,
      end_game_ref: nil,
    }

    player_sync_data = build_sync_data(game, :player)
    audience_sync_data = build_sync_data(game, :audience)

    {n, g} = game
    |> add_sync_notification(:players, {:sync, player_sync_data})
    |> add_sync_notification(:audience, {:sync, audience_sync_data})
    |> take_notifications()

    {:ok, n, g}
  end

  # If a game is over, do nothing.
  @impl true
  def handle_event(%__MODULE__{status: :win} = game, _, _), do: {:ok, [], game}
  @impl true
  def handle_event(%__MODULE__{status: :lose} = game, _, _), do: {:ok, [], game}

  @impl true
  def handle_event(%__MODULE__{status: :init} = game, _, {:open, space}) do
    {n, g} = begin_game(game, space)
    |> then(&(click_cell(space, &1)))
    |> then(&(try_open(space, &1)))
    |> set_status_win_or_play()
    |> take_notifications()

    # if Mix.env() === :dev do
    #   Display.display_grid(g, true)
    # end

    {:ok, n, g}
  end

  @impl true
  def handle_event(%__MODULE__{status: :play} = game, _, {:open, space}) do
    {n, g} = click_cell(space, game)
    |> then(&(try_open(space, &1)))
    |> set_status_win_or_play()
    |> take_notifications()

    {:ok, n, g}
  end

  @impl true
  def handle_event(%__MODULE__{} = game, _, {:flag, space}) do
    {n, g} = toggle_flag(space, game)
    |> take_notifications()

    {:ok, n, g}
  end

  defp build_sync_data(game, player_type) when player_type in [:player, :audience] do
    # Pre-calculate this so we don't do it inside the loop a bunch of times.
    show_mines? = game.status in [:win, :lose]

    # TODO: This could get expensive, maybe count as flags are placed?
    num_flags = count_flags(game)

    display_grid = Enum.map(game.grid, fn {coord, cell} ->
      {coord, Cell.display(cell, show_mines?)}
    end)
    |> Enum.into(%{})

    %{
      grid: display_grid,
      width: game.w,
      height: game.h,
      num_mines: game.num_mines,
      num_flags: num_flags,
      status: game.status,
      start_time: game.start_time,
      end_time: game.end_time,
      game_type: game.game_type,
      player_type: player_type,
      audience_size: MapSet.size(game.audience),
    }
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
        game = %__MODULE__{game | grid: Map.replace(game.grid, coord, cell)}
        |> end_game(:lose)

        {[{coord, cell.value} | opened_cells], game}
    end
  end

  defp toggle_flag(coord, game) do
    case Cell.toggle_flag(game.grid[coord]) do
      {:error, _} -> game
      {:noop, _} -> game
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

  defp set_status_win_or_play(%__MODULE__{status: :lose} = game), do: game
  defp set_status_win_or_play(%__MODULE__{status: :win} = game), do: game
  defp set_status_win_or_play(%__MODULE__{status: _status} = game) do
    if has_won?(game) do
      end_game(game, :win)
    else
      %__MODULE__{game | status: :play}
    end
  end

  defp end_game(game, status) do
    end_game_ref = InternalComms.schedule_end_game(@post_game_timeout)

    end_time = DateTime.utc_now()

    game
    |> Map.put(:end_game_ref, end_game_ref)
    |> Map.put(:status, status)
    |> Map.put(:end_time, end_time)
    |> add_notification(:all, {:game_over, %{status: status, end_time: end_time}})
    |> add_notification(:all, {:show_mines, get_mine_locations(game.grid)})
  end

  # We win if all cells that don't have mines are open
  defp has_won?(game) do
    not Enum.any?(game.grid, fn {_, cell} ->
      !cell.has_mine? && !cell.opened?
    end)
  end

  defp take_notifications(game) do
    {PubSubMessage.combine_msgs(game.notifications), struct(game, notifications: [])}
  end

  defp add_notification(game, to, msg) do
    %__MODULE__{game | notifications: [PubSubMessage.build(to, msg) | game.notifications]}
  end

  defp add_sync_notification(game, to, msg) do
    %__MODULE__{game | notifications: [PubSubMessage.build(to, msg, :sync) | game.notifications]}
  end

  defp count_flags(game) do
    game.grid
    |> Enum.reduce(0, fn
      {_, %{flagged?: true}}, acc -> acc + 1
      {_, %{flagged?: false}}, acc -> acc
    end)
  end
end
