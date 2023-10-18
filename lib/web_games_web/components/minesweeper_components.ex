defmodule WebGamesWeb.MinesweeperComponents do
  use WebGamesWeb, :html

  def grid(assigns) do
    ~H"""
    <table id="grid">
      <tr :for={row <- 1..(@width)}>
        <td :for={column <- 1..(@height)}>
          <.cell cell={@grid[{column, row}]} x={column} y={row} />
        </td>
      </tr>
    </table>
    """
  end

  def grid2(assigns) do
    ~H"""
    <div style={"display:grid; grid-template-columns:repeat(#{@width},32px); grid-template-rows:repeat(#{@height},32px);"}>
      <%= for {{x,y}, cell} <- @grid do %>
        <div id={"p#{x}_#{y}"} style={"grid-column-start:#{x};grid-row-start:#{y}"}>
          <.cell cell={cell} x={x} y={y} />
        </div>
      <% end %>
    </div>
    """
  end

  def cell(assigns) do
    ~H"""
    <div class={"w-8 h-8 #{@cell.background_color} #{@cell.text_color} #{@cell.border_color} border"}
      phx-click="click"
      phx-hook="MinesweeperFlag"
      phx-value-x={@x}
      phx-value-y={@y}
      id={"cell_#{@x}_#{@y}"}
    >
      <%= @cell.value %>
    </div>
    """
  end
end
