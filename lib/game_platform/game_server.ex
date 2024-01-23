defmodule GamePlatform.GameServer do
  @moduledoc """
  Generic game server that runs game implementations.
  """

  use GenServer, restart: :transient

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias GamePlatform.PubSubMessage
  alias GamePlatform.GameServer.InternalComms

  @default_server_config %{
    game_timeout_length: :timer.minutes(5),
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

  defmodule GameMessage do
    @moduledoc """
    Structure representing a packaged message _to_ the game server.
    """
    defstruct [
      :action,
      :payload,
      :from,
      :ctx,
    ]

    @type action ::
      :player_join
      | :player_connected
      | :game_event

    @type t :: %__MODULE__{
      action: action(),
      payload: term(),
      from: String.t() | atom() | nil,
      ctx: OpenTelemetry.Ctx.t(),
    }
  end

  @doc """
  This is the start_link() function called by GenServer when creating a
  new process.

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
    # TODO: Ensure timeouts cannot be too long.
    # TODO: Use Ecto for validation here so we can get better error messages.
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
  @spec handle_continue(:init_game, state_t()) :: {:noreply, state_t()}
  def handle_continue(:init_game, state) do
    Logger.info("Game #{state.game_id} initializing game state...", state_metadata(state))
    Tracer.with_span :gs_init_game, span_opts(state) do
      # Initialize the game state using the provided "game_config".
      # If this fails, it will crash the game server process.
      # For now, this is fine, as the game will simply fail to start.
      # However, it will give a weird error in the UI and not say why a game
      # didn't start. (It'll just say "game does not exist".)
      # TODO: Do a better job of communicating startup failures in the UI.
      {:ok, game_state} = state.game_module.init(state.game_config)

      new_state = state
      |> Map.put(:game_state, game_state)
      |> schedule_game_timeout()

      Logger.info("Game #{new_state.game_id} successfully initialized!", state_metadata(new_state))
      {:noreply, new_state}
    end
  end

  @impl true
  def handle_call(%GameMessage{action: :player_join} = msg, _from, state) do
    Logger.info("Game #{state.game_id} player #{msg.from} attempting to join...", state_metadata(state, player_id: msg.from, msg: msg))
    Tracer.with_span :gs_join_game, span_opts(state, [{:player_id, msg.from}], msg.ctx) do
      # Tell the game server a player is attempting to join.
      # Players will ALWAYS join "game:<game_id>" and "game:<game_id>:player:<player_id>".
      # Anything else is added by the game itself.
      # e.g. "game:<game_id>:players", "game:<game_id>:team:<team_id>",
      # "game:<game_id>:audience", etc.

      default_topics = [:all, {:player, msg.from}]

      case state.game_module.join_game(state.game_state, msg.from) do
        # A player joined the state, tell everyone about it.
        {:ok, topic_refs, msgs, new_game_state} ->
          # TODO: Broadcast player join to all connected players automatically.
          # Right now it's on the individual games to handle that part.
          broadcast_pubsub(msgs, state)
          # TODO: Send the topic refs instead of the topics
          # The "subscribe" function should live in the Notification module,
          # and should automatically translate refs to topic strings.
          topics = topic_refs
          |> Enum.concat(default_topics)
          |> Enum.uniq()
          |> Enum.map(&(PubSubMessage.get_topic(&1, state.game_id)))

          new_state = state
          |> Map.put(:game_state, new_game_state)
          |> schedule_game_timeout()

          Logger.info("Game #{new_state.game_id} player #{msg.from} successfully joined, given topics #{inspect(topics)}", state_metadata(new_state, player_id: msg.from, msg: msg, topics: topics))

          {:reply, {:ok, topics}, new_state}

        # The player was rejected for some reason.
        # Log it, but no need to send msgs.
        {:error, reason} ->
          Logger.error("Game #{state.game_id} rejected player #{msg.from} for reason: #{inspect(reason)}", state_metadata(state, player_id: msg.from, msg: msg, err: reason))
          {:reply, {:error, reason}, state}
      end
    end
  end

  @impl true
  def handle_call(:game_info, _from, state) do
    Logger.info("Game #{state.game_id} game info called.", state_metadata(state))
    Tracer.with_span :gs_game_info, span_opts(state) do
      # Return the game module this server is running.
      {:reply, state.game_module.game_info(), state}
    end
  end

  @impl true
  def handle_call(%GameMessage{action: :player_leave} = msg, _from, state) do
    Logger.info("Game #{state.game_id} player #{msg.from} leaving game...", state_metadata(state, player_id: msg.from, msg: msg))
    Tracer.with_span :gs_player_leave, span_opts(state, [{:player_id, msg.from}], msg.ctx) do
      {status, new_state} = do_remove_player(msg.from, state, :manual)
      {:reply, status, new_state}
    end
  end

  @impl true
  def handle_cast(%GameMessage{action: :game_event} = msg, state) do
    Logger.info("Game #{state.game_id} recieved an event from player #{msg.from}.", state_metadata(state, player_id: msg.from, msg: msg, event: msg.payload))
    # Not sure if "event" should be included here?
    # Maybe that should be up to the implementation to add?
    Tracer.with_span :gs_game_event, span_opts(state, [{:player_id, msg.from}, {:event, msg.payload |> inspect()}], msg.ctx) do
      # Only handle events from connected players.
      with true <- MapSet.member?(state.connected_player_ids, msg.from),
        {:ok, msgs, new_game_state} <- state.game_module.handle_event(state.game_state, msg.from, msg.payload)
      do
        new_state = state
        |> Map.replace(:game_state, new_game_state)
        |> schedule_game_timeout()

        broadcast_pubsub(msgs, state)

        {:noreply, new_state}
      else
        false ->
          # Ignore - we got a message from an unconnected player.
          Logger.warning("Game #{state.game_id} got a :game_event from an unconnected player, #{msg.from}.", state_metadata(state, player_id: msg.from, msg: msg, event: msg.payload))
          {:noreply, state}
        {:error, err} ->
          Logger.error("Game #{state.game_id} experienced an error on :game_event!", state_metadata(state, player_id: msg.from, msg: msg, event: msg.payload, error: err))
          # TODO: Message all players that there was an error.
          {:noreply, state}
      end
    end
  end

  @impl true
  def handle_cast(%GameMessage{action: :player_connected} = msg, state) do
    # Limit the number of connected players to 100.
    # TODO: Code is indented too far, break this up somehow.
    if MapSet.size(state.connected_player_ids) >= 100 do
      {:noreply, state}
    else
      Logger.info("Game #{state.game_id} player #{msg.from} attempting to connect...", state_metadata(state, player_id: msg.from, msg: msg))
      Tracer.with_span :gs_player_connected, span_opts(state, [{:player_id, msg.from}], msg.ctx) do
        # Just in case this is a previously disconnected player,
        # cancel their timeout.
        state = state |> cancel_player_timeout(msg.from)

        case state.game_module.player_connected(state.game_state, msg.from) do
          {:ok, msgs, new_game_state} ->
            # Monitor connected player to see if/when they disconnect

            new_state = if MapSet.member?(state.connected_player_ids, msg.from) do
              # This player is already connected - don't monitor them twice.
              state
            else
              state
              |> Map.replace(:connected_player_monitors, Map.put(state.connected_player_monitors, Process.monitor(msg.payload[:pid]), msg.from))
              |> Map.replace(:connected_player_ids, MapSet.put(state.connected_player_ids, msg.from))
            end
            |> Map.replace(:game_state, new_game_state)

            broadcast_pubsub(msgs, new_state)

            Logger.info("Game #{new_state.game_id} player #{msg.from} connected successfully!", state_metadata(new_state, player_id: msg.from, msg: msg))
            {:noreply, new_state}

          {:error, reason} ->
            Logger.error("Game #{state.game_id} failed to connect player #{msg.from} for reason: #{inspect(reason)}.", state_metadata(state, player_id: msg.from, msg: msg, err: reason))
            {:noreply, state}
        end
      end
    end
  end

  # This should be triggered by the monitors on connected players.
  @impl true
  def handle_info({:DOWN, ref, :process, _object, _reason}, state) do
    Logger.info("Game #{state.game_id} player disconnect message received!", state_metadata(state, ref: ref))
    Tracer.with_span :gs_player_disconnected, span_opts(state) do
      # Oh no! A player has disconnected!
      # Pop their monitor from connected players.
      {player_id, connected_player_monitors} = Map.pop(state.connected_player_monitors, ref)
      connected_player_ids = MapSet.delete(state.connected_player_ids, player_id)

      Tracer.set_attribute(:player_id, player_id)

      # Update the monitors and connected players maps before we tell the game state.
      state = state
      |> Map.replace(:connected_player_monitors, connected_player_monitors)
      |> Map.replace(:connected_player_ids, connected_player_ids)

      if player_id |> is_nil() do
        # Nevermind, this is probably not actually a connected player.
        Logger.warning("Game #{state.game_id} disconnect message recieved from player that doesn't exist or has already disconnected.", state_metadata(state, ref: ref))
        {:noreply, state}
      else
        # Schedule a timeout
        state = schedule_player_timeout(state, player_id)
        # Tell the game state that a player has disconnected
        case state.game_module.player_disconnected(state.game_state, player_id) do
          {:ok, msgs, new_game_state} ->
            new_state = state
            |> Map.replace(:game_state, new_game_state)

            broadcast_pubsub(msgs, new_state)

            Logger.info("Game #{state.game_id} player #{player_id} disconneced successfully.", state_metadata(state, ref: ref, player_id: player_id))
            {:noreply, new_state}

          {:error, reason} ->
            # There was an error updating the state.
            # Should this be inverted? Updating the game state first, then
            # the server state?
            Logger.error("Game #{state.game_id} failed to disconnect player #{player_id} for reason: #{inspect(reason)}", state_metadata(state, player_id: player_id, err: reason))
            {:noreply, state}
        end
      end
    end
  end

  # Internal events, triggered via Process.send_after(self()) within the schedule_event().
  # Essentially this is handle_cast({:game_event, :game, event}, state), if :game were a legal value in that call.
  # This is notibly also not wrapped in a %GameMessage%{}, an is instead just a tuple.
  # This possibly needs changing in the future to remain consistent.
  @impl true
  def handle_info({:game_event, event}, state) do
    # TODO: I'm not sure if this one should be traced, since it encompasses
    # real-time ticks. Might slow things down, and clutter results...
    case state.game_module.handle_event(state.game_state, :game, event) do
      {:ok, msgs, new_game_state} ->
        # Internal game events do not reset the timer.
        # InternalComms.cancel_scheduled_message(state.timeout_ref)
        # new_timeout_ref = schedule_game_timeout(state)

        new_state = state
        |> Map.replace(:game_state, new_game_state)
        # |> Map.replace(:timeout_ref, new_timeout_ref)

        broadcast_pubsub(msgs, state)

        {:noreply, new_state}

      {:error, _reason} ->
        Logger.error("Game #{state.game_id} failed to handle an internal game event!", state_metadata(state, event: event))
        {:noreply, state}
    end
  end

  # This is the primary way the game-specific module can communicate with this module.
  # Sending a message to itself with {:server_event, event}.

  # :end_game and :game_timeout are functionally identical
  # However, they are semantically different.
  # :end_game is called from within the game state - the game itself has determined that it is over.
  # :game_timeout happens at the server level, and represents an idle timeout where nothing has happened.

  def handle_info({:server_event, :end_game}, state) do
    Logger.info("Game #{state.game_id} told to end normally...", state_metadata(state))
    Tracer.with_span :gs_end_game, span_opts(state, [{:reason, "end_game"}]) do
      halt_game(state)
    end
  end

  def handle_info({:server_event, :game_timeout}, state) do
    Logger.info("Game #{state.game_id} has timed out due to inactivity...", state_metadata(state))
    Tracer.with_span :gs_end_game, span_opts(state, [{:reason, "game_timeout"}]) do
      halt_game(state)
    end
  end

  def handle_info({:server_event, {:player_disconnect_timeout, player_id}}, state) do
    Logger.info("Game #{state.game_id} player #{player_id} has disconnected and timed out!", state_metadata(state, player_id: player_id))
    Tracer.with_span :gs_player_disconnect_timeout, span_opts(state, [{:player_id, player_id}]) do
      {_, new_state} = do_remove_player(player_id, state, :player_disconnect_timeout)
      {:noreply, new_state}
    end
  end

  defp halt_game(state) do
    Logger.info("Game #{state.game_id} halting game...", state_metadata(state))
    case state.game_module.handle_game_shutdown(state.game_state) do
      {:ok, msgs, new_game_state} ->
        new_state = state
        |> Map.replace(:game_state, new_game_state)

        # TODO: Add a server-level notification?
        broadcast_pubsub(msgs, state)

        Logger.info("Game #{state.game_id} halted successfully!", state_metadata(state))
        {:stop, :normal, new_state}
      {:error, err} ->
        Logger.error("Game #{state.game_id} errored while handling shutdown - shutting down anyway.", state_metadata(state, error: err))
        {:stop, :normal, state}
      err ->
        # No matter what, we NEED to return :stop if told to halt.
        Logger.error("Game #{state.game_id} encountered unknown error while handling shutdown - shutting down anyway.", state_metadata(state, error: err))
        {:stop, :normal, state}
    end
  end

  # Remove the given player from the game.
  # This involves removing their monitors and connected lists, and cancelling any associated timeouts.
  defp do_remove_player(player_id, state, reason) do
    # Pop the player from relevant lists
    Logger.info("Game #{state.game_id} removing player #{player_id}...", state_metadata(state, player_id: player_id, reason: reason))
    new_state = case Enum.find(state.connected_player_monitors, fn {_, id} -> player_id == id end) do
      {monitor_ref, ^player_id} ->
        # Stop monitoring if they're a connected player.
        connected_player_monitors = Map.drop(state.connected_player_monitors, [monitor_ref])
        connected_player_ids = MapSet.delete(state.connected_player_ids, player_id)
        Process.demonitor(monitor_ref)

        Logger.info("Game #{state.game_id} removing a player #{player_id} that was connected.")

        state
        |> Map.replace(:connected_player_monitors, connected_player_monitors)
        |> Map.replace(:connected_player_ids, connected_player_ids)
        |> cancel_player_timeout(player_id)
        |> end_game_if_no_one_is_here()

        # TODO: Since this is a connected player, we should call player_disconnect first.
      nil ->
        # We are removing a player that has already disconnected.
        Logger.info("Game #{state.game_id} removing a player #{player_id} that has already disconnected or never existed.", state_metadata(state, player_id: player_id, reason: reason))
        state
        |> end_game_if_no_one_is_here()
    end

    # Tell the game state that this player is leaving.
    case state.game_module.leave_game(new_state.game_state, player_id, reason) do
      {:ok, msgs, new_game_state} ->
        broadcast_pubsub(msgs, state)

        {:ok, %{new_state | game_state: new_game_state}}
      {:error, err} ->
        # The game state has failed somehow. But we've already removed this player.
        # Do we want to invert this, only removing the player if the game
        # state removal is successful?
        # Might need to make some more sophisticated games to test cases on this.
        Logger.error("Game #{new_state.game_id} failed to remove player #{player_id} from game state for reason: #{inspect(err)}.", state_metadata(state, player_id: player_id, err: err))
        {{:error, err}, new_state}
    end
  end

  defp broadcast_pubsub([], _), do: :ok
  defp broadcast_pubsub(msgs, state) do
    PubSubMessage.broadcast_all(msgs, state.game_id, state.server_config.pubsub)
  end

  # defp broadcast_all_players(payload, state) do
  #   PubSubMessage.build(:all, payload, :server_event)
  #   |> List.wrap()
  #   |> broadcast_pubsub(state)
  # end

  # defp broadcast_player(payload, player_id, state) do
  #   PubSubMessage.build({:player, player_id}, payload, :server_event)
  #   |> List.wrap()
  #   |> broadcast_pubsub(state)
  # end

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
    timer_ref = InternalComms.schedule_player_disconnect_timeout(player_id, millis)
    state
    |> cancel_player_timeout(player_id)
    |> put_in([:player_timeout_refs, player_id], timer_ref)
  end

  defp span_opts(state, extra_attrs \\ []) do
    %{
      attributes: [
        {:game_id, state.game_id},
        {:game_module, state.game_module},
      ] ++ extra_attrs,
    }
  end

  defp span_opts(state, extra_attrs, ctx) do
    %{
      attributes: [
        {:game_id, state.game_id},
        {:game_module, state.game_module},
      ] ++ extra_attrs,
      links: [OpenTelemetry.link(ctx)]
    }
  end

  defp state_metadata(state, extra_attrs \\ []) do
    %{
      game_id: state.game_id,
      game_module: state.game_module,
    } |> Map.merge(Enum.into(extra_attrs, %{}))
  end

  # Cancels the players disconnect timeout, usually because that player has reconnected.
  defp cancel_player_timeout(state, player_id) do
    {timer_ref, player_timeout_refs} = Map.pop(state.player_timeout_refs, player_id)

    unless timer_ref |> is_nil(), do: InternalComms.cancel_scheduled_message(timer_ref)

    Map.replace(state, :player_timeout_refs, player_timeout_refs)
  end

  # Cancels the internal game timeout
  defp cancel_game_timeout(state) do
    unless state.timeout_ref |> is_nil(), do: InternalComms.cancel_scheduled_message(state.timeout_ref)
    # Map.put(state, :timeout_ref, nil)
    state
  end

  # Updates the game timeout.
  # If no time is provided, use the default in the config.
  # Breaking it out like this lets us do things like setting the timeout to a lower number after all players have left.
  defp schedule_game_timeout(state), do: schedule_game_timeout(state, state.server_config.game_timeout_length)
  defp schedule_game_timeout(state, millis) when is_integer(millis) do
    Logger.info("Game #{state.game_id} scheduling game timeout in #{millis} ms.", state_metadata(state))
    timer_ref = InternalComms.schedule_game_timeout(millis)
    state
    |> cancel_game_timeout()
    |> Map.put(:timeout_ref, timer_ref)
  end

  defp end_game_if_no_one_is_here(state) do
    # The last connected player has left the game.
    # Since no one is here, end the game sooner rather than later.
    if state.connected_player_ids == MapSet.new() do
      # Do it as a game timeout, in case a player re-joins.
      # That way, if a player _does_ decide to come back, it resets automatically.
      Logger.info("Game #{state.game_id}, no one is here, scheduling game timeout in 60s.", state_metadata(state))
      schedule_game_timeout(state, :timer.minutes(1))
    else
      state
    end
  end
end
