defmodule GamePlatform.GameServer.InternalComms do
  @moduledoc """
  Module containing functions for internal communication and scheduling of future
  events/messages for this server.

  Calls `Process.send_after(self(),...)` to send messages, so this is intended
  only to be used either by GameServer of an implementation of GameState.
  """

  @doc """
  Schedules a game_event to be delivered in the future. This event will arrive
  as if coming from `:game` and is considered an "internal event".

  A reference to this schedule is returned, and this message can be cancelled
  via that reference.

  If given a delay, this message will be sent after the given number of milliseconds.
  """
  @spec schedule_game_event(any(), non_neg_integer()) :: reference()
  @spec schedule_game_event(any()) :: reference()
  def schedule_game_event(event, time \\ 0) do
    Process.send_after(self(), {:game_event, event}, time)
  end

  defp schedule_server_event(event, time) do
    Process.send_after(self(), {:server_event, event}, time)
  end

  @doc """
  Schedules the :end_game message for the server, telling it to shut down.

  A reference to this schedule is returned, and this message can be cancelled
  via that reference.

  If given a delay, this message will be sent after the given number of milliseconds.
  """
  @spec schedule_end_game(non_neg_integer()) :: reference()
  @spec schedule_end_game() :: reference()
  def schedule_end_game(after_millis \\ 0) do
    schedule_server_event(:end_game, after_millis)
  end

  @doc """
  Schedules a disconnect timeout for the given player. After this message is
  delivered, the player will be considered lost and will be kicked from the game.
  (Meaning a "leave_game" message will be sent to the game state.)

  A reference to this schedule is returned, and this message can be cancelled
  via that reference.

  If given a delay, this message will be sent after the given number of milliseconds.
  """
  @spec schedule_player_disconnect_timeout(any(), non_neg_integer()) :: reference()
  @spec schedule_player_disconnect_timeout(any()) :: reference()
  def schedule_player_disconnect_timeout(player_id, after_millis \\ 0) do
    schedule_server_event({:player_disconnect_timeout, player_id}, after_millis)
  end

  @doc """
  Schedules an internal game timeout. Once sent, this will tell the game to
  shut down due to inactivity. Within the server, this timeout is automatically
  refreshed after every player event.

  A reference to this schedule is returned, and this message can be cancelled
  via that reference.

  If given a delay, this message will be sent after the given number of milliseconds.
  """
  @spec schedule_game_timeout(non_neg_integer()) :: reference()
  @spec schedule_game_timeout() :: reference()
  def schedule_game_timeout(after_millis \\ 0) do
    schedule_server_event(:game_timeout, after_millis)
  end

  @doc """
  Cancels a timer reference via `Process.cancel_timer`.
  """
  @spec cancel_scheduled_message(reference()) :: non_neg_integer() | false
  def cancel_scheduled_message(ref) do
    Process.cancel_timer(ref)
  end
end
