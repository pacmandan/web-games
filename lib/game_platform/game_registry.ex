defmodule GamePlatform.GameRegistry do
  @moduledoc """
  Module for handling Game Registry functions.
  """

  @default_registry :game_registry

  @doc """
  Get the name the Registry process should be registered under.

  This is configurable in the application config under `[:game_platform, :registry]`.
  Defaults to #{@default_registry}.
  """
  @spec registry_name() :: atom()
  def registry_name() do
    Application.get_env(:game_platform, :registry, @default_registry)
  end

  @doc """
  Look up the pid of a game with the given ID.

  If the game exists, this will return `{:ok, pid}`.
  Otherwise it will return `{:error, :not_found}`.
  (If there are somehow 2 games with the same ID, or there is some other
  unknown error, this will return `{:error, :unknown}`.)
  """
  @spec lookup(game_id :: String.t()) :: {:ok, pid()} | {:error, :not_found | :unknown}
  def lookup(game_id) do
    case Registry.lookup(registry_name(), game_id) do
      [] -> {:error, :not_found}
      [{pid, _}] -> {:ok, pid}
      _ -> {:error, :unknown}
    end
  end

  @doc """
  Generate a new ID used by the registry to find each game.

  The generated ID will be a string of capital letters with the given length.
  IDs must be at least 4 characters long, and will default to 4 if not given.
  """
  @spec generate_game_id(length :: integer()) :: binary()
  def generate_game_id(length \\ 4)
  def generate_game_id(length) when length >= 4 do
    # TODO: Filter out curse words from the possible list of IDs.
    # Make sure we don't accidentally generate a game server called "FUCK", "SHIT", etc.
    # We'll need to keep a list of 4-letter, 5-letter, etc, words to filter,
    # in addition to checking substrings for these words.
    # If we land on a filtered word, just re-roll the ID with the same length.
    for _ <- 1..(length), into: "", do: <<Enum.random(?A..?Z)>>
  end

  def generate_game_id(_length), do: generate_game_id()
end
