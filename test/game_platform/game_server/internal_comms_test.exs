defmodule GamePlatform.GameServer.InternalCommsTest do
  use ExUnit.Case, async: true

  alias GamePlatform.GameServer.InternalComms

  test "schedule_game_event sends a message to self" do
    ref = InternalComms.schedule_game_event(:test_event)
    assert ref |> is_reference()
    assert_receive {:game_event, :test_event}
  end

  test "schedule_end_game sends a message to self" do
    ref = InternalComms.schedule_end_game()
    assert ref |> is_reference()
    assert_receive {:server_event, :end_game}
  end

  test "schedule_player_disconnect_timeout sends a message to self" do
    ref = InternalComms.schedule_player_disconnect_timeout("playerid_1")
    assert ref |> is_reference()
    assert_receive {:server_event, {:player_disconnect_timeout, "playerid_1"}}
  end

  test "schedule_game_timeout sends a message to self" do
    ref = InternalComms.schedule_game_timeout()
    assert ref |> is_reference()
    assert_receive {:server_event, :game_timeout}
  end

  test "cancel_scheduled_message cancels a message" do
    ref = InternalComms.schedule_game_timeout(100)
    result = InternalComms.cancel_scheduled_message(ref)
    assert ref |> is_reference()
    assert result |> is_number()
    refute_receive {:server_event, :game_timeout}, 500
  end
end
