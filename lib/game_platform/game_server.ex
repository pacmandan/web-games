defmodule GamePlatform.GameServer do
  @moduledoc """
  Generic game server that runs game implementations.
  """
  alias GamePlatform.Notification
  use GenServer, restart: :transient

  require Logger

  @default_server_config %{
    game_timeout_length: :timer.minutes(30),
    player_disconnect_timeout_length: :timer.minutes(2),
  }

  @type game_spec_t :: {module(), any()}

  @type state_t :: %{
    game_id: String.t(),
    game_module: module(),
    game_config: map(),
    game_state: term(),
    server_config: map(),
    timeout_ref: reference(),
    connected_player_ids: MapSet.t(String.t()),
    connected_player_monitors: %{reference() => String.t()},
    player_timeout_refs: %{String.t() => reference()},
  }

  @doc """
  To start a game, it needs the following:
  - A game ID to register itself under. This should be a 4-letter string.
  - A game spec, consisting of a module that implements GameState, and a
    config map to pass to that module during initialization.
  - A server config, used to configure this server.
  """
  @spec start_link({String.t(), game_spec_t(), map()}) :: {:ok, pid()} | {:error, any()}
  def start_link({game_id, _game_spec, server_config} = init_arg) do
    if valid_server_config(server_config) do
      GenServer.start_link(__MODULE__, init_arg, name: via_tuple(game_id))
    else
      {:error, :invalid_config}
    end
  end

  @doc """
  Produces the via_tuple to find a GameServer pid from its ID.
  """
  @spec via_tuple(String.t()) :: {:via, Registry, {atom(), String.t()}}
  def via_tuple(id) do
    {:via, Registry, {GamePlatform.GameRegistry.registry_name(), id}}
  end

  defp valid_server_config(config) do
    Map.has_key?(config, :pubsub) &&
    Map.get(config, :game_timeout_length, @default_server_config[:game_timeout_length]) > 0 &&
    Map.get(config, :player_disconnect_timeout_length, @default_server_config[:player_disconnect_timeout_length]) > 0
  end

  @impl true
  @spec init({String.t(), game_spec_t(), map()}) :: {:ok, map(), {:continue, atom()}}
  def init({game_id, {game_module, game_config}, server_config}) do
    server_config = Map.merge(@default_server_config, server_config)

    init_state = %{
      game_id: game_id,
      game_module: game_module,
      game_config: game_config,
      game_state: nil,
      start_time: DateTime.utc_now(),
      start_time_mono: System.monotonic_time(),
      server_config: server_config,
      timeout_ref: nil,
      # TODO: Look more into Phoenix.Presence and Phoenix.Tracker to see if it could replace or augment this.
      connected_player_ids: MapSet.new(),
      connected_player_monitors: %{},
      player_timeout_refs: %{},
    }

    {:ok, init_state, {:continue, :init_game}}
  end

  @impl true
  def handle_continue(:init_game, state) do
    # TODO: Handle error in game state init
    # Initialize the game state using the provided "game_config".
    {:ok, game_state} = state.game_module.init(state.game_config)

    new_state = state
    |> Map.put(:game_state, game_state)
    |> schedule_game_timeout()

    # emit_game_start(state)

    {:noreply, new_state}
  end

  @impl true
  def handle_call({:join_game, player_id}, _from, state) do
    # Tell the game server a player is attempting to join.
    case state.game_module.join_game(state.game_state, player_id) do
      # A player joined the state, tell everyone about it.
      {:ok, topic_refs, notifications, new_game_state} ->
        send_notifications(notifications, state)
        # TODO: Should we cache these in the server state? (per-player?)
        # TODO: Send the topic refs instead of the topics
        # The "subscribe" function should live in the Notification module,
        # and should automatically translate refs to topic strings.
        topics = Enum.map(topic_refs, &(Notification.get_topic(&1, state.game_id)))

        new_state = state
        |> Map.put(:game_state, new_game_state)
        |> schedule_game_timeout()

        {:reply, {:ok, topics}, new_state}

      # The player was rejected for some reason.
      # Log it, but no need to send notifications.
      {:error, reason} ->
        # TODO: Log error
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:game_type, _from, state) do
    # Return the game module this server is running.
    {:reply, {:ok, state.game_module, state.game_module.game_view_module()}, state}
  end

  @impl true
  def handle_cast({:leave_game, player_id}, state) do
    do_remove_player(player_id, state)
  end

  @impl true
  def handle_cast({:game_event, from, event}, state) do
    # Only handle events from connected players.
    with true <- MapSet.member?(state.connected_player_ids, from),
      {:ok, notifications, new_game_state} <- state.game_module.handle_event(state.game_state, from, event)
    do
      new_state = state
      |> Map.replace(:game_state, new_game_state)
      |> schedule_game_timeout()

      send_notifications(notifications, state)

      {:noreply, new_state}
    else
      _error ->
        # TODO: Log error
        # Need to interpret this - can be either "false" or {:error, reason}
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:player_connected, player_id, pid}, state) do
    # Just in case this is a previously disconnected player,
    # cancel their timeout.
    state = state |> cancel_player_timeout(player_id)

    case state.game_module.player_connected(state.game_state, player_id) do
      {:ok, notifications, new_game_state} ->
        # Monitor connected player to see if/when they disconnect
        new_state = state
        |> Map.replace(:connected_player_monitors, Map.put(state.connected_player_monitors, Process.monitor(pid), player_id))
        |> Map.replace(:connected_player_ids, MapSet.put(state.connected_player_ids, player_id))
        |> Map.replace(:game_state, new_game_state)

        send_notifications(notifications, new_state)
        {:noreply, new_state}

      {:error, _reason} ->
        {:noreply, state}
    end
  end

  # This should be triggered by the monitors on connected players.
  @impl true
  def handle_info({:DOWN, ref, :process, _object, _reason}, state) do
    # Oh no! A player has disconnected!
    # Pop their monitor from connected players.
    {player_id, connected_player_monitors} = Map.pop(state.connected_player_monitors, ref)
    connected_player_ids = MapSet.delete(state.connected_player_ids, player_id)

    # Update the monitors and connected players maps before we tell the game state.
    state = state
    |> Map.replace(:connected_player_monitors, connected_player_monitors)
    |> Map.replace(:connected_player_ids, connected_player_ids)
    |> schedule_player_timeout(player_id)

    if player_id |> is_nil() do
      # Nevermind, this is probably not actually a connected player.
      {:noreply, state}
    else
      # Tell the game state that a player has disconnected
      case state.game_module.player_disconnected(state.game_state, player_id) do
        {:ok, notifications, new_game_state} ->
          new_state = state
          |> Map.replace(:game_state, new_game_state)

          send_notifications(notifications, new_state)
          {:noreply, new_state}

        {:error, _reason} ->
          # There was an error updating the state.
          {:noreply, state}
      end
    end
  end

  # Internal events, triggered via Process.send_after(self()) within the Game.schedule_event().
  # Essentially this is handle_cast({:game_event, :game, event}, state), if :game were a legal value in that call.
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

        send_notifications(notifications, new_state)

        {:noreply, new_state}

      {:error, _reason} ->
        # TODO: Log error
        {:noreply, state}
    end
  end

  def handle_info({:server_event, event}, state) do
    handle_server_event(event, state)
  end

  # :end_game and :game_timeout are functionally identical
  # However, they are semantically different.
  # :end_game is called from within the game state - the game itself has determined that it is over.
  # :game_timeout happens at the server level, and represents an idle timeout where nothing has happened.
  # TODO: Reflect the different stop conditions in metrics and logs
  defp handle_server_event(:end_game, state) do
    Logger.info("Game #{state.game_id} has ended normally")
    # emit_game_stop(state, :normal)
    halt_game(state)
  end

  defp handle_server_event(:game_timeout, state) do
    Logger.info("Game #{state.game_id} has timed out due to inactivity")
    # emit_game_stop(state, :game_timeout)
    halt_game(state)
  end

  defp handle_server_event({:player_disconnect_timeout, player_id}, state) do
    do_remove_player(player_id, state)
  end

  defp halt_game(state) do
    {:ok, notifications, new_game_state} = state.game_module.handle_game_shutdown(state.game_state)

    new_state = state
    |> Map.replace(:game_state, new_game_state)

    # TODO: Add a server-level notification (somehow)?
    send_notifications(notifications, new_state)
    {:stop, :normal, new_state}
  end

  # Remove the given player from the game.
  # This involves removing their monitors and connected lists, and cancelling any associated timeouts.
  defp do_remove_player(player_id, state) do
    # Pop the player from relevant lists
    monitor_ref = Enum.find(state.connected_player_monitors, fn {_, id} -> player_id == id end)
    connected_player_monitors = Map.drop(state.connected_player_monitors, [monitor_ref])
    connected_player_ids = MapSet.delete(state.connected_player_ids, player_id)

    # Stop monitoring if they're a connected player.
    unless monitor_ref |> is_nil(), do: Process.demonitor(monitor_ref)

    new_state = state
    |> Map.replace(:connected_player_monitors, connected_player_monitors)
    |> Map.replace(:connected_player_ids, connected_player_ids)
    |> cancel_player_timeout(player_id)
    |> end_game_if_no_one_is_here()

    # Tell the game state that this player is leaving.
    case state.game_module.leave_game(new_state.game_state, player_id) do
      {:ok, notifications, new_game_state} ->
        send_notifications(notifications, new_state)

        {:noreply, %{new_state | game_state: new_game_state}}
      {:error, _reason} ->
        {:noreply, new_state}
    end
  end

  defp send_notifications([], _), do: :ok
  defp send_notifications(notifications, state) do
    Notification.send_all(notifications, state.game_id, state.server_config.pubsub)
  end

  # This should be called when a player has disconnected.
  # After a timeout, this will call back to itself with `{:player_disconnect_timeout, player_id}`,
  # which will tell the game state that this player should be removed from the game.

  # If `:player_disconnect_timeout_length` in the server config is set to `:infinity`,
  # then this timeout is never scheduled.

  # If the player reconnects before the message can be sent, the scheduled message can be cancelled
  # by cancelling the timer ref stored in `state.player_timeout_refs[player_id]`.\
  defp schedule_player_timeout(state, player_id), do: schedule_player_timeout(state, player_id, state.server_config.player_disconnect_timeout_length)
  # Dropping this case, since due to how the config validation works right now, it's impossible.
  # defp schedule_player_timeout(state, _player_id, :infinity), do: state
  defp schedule_player_timeout(state, player_id, millis) when is_integer(millis) do
    timer_ref = send_self_server_event({:player_disconnect_timeout, player_id}, millis)
    state
    |> cancel_player_timeout(player_id)
    |> put_in([:player_timeout_refs, player_id], timer_ref)
  end

  # Cancels the players disconnect timeout, usually because that player has reconnected.
  defp cancel_player_timeout(state, player_id) do
    {timer_ref, player_timeout_refs} = Map.pop(state.player_timeout_refs, player_id)

    unless timer_ref |> is_nil(), do: Process.cancel_timer(timer_ref)

    Map.replace(state, :player_timeout_refs, player_timeout_refs)
  end

  # Cancels the internal game timeout
  defp cancel_game_timeout(state) do
    unless state.timeout_ref |> is_nil(), do: Process.cancel_timer(state.timeout_ref)
    # Map.put(state, :timeout_ref, nil)
    state
  end

  # Updates the game timeout.
  # If no time is provided, use the default in the config.
  # Breaking it out like this lets us do things like setting the timeout to a lower number after all players have left.
  defp schedule_game_timeout(state), do: schedule_game_timeout(state, state.server_config.game_timeout_length)
  defp schedule_game_timeout(state, millis) when is_integer(millis) do
    timer_ref = send_self_server_event(:game_timeout, millis)
    state
    |> cancel_game_timeout()
    |> Map.put(:timeout_ref, timer_ref)
  end

  defp end_game_if_no_one_is_here(state) do
    # The last connected player has left the game.
    # Since no one is here, end the game sooner rather than later.
    if state.connected_player_ids == MapSet.new() do
      # Do it as a game timeout, in case a player re-joins.
      # That way, when if a player _does_ decide to come back, it resets automatically.
      schedule_game_timeout(state, :timer.minutes(1))
    else
      state
    end
  end

  @doc """
  Sends a game event to itself.

  This is useful for internal game events not triggered by any particular players.
  (e.g. A timeout on a players turn, a tick to progress a real-time game, etc.)

  In the context of the game state, these are handled like normal events, except
  the "player_id" is set to `:game`.
  """
  def send_self_game_event(event, time \\ 0) do
    Process.send_after(self(), {:game_event, event}, time)
  end

  defp send_self_server_event(event, time) do
    Process.send_after(self(), {:server_event, event}, time)
  end

  def end_game(after_millis \\ 0) do
    send_self_server_event(:end_game, after_millis)
  end

  # # Telemetry functions
  # defp emit_game_start(state) do
  #   :telemetry.execute(
  #     [:game_platform, :server, :start],
  #     %{system_time: System.system_time()},
  #     %{game_id: state.game_id, game_type: state.game_module |> to_string()}
  #   )
  # end

  # defp emit_game_stop(state, status) do
  #   duration = System.monotonic_time() - state.start_time_mono

  #   :telemetry.execute(
  #     [:game_platform, :server, :stop],
  #     %{duration: duration},
  #     %{game_id: state.game_id, game_type: state.game_module |> to_string(), status: status |> to_string()}
  #   )
  # end
end
