defmodule GamePlatform.Notification do
  defstruct [
    to: :all,
    msgs: [],
  ]

  @type t :: %__MODULE__{
    to: any(),
    msgs: list(any()),
  }

  def build(to), do: build(to, [])
  def build(to, msgs) when is_list(msgs), do: %__MODULE__{to: to, msgs: msgs}
  def build(to, msg), do: %__MODULE__{to: to, msgs: [msg]}

  def add_msg(%__MODULE__{msgs: msgs} = n, new_msgs) when is_list(new_msgs), do: %__MODULE__{n | msgs: new_msgs ++ msgs}
  def add_msg(%__MODULE__{msgs: msgs} = n, new_msg), do: %__MODULE__{n | msgs: [new_msg | msgs]}

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
end
