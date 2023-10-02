defmodule GamePlatform.Notification do
  defstruct [
    to: :all,
    msgs: [],
  ]

  @type t :: %__MODULE__{
    to: any(),
    msgs: list(any()),
  }

  @spec build(term()) :: t()
  def build(to), do: build(to, [])

  @spec build(term(), term()) :: term()
  def build(to, msgs) when is_list(msgs), do: %__MODULE__{to: to, msgs: msgs}
  def build(to, msg), do: %__MODULE__{to: to, msgs: [msg]}

  @spec add_msg(t(), term()) :: t()
  def add_msg(%__MODULE__{msgs: msgs} = n, new_msgs) when is_list(new_msgs), do: %__MODULE__{n | msgs: new_msgs ++ msgs}
  def add_msg(%__MODULE__{msgs: msgs} = n, new_msg), do: %__MODULE__{n | msgs: [new_msg | msgs]}

  @spec collate_notifications(list(t())) :: list(t())
  def collate_notifications(notifications) do
    # Go from a flat map of notifications...
    # [%{to: a, msgs: [1]}, %{to: a, msgs: [2]}, %{to: b, msgs: [3]}]
    # ...to a collated list of notifications
    # [%{to: a, msgs: [1, 2]}, %{to: b, msgs: [3]}]

    notifications
    |> Enum.reverse()
    |> Enum.reduce(%{}, fn n, acc ->
      if acc[n.to] do
        %{acc | n.to => add_msg(acc[n.to], n.msgs)}
      else
        Map.put(acc, n.to, n)
      end
    end)
    |> Map.values()
  end

  def send_all(notifications, game_id, pubsub) do
    for n <- notifications, do: send_one(n, game_id, pubsub)
  end

  def send_one(%__MODULE__{to: to, msgs: msgs}, game_id, pubsub) do
    # TODO: Resend on failure?
    Phoenix.PubSub.broadcast(pubsub, get_topic(to, game_id), {:game_event, game_id, msgs})
  end

  def get_topic(:all, game_id), do: "game:#{game_id}"
  def get_topic(:audience, game_id), do: "game:#{game_id}:audience"
  def get_topic({:player, player_id}, game_id), do: "game:#{game_id}:player:#{player_id}"
  def get_topic({:team, team_id}, game_id), do: "game:#{game_id}:team:#{team_id}"
  def get_topic(to, game_id), do: "game:#{game_id}:#{to}"
end
