defmodule GamePlatform.GameInfoTest do
  use GamePlatform.GameServerCase

  test "game_info should return the correct information", %{state: state} do
    # Just make sure the right info is being returned
    assert {:reply, {:ok, %GamePlatform.GameState.GameInfo{
        server_module: MockGameState,
        view_module: GamePlatform.MockGameView,
        display_name: "MOCK_GAME",
      }}, _new_state}
        = GameServer.handle_call(:game_info, self(), state)
  end
end
