defmodule GamePlatform.GameServer.ServerEventTest do
  use GamePlatform.GameServerCase

  test "handle_info {:server_event, :end_game} stops the server", %{state: state} do
    assert {:stop, :normal, new_state} = GameServer.handle_info({:server_event, :end_game}, state)
    assert_called MockGameState.handle_game_shutdown(%{game_type: :test})
    assert new_state.game_state[:last_called] === :handle_game_shutdown
  end

  test "handle_info {:server_event, :end_game} stops the server even on error", %{state: state} do
    game_state = %{game_type: :test, error: true}
    state = state
    |> Map.put(:game_state, game_state)
    assert {:stop, :normal, new_state} = GameServer.handle_info({:server_event, :end_game}, state)
    assert_called MockGameState.handle_game_shutdown(game_state)
    assert new_state === state
  end

  test "handle_info {:server_event, :game_timeout} stops the server", %{state: state} do
    assert {:stop, :normal, new_state} = GameServer.handle_info({:server_event, :game_timeout}, state)
    assert_called MockGameState.handle_game_shutdown(%{game_type: :test})
    assert new_state.game_state[:last_called] === :handle_game_shutdown
  end

  test "handle_info {:server_event, :game_timeout} stops the server even on error", %{state: state} do
    game_state = %{game_type: :test, error: true}
    state = state
    |> Map.put(:game_state, game_state)
    assert {:stop, :normal, new_state} = GameServer.handle_info({:server_event, :game_timeout}, state)
    assert_called MockGameState.handle_game_shutdown(game_state)
    assert new_state === state
  end
end
