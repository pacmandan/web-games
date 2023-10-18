defmodule GamePlatform.GameRegistry do

  @default_registry :game_registry

  def registry_name() do
    Application.get_env(:game_platform, :registry, @default_registry)
  end
end
