defmodule WebGames.Minesweeper.GameStateTest do
  use ExUnit.Case

  alias WebGames.Minesweeper.Config
  alias WebGames.Minesweeper.GameState
  alias WebGames.Minesweeper.Cell

  """
  init sets state based on config
  init returns error on invalid config
  join game adds player, gives no topics, and returns an :added notification
  join game on existing player does nothing
  join game returns error when a player is already in
  player connected sends sync notification
  player connected returns error on unknown player
  handle game shutdown sends shutdown message
  restart event cancels shutdown timer, resets game state, sends sync notification
  mines are placed on :open when state is :init
  cell is opened on :open when state is :play
  adjacent cells are opened on :open when cell has 0 value
  send failed message when opened cell has mine
  send win message when opened last unmined cell
  cell is not opened when state is :win or :lose
  cell is not opened when cell has a flag
  cell has flag placed on :flag when state is :play
  cell is not flagged when state is :win or :lose
  """

  setup do
    {:ok, %{state: %GameState{
      w: 4,
      h: 4,
      num_mines: 2,
      # |1234
      #------
      #1|11..
      #2|X1..
      #3|1211
      #4|.1X1
      grid: %{
        {1,1} => %Cell{value: 1},
        {1,2} => %Cell{value: 1},
        {1,3} => %Cell{},
        {1,4} => %Cell{},

        {2,1} => %Cell{value: 1, has_mine?: true},
        {2,2} => %Cell{value: 1},
        {2,3} => %Cell{},
        {2,4} => %Cell{},

        {3,1} => %Cell{value: 1},
        {3,2} => %Cell{value: 2},
        {3,3} => %Cell{value: 1},
        {3,4} => %Cell{value: 1},

        {4,1} => %Cell{},
        {4,2} => %Cell{value: 1},
        {4,3} => %Cell{value: 1, has_mine?: true},
        {4,4} => %Cell{value: 1},
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
end
