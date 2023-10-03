defmodule WebGames.Minesweeper.Cell do
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

  @spec open(__MODULE__.t()) ::
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

  def click(nil), do: {:error, nil}
  def click(%__MODULE__{flagged?: true} = cell), do: {:noop, cell}
  def click(%__MODULE__{opened?: true} = cell), do: {:noop, cell}
  def click(%__MODULE__{clicked?: true} = cell), do: {:noop, cell}
  def click(%__MODULE__{} = cell), do: {:ok, %__MODULE__{cell | clicked?: true}}

  @spec toggle_flag(__MODULE__.t()) :: {:error, nil} | {:ok, __MODULE__.t()}
  def toggle_flag(nil), do: {:error, nil}
  def toggle_flag(%{opened?: true} = cell), do: {:ok, cell}
  def toggle_flag(%{flagged?: flagged} = cell), do: {:ok, %__MODULE__{cell | flagged?: !flagged}}

  def place_mine(nil), do: nil
  def place_mine(%__MODULE__{} = cell), do: %__MODULE__{cell | has_mine?: true}

  def increment_value(nil), do: nil
  def increment_value(%__MODULE__{value: value} = cell), do: %__MODULE__{cell | value: value + 1}

  def display_value(nil), do: nil
  def display_value(%__MODULE__{} = cell) do
    cond do
      cell.opened? -> cell.value |> to_string()
      cell.flagged? -> "F"
      true -> "."
    end
  end

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
