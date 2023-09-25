defmodule GamePlatform.Notification do
  defstruct [
    to: :all,
    event: nil,
  ]

  @type t :: %__MODULE__{
    to: atom() | String.t(),
    event: any(),
  }

  def build(to, event), do: %__MODULE__{to: to, event: event}

  def game_over(), do: %__MODULE__{to: :all, event: :game_over}

  # def add(to, event, notifications) do
  #   if Map.has_key?(notifications, to) do
  #     Map.replace(notifications, to, [event | notifications[to]])
  #   else
  #     Map.put(notifications, to, [event])
  #   end
  # end

  # @spec collate(list(__MODULE__.t())) :: %{ term() => list(__MODULE__.t())}
  # def collate(notifications) do
  #   notifications
  #   |> Enum.reduce(%{}, fn n, acc ->
  #     if Map.has_key?(acc, n.to) do
  #       Map.replace(acc, n.to, [n | acc[n.to]])
  #     else
  #       Map.put(acc, n.to, [n])
  #     end
  #   end)
  # end
end
