defmodule WebGames.Minesweeper.Cell do
  @moduledoc """
  Structure representing the state of a single grid cell.
  Contains information about the internal value, whether or not
  it is opened, mined, and/or flagged, etc.

  This module contains functions for manipulating a given cell.
  """
  defstruct [
    value: 0,
    opened?: false,
    has_mine?: false,
    flagged?: false,
    clicked?: false,
  ]

  @type t :: %__MODULE__{
    value: integer(),
    opened?: boolean(),
    has_mine?: boolean(),
    flagged?: boolean(),
    clicked?: boolean(),
  }

  @type display_t :: %{
    value: nil | integer(),
    opened?: boolean(),
    has_mine?: nil | boolean(),
    flagged?: boolean(),
    clicked?: boolean(),
  }

  @doc """
  Opens the given cell.

  Already opened or flagged cells cannot be opened.

  Returns the updated cell as well as an action describing next steps.
  * :ok -> Cell has been opened
  * :noop -> Cell cannot be opened
  * :boom -> Cell contained a mine, game should end
  * :cascade -> Cell had a zero value, open all adjacent cells

  ## Examples
    iex> Cell.open(%Cell{value: 2, opened?: false})
    {:ok, %Cell{value: 2, opened?: true}}

    iex> Cell.open(%Cell{opened?: true, value: 2})
    {:noop, %Cell{opened?: true, value: 2}}

    iex> Cell.open(%Cell{flagged?: true, opened?: false, value: 2})
    {:noop, %Cell{flagged?: true, opened?: false, value: 2}}

    iex> Cell.open(%Cell{has_mine?: true})
    {:boom, %Cell{has_mine?: true, opened?: true}}

    iex> Cell.open(%Cell{value: 0, opened?: false})
    {:cascade, %Cell{value: 0, opened?: true}}

    iex> Cell.open(nil)
    {:error, nil}
  """
  @spec open(__MODULE__.t() | nil) ::
    {:error, nil}
    | {:noop, __MODULE__.t()}
    | {:boom, __MODULE__.t()}
    | {:cascade, __MODULE__.t()}
    | {:ok, __MODULE__.t()}
  def open(nil), do: {:error, nil}
  def open(%__MODULE__{opened?: true} = cell), do: {:noop, cell}
  def open(%__MODULE__{flagged?: true} = cell), do: {:noop, cell}
  def open(%__MODULE__{has_mine?: true} = cell), do: {:boom, %__MODULE__{cell | opened?: true}}
  def open(%__MODULE__{value: 0} = cell), do: {:cascade, %__MODULE__{cell | opened?: true}}
  def open(%__MODULE__{} = cell), do: {:ok, %__MODULE__{cell | opened?: true}}

  @doc """
  Marks a given cell as having been "clicked". This is different from being
  "opened", as a cell can be opened without having been clicked.

  This status is mostly used for display, showing which mine the user
  stepped on if they lose.

  Flagged, already opened, and already clicked cells cannot be clicked.

  Returns the updated cell as well as a status.

  ## Examples
    iex> Cell.click(%Cell{flagged?: false, opened?: false, clicked?: false})
    {:ok, %Cell{flagged?: false, opened?: false, clicked?: true}}

    iex> Cell.click(%Cell{flagged?: true, opened?: false, clicked?: false})
    {:noop, %Cell{flagged?: true, opened?: false, clicked?: false}}

    iex> Cell.click(%Cell{flagged?: false, opened?: true, clicked?: false})
    {:noop, %Cell{flagged?: false, opened?: true, clicked?: false}}

    iex> Cell.click(%Cell{flagged?: false, opened?: false, clicked?: true})
    {:noop, %Cell{flagged?: false, opened?: false, clicked?: true}}

    iex> Cell.click(nil)
    {:error, nil}
  """
  @spec click(__MODULE__.t() | nil) ::
    {:error, nil}
    | {:noop, __MODULE__.t()}
    | {:ok, __MODULE__.t()}
  def click(nil), do: {:error, nil}
  def click(%__MODULE__{flagged?: true} = cell), do: {:noop, cell}
  def click(%__MODULE__{opened?: true} = cell), do: {:noop, cell}
  def click(%__MODULE__{clicked?: true} = cell), do: {:noop, cell}
  def click(%__MODULE__{} = cell), do: {:ok, %__MODULE__{cell | clicked?: true}}

  @doc """
  Updates the "flagged?" value of the cell.
  If it is flagged, it will become unflagged.
  If it is unflagged, it will become flagged.
  Open cells cannot be flagged, and will result in a noop.

  ## Examples
    iex> Cell.toggle_flag(%Cell{flagged?: true})
    {:ok, %Cell{flagged?: false}}

    iex> Cell.toggle_flag(%Cell{flagged?: false})
    {:ok, %Cell{flagged?: true}}

    iex> Cell.toggle_flag(%Cell{opened?: true, flagged?: false})
    {:noop, %Cell{opened?: true, flagged?: false}}

    iex> Cell.toggle_flag(nil)
    {:error, nil}
  """
  @spec toggle_flag(__MODULE__.t() | nil) ::
    {:error, nil}
    | {:noop, __MODULE__.t()}
    | {:ok, __MODULE__.t()}
  def toggle_flag(nil), do: {:error, nil}
  def toggle_flag(%{opened?: true} = cell), do: {:noop, cell}
  def toggle_flag(%{flagged?: flagged} = cell), do: {:ok, %__MODULE__{cell | flagged?: !flagged}}

  @doc """
  Adds a mine to the given cell.

  ## Examples
    iex> Cell.place_mine(%Cell{has_mine?: false})
    %Cell{has_mine?: true}

    iex> Cell.place_mine(%Cell{has_mine?: true})
    %Cell{has_mine?: true}

    iex> Cell.place_mine(nil)
    nil
  """
  @spec place_mine(__MODULE__.t() | nil) :: nil | __MODULE__.t()
  def place_mine(nil), do: nil
  def place_mine(%__MODULE__{} = cell), do: %__MODULE__{cell | has_mine?: true}

  @doc """
  Increments the value in the cell by 1.

  ## Examples
    iex> Cell.increment_value(%Cell{value: 0})
    %Cell{value: 1}

    iex> Cell.increment_value(%Cell{value: 5})
    %Cell{value: 6}

    iex> Cell.increment_value(nil)
    nil
  """
  @spec increment_value(__MODULE__.t() | nil) :: nil | __MODULE__.t()
  def increment_value(nil), do: nil
  def increment_value(%__MODULE__{value: value} = cell), do: %__MODULE__{cell | value: value + 1}

  @doc """
  Converts a Cell struct into a "display" version.
  This version contains no private information, such its value if it is
  unopened, and is safe to send to the players.

  Mines on unopened cells can be displayed by passing true to
  `show_unopened_mines?`. This is used to show mine positions at the end
  of games.

  ## Examples
    iex> cell = %Cell{
    ...>   opened?: false,
    ...>   clicked?: false,
    ...>   flagged?: true,
    ...>   has_mine?: true,
    ...>   value: 3,
    ...> }
    iex> Cell.display(cell, false)
    %{
      opened?: false,
      clicked?: false,
      flagged?: true,
      value: nil,
      has_mine?: nil,
    }
  """
  @spec display(__MODULE__.t() | nil, boolean()) :: nil | display_t()
  def display(nil, _), do: nil
  def display(%__MODULE__{} = cell, show_unopened_mines?) do
    %{
      opened?: cell.opened?,
      clicked?: cell.clicked?,
      flagged?: cell.flagged?,
      value: cond do
        cell.opened? && cell.has_mine? -> nil
        cell.opened? -> cell.value
        true -> nil
      end,
      has_mine?: cond do
        cell.opened? || show_unopened_mines? -> cell.has_mine?
        true -> nil
      end
    }
  end
end
