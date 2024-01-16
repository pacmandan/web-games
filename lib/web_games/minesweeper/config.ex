defmodule WebGames.Minesweeper.Config do
  @moduledoc """
  Config object for a game of Minesweeper.

  Contains all options for starting a new game.
  """
  defstruct [
    :type,
    width: 10,
    height: 10,
    num_mines: 10,
  ]

  @type t :: %__MODULE__{
    width: non_neg_integer(),
    height: non_neg_integer(),
    num_mines: non_neg_integer(),
  }

  @type string_or_int :: non_neg_integer() | String.t()

  @doc """
  Config for a "beginner" game.
  Generates a 9x9 grid with 10 mines.
  """
  @spec beginner() :: __MODULE__.t()
  def beginner(), do: %__MODULE__{width: 9, height: 9, num_mines: 10, type: :beginner}

  @doc """
  Config for an "intermidiate" game.
  Generates a 16x16 grid with 40 mines.
  """
  @spec intermediate() :: __MODULE__.t()
  def intermediate(), do: %__MODULE__{width: 16, height: 16, num_mines: 40, type: :intermediate}

  @doc """
  Config for an "advanced" game.
  Generates a 30x16 grid with 99 mines.
  """
  @spec advanced() :: __MODULE__.t()
  def advanced(), do: %__MODULE__{width: 30, height: 16, num_mines: 99, type: :advanced}

  @doc """
  Creates a "custom" game with the given height, width, and number of mines.
  This game will have the type `:custom` when displayed.
  """
  @spec custom(string_or_int(), string_or_int(), string_or_int()) ::
    __MODULE__.t()
  def custom(width, height, num_mines) do
    %__MODULE__{width: coerce_to_integer(width), height: coerce_to_integer(height), num_mines: coerce_to_integer(num_mines), type: :custom}
  end

  defp coerce_to_integer(i) when i |> is_integer(), do: i
  defp coerce_to_integer(s) when s |> is_binary(), do: String.to_integer(s)

  @doc """
  Checks if a Config is valid or not.

  A config is considered valid if:
  * The height is set and is between 1 and 99
  * The width is set and is between 1 and 99
  * The number of mines is set and is smaller than the number of spaces in the grid.

  ## Examples
    iex> conf = %Config{
    ...>   height: 10,
    ...>   width: 10,
    ...>   num_mines: 15,
    ...> }
    iex> Config.valid?(conf)
    true

    iex> conf = %Config{
    ...>   height: 10,
    ...>   width: 10,
    ...>   num_mines: 101,
    ...> }
    iex> Config.valid?(conf)
    false
  """
  @spec valid?(__MODULE__.t()) :: boolean()
  def valid?(%__MODULE__{} = c) do
    cond do
      c.width |> is_nil() -> false
      c.width < 1 -> false
      c.width > 99 -> false
      c.height |> is_nil() -> false
      c.height < 1 -> false
      c.height > 99 -> false
      c.num_mines |> is_nil() -> false
      c.num_mines < 1 -> false
      c.width * c.height <= c.num_mines -> false
      true -> true
    end
  end
end
