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
      grid: mined_grid(),
      status: :init,
      notifications: [],
      player: nil,
      audience: MapSet.new(),
      start_time: nil,
      end_time: nil,
      game_type: :custom,
      end_game_ref: nil,
    }}}
  end

  defp empty_grid() do
    %{
      {1,1} => %Cell{},
      {1,2} => %Cell{},
      {1,3} => %Cell{},
      {1,4} => %Cell{},

      {2,1} => %Cell{},
      {2,2} => %Cell{},
      {2,3} => %Cell{},
      {2,4} => %Cell{},

      {3,1} => %Cell{},
      {3,2} => %Cell{},
      {3,3} => %Cell{},
      {3,4} => %Cell{},

      {4,1} => %Cell{},
      {4,2} => %Cell{},
      {4,3} => %Cell{},
      {4,4} => %Cell{},

      {5,1} => %Cell{},
      {5,2} => %Cell{},
      {5,3} => %Cell{},
      {5,4} => %Cell{},
    }
  end

  defp mined_grid() do
    %{
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
    }
  end

  defp almost_opened_grid() do
    %{
      {1,1} => %Cell{value: 1, opened?: true},
      {1,2} => %Cell{value: 1, has_mine?: true},
      {1,3} => %Cell{value: 1, opened?: true},
      {1,4} => %Cell{opened?: true},

      {2,1} => %Cell{value: 1, opened?: true},
      {2,2} => %Cell{value: 1, opened?: true},
      {2,3} => %Cell{value: 2, opened?: true},
      {2,4} => %Cell{value: 1}, # <-- Last unopened cell

      {3,1} => %Cell{opened?: true},
      {3,2} => %Cell{opened?: true},
      {3,3} => %Cell{value: 1, opened?: true},
      {3,4} => %Cell{value: 1, has_mine?: true},

      {4,1} => %Cell{opened?: true},
      {4,2} => %Cell{opened?: true},
      {4,3} => %Cell{value: 1, opened?: true},
      {4,4} => %Cell{value: 1, opened?: true},

      {5,1} => %Cell{opened?: true},
      {5,2} => %Cell{opened?: true},
      {5,3} => %Cell{opened?: true},
      {5,4} => %Cell{opened?: true},
    }
  end

  test "init sets state based on config" do
    config = %Config{
      width: 5,
      height: 6,
      num_mines: 7,
      type: :custom,
    }

    assert {:ok, %GameState{} = game_state} = GameState.init(config, "playerid_1")
    assert game_state.w === 5
    assert game_state.h === 6
    assert game_state.num_mines === 7
    assert game_state.game_type === :custom
    assert game_state.start_time |> is_nil()
    assert game_state.end_time |> is_nil()
    assert game_state.end_game_ref |> is_nil()
    assert game_state.player === "playerid_1"
    assert game_state.audience === MapSet.new()
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

    assert GameState.init(config, "playerid_1") === {:error, :invalid_config}
  end

  test "join game with no set player adds player, gives player topic, and returns an :new_active_player notification", %{state: state} do
    {:ok, topics, msgs, new_state} = GameState.join_game(state, "playerid_1")

    assert topics === [:players]
    assert msgs === [
      %PubSubMessage{to: :all, payload: {:new_active_player, "playerid_1"}, type: :game_event}
    ]
    assert new_state.player === "playerid_1"
  end

  test "join game on existing player just returns relevant topics", %{state: state} do
    state = state
    |> Map.put(:player, "playerid_1")

    {:ok, topics, msgs, new_state} = GameState.join_game(state, "playerid_1")

    assert topics === [:players]
    assert msgs === []
    assert new_state.player === "playerid_1"
  end

  test "join game adds audience member when a non-active player joins", %{state: state} do
    state = state
    |> Map.put(:player, "playerid_1")

    {:ok, topics, msgs, new_state} = GameState.join_game(state, "playerid_2")

    assert topics === [:audience]
    assert msgs === [
      %PubSubMessage{to: :all, payload: {:audience_join, "playerid_2"}, type: :game_event}
    ]
    assert new_state.player === "playerid_1"
    assert new_state.audience === MapSet.new(["playerid_2"])
  end

  test "join game returns error when player list is full", %{state: state} do
    state = state
    |> Map.put(:player, "playerid_1")
    |> Map.put(:audience, 1..101 |> Enum.to_list |> MapSet.new())

    assert GameState.join_game(state, "playerid_999") === {:error, :game_full}
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
        game_type: :custom,
        player_type: :player,
        audience_size: 0,
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
      %PubSubMessage{to: :audience, type: :sync, payload: {:sync, %{
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
        game_type: :custom,
        player_type: :audience,
        audience_size: 0,
      }}},
      %PubSubMessage{to: :players, type: :sync, payload: {:sync, %{
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
        game_type: :custom,
        player_type: :player,
        audience_size: 0,
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

    {:ok, msgs, new_state} = GameState.handle_event(state, "playerid_1", {:flag, {-2,0}})

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

  # TODO: This sometimes fails due to randomness
  # If the mines are placed in a certain way, it's possible to win in one move.
  # Meaning the output is going to be different.
  # Need to find a way to fix the mine placement results.
  @tag :skip
  test ":open opens cell and places initial mines when status is :init", %{state: state} do
    state = state
    |> Map.put(:player, "playerid_1")
    |> Map.put(:status, :init)
    |> Map.put(:grid, empty_grid())

    with_mock DateTime, [utc_now: fn() -> ~U[2024-01-06 23:25:38.371659Z] end] do
      {:ok, msgs, new_state} = GameState.handle_event(state, "playerid_1", {:open, {1,1}})

      assert new_state.status === :play
      assert new_state.grid[{1,1}].opened?
      assert new_state.grid[{1,1}].value === 0

      # Adjacent cells are also open, since initial value MUST be 0
      assert new_state.grid[{1,2}].opened?
      assert new_state.grid[{2,1}].opened?
      assert new_state.grid[{2,2}].opened?

      assert Enum.count(new_state.grid, fn {_, cell} -> cell.has_mine? end) === 2
      [
        %PubSubMessage{to: :all, type: :game_event, payload: [
          {:open, open_cells},
          {:click, clicked_cells},
          {:start_game, ~U[2024-01-06 23:25:38.371659Z]},
        ]},
      ] = msgs

      # We can't know the exact list here - it's random based on where
      # the mines ended up.
      assert open_cells |> is_map()
      assert clicked_cells === %{{1,1} => true}
    end
  end

  test ":open opens cell with non-zero value on :play", %{state: state} do
    state = state
    |> Map.put(:player, "playerid_1")
    |> Map.put(:status, :play)

    {:ok, msgs, new_state} = GameState.handle_event(state, "playerid_1", {:open, {1,1}})

    assert new_state.status === :play
    assert new_state.grid[{1,1}].opened?
    assert Enum.count(new_state.grid, fn {_, cell} -> cell.opened? end) === 1

    assert msgs === [
      %PubSubMessage{to: :all, type: :game_event, payload: [{:open, %{{1,1} => 1}}, {:click, %{{1,1} => true}}]},
    ]
  end

  test ":open opens all adjacent cells when cell value is 0", %{state: state} do
    state = state
    |> Map.put(:player, "playerid_1")
    |> Map.put(:status, :play)

    {:ok, msgs, new_state} = GameState.handle_event(state, "playerid_1", {:open, {5,1}})

    #  |12345  x
    # -------
    # 1|11...<-- Cascade off this corner
    # 2|X1...
    # 3|1211.
    # 4|.1X1.
    #
    # y

    assert new_state.status === :play
    assert new_state.grid[{5,1}].opened?
    assert new_state.grid[{5,1}].value === 0
    assert new_state.grid[{5,1}].clicked?

    assert new_state.grid[{2,1}].opened?
    assert new_state.grid[{2,1}].value === 1
    assert new_state.grid[{3,1}].opened?
    assert new_state.grid[{3,1}].value === 0
    assert new_state.grid[{4,1}].opened?
    assert new_state.grid[{4,1}].value === 0

    assert new_state.grid[{2,2}].opened?
    assert new_state.grid[{2,2}].value === 1
    assert new_state.grid[{3,2}].opened?
    assert new_state.grid[{3,2}].value === 0
    assert new_state.grid[{4,2}].opened?
    assert new_state.grid[{4,2}].value === 0
    assert new_state.grid[{5,2}].opened?
    assert new_state.grid[{5,2}].value === 0

    assert new_state.grid[{2,3}].opened?
    assert new_state.grid[{2,3}].value === 2
    assert new_state.grid[{3,3}].opened?
    assert new_state.grid[{3,3}].value === 1
    assert new_state.grid[{4,3}].opened?
    assert new_state.grid[{4,3}].value === 1
    assert new_state.grid[{5,3}].opened?
    assert new_state.grid[{5,3}].value === 0

    assert new_state.grid[{4,4}].opened?
    assert new_state.grid[{4,4}].value === 1
    assert new_state.grid[{5,4}].opened?
    assert new_state.grid[{5,4}].value === 0

    assert msgs === [
      %PubSubMessage{to: :all, type: :game_event, payload: [
        {:open, %{
          {5,1} => 0,

          {2,1} => 1,
          {3,1} => 0,
          {4,1} => 0,

          {2,2} => 1,
          {3,2} => 0,
          {4,2} => 0,
          {5,2} => 0,

          {2,3} => 2,
          {3,3} => 1,
          {4,3} => 1,
          {5,3} => 0,

          {4,4} => 1,
          {5,4} => 0,
          }},
        {:click, %{{5,1} => true}}
      ]},
    ]
  end

  test ":open ends the game when opening a mine", %{state: state} do
    state = state
    |> Map.put(:player, "playerid_1")
    |> Map.put(:status, :play)

    with_mocks([
      {DateTime, [], [utc_now: fn() -> ~U[2024-01-06 23:25:38.371659Z] end]},
      {InternalComms, [], [schedule_end_game: fn(_) -> Kernel.make_ref() end]}
     ]) do
      {:ok, msgs, new_state} = GameState.handle_event(state, "playerid_1", {:open, {1,2}})

      assert new_state.grid[{1,2}].clicked?
      assert new_state.grid[{1,2}].opened?
      assert new_state.status === :lose
      assert new_state.end_time === ~U[2024-01-06 23:25:38.371659Z]
      assert new_state.end_game_ref |> is_reference()

      assert msgs === [
        %PubSubMessage{to: :all, type: :game_event, payload: [
          {:open, %{{1, 2} => 1}},
          {:show_mines, [{1, 2}, {3, 4}]},
          {:game_over, %{status: :lose, end_time: ~U[2024-01-06 23:25:38.371659Z]}},
          {:click, %{{1, 2} => true}}
        ]}
      ]
    end
  end

  test ":open ends the game when opening the last unopened mine", %{state: state} do
    state = state
    |> Map.put(:player, "playerid_1")
    |> Map.put(:status, :play)
    |> Map.put(:grid, almost_opened_grid())
    # The last unopened cell is {2,4}

    with_mocks([
      {DateTime, [], [utc_now: fn() -> ~U[2024-01-06 23:25:38.371659Z] end]},
      {InternalComms, [], [schedule_end_game: fn(_) -> Kernel.make_ref() end]}
     ]) do
      {:ok, msgs, new_state} = GameState.handle_event(state, "playerid_1", {:open, {2,4}})

      assert new_state.grid[{2,4}].clicked?
      assert new_state.grid[{2,4}].opened?
      assert new_state.status === :win
      assert new_state.end_time === ~U[2024-01-06 23:25:38.371659Z]
      assert new_state.end_game_ref |> is_reference()

      assert msgs === [
        %PubSubMessage{to: :all, type: :game_event, payload: [
          {:show_mines, [{1, 2}, {3, 4}]},
          {:game_over, %{status: :win, end_time: ~U[2024-01-06 23:25:38.371659Z]}},
          {:open, %{{2, 4} => 1}},
          {:click, %{{2, 4} => true}}
        ]}
      ]
    end
  end

  test ":open ignores command when in :win status", %{state: state} do
    state = state
    |> Map.put(:player, "playerid_1")
    |> Map.put(:status, :win)

    {:ok, [], new_state} = GameState.handle_event(state, "playerid_1", {:open, {1,1}})

    assert new_state === state
  end

  test ":open ignores command when in :lose status", %{state: state} do
    state = state
    |> Map.put(:player, "playerid_1")
    |> Map.put(:status, :lose)

    {:ok, [], new_state} = GameState.handle_event(state, "playerid_1", {:open, {1,1}})

    assert new_state === state
  end

  test ":open does nothing when opening a flagged cell", %{state: state} do
    state = state
    |> Map.put(:player, "playerid_1")
    |> Map.put(:status, :play)
    |> Map.put(:grid, %{state.grid | {1,1} => %{state.grid[{1,1}] | flagged?: true}})

    {:ok, [], new_state} = GameState.handle_event(state, "playerid_1", {:open, {1,1}})

    assert new_state === state
  end

  test ":open does nothing when opening a cell that is off-grid", %{state: state} do
    state = state
    |> Map.put(:player, "playerid_1")
    |> Map.put(:status, :play)

    {:ok, [], new_state} = GameState.handle_event(state, "playerid_1", {:open, {-2,0}})

    assert new_state === state
  end
end
