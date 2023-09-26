defmodule GamePlatform.Game do
  use GenServer, restart: :transient

  @registry :game_registry

  def start_link(%{id: id, state_module: _, config: _} = init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: via_tuple(id))
  end

  defp initial_state(id, module) do
    %{
      game_id: id,
      state_module: module,
      game_state: %{}
    }
  end

  def add_player(player_id, game_id) do
    GenServer.cast(via_tuple(game_id), {:add_player, player_id})
  end

  def send_event(event, from, game_id) do
    GenServer.cast(via_tuple(game_id), {:game_event, from, event})
  end

  def player_connected(player_id, game_id) do
    IO.inspect("GAME PLAYER CONNECTED")
    GenServer.cast(via_tuple(game_id), {:player_connected, player_id})
  end

  defp via_tuple(id) do
    {:via, Registry, {@registry, id}}
  end

  @impl true
  def init(%{id: id, state_module: module, config: config, start_player_id: player_id}) do
    # TODO: Add the first player join inside the continue
    {:ok, initial_state(id, module), {:continue, {:init_game, config, player_id}}}
  end

  @impl true
  def handle_continue({:init_game, config, player_id}, state) do
    game = state.state_module.init(config)
    |> then(fn {:ok, game} -> game end)
    |> GamePlatform.GameState.add_player(player_id)

    {:noreply, Map.replace(state, :game_state, game)}
  end

  @impl true
  def handle_call(:end_game, _from, state) do
    # Send final game state to all players
    # Halt game
    {:stop, :normal, state}
  end

  @impl true
  def handle_cast({:game_event, _player_id, event}, state) do
    # TODO: Confirm player_id is in the game state
    # Send event to the game state module
    case state.state_module.handle_event(event, state.game_state) do
      {:ok, notifications, new_game_state} ->
        # TODO: Move notification broadcasting to a separate process
        new_state = %{state | game_state: new_game_state}
        send_notifications(notifications, new_state)
        {:noreply, new_state}
      {:error, _reason, _new_game_state} ->
        # TODO: Error handling
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:add_player, player_id}, state) do
    {:ok, notifications, new_game_state} = GamePlatform.GameState.add_player(state.game_state, player_id)
    new_state = %{state | game_state: new_game_state}

    send_notifications(notifications, new_state)

    {:noreply, new_state}
  end

  def handle_cast({:player_connected, player_id}, state) do
    IO.inspect("HANDLING PLAYER CONNECTED...")
    {:ok, notifications, new_game_state} = state.state_module.player_connected(state.game_state, player_id)
    new_state = %{state | game_state: new_game_state}

    send_notifications(notifications, new_state)

    {:noreply, new_state}
  end

  def send_notifications(notifications, state) do
    for n <- notifications do
      case n.to do
        :all ->
          IO.inspect("BROADCASTING TO ALL")
          Phoenix.PubSub.broadcast(WebGames.PubSub, "game:#{state.game_id}", {:game_event, state.game_id, n.event})
        {:player, player_id} ->
          IO.inspect("BROADCASTING TO PLAYER #{player_id}")
          Phoenix.PubSub.broadcast(WebGames.PubSub, "game:#{state.game_id}:player:#{player_id}", {:game_event, state.game_id, n.event})
        _ -> :ok
      end
    end
  end
end
