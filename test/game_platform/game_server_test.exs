defmodule GamePlatform.GameServerTest do
  use ExUnit.Case
  doctest GamePlatform.Cache

  import Mock

  alias GamePlatform.PubSubMessage
  alias GamePlatform.GameServer.GameMessage
  alias GamePlatform.GameServer
  alias GamePlatform.GameServer.InternalComms
  alias GamePlatform.MockGameState

  @doc """
  TODO Test cases:
  - :player_leave calls module
  - :player_leave handles errors from module
  - :game_event calls module
  - :game_event handles errors
  - :player_connected calls module, updates connections
  - :player_connected handles errors
  - :DOWN (:player_disconnected) calls module, updates connections
  - :DOWN (:player_disconnected) handles errors
  - :game_event handle_info calls module with :game
  - :game_event handle_info handles errors
  - {:server_event, :end_game} stops the server
  - {:server_event, :game_timeout} stops the server
  - {:server_event, {:player_disconnect_timeout}} removes player, calls module
  - {:server_event, {:player_disconnect_timeout}} handles errors
  """

  setup_with_mocks([
    {MockGameState, [:passthrough], []},
    {InternalComms, [], [
      schedule_game_event: fn(_) ->
        Kernel.make_ref()
      end,
      schedule_end_game: fn(_) ->
        Kernel.make_ref()
      end,
      schedule_game_timeout: fn(_) ->
        Kernel.make_ref()
      end,
      schedule_player_disconnect_timeout: fn(_, _) ->
        Kernel.make_ref()
      end,
      cancel_scheduled_message: fn(_) -> 1000 end
    ]}
  ]) do
    {:ok, %{}}
  end

  @default_state %{
    game_id: "ABCD",
    game_module: MockGameState,
    game_config: %{conf: :success},
    game_state: nil,
    start_time: ~U[2024-01-06 23:25:38.371659Z],
    server_config: %{
      game_timeout_length: :timer.minutes(5),
      player_disconnect_timeout_length: :timer.minutes(2),
      pubsub: WebGames.PubSub,
    },
    timeout_ref: nil,
    connected_player_ids: MapSet.new(),
    connected_player_monitors: %{},
    player_timeout_refs: %{},
  }

  test "start_link fails if :pubsub is not set" do
    init_args = {
      "ABCD",
      {MockGameState, %{conf: :success}},
      %{},
    }
    assert {:error, :invalid_config} === GameServer.start_link(init_args)
  end

  test "start_link fails if :game_timeout_length is negative" do
    init_args = {
      "ABCD",
      {MockGameState, %{conf: :success}},
      %{
        pubsub: WebGames.PubSub,
        game_timeout_length: -50,
      },
    }
    assert {:error, :invalid_config} === GameServer.start_link(init_args)
  end

  test "start_link fails if :player_disconnect_timeout_length is negative" do
    init_args = {
      "ABCD",
      {MockGameState, %{conf: :success}},
      %{
        pubsub: WebGames.PubSub,
        player_disconnect_timeout_length: -50,
      },
    }
    assert {:error, :invalid_config} === GameServer.start_link(init_args)
  end

  test "init initializes server state, then continues to game state" do
    init_args = {
      "ABCD",
      {MockGameState, %{conf: :success}},
      %{},
    }

    with_mock DateTime, [utc_now: fn() -> ~U[2024-01-06 23:25:38.371659Z] end] do
      {:ok, init_state, next} = GameServer.init(init_args)
      assert next === {:continue, :init_game}
      assert init_state.game_id === "ABCD"
      assert init_state.game_module === MockGameState
      assert init_state.game_config === %{conf: :success}
      assert init_state.start_time === ~U[2024-01-06 23:25:38.371659Z]
      assert init_state.server_config === %{
        game_timeout_length: :timer.minutes(5),
        player_disconnect_timeout_length: :timer.minutes(2),
        # Normally there should also be a :pubsub key here, but
        # that is only enforced in start_link and has no default value.
      }
      assert init_state.timeout_ref |> is_nil()
      assert init_state.connected_player_ids === MapSet.new()
      assert init_state.connected_player_monitors === %{}
      assert init_state.player_timeout_refs === %{}
    end
  end

  test "init_game continue calls to initialize game state and schedules timeout" do
    {:noreply, new_state} = GameServer.handle_continue(:init_game, @default_state)
    assert new_state.game_state === %{state: :initialized}
    assert new_state.timeout_ref |> is_reference()
    assert_called MockGameState.init(%{conf: :success})
    assert_called InternalComms.schedule_game_timeout(:timer.minutes(5))
  end

  test "init_game handles failures coming from the game state" do
    state = @default_state
    |> Map.put(:game_config, %{conf: :failed})

    # This simply raises an error, crashing the server.
    # Need to figure out a better way to handle this in the future maybe.
    # If for no better reason than for communication to the frontend.
    assert_raise MatchError, fn -> GameServer.handle_continue(:init_game, state) end
    assert_called MockGameState.init(%{conf: :failed})
  end

  test "player_join success defaults" do
    join_msg = %GameMessage{
      action: :player_join,
      from: "playerid_1",
    }

    state = @default_state
    |> Map.put(:game_state, %{game_type: :test})

    {:reply, {:ok, topics}, new_state}
      = GameServer.handle_call(join_msg, self(), state)

    assert_called MockGameState.join_game(%{game_type: :test}, "playerid_1")
    assert_called InternalComms.schedule_game_timeout(:timer.minutes(5))
    assert new_state.timeout_ref |> is_reference()
    assert topics === ["game:ABCD", "game:ABCD:player:playerid_1"]
    assert new_state.game_state[:last_called] === :join_game

  end

  test "player_join success custom additional topic" do
    join_msg = %GameMessage{
      action: :player_join,
      from: "playerid_1",
    }

    game_state = %{game_type: :test, topics: ["custom"]}

    state = @default_state
    |> Map.put(:game_state, game_state)

    {:reply, {:ok, topics}, new_state}
      = GameServer.handle_call(join_msg, self(), state)

    assert_called MockGameState.join_game(game_state, "playerid_1")
    assert_called InternalComms.schedule_game_timeout(:timer.minutes(5))
    assert new_state.timeout_ref |> is_reference()
    assert topics === ["game:ABCD:custom", "game:ABCD", "game:ABCD:player:playerid_1"]
    assert new_state.game_state[:last_called] === :join_game
  end

  test "player_join success dedups topics" do
    join_msg = %GameMessage{
      action: :player_join,
      from: "playerid_1",
    }

    game_state = %{
      game_type: :test,
      topics: [:all, {:player, "playerid_1"}]
    }

    state = @default_state
    |> Map.put(:game_state, game_state)

    {:reply, {:ok, topics}, new_state}
      = GameServer.handle_call(join_msg, self(), state)

    assert_called MockGameState.join_game(game_state, "playerid_1")
    assert_called InternalComms.schedule_game_timeout(:timer.minutes(5))
    assert new_state.timeout_ref |> is_reference()
    assert topics === ["game:ABCD", "game:ABCD:player:playerid_1"]
    assert new_state.game_state[:last_called] === :join_game
  end

  test "player_join success broadcasts messages from state" do
    join_msg = %GameMessage{
      action: :player_join,
      from: "playerid_1",
    }

    msgs = [
      PubSubMessage.build(:all, "Test msg")
    ]

    game_state = %{
      game_type: :test,
      msgs: msgs
    }

    state = @default_state
    |> Map.put(:game_state, game_state)

    # Subscribe so we can see if the message was sent.
    Phoenix.PubSub.subscribe(WebGames.PubSub, "game:ABCD")

    {:reply, {:ok, topics}, new_state}
      = GameServer.handle_call(join_msg, self(), state)

    assert_called MockGameState.join_game(game_state, "playerid_1")
    assert_called InternalComms.schedule_game_timeout(:timer.minutes(5))
    assert new_state.timeout_ref |> is_reference()
    assert topics === ["game:ABCD", "game:ABCD:player:playerid_1"]
    assert new_state.game_state[:last_called] === :join_game
    assert_receive %PubSubMessage{payload: "Test msg", to: :all, type: :game_event}
  end

  test "player_join failed" do
    join_msg = %GameMessage{
      action: :player_join,
      from: "playerid_1",
    }

    game_state = %{
      game_type: :test,
      error: true
    }

    state = @default_state
    |> Map.put(:game_state, game_state)

    assert {:reply, {:error, :failed_join}, new_state}
      = GameServer.handle_call(join_msg, self(), state)

    # Join game should be called
    assert_called MockGameState.join_game(game_state, "playerid_1")

    # Since it failed, the timeout should NOT be rescheduled.
    assert_not_called InternalComms.schedule_game_timeout(:timer.minutes(5))
    assert new_state.timeout_ref |> is_nil()
  end

  test "game_info should return the correct information" do
    assert {:reply, {:ok, %GamePlatform.GameState.GameInfo{
        server_module: MockGameState,
        view_module: GamePlatform.MockGameView,
        display_name: "MOCK_GAME",
      }}, _new_state}
        = GameServer.handle_call(:game_info, self(), @default_state)
  end
end
