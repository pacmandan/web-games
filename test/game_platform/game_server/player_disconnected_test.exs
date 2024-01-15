defmodule GamePlatform.GameServer.PlayerDisconnectedTest do
  use GamePlatform.GameServerCase

  test "player_disconnect (DOWN) calls the state module, disconnects, and sets timer", %{state: state} do
    game_state = %{
      game_type: :test,
      msgs: [PubSubMessage.build(:all, "Player has disconnected")]
    }

    {id_refs, state} = state
    |> Map.put(:game_state, game_state)
    |> connect_players(["playerid_1", "playerid_2"])

    # Double-check our mock connection
    assert state.connected_player_ids === MapSet.new(["playerid_1", "playerid_2"])
    assert state.connected_player_monitors === %{
      Map.fetch!(id_refs, "playerid_1") => "playerid_1",
      Map.fetch!(id_refs, "playerid_2") => "playerid_2",
    }

    Phoenix.PubSub.subscribe(WebGames.PubSub, "game:ABCD")

    down_msg = {:DOWN, Map.fetch!(id_refs, "playerid_1"), :process, %{}, :crash}

    {:noreply, new_state} = GameServer.handle_info(down_msg, state)

    # State module is called
    assert_called MockGameState.player_disconnected(game_state, "playerid_1")
    # Disconnect timeout is started
    assert_called InternalComms.schedule_player_disconnect_timeout("playerid_1", :timer.minutes(2))
    # Player1 is removed from connections
    assert new_state.connected_player_ids === MapSet.new(["playerid_2"])
    assert new_state.connected_player_monitors === %{
      Map.fetch!(id_refs, "playerid_2") => "playerid_2",
    }
    # Messages are sent successfully
    assert_receive %PubSubMessage{payload: "Player has disconnected", to: :all, type: :game_event}
  end

  test "player_disconnect (DOWN) ignores not connected players", %{state: state} do
    {id_refs, state} = state
    |> connect_players(["playerid_2"])

    # Double-check our mock connection
    assert state.connected_player_ids === MapSet.new(["playerid_2"])
    assert state.connected_player_monitors === %{
      Map.fetch!(id_refs, "playerid_2") => "playerid_2",
    }

    monitor_ref = Kernel.make_ref()

    down_msg = {:DOWN, monitor_ref, :process, %{}, :crash}

    {:noreply, new_state} = GameServer.handle_info(down_msg, state)

    # State module is NOT called
    assert_not_called MockGameState.player_disconnected(:_, :_)
    # Disconnect timeout is NOT started
    assert_not_called InternalComms.schedule_player_disconnect_timeout(:_, :_)
    # Connections are unchanged
    assert new_state.connected_player_ids === MapSet.new(["playerid_2"])
    assert new_state.connected_player_monitors === %{
      Map.fetch!(id_refs, "playerid_2") => "playerid_2",
    }
  end

  test "player disconnect (DOWN) still disconnects on error", %{state: state} do
    game_state = %{
      game_type: :test,
      error: true,
    }

    {id_refs, state} = state
    |> Map.put(:game_state, game_state)
    |> connect_players(["playerid_1", "playerid_2"])

    # Double-check our mock connection
    assert state.connected_player_ids === MapSet.new(["playerid_1", "playerid_2"])
    assert state.connected_player_monitors === %{
      Map.fetch!(id_refs, "playerid_1") => "playerid_1",
      Map.fetch!(id_refs, "playerid_2") => "playerid_2",
    }

    down_msg = {:DOWN, Map.fetch!(id_refs, "playerid_1"), :process, %{}, :crash}

    {:noreply, new_state} = GameServer.handle_info(down_msg, state)

    # State module is called
    assert_called MockGameState.player_disconnected(game_state, "playerid_1")
    # Disconnect timeout is started
    assert_called InternalComms.schedule_player_disconnect_timeout("playerid_1", :timer.minutes(2))
    # Player1 is removed from connections
    assert new_state.connected_player_ids === MapSet.new(["playerid_2"])
    assert new_state.connected_player_monitors === %{
      Map.fetch!(id_refs, "playerid_2") => "playerid_2",
    }
  end
end
