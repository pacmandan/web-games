defmodule GamePlatform.GameServer.GameSpec do
  defstruct [
    :game_module,
    :init_player,
    :game_config,
  ]

  @type t :: %__MODULE__{
    game_module: module(),
    init_player: String.t(),
    game_config: any(),
  }

  @spec make(module(), String.t(), any()) :: t()
  def make(module, init_player, config) do
    %__MODULE__{
      game_module: module,
      init_player: init_player,
      game_config: config,
    }
  end
end
