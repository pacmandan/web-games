defmodule GamePlatform.GameServer.GameEventTest do
  use GamePlatform.GameServerCase

  test "game_event should forward the event to the state module", %{state: state} do
    event_msg = %GameMessage{
      action: :game_event,
      from: "playerid_1",
      payload: %{do_stuff: true},
    }

    game_state = %{
      game_type: :test,
      msgs: [PubSubMessage.build(:all, "Test msg")]
    }

    {id_refs, state} = state
    |> Map.put(:game_state, game_state)
    |> connect_players(["playerid_1", "playerid_2"])

    # Double-check our mock connection
    assert state.connected_player_ids === MapSet.new(["playerid_1", "playerid_2"])
    assert state.connected_player_monitors === %{
      Map.fetch!(id_refs, "playerid_2") => "playerid_2",
      Map.fetch!(id_refs, "playerid_1") => "playerid_1",
    }

    # Subscribe so we can see if the message was sent.
    Phoenix.PubSub.subscribe(WebGames.PubSub, "game:ABCD")

    {:noreply, new_state} = GameServer.handle_cast(event_msg, state)

    # State module is called
    assert_called MockGameState.handle_event(%{game_type: :test}, "playerid_1", %{do_stuff: true})
    # Game timeout is rescheduled
    assert_called InternalComms.schedule_game_timeout(:timer.minutes(5))
    assert new_state.timeout_ref |> is_reference()
    # Connections do not change
    assert new_state.connected_player_ids === state.connected_player_ids
    assert new_state.connected_player_monitors === state.connected_player_monitors
    # Game state is updated
    assert new_state.game_state[:last_called] === :handle_event
    # Messages are sent correctly
    assert_receive %PubSubMessage{payload: "Test msg", to: :all, type: :game_event}
  end

  test "game_event should ignore messages from unconnected players", %{state: state} do
    event_msg = %GameMessage{
      action: :game_event,
      from: "playerid_1",
      payload: %{do_stuff: true},
    }

    game_state = %{
      game_type: :test,
      msgs: [PubSubMessage.build(:all, "Test msg")]
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
    Phoenix.PubSub.subscribe(WebGames.PubSub, "game:ABCD")

    {:noreply, new_state} = GameServer.handle_cast(event_msg, state)

    # State module is NOT called
    assert_not_called MockGameState.handle_event(:_, :_, :_)
    # Game timeout is NOT rescheduled
    assert_not_called InternalComms.schedule_game_timeout(:_)
    # State remains unchanged
    assert new_state === state
    # No messages are sent
    refute_receive %PubSubMessage{payload: "Test msg", to: :all, type: :game_event}
  end

  test "game_event should properly handle errors from state module", %{state: state} do
    event_msg = %GameMessage{
      action: :game_event,
      from: "playerid_1",
      payload: %{do_stuff: true},
    }

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
      Map.fetch!(id_refs, "playerid_2") => "playerid_2",
      Map.fetch!(id_refs, "playerid_1") => "playerid_1",
    }

    {:noreply, new_state} = GameServer.handle_cast(event_msg, state)

    # State module is called
    assert_called MockGameState.handle_event(%{game_type: :test, error: true}, "playerid_1", %{do_stuff: true})
    # Game timeout is NOT rescheduled
    assert_not_called InternalComms.schedule_game_timeout(:_)
    # State remains unchanged
    assert new_state === state
    # No messages are sent
    refute_receive %PubSubMessage{payload: "Test msg", to: :all, type: :game_event}
  end

  test "handle_info :game_event works just like handle_call game_event, but uses :game", %{state: state} do
    game_state = %{
      game_type: :test,
      msgs: [PubSubMessage.build(:all, "Game Triggered Event!")]
    }
    state = state
    |> Map.put(:game_state, game_state)

    Phoenix.PubSub.subscribe(WebGames.PubSub, "game:ABCD")

    {:noreply, new_state} = GameServer.handle_info({:game_event, %{do_stuff: true}}, state)

    assert_called MockGameState.handle_event(game_state, :game, %{do_stuff: true})
    assert_not_called InternalComms.schedule_game_timeout(:_)
    assert_receive %PubSubMessage{payload: "Game Triggered Event!", to: :all, type: :game_event}
    assert new_state.timeout_ref |> is_nil()
    assert new_state.game_state[:last_called] === :handle_event
  end

  test "handle_info :game_event handles errors from module", %{state: state} do
    game_state = %{
      game_type: :test,
      msgs: [PubSubMessage.build(:all, "Game Triggered Event!")],
      error: true,
    }
    state = state
    |> Map.put(:game_state, game_state)

    Phoenix.PubSub.subscribe(WebGames.PubSub, "game:ABCD")

    {:noreply, new_state} = GameServer.handle_info({:game_event, %{do_stuff: true}}, state)

    assert_called MockGameState.handle_event(game_state, :game, %{do_stuff: true})
    assert_not_called InternalComms.schedule_game_timeout(:_)
    refute_receive %PubSubMessage{payload: "Game Triggered Event!", to: :all, type: :game_event}
    assert new_state === state
  end
end
