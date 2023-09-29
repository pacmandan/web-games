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
    ~H"""
    <div style="width:32px;height:32px;background-color:grey;border-color:black;border-width:thin"
      phx-click="click"
      phx-value-x={@x}
      phx-value-y={@y}
    >
      <%= @value %>
    </div>
    """
  end
end
