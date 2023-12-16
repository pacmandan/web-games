defmodule GamePlatform.Game do
  @moduledoc """
  Module with commands used to interact with game servers from the player views.
  """

  alias GamePlatform.GameRegistry
  alias GamePlatform.GameServer
  alias GamePlatform.GameServer.GameMessage

  @doc """
  Join the given game under the given player ID.

  The game will record this player ID as having "joined" and will
  return a list of PubSub topics this player should subscribe to.
  """
  @spec join_game(player_id :: String.t(), game_id :: String.t()) ::
    {:ok, list(String.t())} | {:error, any()}
  def join_game(player_id, game_id) do
    msg = %GameMessage{
      action: :player_join,
      from: player_id,
      ctx: OpenTelemetry.Tracer.current_span_ctx(),
    }

    GenServer.call(GameServer.via_tuple(game_id), msg)
  end

  @doc """
  Send the given event to the game server.

  This is done as a cast, so this will not return a response.
  Responses from the server will come in the form of PubSub messages to
  whichever player is appropriate to notify.
  """
  @spec send_event(any(), from :: String.t(), game_id :: String.t()) :: :ok
  def send_event(event, from, game_id) do
    msg = %GameMessage{
      action: :game_event,
      from: from,
      payload: event,
      ctx: OpenTelemetry.Tracer.current_span_ctx(),
    }
    GenServer.cast(GameServer.via_tuple(game_id), msg)
  end

  @doc """
  Tell the server that this player is connected to all of the appropriate
  PubSub topics and is ready to recieve a :sync message on one of them.

  This also gives the game server the players PID so it can monitor if any
  player process dies due to disconnection.
  """
  @spec player_connected(player_id :: String.t(), game_id :: String.t(), pid()) :: :ok
  def player_connected(player_id, game_id, pid) do
    msg = %GameMessage{
      action: :player_connected,
      from: player_id,
      payload: %{
        pid: pid,
      },
      ctx: OpenTelemetry.Tracer.current_span_ctx(),
    }
    GenServer.cast(GameServer.via_tuple(game_id), msg)
  end

  @doc """
  Tell the server this player is leaving the game.

  Doing it this way instead of just disconnecting will force the server to
  remove the player instead of waiting for a reconnection and timing out.
  """
  @spec leave_game(player_id :: String.t(), game_id :: String.t()) ::
    :ok | :error
  def leave_game(player_id, game_id) do
    msg = %GameMessage{
      action: :player_leave,
      from: player_id,
      ctx: OpenTelemetry.Tracer.current_span_ctx(),
    }
    GenServer.call(GameServer.via_tuple(game_id), msg)
  end

  # def restart_game(player_id, game_id) do
  #   msg = %GameMessage{
  #     action: :restart,
  #     from: player_id,
  #     ctx: OpenTelemetry.Tracer.current_span_ctx(),
  #   }
  #   GenServer.call(GameServer.via_tuple(game_id), msg)
  # end

  @doc """
  Get the game info for the server.

  This info includes things like the display name, component module,
  and server module.
  """
  @spec get_game_info(game_id :: String.t()) :: {:ok, GamePlatform.GameState.GameInfo.t()}
  def get_game_info(game_id) do
    GenServer.call(GameServer.via_tuple(game_id), :game_info)
  end

  # TODO: Move some of these Registry.lookup() functions into GameRegistry

  def monitor(game_id) do
    {:ok, pid} = GameRegistry.lookup(game_id)
    Process.monitor(pid)
  end

  def game_exists?(game_id) do
    Registry.lookup(GameRegistry.registry_name(), game_id) |> Enum.count() > 0
  end

  def is_game_alive?(game_id) do
    case Registry.lookup(GameRegistry.registry_name(), game_id) do
      [] -> false
      [{pid, _}] -> Process.alive?(pid)
    end
  end
end
