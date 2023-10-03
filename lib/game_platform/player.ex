defmodule GamePlatform.Player do
  defstruct [
    :id,
    :role,
    :name,
    :game_id,
  ]

  def new_player(game_id, player_id, role) do
    %__MODULE__{id: player_id, role: role, game_id: game_id}
  end

  def generate_id() do
    for _ <- 1..20, into: "", do: <<Enum.random(?a..?z)>>
  end
end
