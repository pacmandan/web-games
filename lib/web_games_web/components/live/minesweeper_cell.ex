defmodule WebGamesWeb.Live.MinesweeperCell do
  use WebGamesWeb, :live_component

  def render(assigns) do
    ~H"""
      <div style={"grid-column-start:#{@x};grid-row-start:#{@y}"} id={"cell_box_#{@x}_#{@y}"}>
        <div class={"w-8 h-8 #{@cell.background_color} #{@cell.text_color} #{@cell.border_color} border"}
          phx-click="click"
          phx-hook="MinesweeperFlag"
          phx-value-x={@x}
          phx-value-y={@y}
          id={"cell_click_#{@x}_#{@y}"}
        >
          <%= @cell.value %>
        </div>
      </div>
    """
  end
end
