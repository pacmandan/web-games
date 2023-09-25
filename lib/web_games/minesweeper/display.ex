defmodule WebGames.Minesweeper.Display do
  def display_grid(game, cheat? \\ false) do
    num_width_digits = num_digits(game.w - 1)
    display_rows = Map.keys(game.grid)
    |> Enum.sort_by(fn {x, y} -> {y, x} end)
    |> Enum.map(fn space -> cell_to_string(game.grid[space], game.state, cheat?) end)
    |> Enum.chunk_every(game.w)
    |> Enum.zip(0..(game.h - 1))
    |> Enum.map(fn {row, index} ->
      "#{List.duplicate(" ", num_width_digits - num_digits(index)) |> Enum.join()}#{index}|#{Enum.join(row)}"
    end)

    display_state = case game.state do
      :win -> "WIN!"
      :lose -> "LOSE!"
      _ -> ""
    end

    IO.puts(display_state)

    leftpad = List.duplicate(" ", num_width_digits) |> Enum.join()
    if game.h > 100 do
      IO.puts("#{leftpad}|#{0..(game.w - 1) |> Enum.map_join("", &(nth_digit(&1, 3)))}")
    end
    if game.h > 10 do
      IO.puts("#{leftpad}|#{0..(game.w - 1) |> Enum.map_join("", &(nth_digit(&1, 2)))}")
    end
    IO.puts("#{leftpad}|#{0..(game.w - 1) |> Enum.map_join("", &(nth_digit(&1, 1)))}")
    IO.puts("--#{for _ <- 0..(game.w + num_width_digits - 1), do: "-"}")
    Enum.each(display_rows, &IO.puts/1)

    :ok
  end

  defp nth_digit(0, 1), do: "0"
  defp nth_digit(0, _), do: " "
  defp nth_digit(num, n) do
    divisor = :math.pow(10, n - 1) |> trunc()
    digit = rem(div(num, divisor), 10)
    if digit == 0 && divisor > num, do: " ", else: digit |> to_string()
  end

  defp num_digits(num) do
    next = div(num, 10)
    if next == 0, do: 1, else: 1 + num_digits(next)
  end

  defp cell_to_string(cell, state, cheat?) do
    cond do
      # The cell that made you go boom
      cell.has_mine? && cell.clicked? -> "+"
      # X where cells are hidden, shown either because you lost or you're cheating
      cell.has_mine? && (cheat? || state == :lose) -> "X"
      # F where a flag has been placed. When you win, all mines show as flags.
      (cell.has_mine? && state == :win) || cell.flagged? -> "F"
      # An open cell. On 0's, show a ".", otherwise show the numerical value.
      cell.opened? -> if cell.value == 0, do: ".", else: cell.value |> to_string()
      # Everything else that hasn't been clicked.
      true -> "*"
    end
  end
end
