defmodule GamePlatform.GameServerCase do
  @moduledoc """
  This module defines the test case to be used by
  tests on the GameServer module.

  This case will set up appropriate mocks and provide
  helper functions.
  """

  use ExUnit.CaseTemplate

  import Mock

  alias GamePlatform.MockGameState
  alias GamePlatform.GameServer.InternalComms

  def connect_players(state, ids) do
    #Fake some monitors for connected players by generating refs for them.
    {id_refs, connected_ids, connected_monitors} = ids
    |> Stream.map(fn id -> {id, Kernel.make_ref()} end)
    |> Enum.reduce({%{}, MapSet.new(), %{}}, fn ({id, ref}, {id_refs, connected_ids, connected_monitors}) ->
      {Map.put(id_refs, id, ref), MapSet.put(connected_ids, id), Map.put(connected_monitors, ref, id)}
    end)

    connected_state = state
    |> Map.put(:connected_player_ids, connected_ids)
    |> Map.put(:connected_player_monitors, connected_monitors)

    # Return which refs correspond to which ids too so we can
    # do assertions on them.
    {id_refs, connected_state}
  end

  defp default_state() do
    %{
      game_id: "ABCD",
      game_module: MockGameState,
      game_config: %{conf: :success},
      game_state: %{game_type: :test},
      start_time: ~U[2024-01-06 23:25:38.371659Z],
      server_config: %{
        game_timeout_length: :timer.minutes(5),
        player_disconnect_timeout_length: :timer.minutes(2),
        pubsub: WebGames.PubSub,
      },
      timeout_ref: nil,
      connected_player_ids: MapSet.new(),
      connected_player_monitors: %{},
      player_timeout_refs: %{},
    }
  end

  using do
    quote do
      import GamePlatform.GameServerCase, only: [connect_players: 2]
      import Mock

      alias GamePlatform.PubSubMessage
      alias GamePlatform.GameServer
      alias GamePlatform.GameServer.GameMessage
      alias GamePlatform.GameServer.InternalComms
      alias GamePlatform.MockGameState
    end
  end

  setup_with_mocks([
    {MockGameState, [:passthrough], []},
    {InternalComms, [], [
      schedule_game_event: fn(_) ->
        Kernel.make_ref()
      end,
      schedule_end_game: fn(_) ->
        Kernel.make_ref()
      end,
      schedule_game_timeout: fn(_) ->
        Kernel.make_ref()
      end,
      schedule_player_disconnect_timeout: fn(_, _) ->
        Kernel.make_ref()
      end,
      cancel_scheduled_message: fn(_) -> 1000 end
    ]}
  ]) do
    {:ok, %{state: default_state()}}
  end
end
