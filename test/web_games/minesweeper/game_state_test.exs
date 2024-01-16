defmodule WebGames.Minesweeper.GameStateTest do
  use ExUnit.Case

  import Mock

  alias GamePlatform.GameServer.InternalComms
  alias GamePlatform.PubSubMessage
  alias WebGames.Minesweeper.Config
  alias WebGames.Minesweeper.GameState
  alias WebGames.Minesweeper.Cell

  setup do
    {:ok, %{state: %GameState{
      w: 5,
      h: 4,
      num_mines: 2,
      #  |12345  x
      # -------
      # 1|11...
      # 2|X1...
      # 3|1211.
      # 4|.1X1.
      #
      # y
      #
      grid: %{
        {1,1} => %Cell{value: 1},
        {1,2} => %Cell{value: 1, has_mine?: true},
        {1,3} => %Cell{value: 1},
        {1,4} => %Cell{},

        {2,1} => %Cell{value: 1},
        {2,2} => %Cell{value: 1},
        {2,3} => %Cell{value: 2},
        {2,4} => %Cell{value: 1},

        {3,1} => %Cell{},
        {3,2} => %Cell{},
        {3,3} => %Cell{value: 1},
        {3,4} => %Cell{value: 1, has_mine?: true},

        {4,1} => %Cell{},
        {4,2} => %Cell{},
        {4,3} => %Cell{value: 1},
        {4,4} => %Cell{value: 1},

        {5,1} => %Cell{},
        {5,2} => %Cell{},
        {5,3} => %Cell{},
        {5,4} => %Cell{},
      },
      status: :init,
      notifications: [],
      player: nil,
      start_time: nil,
      end_time: nil,
      game_type: :custom,
      end_game_ref: nil,
    }}}
  end

  test "init sets state based on config" do
    config = %Config{
      width: 5,
      height: 6,
      num_mines: 7,
      type: :custom,
    }

    assert {:ok, %GameState{} = game_state} = GameState.init(config)
    assert game_state.w === 5
    assert game_state.h === 6
    assert game_state.num_mines === 7
    assert game_state.game_type === :custom
    assert game_state.start_time |> is_nil()
    assert game_state.end_time |> is_nil()
    assert game_state.end_game_ref |> is_nil()
    assert game_state.player |> is_nil()
    assert game_state.notifications === []
    assert game_state.status === :init
    assert game_state.grid |> is_map()
    assert game_state.grid |> Map.keys() |> length() === 30

    # Keys are all in the correct form
    assert game_state.grid |> Enum.all?(fn {{x,y}, _} ->
      x >= 1 && x <= 5
      && y >= 1 && y <= 6
    end)

    # Mines should not be placed yet
    assert Enum.count(game_state.grid, fn {_, cell} -> cell.has_mine? end) === 0
  end

  test "init returns error on invalid config" do
    config = %Config{
      width: 1,
      height: 1,
      num_mines: 99,
      type: :custom,
    }

    assert GameState.init(config) === {:error, :invalid_config}
  end

  test "join game adds player, gives no topics, and returns an :added notification", %{state: state} do
    {:ok, topics, msgs, new_state} = GameState.join_game(state, "playerid_1")

    assert topics === []
    assert msgs === [
      %PubSubMessage{to: :all, payload: {:added, "playerid_1"}, type: :game_event}
    ]
    assert new_state.player === "playerid_1"
  end

  test "join game on existing player does nothing", %{state: state} do
    state = state
    |> Map.put(:player, "playerid_1")

    {:ok, topics, msgs, new_state} = GameState.join_game(state, "playerid_1")

    assert topics === []
    assert msgs === []
    assert new_state.player === "playerid_1"
  end

  test "join game returns error when a second player tries to join", %{state: state} do
    state = state
    |> Map.put(:player, "playerid_2")

    assert GameState.join_game(state, "playerid_1") === {:error, :game_full}
  end

  test "player connected sends sync notification", %{state: state} do
    state = state
    |> Map.put(:player, "playerid_1")

    {:ok, msgs, new_state} = GameState.player_connected(state, "playerid_1")

    display_cell = %{value: nil, has_mine?: nil, flagged?: false, opened?: false, clicked?: false}
    assert state === new_state
    assert msgs === [
      %PubSubMessage{to: {:player, "playerid_1"}, type: :sync, payload: {:sync, %{
        grid: %{
          {1, 1} => display_cell,
          {1, 2} => display_cell,
          {1, 3} => display_cell,
          {1, 4} => display_cell,
          {2, 1} => display_cell,
          {2, 2} => display_cell,
          {2, 3} => display_cell,
          {2, 4} => display_cell,
          {3, 1} => display_cell,
          {3, 2} => display_cell,
          {3, 3} => display_cell,
          {3, 4} => display_cell,
          {4, 1} => display_cell,
          {4, 2} => display_cell,
          {4, 3} => display_cell,
          {4, 4} => display_cell,
          {5, 1} => display_cell,
          {5, 2} => display_cell,
          {5, 3} => display_cell,
          {5, 4} => display_cell
        },
        width: 5,
        height: 4,
        num_mines: 2,
        num_flags: 0,
        status: :init,
        start_time: nil,
        end_time: nil,
        game_type: :custom
      }}}
    ]
  end

  test "player connected returns error on unknown player", %{state: state} do
    state = state
    |> Map.put(:player, "playerid_2")

    assert GameState.player_connected(state, "playerid_1") === {:error, :unknown_player}
  end

  test "handle game shutdown sends shutdown message", %{state: state} do
    {:ok, msgs, new_state} = GameState.handle_game_shutdown(state)

    assert new_state === state
    assert msgs === [
      %PubSubMessage{to: :all, payload: {:shutdown, :normal}, type: :shutdown}
    ]
  end

  test "restart event resets game state, sends sync notification", %{state: state} do
    state = state
    |> Map.put(:player, "playerid_1")

    # Pre-event state should have 2 mines
    assert Enum.count(state.grid, fn {_, cell} -> cell.has_mine? end) === 2

    {:ok, msgs, new_state} = GameState.handle_event(state, "playerid_1", :restart)
    # Post-event state should have 0 mines
    assert Enum.count(new_state.grid, fn {_, cell} -> cell.has_mine? end) === 0
    display_cell = %{value: nil, has_mine?: nil, flagged?: false, opened?: false, clicked?: false}
    assert msgs === [
      %PubSubMessage{to: :all, type: :sync, payload: {:sync, %{
        grid: %{
          {1, 1} => display_cell,
          {1, 2} => display_cell,
          {1, 3} => display_cell,
          {1, 4} => display_cell,
          {2, 1} => display_cell,
          {2, 2} => display_cell,
          {2, 3} => display_cell,
          {2, 4} => display_cell,
          {3, 1} => display_cell,
          {3, 2} => display_cell,
          {3, 3} => display_cell,
          {3, 4} => display_cell,
          {4, 1} => display_cell,
          {4, 2} => display_cell,
          {4, 3} => display_cell,
          {4, 4} => display_cell,
          {5, 1} => display_cell,
          {5, 2} => display_cell,
          {5, 3} => display_cell,
          {5, 4} => display_cell
        },
        width: 5,
        height: 4,
        num_mines: 2,
        num_flags: 0,
        status: :init,
        start_time: nil,
        end_time: nil,
        game_type: :custom
      }}}
    ]
  end

  test "restart event resets game shutdown timer if it exists", %{state: state} do
    state = state
    |> Map.put(:player, "playerid_1")
    |> Map.put(:end_game_ref, Kernel.make_ref)

    with_mock InternalComms, [cancel_scheduled_message: fn(_) -> 1000 end] do
      {:ok, _msgs, new_state} = GameState.handle_event(state, "playerid_1", :restart)

      assert new_state.end_game_ref |> is_nil()
      assert_called InternalComms.cancel_scheduled_message(state.end_game_ref)
    end
  end

  test ":flag places flag on given cell when in :play", %{state: state} do
    state = state
    |> Map.put(:player, "playerid_1")
    |> Map.put(:status, :play)

    {:ok, msgs, new_state} = GameState.handle_event(state, "playerid_1", {:flag, {1,1}})

    assert msgs === [
      %PubSubMessage{to: :all, type: :game_event, payload: {:flag, %{{1,1} => true}}}
    ]
    assert new_state.grid[{1,1}].flagged?
  end

  test ":flag places flag on given cell when in :init", %{state: state} do
    state = state
    |> Map.put(:player, "playerid_1")
    |> Map.put(:status, :init)

    {:ok, msgs, new_state} = GameState.handle_event(state, "playerid_1", {:flag, {1,1}})

    assert msgs === [
      %PubSubMessage{to: :all, type: :game_event, payload: {:flag, %{{1,1} => true}}}
    ]
    assert new_state.grid[{1,1}].flagged?
  end

  test ":flag ignores event when in :win", %{state: state} do
    state = state
    |> Map.put(:player, "playerid_1")
    |> Map.put(:status, :win)

    {:ok, msgs, new_state} = GameState.handle_event(state, "playerid_1", {:flag, {1,1}})

    assert msgs === []
    refute new_state.grid[{1,1}].flagged?
  end

  test ":flag ignores event when in :lose", %{state: state} do
    state = state
    |> Map.put(:player, "playerid_1")
    |> Map.put(:status, :lose)

    {:ok, msgs, new_state} = GameState.handle_event(state, "playerid_1", {:flag, {1,1}})

    assert msgs === []
    refute new_state.grid[{1,1}].flagged?
  end

  test ":flag ignores event when cell is off-grid", %{state: state} do
    state = state
    |> Map.put(:player, "playerid_1")
    |> Map.put(:status, :play)

    {:ok, msgs, new_state} = GameState.handle_event(state, "playerid_1", {:flag, {0,0}})

    assert msgs === []
    assert new_state.grid === state.grid
  end

  test ":flag removes a flag if one already exists", %{state: state} do
    state = state
    |> Map.put(:player, "playerid_1")
    |> Map.put(:status, :play)
    |> Map.put(:grid, %{state.grid | {1,1} => %{state.grid[{1,1}] | flagged?: true}})

    {:ok, msgs, new_state} = GameState.handle_event(state, "playerid_1", {:flag, {1,1}})

    assert msgs === [
      %PubSubMessage{to: :all, type: :game_event, payload: {:flag, %{{1,1} => false}}}
    ]
    refute new_state.grid[{1,1}].flagged?
  end

  test ":flag ignores event when cell is opened already", %{state: state} do
    state = state
    |> Map.put(:player, "playerid_1")
    |> Map.put(:status, :play)
    |> Map.put(:grid, %{state.grid | {1,1} => %{state.grid[{1,1}] | opened?: true}})

    {:ok, msgs, new_state} = GameState.handle_event(state, "playerid_1", {:flag, {1,1}})

    assert msgs === []
    assert new_state.grid === state.grid
  end

  """
  TODO:
  mines are placed on :open when state is :init
  cell is opened on :open when state is :play
  adjacent cells are opened on :open when cell has 0 value
  send failed message when opened cell has mine
  send win message when opened last unmined cell
  cell is not opened when state is :win or :lose
  cell is not opened when cell has a flag
  nothing happens when opening cell outside of grid
  """

end
