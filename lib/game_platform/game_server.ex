defmodule GamePlatform.GameServer do
  alias GamePlatform.Notification
  use GenServer, restart: :transient

  @registry :game_registry
  @default_server_config %{
    timeout_length: :timer.minutes(30),
  }

  def start_link({game_id, _game_spec, server_config} = init_arg) do
    if valid_server_config(server_config) do
      GenServer.start_link(__MODULE__, init_arg, name: via_tuple(game_id))
    else
      {:error, :invalid_config}
    end
  end

  defp via_tuple(id) do
    {:via, Registry, {@registry, id}}
  end

  defp valid_server_config(config) do
    Map.has_key?(config, :pubsub)
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
    }

    {:ok, init_state, {:continue, :init_game}}
  end

  @impl true
  def handle_continue(:init_game, state) do
    timeout_ref = schedule_timeout(state)

    {:ok, game_state} = state.game_module.init(state.game_config)

    {:noreply, %{state | game_state: game_state, timeout_ref: timeout_ref}}
  end

  @impl true
  def handle_call({:join_game, player}, _from, state) do
    case state.game_module.add_player(state.game_state, player) do
      {:ok, topics, notifications, new_game_state} ->
        send_notifications(notifications, state)

        {:reply, {:ok, topics}, %{state | game_state: new_game_state}}

      {:error, reason} ->
        # TODO: Log error
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast({:game_event, _from, event}, state) do
    case state.game_module.handle_event(state.game_state, event) do
      {:ok, notifications, new_game_state} ->
        Process.cancel_timer(state.timeout_ref)
        new_timeout_ref = schedule_timeout(state)

        new_state = state
        |> Map.replace(:game_state, new_game_state)
        |> Map.replace(:timeout_ref, new_timeout_ref)

        send_notifications(notifications, state)

        {:noreply, new_state}

      {:error, _reason} ->
        # TODO: Log error
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:player_connected, player_id, pid}, state) do
    case state.game_module.player_connected(state.game_state, player_id, pid) do
      {:ok, notifications, new_game_state} ->
        send_notifications(notifications, state)
        {:noreply, %{state | game_state: new_game_state}}
      {:error, _reason} ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:game_timeout, state) do
    # TODO: Log game timeout
    # TODO: Send final notifications (get from game state)
    {:stop, :normal, state}
  end

  # Internal events, triggered via Process.send_after(self()) within the Game.schedule_event().
  @impl true
  def handle_info({:game_event, event}, state) do
    # TODO: When adding "from", use :game
    case state.game_module.handle_event(state.game_state, event) do
      {:ok, notifications, new_game_state} ->
        # Internal game events do not reset the timer.
        # Process.cancel_timer(state.timeout_ref)
        # new_timeout_ref = schedule_timeout(state)

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

  defp send_notifications(notifications, state) do
    Notification.send_all(notifications, state.game_id, state.server_config.pubsub)
  end

  defp schedule_timeout(state) do
    Process.send_after(self(), :game_timeout, state.server_config.timeout_length)
  end
end
