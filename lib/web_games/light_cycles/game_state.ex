defmodule WebGames.LightCycles.GameState do
  alias GamePlatform.Notification
  alias GamePlatform.GameServer

  use GamePlatform.GameState, view_module: WebGamesWeb.LightCycles.PlayerState

  defstruct [
    free_spaces: MapSet.new(),
    players: %{},
    current_state: :init,
    notifications: [],
    timer_ref: nil,
    ticks: 0,
    height: nil,
    width: nil,
  ]

  @behaviour Access
  @impl true
  defdelegate fetch(v, key), to: Map
  @impl true
  defdelegate get_and_update(v, key, func), to: Map
  @impl true
  def pop(v, key), do: {v[key], v}

  @tick_interval 50

  @max_players 4

  @colors [
    "#3b82f6",
    "#ef4444",
    "#22c55e",
    "#fef08a",
  ]

  @type player_config_t :: %{
    color: String.t(),
    name: String.t(),
    player_number: integer(),
    role: :player,
  }

  @type player_t :: %{
    config: player_config_t(),
    status: :init | :ready | :running | :crashed,
    spaces: MapSet.t(),
    location: point(),
    turns: list(turn()),
    next_turn: turn(),
  }

  @type point :: {integer(), integer()}
  @type direction :: :north | :south | :east | :west
  @type turn :: {point(), direction()}

  @type t :: %__MODULE__{
    free_spaces: MapSet.t(),
    players: %{String.t() => player_t()},
    current_state: :init | :ready | :play | :paused | :end,
    notifications: [],
    timer_ref: any(),
    ticks: integer(),
  }

  @impl true
  def init(config) do
    state = %__MODULE__{
      free_spaces: MapSet.new(generate_blank_grid(config.width, config.height)),
      height: config.height,
      width: config.width,
    }

    # TODO: Remove to allow multiplayer!
    GameServer.send_self_game_event(:start_game, 1500)

    {:ok, state}
  end

  @impl true
  def join_game(%__MODULE__{} = game_state, player_id) do
    cond do
      existing_player?(game_state, player_id) ->
        # This is an existing player joining or re-joining.
        {:ok, player_topics(player_id), [], game_state}

      game_state.current_state == :init && game_state.players |> Kernel.map_size() < @max_players ->
        # A new player is attempting to join,
        # we're in the state of the game that allows that,
        # and we're not full on players.

        # Add this player to the state.

        new_state = add_player(game_state, player_id)

        n = Notification.build(:all, {:player_added, new_state.players[player_id].config})

        {:ok, player_topics(player_id), [n], new_state}

      true ->
        {:error, :cannot_join}
    end
  end

  defp existing_player?(%__MODULE__{} = game_state, player_id) do
    Map.has_key?(game_state.players, player_id)
  end

  def add_player(%__MODULE__{} = game_state, player_id) do
    # Add player to config with default config for the players position.
    player_number = (game_state.players |> Kernel.map_size()) + 1
    {point, _facing} = turn = starting_turn(game_state, player_number)
    new_player_state = %{
      config: %{
        color: Enum.at(@colors, player_number - 1),
        name: nil,
        player_number: player_number,
        role: :player,
      },
      status: :init,
      spaces: MapSet.new(),
      location: point,
      turns: [turn],
      next_turn: nil,
    }

    game_state.players
    |> Map.put_new(player_id, new_player_state)
    |> then(fn players -> Map.replace(game_state, :players, players) end)
  end

  defp starting_turn(game_state, 1), do: {{1, game_state.height - 1}, :east}
  defp starting_turn(game_state, 2), do: {{game_state.width - 1, 1}, :west}
  defp starting_turn(game_state, 3), do: {{game_state.width - 1, game_state.height - 1}, :west}
  defp starting_turn(_game_state, 4), do: {{1, 1}, :east}
  defp starting_turn(_, _), do: throw "Too many players"

  defp player_topics(player_id), do: [
    :all,
    {:player, player_id}
  ]

  @impl true
  def player_connected(%__MODULE__{} = game_state, player_id) do
    case game_state.players[player_id] do
      nil -> {:ok, [], game_state}
      _player_state ->
        n = [
          Notification.build(:all, {:player_connected, player_id}),
          Notification.build({:player, player_id}, {:sync, display_state(game_state)}, :sync)
        ]

        {:ok, n, game_state}
    end
  end

  defp display_state(game_state) do
    Map.take(game_state, [:players, :width, :height, :ticks, :current_state])
  end

  @impl true
  def player_disconnected(%__MODULE__{} = game_state, player_id) do
    if game_state.players[player_id] do
      n = Notification.build(:all, {:player_disconnected, player_id})
      {:ok, [n], game_state}
    else
      {:ok, [], game_state}
    end
  end

  # @impl true
  # def leave_game(%__MODULE__{} = game_state, _player_id) do
  #   {:ok, [], game_state}
  # end

  @impl true
  def handle_event(%__MODULE__{current_state: :init} = game_state, player_id, {:player_config, opts}) do
    if game_state.players[player_id] do
      # If player exists, set player config in state
      # Set player_state to :init
      opts = Map.take(opts, [:name, :color])
      current_config = game_state.players[player_id].config
      new_config = Map.merge(current_config, opts)
      new_state = put_in(game_state, [:players, player_id, :config], new_config)

      n = Notification.build(:all, {:player_config_change, player_id, new_config})

      {:ok, [n], new_state}
    else
      {:ok, [], game_state}
    end
  end

  @impl true
  def handle_event(game_state, _, {:set_config, _}), do: {:ok, [], game_state}

  def handle_event(%__MODULE__{current_state: :init} = game_state, player_id, :player_ready) do
    if game_state.players[player_id] do
      # If player exists, set player config in state and add notifications
      # If all players are ready, add :all_players_ready to notifications
      {n, g} = game_state
      |> put_in([:players, player_id, :status], :ready)
      |> add_notification(:all, {:player_ready, player_id})
      |> check_players_ready()
      |> take_notifications()

      {:ok, n, g}
    else
      {:ok, [], game_state}
    end
  end

  def handle_event(game_state, _, :player_ready), do: {:ok, [], game_state}

  def handle_event(%__MODULE__{current_state: :init} = game_state, _, :start_game) do
    new_player_state = Enum.into(game_state.players, %{}, fn {player_id, player_state} ->
      {player_id, %{player_state | status: :running}}
    end)

    new_state = game_state
    |> Map.replace(:players, new_player_state)
    |> Map.replace(:current_state, :ready)

    schedule_countdown()
    {:ok, [Notification.build(:all, :start_countdown)], new_state}
  end

  def handle_event(game_state, _, :start_game), do: {:ok, [], game_state}

  def handle_event(%__MODULE__{current_state: :ready} = game_state, :game, {:countdown, n}) do
    case n do
      3 ->
        {:ok, [Notification.build(:all, {:countdown, 3})], game_state}
      2 ->
        {:ok, [Notification.build(:all, {:countdown, 2})], game_state}
      1 ->
        {:ok, [Notification.build(:all, {:countdown, 1})], game_state}
      0 ->
        new_state = game_state
        |> start_game()

        {:ok, [Notification.build(:all, :start_game)], new_state}
      _ ->
        {:error, :invalid_countdown}
    end
  end

  def handle_event(game_state, _, {:countdown, _}), do: {:ok, [], game_state}

  def handle_event(%__MODULE__{current_state: :play} = game_state, :game, :tick) do
    new_state = game_state.players
    |> Enum.filter(fn {_, player_state} -> player_state.status === :running end)
    # Randomize the order to not give advantage to player 1.
    |> Enum.shuffle()
    |> Enum.reduce(game_state, fn {player_id, player_state}, acc_state ->
      # Set current facing direction to next facing direction
      player_state = turn_player(player_state)
      # Determine "next" space based on facing direction
      next = next_space(player_state.location, get_player_facing(player_state))
      if space_free?(next, acc_state) do
        # Move the player to the next space
        player_state = player_state
        |> Map.replace(:location, next)
        |> Map.replace(:spaces, MapSet.put(player_state.spaces, next))

        # Remove next from free spaces
        acc_state
        |> Map.replace(:free_spaces, MapSet.delete(acc_state.free_spaces, next))
        |> put_in([:players, player_id], player_state)
      else
        # Otherwise, crash
        # - Return all player spaces for crashed player to "free"
        acc_state
        |> put_in([:players, player_id, :location], next)
        |> put_in([:players, player_id, :status], :crashed)
        |> Map.replace(:free_spaces, MapSet.union(acc_state.free_spaces, player_state.spaces))
        |> put_in([:players, player_id, :spaces], MapSet.new())
        |> add_notification(:all, {:crashed, player_id})
      end
    end)

    active_players = Enum.filter(new_state.players, fn {_, %{status: status}} -> status === :running end)

    {n, g} = case Enum.count(active_players) do
      # 1 ->
      #   # Winner
      #   [{winner_id, _winner_state}] = active_players
      #   new_state
      #   # TODO: Pause game
      #   |> add_notification(:all, {:winner, winner_id})
      0 ->
        # Tie
        GameServer.end_game(:timer.minutes(2))
        new_state
        |> add_notification(:all, :draw)
        |> pause_game()
      _n ->
        # Keep playing
        new_state
    end
    |> Map.replace(:ticks, new_state.ticks + 1)
    |> then(fn state -> add_notification(state, :all, {:tick, display_state(state)}) end)
    |> take_notifications()

    {:ok, n, g}
  end

  def handle_event(game_state, _, :tick) do
    # Game shouldn't be running, pause the game if it isn't already
    {:ok, [], game_state}
  end

  def handle_event(%__MODULE__{current_state: :play} = game_state, player_id, {:turn, direction, turn_at_point}) do
    with player_state when not is_nil(player_state) <- game_state.players[player_id],
      {last_turn_point, facing} <- player_state.turns |> hd(),
      true <- allowed_turn?(facing, direction),
      true <- is_point_ahead?(last_turn_point, facing, turn_at_point)
    do
      # Set next facing direction of player, if it's a legal turn.
      new_state = player_state
      |> Map.replace(:next_turn, {turn_at_point, direction})
      |> then(fn new_player_state -> put_in(game_state, [:players, player_id], new_player_state) end)

      # No notifications here - the update will happen on the next tick.
      {:ok, [], new_state}
    else
      _ -> {:ok, [], game_state}
    end
  end

  def handle_event(game_state, _, {:turn, _, _}), do: {:ok, [], game_state}

  @impl true
  def handle_game_shutdown(game_state) do
    n = Notification.build(:all, :end_game)
    {:ok, [n], pause_game(game_state)}
  end

  defp check_players_ready(game_state) do
    if all_players_ready?(game_state) do
      game_state
      |> add_notification(:all, :all_players_ready)
    else
      game_state
    end
  end

  defp all_players_ready?(%__MODULE__{players: players}) do
    Enum.all?(players, fn {_, state} ->
      state.status === :ready
    end)
  end

  defp schedule_countdown() do
    GameServer.send_self_game_event({:countdown, 3}, :timer.seconds(1))
    GameServer.send_self_game_event({:countdown, 2}, :timer.seconds(2))
    GameServer.send_self_game_event({:countdown, 1}, :timer.seconds(3))
    GameServer.send_self_game_event({:countdown, 0}, :timer.seconds(4))
  end

  defp turn_player(%{next_turn: nil} = player_state), do: player_state
  defp turn_player(%{next_turn: {_point, facing}, turns: turns, location: location} = player_state) do
    %{player_state | next_turn: nil, turns: [{location, facing} | turns]}
  end

  defp next_space({x, y}, facing) do
    case facing do
      :north -> {x, y - 1}
      :south -> {x, y + 1}
      :east -> {x + 1, y}
      :west -> {x - 1, y}
      _ -> throw "Invalid facing direction"
    end
  end

  defp space_free?(point, %__MODULE__{free_spaces: free} = _game_state) do
    MapSet.member?(free, point)
  end

  defp allowed_turn?(current_facing, next_facing) do
    case current_facing do
      :north -> next_facing in [:west, :north, :east]
      :south -> next_facing in [:west, :south, :east]
      :east -> next_facing in [:south, :north, :east]
      :west -> next_facing in [:west, :north, :south]
      _ -> throw "Invalid facing direction"
    end
  end

  defp is_point_ahead?({x, y} = _current_point, facing, {nx, ny} = _next_point) do
    case facing do
      :north ->
        x === nx && y >= ny
      :south ->
        x === nx && y <= ny
      :east ->
        x <= nx && y === ny
      :west ->
        x >= nx && y === ny
    end
  end

  defp get_player_facing(%{turns: [{_, facing} | _]}), do: facing

  defp take_notifications(game) do
    {Notification.collate_notifications(game.notifications), struct(game, notifications: [])}
  end

  defp add_notification(game, to, msg) do
    %__MODULE__{game | notifications: [Notification.build(to, msg) | game.notifications]}
  end

  defp generate_blank_grid(width, height) do
    for x <- 0..(width - 1), y <- 0..(height - 1), do: {x, y}
  end

  defp start_game(%__MODULE__{} = game_state) do
    # If there's already a ticker going, halt it immediately.
    pause_game(game_state)

    # This needs to be something that can be handled by :handle_info
    # in the parent GameServer, which is why we need :game_event.
    {:ok, ref} = :timer.send_interval(@tick_interval, {:game_event, :tick})
    %__MODULE__{game_state | timer_ref: ref, current_state: :play}
  end

  defp pause_game(%__MODULE__{} = game_state) do
    if game_state.timer_ref do
      {:ok, :cancel} = :timer.cancel(game_state.timer_ref)
    end
    %__MODULE__{game_state | timer_ref: nil, current_state: :paused}
  end
end
