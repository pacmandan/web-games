defmodule WebGames.Minesweeper.CellTest do
  use ExUnit.Case, async: true

  alias WebGames.Minesweeper.Cell

  doctest WebGames.Minesweeper.Cell

  describe "display()" do
    test "nil" do
      assert Cell.display(nil, false) |> is_nil()
    end

    test "unopened, unmined cell should show nil for mines and values" do
      cell = %Cell{
        value: 1,
        opened?: false,
        has_mine?: false,
      }
      assert Cell.display(cell, false) === %{
        opened?: false,
        has_mine?: nil,
        clicked?: false,
        flagged?: false,
        value: nil,
      }
    end

    test "unopened, mined cell should show nil for mines and values" do
      cell = %Cell{
        value: 1,
        opened?: false,
        has_mine?: true,
      }
      assert Cell.display(cell, false) === %{
        opened?: false,
        has_mine?: nil,
        clicked?: false,
        flagged?: false,
        value: nil,
      }
    end

    test "unopened, mined cell should show mines when asked" do
      cell = %Cell{
        value: 1,
        opened?: false,
        has_mine?: true,
      }
      assert Cell.display(cell, true) === %{
        opened?: false,
        has_mine?: true,
        clicked?: false,
        flagged?: false,
        value: nil,
      }
    end

    test "opened cell should show value" do
      cell = %Cell{
        value: 1,
        opened?: true,
        has_mine?: false,
      }
      assert Cell.display(cell, false) === %{
        opened?: true,
        has_mine?: false,
        clicked?: false,
        flagged?: false,
        value: 1,
      }
    end

    test "opened cell with mine should show a mine, but nil value" do
      cell = %Cell{
        value: 1,
        opened?: true,
        has_mine?: true,
      }
      assert Cell.display(cell, false) === %{
        opened?: true,
        has_mine?: true,
        clicked?: false,
        flagged?: false,
        value: nil,
      }
    end

    test "flagged and clicked should show no matter what" do
      cell = %Cell{
        value: 1,
        opened?: false,
        has_mine?: false,
        clicked?: true,
        flagged?: true,
      }
      assert Cell.display(cell, false) === %{
        opened?: false,
        has_mine?: nil,
        clicked?: true,
        flagged?: true,
        value: nil,
      }
    end
  end
end
