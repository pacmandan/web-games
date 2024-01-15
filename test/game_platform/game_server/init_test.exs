defmodule GamePlatform.GameServer.InitTest do
  use GamePlatform.GameServerCase

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

  test "init_game continue calls to initialize game state and schedules timeout", %{state: state} do
    {:noreply, new_state} = GameServer.handle_continue(:init_game, state)

    # State module is called
    assert_called MockGameState.init(%{conf: :success})
    # Game state is initialized
    assert new_state.game_state === %{state: :initialized}
    # Game timeout is scheduled
    assert_called InternalComms.schedule_game_timeout(:timer.minutes(5))
    assert new_state.timeout_ref |> is_reference()
  end

  test "init_game handles failures coming from the game state", %{state: state} do
    state = state
    |> Map.put(:game_config, %{conf: :failed})

    # This simply raises an error, crashing the server.
    # Need to figure out a better way to handle this in the future maybe.
    # If for no better reason than for communication to the frontend.
    assert_raise MatchError, fn -> GameServer.handle_continue(:init_game, state) end
    assert_called MockGameState.init(%{conf: :failed})
  end
end
