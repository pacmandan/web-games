defmodule GamePlatform.MockGameState do
  use GamePlatform.GameState,
    view_module: GamePlatform.MockGameView,
    display_name: "MOCK_GAME"

  def init(_game_config) do
    {:ok, %{state: :initialized}}
  end

  def join_game(game_state, _player_id) do
    {:ok, [], [], game_state}
  end

  def leave_game(game_state, _player_id, _reason) do
    {:ok, [], game_state}
  end

  def player_connected(game_state, _player_id) do
    {:ok, [], game_state}
  end

  def player_disconnected(game_state, _player_id) do
    {:ok, [], game_state}
  end

  def handle_event(game_state, _from, _event) do
    {:ok, [], game_state}
  end

  def handle_game_shutdown(game_state) do
    {:ok, [], game_state}
  end
end
