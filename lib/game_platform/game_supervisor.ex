defmodule GamePlatform.GameSupervisor do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def start_game(game_spec, server_config, id_length \\ 4)
  def start_game(_game_spec, _server_config, id_length) when id_length > 30, do: throw "ID is too long"
  def start_game(game_spec, server_config, id_length) do
    game_id = generate_game_id(id_length)
    child_spec = {GamePlatform.GameServer, {game_id, game_spec, server_config}}

    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, child} ->
        {:ok, game_id, child}
      {:ok, child, _} ->
        {:ok, game_id, child}
      {:error, {:already_started, _}} ->
        # Try again with a longer ID
        start_game(game_spec, server_config, id_length + 1)
      {:error, :max_children} ->
        {:error, :max_children}
      :ignore ->
        {:error, :ignore}
      _ ->
        {:error, :unknown}
    end
  end

  def kill_game(game_id) do
    case Registry.lookup(GamePlatform.GameRegistry.registry_name(), game_id) do
      [] -> :ok
      [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
    end
  end

  # TODO: Move this into the Registry module?
  defp generate_game_id(length) do
    # TODO: Filter out curse words from the possible list of IDs.
    # Make sure we don't accidentally generate a game server called "FUCK", "SHIT", etc.
    # We'll need to keep a list of 4-letter, 5-letter, etc, words to filter.
    for _ <- 1..(length), into: "", do: <<Enum.random(?A..?Z)>>
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
