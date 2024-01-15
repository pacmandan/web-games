defmodule GamePlatform.GameServer.PlayerConnectedTest do
  use GamePlatform.GameServerCase

  test "player_connected adds player to connected list and calls module", %{state: state} do
    connection_msg = %GameMessage{
      action: :player_connected,
      from: "playerid_1",
      payload: %{
        pid: self()
      },
    }

    game_state = %{
      game_type: :test,
      msgs: [PubSubMessage.build({:player, "playerid_1"}, {:sync, %{game_type: :test}}, :sync)]
    }

    {id_refs, state} = state
    |> Map.put(:game_state, game_state)
    |> connect_players(["playerid_2"])

    # Double-check our mock connection
    assert state.connected_player_ids === MapSet.new(["playerid_2"])
    assert state.connected_player_monitors === %{
      Map.fetch!(id_refs, "playerid_2") => "playerid_2",
    }

    # Subscribe so we can see if the message was sent.
    Phoenix.PubSub.subscribe(WebGames.PubSub, "game:ABCD:player:playerid_1")

    {:noreply, new_state} = GameServer.handle_cast(connection_msg, state)

    # State module is called
    assert_called MockGameState.player_connected(game_state, "playerid_1")
    # Player1 is connected properly
    assert new_state.connected_player_ids === MapSet.new(["playerid_1", "playerid_2"])
    # This one is harder to check, so invert the map so we can better check it.
    cpms = Map.new(new_state.connected_player_monitors, fn {ref, id} -> {id, ref} end)
    assert Enum.count(cpms) === 2
    assert cpms["playerid_1"] |> is_reference()
    assert cpms["playerid_2"] === Map.fetch!(id_refs, "playerid_2")

    # Messages are sent correctly
    assert_receive %PubSubMessage{payload: {:sync, %{game_type: :test}}, to: {:player, "playerid_1"}, type: :sync}
  end

  test "player_connected cancels any active timeout for player", %{state: state} do
    connection_msg = %GameMessage{
      action: :player_connected,
      from: "playerid_1",
      payload: %{
        pid: self()
      },
    }

    # Set up timeout refs
    p1timeout_ref = Kernel.make_ref()
    p2timeout_ref = Kernel.make_ref()

    {id_refs, state} = state
    |> Map.put(:player_timeout_refs, %{
      "playerid_1" => p1timeout_ref,
      "playerid_2" => p2timeout_ref,
    })
    |> connect_players(["playerid_2"])

    # Double-check our mock connection
    assert state.connected_player_ids === MapSet.new(["playerid_2"])
    assert state.connected_player_monitors === %{
      Map.fetch!(id_refs, "playerid_2") => "playerid_2",
    }

    {:noreply, new_state} = GameServer.handle_cast(connection_msg, state)

    # State module is called
    assert_called MockGameState.player_connected(%{game_type: :test}, "playerid_1")
    # Player1 is connected properly
    assert new_state.connected_player_ids === MapSet.new(["playerid_1", "playerid_2"])
    # This one is harder to check, so invert the map so we can better check it.
    cpms = Map.new(new_state.connected_player_monitors, fn {ref, id} -> {id, ref} end)
    assert Enum.count(cpms) === 2
    assert cpms["playerid_1"] |> is_reference()
    assert cpms["playerid_2"] === Map.fetch!(id_refs, "playerid_2")

    # The Player1 timeout is cancelled
    assert_called InternalComms.cancel_scheduled_message(p1timeout_ref)
    assert new_state.player_timeout_refs === %{
      "playerid_2" => p2timeout_ref
    }
  end

  test "player_connected does not connect player on error", %{state: state} do
    connection_msg = %GameMessage{
      action: :player_connected,
      from: "playerid_1",
      payload: %{
        pid: self()
      },
    }

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

    {:noreply, new_state} = GameServer.handle_cast(connection_msg, state)

    # State module is called
    assert_called MockGameState.player_connected(game_state, "playerid_1")
    # Player1 is not connected
    assert new_state.connected_player_ids === MapSet.new(["playerid_2"])
    assert new_state.connected_player_monitors === %{
      Map.fetch!(id_refs, "playerid_2") => "playerid_2",
    }
  end

  test "player_connected handles connection from already connected player", %{state: state} do
    # It should still call the module, because maybe it missed the sync message.
    # But it shouldn't set up a second monitor.
    connection_msg = %GameMessage{
      action: :player_connected,
      from: "playerid_1",
      payload: %{
        pid: self()
      },
    }

    {id_refs, state} = state
    |> connect_players(["playerid_1", "playerid_2"])

    # Double-check our mock connection
    assert state.connected_player_ids === MapSet.new(["playerid_1", "playerid_2"])
    assert state.connected_player_monitors === %{
      Map.fetch!(id_refs, "playerid_2") => "playerid_2",
      Map.fetch!(id_refs, "playerid_1") => "playerid_1",
    }

    {:noreply, new_state} = GameServer.handle_cast(connection_msg, state)

    # State module is called
    assert_called MockGameState.player_connected(%{game_type: :test}, "playerid_1")
    # Connections are unchanged
    assert new_state.connected_player_ids === MapSet.new(["playerid_1", "playerid_2"])
    assert new_state.connected_player_monitors === %{
      Map.fetch!(id_refs, "playerid_2") => "playerid_2",
      Map.fetch!(id_refs, "playerid_1") => "playerid_1",
    }
  end
end
