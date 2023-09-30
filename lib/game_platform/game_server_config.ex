defmodule GamePlatform.GameServerConfig do
  # TODO: Deprecate this module
  defstruct [
    start_player_id: nil,
    game_state_module: nil,
    game_state_config: %{},
    max_length: :timer.hours(1),
    pubsub_name: nil,
  ]

  @type t :: %__MODULE__{
    start_player_id: String.t(),
    game_state_module: atom(),
    game_state_config: struct() | map(),
    max_length: integer(),
    pubsub_name: atom(),
  }

  def new_config() do
    %__MODULE__{}
  end

  def set_game_state(config, module, game_state_config) do
    %__MODULE__{config | game_state_config: game_state_config, game_state_module: module}
  end

  def set_start_player_id(config, start_player_id) do
    %__MODULE__{config | start_player_id: start_player_id}
  end

  def set_max_length(config, max_length) when max_length > 0 do
    %__MODULE__{config | max_length: max_length}
  end

  def set_pubsub(config, pubsub_name) do
    %__MODULE__{config | pubsub_name: pubsub_name}
  end

  def initialize_game_state(config) do
    config.game_state_module.init(config.game_state_config)
    |> then(fn {:ok, game} -> game end)
    |> config.game_state_module.add_player(config.start_player_id)
    |> then(fn {:ok, _, game} -> game end)
  end
end
