defmodule GamePlatform.Game do
  # TODO: Rename to "GameServer"?
  use GenServer, restart: :transient

  alias GamePlatform.GameServerConfig

  @registry :game_registry
  def start_link({game_id, %GameServerConfig{}} = init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: via_tuple(game_id))
  end

  defp initial_state(game_id, server_config) do
    %{
      game_id: game_id,
      config: server_config,
      status: :init,
      game_timer: nil,
      start_time: DateTime.utc_now(),
      game_state: nil,
    }
  end

  def add_player(player_id, game_id) do
    GenServer.cast(via_tuple(game_id), {:add_player, player_id})
  end

  def send_event(event, from, game_id) do
    GenServer.cast(via_tuple(game_id), {:game_event, from, event})
  end

  def player_connected(player_id, game_id) do
    GenServer.cast(via_tuple(game_id), {:player_connected, player_id})
  end

  def game_exists?(game_id) do
    Registry.lookup(@registry, game_id) |> Enum.count() > 0
  end

  defp via_tuple(id) do
    {:via, Registry, {@registry, id}}
  end

  @impl true
  def init({game_id, %GameServerConfig{} = server_config}) do
    # TODO: Validate config
    # Initialize the actual game state in continue in case this takes a while.
    {:ok, initial_state(game_id, server_config), {:continue, {:init_game, server_config}}}
  end

  @impl true
  def handle_continue({:init_game, server_config}, state) do
    game = GameServerConfig.initialize_game_state(server_config)

    # Kill this game after a certain point.
    timer_ref = Process.send_after(self(), :game_timeout, server_config.max_length)

    new_state = state
    |> Map.replace(:game_state, game)
    |> Map.replace(:status, :in_progress)
    |> Map.put(:game_timer, timer_ref)

    {:noreply, new_state}
  end

  @impl true
  def handle_call(:end_game, _from, state) do
    # TODO: Send final game state to all players
    stop_game(:normal, state)
  end

  @impl true
  def handle_cast({:game_event, _player_id, event}, state) do
    # TODO: Confirm player_id is in the game state
    # Send event to the game state module
    case state.config.game_state_module.handle_event(event, state.game_state) do
      {:ok, notifications, new_game_state} ->
        # TODO: Move notification broadcasting to a separate process
        new_state = %{state | game_state: new_game_state}
        send_notifications(notifications, new_state)
        {:noreply, new_state}
      {:error, _reason, _new_game_state} ->
        # TODO: Error handling
        {:noreply, state}
    end
    # TODO: If the game _ends_ from this event, need to handle that here.
    # TODO: When playing _AGIAN_ after the game ends, do we want to keep this same server?
    # TODO: Should we refresh the timer after each event?
  end

  @impl true
  def handle_cast({:add_player, player_id}, state) do
    # The game state should handle the logic for adding players
    # This is where logic for single-player, multiplayer, password-protected games, etc live,
    # since there's no way to handle ALL of those possible states here.
    {:ok, notifications, new_game_state} = state.config.game_state_module.add_player(state.game_state, player_id)
    new_state = %{state | game_state: new_game_state}

    send_notifications(notifications, new_state)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:player_connected, player_id}, state) do
    IO.inspect("HANDLING PLAYER CONNECTED...")
    # This shouldn't affect game state, but it MIGHT depending on the game.
    # Proceed as normal for sending notifications and such.
    # In theory, this should only send notifications to the connected player.
    # (Maybe to other players too to let them know?)
    {:ok, notifications, new_game_state} = state.config.game_state_module.player_connected(state.game_state, player_id)
    new_state = %{state | game_state: new_game_state}

    send_notifications(notifications, new_state)

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:game_timeout, state) do
    # TODO: Send final game state and END message to all players
    IO.inspect("GAME TIMEOUT!!")
    stop_game(:normal, state)
  end

  defp stop_game(reason, state) do
    # TODO: Adding the "game_ended" status is kind of superfluous here...
    stopped_state = state |> Map.replace(:status, :game_ended)
    {:stop, reason, stopped_state}
  end

  # TODO: Move this into the Notifications module
  defp send_notifications(notifications, state) do
    # TODO: Collate notifications - only ONE sent per player per update
    # TODO: Keep a "version" of game state that is sent with a notification
    for n <- notifications do
      case n.to do
        :all ->
          IO.inspect("BROADCASTING TO ALL")
          Phoenix.PubSub.broadcast(state.config.pubsub_name, "game:#{state.game_id}", {:game_event, state.game_id, n.event})
        {:player, player_id} ->
          IO.inspect("BROADCASTING TO PLAYER #{player_id}")
          Phoenix.PubSub.broadcast(state.config.pubsub_name, "game:#{state.game_id}:player:#{player_id}", {:game_event, state.game_id, n.event})
        _ -> :ok
      end
    end
  end
end
