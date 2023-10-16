defmodule GamePlatform.Cache do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    table = :ets.new(:game_state_lookup, [:set, :protected, :named_table])
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:load_state, game_id}, _from, state) do
    res = case :ets.lookup(:game_state_lookup, game_id) do
      [{^game_id, game_state}] -> {:ok, game_state}
      [] -> {:error, :not_found}
    end
    {:reply, res, state}
  end

  @impl true
  def handle_cast({:save_state, game_id, game_state}, state) do
    # TODO: TTLS on game state
    :ets.insert(:game_state_lookup, {game_id, game_state})
    {:noreply, state}
  end

  def load_state(game_id) do
    GenServer.call(__MODULE__, {:load_state, game_id})
  end

  def save_state(game_id, state) do
    GenServer.cast(__MODULE__, {:save_state, game_id, state})
  end
end
