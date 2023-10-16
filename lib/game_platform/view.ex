defmodule GamePlatform.View do
  @moduledoc """
  UNFINISHED DOCS
  This should be the "generic LiveView" that game views should build on top of.

  Behaviors to implement:
  mount()
  - initialize socket state
  - subscribe to topics
  - monitor game process
  - redirect on failure (make this configurable somehow?)

  try_reconnect

  handle game :DOWN

  handle game events?
  (Should "process event" be the thing to implement?)
  (Is there a generic thing we can do per-event?)

  I think I need to rename a few things.
  Instead of "notification" or "event", should it just be "message"?


  assigns:
  player_id,
  game_id,
  topics,
  player_opts,
  player_state,

  """

  alias GamePlatform.Game

  defmacro __using__(_) do
    quote do

    end
  end

  def send_event(event, socket) do
    Game.send_event(event, socket.assigns[:player_id], socket.assigns[:game_id])
  end

  # def mount(_params, %{"game_id" => game_id, "player_id" => player_id, "topics" => topics, "player_opts" => _player_opts}, socket) do
  #   if Game.game_exists?(game_id) do
  #     socket = if connected?(socket) do
  #       Enum.each(topics, fn topic -> Phoenix.PubSub.subscribe(WebGames.PubSub, topic) end)
  #       Game.player_connected(player_id, game_id, self())

  #       assign(socket, :game_monitor, Game.monitor(game_id))
  #     else
  #       socket
  #     end
  #   else
  #     {:ok, redirect(socket, to: "/select-game")}
  #   end
  # end
end
