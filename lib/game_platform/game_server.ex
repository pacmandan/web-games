defmodule GamePlatform.GameServer do
  alias GamePlatform.Notification
  use GenServer, restart: :transient

  @registry :game_registry
  @default_server_config %{
    game_timeout_length: :timer.minutes(30),
    player_disconnect_timeout_length: :timer.minutes(2),
  }

  def start_link({game_id, _game_spec, server_config} = init_arg) do
    if valid_server_config(server_config) do
      GenServer.start_link(__MODULE__, init_arg, name: via_tuple(game_id))
    else
      {:error, :invalid_config}
    end
  end

  def via_tuple(id) do
    {:via, Registry, {@registry, id}}
  end

  defp valid_server_config(config) do
    Map.has_key?(config, :pubsub)
    # TODO: Check if game_timeout_length is a positive integer
    # TODO: Check if player_disconnect_timeout_length is a positive integer
  end

  @impl true
  def init({game_id, {game_module, game_config}, server_config}) do
    server_config = Map.merge(@default_server_config, server_config)

    init_state = %{
      game_id: game_id,
      game_module: game_module,
      game_config: game_config,
      game_state: nil,
      server_config: server_config,
      timeout_ref: nil,
      connected_players: %{},
      player_timeout_refs: %{},
    }

    {:ok, init_state, {:continue, :init_game}}
  end

  @impl true
  def handle_continue(:init_game, state) do
    {:ok, game_state} = state.game_module.init(state.game_config)

    new_state = state
    |> Map.put(:game_state, game_state)
    |> schedule_game_timeout()

    {:noreply, new_state}
  end

  @impl true
  def handle_call({:join_game, player}, _from, state) do
    case state.game_module.join_game(state.game_state, player) do
      {:ok, {topic_refs, player_opts}, notifications, new_game_state} ->
        send_notifications(notifications, state)
        topics = Enum.map(topic_refs, &(Notification.get_topic(&1, state.game_id)))

        {:reply, {:ok, topics, player_opts}, %{state | game_state: new_game_state}}

      {:error, reason} ->
        # TODO: Log error
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:game_type, _from, state) do
    {:reply, {:ok, state.game_module.game_type(state.game_state)}, state}
  end

  @impl true
  def handle_cast({:leave_game, player_id}, state) do
    do_remove_player(player_id, state)
  end

  @impl true
  def handle_cast({:game_event, from, event}, state) do
    # TODO: Check if "from" is an ID of a connected player.
    case state.game_module.handle_event(state.game_state, from, event) do
      {:ok, notifications, new_game_state} ->
        new_state = state
        |> Map.replace(:game_state, new_game_state)
        |> schedule_game_timeout()

        send_notifications(notifications, state)

        {:noreply, new_state}

      {:error, _reason} ->
        # TODO: Log error
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:player_connected, player_id, pid}, state) do
    new_state = state
    |> cancel_player_timeout(player_id)

    case state.game_module.player_connected(state.game_state, player_id) do
      {:ok, notifications, new_game_state} ->
        # Monitor connected player to see if/when they disconnect
        connected_players = Map.put(new_state.connected_players, Process.monitor(pid), player_id)
        send_notifications(notifications, new_state)
        {:noreply, %{new_state | game_state: new_game_state, connected_players: connected_players}}
      {:error, _reason} ->
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(:game_timeout, state) do
    # TODO: Log game timeout
    # TODO: Send final notifications (get from game state)
    {:ok, notifications, new_state} = state.game_module.end_game(state.game_state)
    send_notifications(notifications, new_state)
    {:stop, :normal, new_state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _object, _reason}, state) do
    {player_id, connected_players} = Map.pop(state.connected_players, ref)
    case player_id do
      # This monitor probably isn't a disconnected player
      nil ->
        {:noreply, state}
      _ -> case state.game_module.player_disconnected(state.game_state, player_id) do
        {:ok, notifications, new_game_state} ->
          send_notifications(notifications, state)

          new_state = state
          |> Map.replace(:game_state, new_game_state)
          |> Map.replace(:connected_players, connected_players)
          |> schedule_player_timeout(player_id)

          {:noreply, new_state}
        {:error, _reason} ->
          {:noreply, state}
      end
    end
  end

  # Internal events, triggered via Process.send_after(self()) within the Game.schedule_event().
  @impl true
  def handle_info({:game_event, event}, state) do
    case state.game_module.handle_event(state.game_state, :game, event) do
      {:ok, notifications, new_game_state} ->
        # Internal game events do not reset the timer.
        # Process.cancel_timer(state.timeout_ref)
        # new_timeout_ref = schedule_game_timeout(state)

        new_state = state
        |> Map.replace(:game_state, new_game_state)
        # |> Map.replace(:timeout_ref, new_timeout_ref)

        send_notifications(notifications, state)

        {:noreply, new_state}

      {:error, _reason} ->
        # TODO: Log error
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:player_disconnect_timeout, player_id}, state) do
    do_remove_player(player_id, state)
  end

  defp do_remove_player(player_id, state) do
    monitor_ref = Enum.find(state.connected_players, fn {_, id} -> player_id == id end)
    connected_players = Map.drop(state.connected_players, [monitor_ref])

    unless monitor_ref |> is_nil(), do: Process.demonitor(monitor_ref)

    new_state = state
    |> Map.replace(:connected_players, connected_players)
    |> cancel_player_timeout(player_id)

    case state.game_module.leave_game(new_state.game_state, player_id) do
      {:ok, notifications, new_game_state} ->
        send_notifications(notifications, new_state)

        # TODO: If we remove the last player, set the game stop timeout for 2 minutes
        # Need some system for signalling the server to do stuff from within the game state...
        {:noreply, %{new_state | game_state: new_game_state}}
      {:error, _reason} ->
        {:noreply, new_state}
    end
  end

  defp send_notifications([], _), do: :ok
  defp send_notifications(notifications, state) do
    Notification.send_all(notifications, state.game_id, state.server_config.pubsub)
  end

  defp schedule_player_timeout(state, player_id) do
    case state.server_config.player_disconnect_timeout_length do
      :infinity ->
        state
      milis when is_integer(milis) ->
        timer_ref = Process.send_after(self(), {:player_disconnect_timeout, player_id}, milis)

        state
        |> cancel_player_timeout(player_id)
        |> put_in([:player_timeout_refs, player_id], timer_ref)
      _ ->
        throw "Invalid config: :player_disconnect_timeout_length"
    end
  end

  defp cancel_player_timeout(state, player_id) do
    {timer_ref, player_timeout_refs} = Map.pop(state.player_timeout_refs, player_id)

    unless timer_ref |> is_nil(), do: Process.cancel_timer(timer_ref)

    Map.replace(state, :player_timeout_refs, player_timeout_refs)
  end

  defp schedule_game_timeout(state) do
    case state.server_config.game_timeout_length do
      :infinity ->
        state
      milis when is_integer(milis) ->
        timer_ref = Process.send_after(self(), :game_timeout, milis)
        state
        |> cancel_game_timeout()
        |> Map.put(:timeout_ref, timer_ref)
      _ ->
        throw "Invalid config: :game_timeout_length"
    end
  end

  defp cancel_game_timeout(state) do
    unless state.timeout_ref |> is_nil(), do: Process.cancel_timer(state.timeout_ref)
    # Map.put(state, :timeout_ref, nil)
    state
  end

  def send_event_after(event, time) do
    Process.send_after(self(), {:game_event, event}, time)
  end
end
