defmodule GamePlatform.GameServer.PlayerDisconnectTimeoutTest do
  use GamePlatform.GameServerCase

  test "handle_info :player_disconnect_timeout tells player to leave", %{state: state} do
    game_state = %{
      game_type: :test,
      msgs: [PubSubMessage.build(:all, "Player disconnected!")],
    }
    {id_refs, state} = state
    |> Map.put(:game_state, game_state)
    |> connect_players(["playerid_2"])

    # Double-check our mock connection
    assert state.connected_player_ids === MapSet.new(["playerid_2"])
    assert state.connected_player_monitors === %{
      Map.fetch!(id_refs, "playerid_2") => "playerid_2",
    }

    Phoenix.PubSub.subscribe(WebGames.PubSub, "game:ABCD")

    {:noreply, new_state} = GameServer.handle_info({:server_event, {:player_disconnect_timeout, "playerid_1"}}, state)

    assert_called MockGameState.leave_game(%{game_type: :test}, "playerid_1", :player_disconnect_timeout)
    assert_not_called InternalComms.schedule_game_timeout(:_)
    assert new_state.timeout_ref |> is_nil()
    assert new_state.game_state[:last_called] === :leave_game
    assert new_state.connected_player_ids === MapSet.new(["playerid_2"])
    assert new_state.connected_player_monitors === %{
      Map.fetch!(id_refs, "playerid_2") => "playerid_2",
    }
    assert_receive %PubSubMessage{payload: "Player disconnected!", to: :all, type: :game_event}
  end

  test "handle_info :player_disconnect_timeout schedules short timeout if last player leaves", %{state: state} do
    {id_refs, state} = state
    |> connect_players(["playerid_1"])

    # Double-check our mock connection
    assert state.connected_player_ids === MapSet.new(["playerid_1"])
    assert state.connected_player_monitors === %{
      Map.fetch!(id_refs, "playerid_1") => "playerid_1",
    }

    {:noreply, new_state} = GameServer.handle_info({:server_event, {:player_disconnect_timeout, "playerid_1"}}, state)

    assert_called MockGameState.leave_game(%{game_type: :test}, "playerid_1", :player_disconnect_timeout)
    assert_called InternalComms.schedule_game_timeout(:timer.minutes(1))
    assert new_state.timeout_ref |> is_reference()
    assert new_state.game_state[:last_called] === :leave_game
    assert new_state.connected_player_ids === MapSet.new()
    assert new_state.connected_player_monitors === %{}
  end

  test "handle_info :player_disconnect_timeout still works if player is connected", %{state: state} do
    {id_refs, state} = state
    |> connect_players(["playerid_1", "playerid_2"])

    # Double-check our mock connection
    assert state.connected_player_ids === MapSet.new(["playerid_1", "playerid_2"])
    assert state.connected_player_monitors === %{
      Map.fetch!(id_refs, "playerid_2") => "playerid_2",
      Map.fetch!(id_refs, "playerid_1") => "playerid_1",
    }

    {:noreply, new_state} = GameServer.handle_info({:server_event, {:player_disconnect_timeout, "playerid_1"}}, state)

    assert_called MockGameState.leave_game(%{game_type: :test}, "playerid_1", :player_disconnect_timeout)
    assert_not_called InternalComms.schedule_game_timeout(:_)
    assert new_state.timeout_ref |> is_nil()
    assert new_state.game_state[:last_called] === :leave_game
    assert new_state.connected_player_ids === MapSet.new(["playerid_2"])
    assert new_state.connected_player_monitors === %{
      Map.fetch!(id_refs, "playerid_2") => "playerid_2",
    }
  end

  test "handle_info :player_disconnect_timeout handles errors", %{state: state} do
    game_state = %{
      game_type: :test,
      error: true,
    }
    {id_refs, state} = state
    |> Map.put(:game_state, game_state)
    |> connect_players(["playerid_2"])

    # Double-check our mock connection
    assert state.connected_player_ids === MapSet.new(["playerid_2"])
    assert state.connected_player_monitors === %{
      Map.fetch!(id_refs, "playerid_2") => "playerid_2",
    }

    {:noreply, new_state} = GameServer.handle_info({:server_event, {:player_disconnect_timeout, "playerid_1"}}, state)

    assert_called MockGameState.leave_game(%{game_type: :test}, "playerid_1", :player_disconnect_timeout)
    assert_not_called InternalComms.schedule_game_timeout(:_)
    assert new_state === state
  end
end
