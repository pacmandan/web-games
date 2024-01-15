defmodule GamePlatform.PubSubMessageTest do
  use ExUnit.Case, async: true

  alias GamePlatform.PubSubMessage

  @game_id "ASDF"

  test "build creates the correct structure" do
    assert PubSubMessage.build(:all, "Payload string") ===
      %PubSubMessage{
        to: :all,
        payload: "Payload string",
        type: :game_event,
      }

    assert PubSubMessage.build({:player, "id1"}, "Player ID message", :sync) ===
      %PubSubMessage{
        to: {:player, "id1"},
        payload: "Player ID message",
        type: :sync,
      }
  end

  test "combine_msgs reduces messages by sender" do
    msgs = [
      PubSubMessage.build(:all, "Message 1"),
      PubSubMessage.build(:all, "Message 2"),
      PubSubMessage.build(:all, "Message 3"),
      PubSubMessage.build({:player, "id1"}, "Message 4"),
    ]

    assert PubSubMessage.combine_msgs(msgs) === [
      PubSubMessage.build(:all, ["Message 1", "Message 2", "Message 3"]),
      PubSubMessage.build({:player, "id1"}, "Message 4"),
    ]
  end

  test "combine_msgs appends messages that are lists" do
    msgs = [
      PubSubMessage.build(:all, ["Message 1", "Message 2"]),
      PubSubMessage.build(:all, "Message 3"),
      PubSubMessage.build(:all, ["Message 4"]),
    ]

    assert PubSubMessage.combine_msgs(msgs) === [
      PubSubMessage.build(:all, ["Message 1", "Message 2", "Message 3", "Message 4"]),
    ]
  end

  test "broadcast all sends all messages" do
    msgs = [
      PubSubMessage.build(:all, "Message 1"),
      PubSubMessage.build(:all, "Message 2"),
      PubSubMessage.build({:player, "id1"}, "Message 3"),
    ]

    Phoenix.PubSub.subscribe(WebGames.PubSub, "game:ASDF")
    Phoenix.PubSub.subscribe(WebGames.PubSub, "game:ASDF:player:id1")

    PubSubMessage.broadcast_all(msgs, @game_id)

    assert_receive %PubSubMessage{payload: "Message 1", to: :all, type: :game_event}
    assert_receive %PubSubMessage{payload: "Message 2", to: :all, type: :game_event}
    assert_receive %PubSubMessage{payload: "Message 3", to: {:player, "id1"}, type: :game_event}
  end

  test "broadcast sends one message" do
    msg = PubSubMessage.build(:all, "Message 1")


    Phoenix.PubSub.subscribe(WebGames.PubSub, "game:ASDF")

    PubSubMessage.broadcast(msg, @game_id)

    assert_receive %PubSubMessage{payload: "Message 1", to: :all, type: :game_event}
  end

  describe "get_topic" do
    test ":all" do
      assert PubSubMessage.get_topic(:all, @game_id) === "game:ASDF"
    end

    test ":players" do
      assert PubSubMessage.get_topic(:players, @game_id) === "game:ASDF:players"
    end

    test ":audience" do
      assert PubSubMessage.get_topic(:audience, @game_id) === "game:ASDF:audience"
    end

    test "{:player, id}" do
      assert PubSubMessage.get_topic({:player, "playerid_1"}, @game_id) === "game:ASDF:player:playerid_1"
    end

    test "{:team, id}" do
      assert PubSubMessage.get_topic({:team, "team1"}, @game_id) === "game:ASDF:team:team1"
    end

    test "nil" do
      # I don't know how I feel about this one, but I guess it should
      # still be allowed.
      assert PubSubMessage.get_topic(nil, @game_id) === "game:ASDF:nil"
    end

    test "arbitrary string" do
      assert PubSubMessage.get_topic("custom", @game_id) === "game:ASDF:custom"
    end

    test "arbitrary atom" do
      assert PubSubMessage.get_topic(:custom, @game_id) === "game:ASDF::custom"
    end

    test "arbitrary object" do
      assert PubSubMessage.get_topic(%{type: "string"}, @game_id) === "game:ASDF:%{type: \"string\"}"
    end

    test "arbitrary tuple" do
      assert PubSubMessage.get_topic({:one, "two"}, @game_id) === "game:ASDF:{:one, \"two\"}"
    end

    test "arbitrary list" do
      assert PubSubMessage.get_topic([:one, "two"], @game_id) === "game:ASDF:[:one, \"two\"]"
    end
  end
end
