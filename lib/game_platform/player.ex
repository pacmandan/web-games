defmodule GamePlatform.Player do
  def generate_id() do
    for _ <- 1..20, into: "", do: <<Enum.random(?a..?z)>>
  end
end
