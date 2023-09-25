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

  def send_event(event, from, game_id) do
    GenServer.cast(via_tuple(game_id), {:game_event, from, event})
  end

  defp via_tuple(id) do
    {:via, Registry, {@registry, id}}
  end

  @impl true
  def init(%{id: id, state_module: module, config: config}) do
    # TODO: Add the first player join inside the continue
    {:ok, initial_state(id, module), {:continue, {:init_game, config}}}
  end

  @impl true
  def handle_continue({:init_game, config}, state) do
    {:ok, initial_game} = state.state_module.init(config)
    {:noreply, Map.replace(state, :game_state, initial_game)}
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
      {:ok, notifications, new_state} ->
        # TODO: Move notification broadcasting to a separate process
        for n <- notifications do
          case n.to do
            :all -> Phoenix.PubSub.broadcast(WebGames.PubSub, "game:#{state.game_id}", {:game_event, state.game_id, n.event})
            _ -> :ok
          end
        end
        {:noreply, new_state}
      {:error, _reason, _new_state} ->
        # TODO: Error handling
        {:noreply, state}
    end
  end
end
