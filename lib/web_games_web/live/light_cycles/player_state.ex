defmodule WebGamesWeb.LightCycles.PlayerState do
  use GamePlatform.PlayerState

  alias GamePlatform.Game

  @assigns_keys [
    :game_state,
    :player_id,
    :game_id,
    :display,
  ]

  def init(socket) do
    {:ok, assign(socket, init_assigns())}
  end

  defp init_assigns() do
    %{
      game_state: nil,
      display: "",
    }
  end

  def handle_game_event(socket, msgs), do: process_events(socket, msgs)
  def handle_sync(socket, msgs), do: process_events(socket, msgs)

  def handle_info({:display_event, _game_id, :clear_display}, socket) do
    {:noreply, assign(socket, %{display: ""})}
  end

  def handle_event("turn", %{"key" => key}, %{assigns: %{game_state: %{current_state: :play}}} = socket) do
    player = get_player(socket)
    # IO.inspect("PLAYER")
    # IO.inspect(player)
    case key do
      "ArrowUp" ->
        Game.send_event({:turn, :north, player[:location]}, socket.assigns[:player_id], socket.assigns[:game_id])
      "ArrowDown" ->
        Game.send_event({:turn, :south, player[:location]}, socket.assigns[:player_id], socket.assigns[:game_id])
      "ArrowLeft" ->
        Game.send_event({:turn, :west, player[:location]}, socket.assigns[:player_id], socket.assigns[:game_id])
      "ArrowRight" ->
        Game.send_event({:turn, :east, player[:location]}, socket.assigns[:player_id], socket.assigns[:game_id])
      _ -> :ok
    end

    {:noreply, socket}
  end

  def handle_event("turn", %{"key" => _}, socket) do
    {:noreply, socket}
  end

  defp process_events(socket, msgs) do
    new_assigns = Enum.reduce(msgs, Map.take(socket.assigns, @assigns_keys), &process_event/2)

    socket = socket
    |> assign(new_assigns)
    |> draw_grid()

    socket
  end

  defp process_event(:start_game, assigns) do
    Process.send_after(self(), {:display_event, assigns.game_id, :clear_display}, :timer.seconds(2))
    %{assigns | display: "GO!"}
  end

  defp process_event({:countdown, n}, assigns) do
    %{assigns | display: "#{n}..."}
  end

  defp process_event({:sync, game_state}, assigns) do
    %{assigns | game_state: game_state}
  end

  defp process_event({:tick, game_state}, assigns) do
    %{assigns | game_state: game_state}
  end

  defp process_event(_, assigns) do
    assigns
  end

  defp draw_grid(%{assigns: %{game_state: %{current_state: :play}}} = socket) do

    players = Enum.map(socket.assigns.game_state.players, fn {_, player} -> display_player(player) end)

    push_event(socket, "draw", %{players: players})
  end

  defp draw_grid(socket), do: socket

  defp display_player(player) do
    points = Enum.map(player.turns, fn {{x, y}, _} -> [x * 5, y * 5] end)
    |> then(fn point_list ->
      {x, y} = player.location
      [[x * 5, y * 5] | point_list]
    end)

    %{points: points, color: player.config.color}
  end

  defp get_player(socket) do
    # IO.inspect("SOCKET ASSIGNS")
    # IO.inspect(socket.assigns)
    id = socket.assigns[:player_id]
    socket.assigns[:game_state][:players][id]
  end
end
