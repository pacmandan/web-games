defmodule GamePlatform.GameSupervisor do
  @moduledoc """
  Supervisor module for the game processes.
  """

  use DynamicSupervisor

  alias GamePlatform.GameServer.GameSpec
  alias GamePlatform.GameRegistry
  alias GamePlatform.GameServer

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc """
  Start a new game server with the given specs and ID length.
  """
  @spec start_game(GameSpec.t(), map(), integer()) ::
    {:ok, String.t(), any()}
    | {:error, :ignore | :max_children | :unknown}
  def start_game(game_spec, server_config, id_length \\ 4)
  def start_game(_game_spec, _server_config, id_length) when id_length > 30, do: throw "ID is too long"
  def start_game(game_spec, server_config, id_length) do
    game_id = GameRegistry.generate_game_id(id_length)
    child_spec = {GameServer, {game_id, game_spec, server_config}}

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

  @doc """
  Kills the game server with the given ID, if it exists.
  If it does not exist, just return `:ok`.
  """
  @spec kill_game(String.t()) :: :ok
  def kill_game(game_id) do
    case Registry.lookup(GameRegistry.registry_name(), game_id) do
      [] -> :ok
      [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
    end
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
