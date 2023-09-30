defmodule WebGamesWeb.MinesweeperComponents do
  use WebGamesWeb, :html

  def grid(assigns) do
    ~H"""
    <table id="grid">
      <tr :for={row <- 0..(@height-1)}>
        <td :for={column <- 0..(@width-1)}>
          <.cell value={@grid[{row, column}].value} x={row} y={column} />
        </td>
      </tr>
    </table>
    """
  end

  def cell(assigns) do
    # TODO: Have styling be dependent on cell value & properties
    # Pre-calculate this before render for each cell (diffrences should all be in "assigns")
    # TODO: If cell is open or flagged, don't include "phx-click".
    # TODO: Make the background a different color if opened
    # TODO: Make the background a different color if clicked & un-mined
    # TODO: Make the background a different color if clicked and mined (the space that made you lose)
    # TODO: Make each possible "value" a different color (1-8,F,X)
    # TODO: Disable all clicking if win or lose
    ~H"""
    <div class="w-8 h-8 bg-gray-300 border-black border"
      phx-click="click"
      phx-value-x={@x}
      phx-value-y={@y}
    >
      <%= @value %>
    </div>
    """
  end
end
