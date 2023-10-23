defmodule GamePlatform.GameRegistry do

  @default_registry :game_registry

  def registry_name() do
    Application.get_env(:game_platform, :registry, @default_registry)
  end

  def lookup(game_id) do
    case Registry.lookup(registry_name(), game_id) do
      [] -> {:error, :not_found}
      [{pid, _}] -> {:ok, pid}
      _ -> {:error, :unknown}
    end
  end
end
