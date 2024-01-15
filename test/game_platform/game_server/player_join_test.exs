defmodule GamePlatform.GameServer.PlayerJoinTest do
  use GamePlatform.GameServerCase

  test "player_join success defaults", %{state: state} do
    join_msg = %GameMessage{
      action: :player_join,
      from: "playerid_1",
    }

    {:reply, {:ok, topics}, new_state}
      = GameServer.handle_call(join_msg, self(), state)

    # State module is called
    assert_called MockGameState.join_game(%{game_type: :test}, "playerid_1")
    # Game timeout is rescheduled
    assert_called InternalComms.schedule_game_timeout(:timer.minutes(5))
    assert new_state.timeout_ref |> is_reference()
    # Default topics are returned
    assert topics === ["game:ABCD", "game:ABCD:player:playerid_1"]
    # Game state is updated
    assert new_state.game_state[:last_called] === :join_game
  end

  test "player_join success custom additional topic", %{state: state} do
    join_msg = %GameMessage{
      action: :player_join,
      from: "playerid_1",
    }

    game_state = %{game_type: :test, topics: ["custom"]}

    state = state
    |> Map.put(:game_state, game_state)

    {:reply, {:ok, topics}, new_state}
      = GameServer.handle_call(join_msg, self(), state)

    # State module is called
    assert_called MockGameState.join_game(game_state, "playerid_1")
    # Game timeout is rescheduled
    assert_called InternalComms.schedule_game_timeout(:timer.minutes(5))
    assert new_state.timeout_ref |> is_reference()
    # Additional topic is returned
    assert topics === ["game:ABCD:custom", "game:ABCD", "game:ABCD:player:playerid_1"]
    # Game state is updated
    assert new_state.game_state[:last_called] === :join_game
  end

  test "player_join success dedups topics", %{state: state} do
    join_msg = %GameMessage{
      action: :player_join,
      from: "playerid_1",
    }

    game_state = %{
      game_type: :test,
      topics: [:all, {:player, "playerid_1"}]
    }

    state = state
    |> Map.put(:game_state, game_state)

    {:reply, {:ok, topics}, new_state}
      = GameServer.handle_call(join_msg, self(), state)

    # State module is called
    assert_called MockGameState.join_game(game_state, "playerid_1")
    # Game timeout is rescheduled
    assert_called InternalComms.schedule_game_timeout(:timer.minutes(5))
    assert new_state.timeout_ref |> is_reference()
    # Topics are deduped
    assert topics === ["game:ABCD", "game:ABCD:player:playerid_1"]
    # Game state is updated
    assert new_state.game_state[:last_called] === :join_game
  end

  test "player_join success broadcasts messages from state", %{state: state} do
    join_msg = %GameMessage{
      action: :player_join,
      from: "playerid_1",
    }

    game_state = %{
      game_type: :test,
      msgs: [PubSubMessage.build(:all, "Test msg")]
    }

    state = state
    |> Map.put(:game_state, game_state)

    # Subscribe so we can see if the message was sent.
    Phoenix.PubSub.subscribe(WebGames.PubSub, "game:ABCD")

    {:reply, {:ok, topics}, new_state}
      = GameServer.handle_call(join_msg, self(), state)

    # State module is called
    assert_called MockGameState.join_game(game_state, "playerid_1")
    # Game timeout is rescheduled
    assert_called InternalComms.schedule_game_timeout(:timer.minutes(5))
    assert new_state.timeout_ref |> is_reference()
    # Topics are correct
    assert topics === ["game:ABCD", "game:ABCD:player:playerid_1"]
    # Game state is updated
    assert new_state.game_state[:last_called] === :join_game
    # Messages are correctly broadcast
    assert_receive %PubSubMessage{payload: "Test msg", to: :all, type: :game_event}
  end

  test "player_join failed", %{state: state} do
    join_msg = %GameMessage{
      action: :player_join,
      from: "playerid_1",
    }

    game_state = %{
      game_type: :test,
      error: true
    }

    state = state
    |> Map.put(:game_state, game_state)

    assert {:reply, {:error, :failed_join}, new_state}
      = GameServer.handle_call(join_msg, self(), state)

    # State module is called
    assert_called MockGameState.join_game(game_state, "playerid_1")

    # Since it failed, the timeout should NOT be rescheduled
    assert_not_called InternalComms.schedule_game_timeout(:_)
    assert new_state.timeout_ref |> is_nil()
  end
end
