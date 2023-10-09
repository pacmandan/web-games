defmodule WebGamesWeb.LightCycles.Play do
  alias GamePlatform.Game
  use WebGamesWeb, :live_view

  @assigns_keys [
    :game_state,
    :player_id,
    :game_id,
    :display,
  ]

  def mount(_params, %{"game_id" => game_id, "player_id" => player_id, "topics" => topics, "player_opts" => _player_opts}, socket) do
    if Game.game_exists?(game_id) do
      if connected?(socket) do
        Enum.each(topics, fn topic -> Phoenix.PubSub.subscribe(WebGames.PubSub, topic) end)
        Game.player_connected(player_id, game_id, self())
      end

      {:ok, assign(socket, %{game_state: nil, player_id: player_id, game_id: game_id, events: [], display: ""})}
    else
      {:ok, redirect(socket, to: "/select-game")}
    end
  end

  def handle_info({:game_event, _game_id, msgs}, socket) do
    new_assigns = Enum.reduce(msgs, Map.take(socket.assigns, @assigns_keys), fn msg, acc ->
      # IO.inspect("MSG: #{inspect(msg)}")
      process_event(msg, acc)
    end)
    # |> Map.put(:events, [msgs |> inspect() | socket.assigns[:events]])

    socket = socket
    |> assign(new_assigns)
    |> draw_grid()

    {:noreply, socket}
  end

  defp process_event(:start_game, assigns) do
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

  def handle_event("turn", %{"key" => key}, %{assigns: %{game_state: %{current_state: :play}}} = socket) do
    player = get_player(socket)
    # IO.inspect("PLAYER")
    # IO.inspect(player)
    case key do
      "w" ->
        Game.send_event({:turn, :north, player[:location]}, socket.assigns[:player_id], socket.assigns[:game_id])
      "s" ->
        Game.send_event({:turn, :south, player[:location]}, socket.assigns[:player_id], socket.assigns[:game_id])
      "a" ->
        Game.send_event({:turn, :west, player[:location]}, socket.assigns[:player_id], socket.assigns[:game_id])
      "d" ->
        Game.send_event({:turn, :east, player[:location]}, socket.assigns[:player_id], socket.assigns[:game_id])
      _ -> :ok
    end

    {:noreply, socket}
  end

  def handle_event("turn", %{"key" => _}, socket) do
    {:noreply, socket}
  end

  defp get_player(socket) do
    # IO.inspect("SOCKET ASSIGNS")
    # IO.inspect(socket.assigns)
    id = socket.assigns[:player_id]
    socket.assigns[:game_state][:players][id]
  end
end
