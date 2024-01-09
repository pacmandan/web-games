defmodule GamePlatform.MockGameState do
  use GamePlatform.GameState,
    view_module: GamePlatform.MockGameView,
    display_name: "MOCK_GAME"

  def init(%{conf: :failed}) do
    {:error, :invalid_config}
  end

  def init(_game_config) do
    {:ok, %{state: :initialized}}
  end

  def join_game(game_state, _player_id) do
    # Update state
    game_state = if game_state[:no_update] do
      game_state
    else
      game_state
      |> Map.put(:last_called, :join_game)
    end

    # Respond
    if game_state[:error] do
      {:error, :failed_join}
    else
      # This one has a unique structure, so can't use general fns.
      # Pull topics and msgs from state
      topics = game_state[:topics] || []
      msgs = game_state[:msgs] || []
      {:ok, topics, msgs, game_state}
    end
  end

  def leave_game(game_state, _player_id, _reason) do
    game_state
    |> update_state(:leave_game)
    |> respond()
  end

  def player_connected(game_state, _player_id) do
    game_state
    |> update_state(:player_connected)
    |> respond()
  end

  def player_disconnected(game_state, _player_id) do
    game_state
    |> update_state(:player_disconnected)
    |> respond()
  end

  def handle_event(game_state, _from, _event) do
    game_state
    |> update_state(:handle_event)
    |> respond()
  end

  def handle_game_shutdown(game_state) do
    game_state
    |> update_state(:handle_game_shutdown)
    |> respond()
  end

  defp update_state(%{no_update: true} = state, _fn_name) do
    state
  end

  defp update_state(state, fn_name) do
    state |> Map.put(:last_called, fn_name)
  end

  defp respond(%{error: true} = _state) do
    {:error, :failed}
  end

  defp respond(state) do
    msgs = state[:msgs] || []
    {:ok, msgs, state}
  end
end
