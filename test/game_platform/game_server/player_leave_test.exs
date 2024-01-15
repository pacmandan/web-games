defmodule GamePlatform.GameServer.PlayerLeaveTest do
  use GamePlatform.GameServerCase

  test "player_leave calls module but otherwise does nothing on disconnected player", %{state: state} do
    leave_msg = %GameMessage{
      action: :player_leave,
      from: "playerid_1",
    }

    {id_refs, state} = state
    |> connect_players(["playerid_2"])

    # Double-check our mock connection
    assert state.connected_player_ids === MapSet.new(["playerid_2"])
    assert state.connected_player_monitors === %{
      Map.fetch!(id_refs, "playerid_2") => "playerid_2",
    }

    {:reply, :ok, new_state} = GameServer.handle_call(leave_msg, self(), state)

    # State module is called
    assert_called MockGameState.leave_game(%{game_type: :test}, "playerid_1", :manual)
    # Game timeout is NOT rescheduled
    assert_not_called InternalComms.schedule_game_timeout(:_)
    assert new_state.timeout_ref |> is_nil()
    # Game state is updated
    assert new_state.game_state[:last_called] === :leave_game
    # Connected players are the same
    assert new_state.connected_player_ids === MapSet.new(["playerid_2"])
    assert new_state.connected_player_monitors === %{
      Map.fetch!(id_refs, "playerid_2") => "playerid_2",
    }
  end

  test "player_leave removes connected player", %{state: state} do
    leave_msg = %GameMessage{
      action: :player_leave,
      from: "playerid_1",
    }

    {id_refs, state} = state
    |> connect_players(["playerid_1", "playerid_2"])

    # Double-check our mock connection
    assert state.connected_player_ids === MapSet.new(["playerid_1", "playerid_2"])
    assert state.connected_player_monitors === %{
      Map.fetch!(id_refs, "playerid_2") => "playerid_2",
      Map.fetch!(id_refs, "playerid_1") => "playerid_1",
    }

    {:reply, :ok, new_state} = GameServer.handle_call(leave_msg, self(), state)

    # State module is called
    assert_called MockGameState.leave_game(%{game_type: :test}, "playerid_1", :manual)
    # Game timeout is NOT rescheduled
    assert_not_called InternalComms.schedule_game_timeout(:_)
    assert new_state.timeout_ref |> is_nil()
    # Game state is updated
    assert new_state.game_state[:last_called] === :leave_game
    # Player1 has been removed from connected players list
    assert new_state.connected_player_ids === MapSet.new(["playerid_2"])
    assert new_state.connected_player_monitors === %{
      Map.fetch!(id_refs, "playerid_2") => "playerid_2",
    }
  end

  test "player_leave returns an error if module fails", %{state: state} do
    leave_msg = %GameMessage{
      action: :player_leave,
      from: "playerid_1",
    }

    game_state = %{game_type: :test, error: true}

    {id_refs, state} = state
    |> Map.put(:game_state, game_state)
    |> connect_players(["playerid_2"])

    # Double-check our mock connection
    assert state.connected_player_ids === MapSet.new(["playerid_2"])
    assert state.connected_player_monitors === %{
      Map.fetch!(id_refs, "playerid_2") => "playerid_2",
    }

    {:reply, {:error, :failed}, new_state} = GameServer.handle_call(leave_msg, self(), state)

    # State module is called
    assert_called MockGameState.leave_game(game_state, "playerid_1", :manual)
    # Game timeout is NOT rescheduled
    assert_not_called InternalComms.schedule_game_timeout(:_)
    # State should remain unchanged on failure here
    assert new_state === state
  end

  test "player_leave still removes connected player even on module failure", %{state: state} do
    leave_msg = %GameMessage{
      action: :player_leave,
      from: "playerid_1",
    }

    game_state = %{game_type: :test, error: true}

    {id_refs, state} = state
    |> Map.put(:game_state, game_state)
    |> connect_players(["playerid_1", "playerid_2"])

    # Double-check our mock connection
    assert state.connected_player_ids === MapSet.new(["playerid_1", "playerid_2"])
    assert state.connected_player_monitors === %{
      Map.fetch!(id_refs, "playerid_2") => "playerid_2",
      Map.fetch!(id_refs, "playerid_1") => "playerid_1",
    }

    {:reply, {:error, :failed}, new_state} = GameServer.handle_call(leave_msg, self(), state)

    # State module is called
    assert_called MockGameState.leave_game(%{game_type: :test}, "playerid_1", :manual)
    # Game timeout is NOT rescheduled
    assert_not_called InternalComms.schedule_game_timeout(:_)
    assert new_state.timeout_ref |> is_nil()
    # Player1 should still be removed, even on failure
    assert new_state.connected_player_ids === MapSet.new(["playerid_2"])
    assert new_state.connected_player_monitors === %{
      Map.fetch!(id_refs, "playerid_2") => "playerid_2",
    }
  end
end
