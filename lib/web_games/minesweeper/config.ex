defmodule WebGames.Minesweeper.Config do
  defstruct [
    :type,
    width: 10,
    height: 10,
    num_mines: 10,
  ]

  @type t :: %{
    width: integer(),
    height: integer(),
    num_mines: integer(),
  }

  def beginner(), do: %__MODULE__{width: 9, height: 9, num_mines: 10, type: :beginner}

  def intermediate(), do: %__MODULE__{width: 16, height: 16, num_mines: 40, type: :intermediate}

  def advanced(), do: %__MODULE__{width: 30, height: 16, num_mines: 99, type: :advanced}

  def custom(width, height, num_mines) do
    %__MODULE__{width: coerce_to_integer(width), height: coerce_to_integer(height), num_mines: coerce_to_integer(num_mines), type: :custom}
  end

  defp coerce_to_integer(i) when i |> is_integer(), do: i
  defp coerce_to_integer(s) when s |> is_binary(), do: String.to_integer(s)

  def valid?(%__MODULE__{} = c) do
    cond do
      c.width < 1 -> false
      c.width > 99 -> false
      c.height < 1 -> false
      c.height > 99 -> false
      c.num_mines < 1 -> false
      c.width * c.height <= c.num_mines -> false
      true -> true
    end
  end
end
