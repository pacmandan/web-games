defmodule GamePlatform.PubSubMessage do
  defstruct [
    :from,
    :payload,
    :to,
    :ctx,
    type: :game_event,
  ]

  @type topic_ref ::
    :all
    | :audience
    | {:player, String.t()}
    | {:team, String.t()}
    | any()

  @type t :: %__MODULE__{
    payload: any(),
    from: String.t(),
    to: topic_ref(),
    ctx: OpenTelemetry.Ctx.t(),
    type: :game_event | :sync,
  }

  def build(to, payload, type \\ :game_event) do
    %__MODULE__{
      payload: payload,
      to: to,
      type: type,
    }
  end

  def combine_msgs(msgs) do
    msgs
    |> Enum.reverse()
    |> Enum.reduce(%{}, fn msg, acc ->
      if acc[{msg.to, msg.type}] do
        acc_msg = acc[{msg.to, msg.type}]
        %{acc | {msg.to, msg.type} => append_payload(acc_msg, msg.payload)}
      else
        Map.put(acc, {msg.to, msg.type}, msg)
      end
    end)
    |> Map.values()
  end

  defp append_payload(%__MODULE__{payload: payload} = msg, more_payload) do
    %__MODULE__{msg | payload: List.wrap(payload) ++ List.wrap(more_payload)}
  end

  defp add_ctx(%__MODULE__{} = msg) do
    %__MODULE__{msg | ctx: OpenTelemetry.Tracer.current_span_ctx()}
  end

  def broadcast_all(msgs, from_id, pubsub_name \\ WebGames.PubSub) do
    for msg <- msgs, do: broadcast(msg, from_id, pubsub_name)
  end

  def broadcast(%__MODULE__{} = msg, from_id, pubsub_name \\ WebGames.PubSub) do
    msg = msg
    |> add_ctx()
    |> set_from(from_id)

    Phoenix.PubSub.broadcast(pubsub_name, get_topic(msg.to, msg.from), msg)
  end

  defp set_from(%__MODULE__{} = msg, from_id) do
    %__MODULE__{msg | from: from_id}
  end

  def get_topic(:all, game_id), do: "game:#{game_id}"
  def get_topic(:audience, game_id), do: "game:#{game_id}:audience"
  def get_topic({:player, player_id}, game_id), do: "game:#{game_id}:player:#{player_id}"
  def get_topic({:team, team_id}, game_id), do: "game:#{game_id}:team:#{team_id}"
  def get_topic(to, game_id), do: "game:#{game_id}:#{inspect(to)}"
end
