defmodule WebGames.Minesweeper.ConfigTest do
  use ExUnit.Case, async: true

  alias WebGames.Minesweeper.Config

  doctest WebGames.Minesweeper.Config

  # Defaults are height: 10, width: 10, num_mines 10.
  # To test nil, we have to explicitly set nil.

  test "valid config" do
    conf = %Config{height: 10, width: 10, num_mines: 10}
    assert Config.valid?(conf)
  end

  test "height is too low" do
    conf = %Config{height: 0, width: 10, num_mines: 10}
    refute Config.valid?(conf)
  end

  test "height is too high" do
    conf = %Config{height: 101, width: 10, num_mines: 10}
    refute Config.valid?(conf)
  end

  test "height is not set" do
    conf = %Config{height: nil, width: 10, num_mines: 10}
    refute Config.valid?(conf)
  end

  test "height is negative" do
    conf = %Config{height: -10, width: 10, num_mines: 10}
    refute Config.valid?(conf)
  end

  test "width is too low" do
    conf = %Config{height: 10, width: 0, num_mines: 10}
    refute Config.valid?(conf)
  end

  test "width is too high" do
    conf = %Config{height: 10, width: 101, num_mines: 10}
    refute Config.valid?(conf)
  end

  test "width is not set" do
    conf = %Config{height: 10, width: nil, num_mines: 10}
    refute Config.valid?(conf)
  end

  test "width is negative" do
    conf = %Config{height: 10, width: -10, num_mines: 10}
    refute Config.valid?(conf)
  end

  test "num_mines is too low" do
    conf = %Config{height: 10, width: 10, num_mines: 0}
    refute Config.valid?(conf)
  end

  test "num_mines is too high" do
    # Conf can't be larger than width * height
    conf = %Config{height: 5, width: 5, num_mines: 26}
    refute Config.valid?(conf)
  end

  test "num_mines is not set" do
    conf = %Config{height: 10, width: 10, num_mines: nil}
    refute Config.valid?(conf)
  end

  test "num_mines is negative" do
    conf = %Config{height: 10, width: 10, num_mines: -10}
    refute Config.valid?(conf)
  end
end
