defmodule GamePlatform.Notification do
  defstruct [
    to: :all,
    msgs: [],
    type: :game_event
  ]

  @type t :: %__MODULE__{
    to: any(),
    msgs: list(any()),
    type: :game_event | :sync
  }

  @spec build(term()) :: t()
  def build(to), do: build(to, [])

  @spec build(term(), term(), atom()) :: term()
  def build(to, msgs, type \\ :game_event), do: %__MODULE__{to: to, msgs: List.wrap(msgs), type: type}

  @spec add_msg(t(), term()) :: t()
  def add_msg(%__MODULE__{msgs: msgs} = n, new_msgs), do: %__MODULE__{n | msgs: List.wrap(new_msgs) ++ msgs}

  @spec collate_notifications(list(t())) :: list(t())
  def collate_notifications(notifications) do
    # Group notification messages by :to and :type.
    notifications
    |> Enum.reverse()
    |> Enum.reduce(%{}, fn n, acc ->
      if acc[{n.to, n.type}] do
        %{acc | {n.to, n.type} => add_msg(acc[{n.to, n.type}], n.msgs)}
      else
        Map.put(acc, {n.to, n.type}, n)
      end
    end)
    |> Map.values()
  end

  def send_all(notifications, game_id, pubsub) do
    for n <- notifications, do: send_one(n, game_id, pubsub)
  end

  def send_one(%__MODULE__{to: to, msgs: msgs, type: type}, game_id, pubsub) do
    # TODO: Resend on failure?
    ctx = OpenTelemetry.Tracer.current_span_ctx()
    Phoenix.PubSub.broadcast(pubsub, get_topic(to, game_id), {type, msgs, ctx})
  end

  def get_topic(:all, game_id), do: "game:#{game_id}"
  def get_topic(:audience, game_id), do: "game:#{game_id}:audience"
  def get_topic({:player, player_id}, game_id), do: "game:#{game_id}:player:#{player_id}"
  def get_topic({:team, team_id}, game_id), do: "game:#{game_id}:team:#{team_id}"
  def get_topic(to, game_id), do: "game:#{game_id}:#{inspect(to)}"
end
