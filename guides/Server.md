# The Game Server

The backend Server of your game should contain the logic for manipulating game
state based on incoming events.

## GameServer boilerplate

The GameServer module handles some boilerplate for each game:

### Connection monitoring
Once a View has connected and sent a `player_connected` message, the GameServer
will keep `Monitor` the process that sent the message. If the process crashes,
it is treated as a player disconnect.

### Disconnection timeouts
Once a player has disconnected, the GameServer will start a timeout for that
player. If the timeout expires, that player will be treated as though they
have left, and `leave_game()` will be called on that player.

If a player sends a `player_connected` message before the timer expires to
re-establish the connection, the timer is automatically cancelled.

Once the last player has disconnected from the game, the GameServer will
schedule a 60 second game timeout before shutting down.

## Game timeouts
In order to not have games running perpetually, each Server is given a "game
timeout". If this timeout ever expires, the game is considered to be abandoned
and will automatically shut down.

This timeout is refreshed every time a new player joins, or every time a game
event is sent by a player. (Game events triggered internally do not count.)

## PubSub Message Broadcasting
Nearly every function in the `GameState` behaviour can return a `[msgs]` array,
containing `PubSubMessage`s that will be sent out to players.

## The GameState @behaviour

The GameState implementation should be built around a "state" that is updated
by game events. This "state" can be whatever you want it to be,
though it is recommended that you use a struct.

To create a new GameState, add the following to your module:
```elixir
  use GamePlatform.GameState,
    view_module: ModuleName.Of.PlayerComponent,
    dispay_name: "Name of My Game"
```

When implementing the GameState behaviour, the only function that is strictly
necessary is `init()`, as all the others have default no-op operations. However,
this would make for a very boring game that does nothing, so here are all of the
available functions of a GameState, what their purposes are, and some tips on
using them.

### `init(config) :: {:ok, initial_state}`
Once a Server has started, it will call this function to initialize the game
state. No players have connected, no actions have been taken, this is just
initial setup using the provided config.

If the config is invalid for some reason, you can return `{:error, reason}` to
communicate that to the Server, at which point it will shut down - can't recover
from an invalid startup config.

### `join_game(state, player_id) :: {:ok, [topics], [msgs], new_state}`
When a new player starts trying to connect to the game, this is always the first
function called. It is essentially asking the game state both for permission to
join, as well as for what topics it needs to subscribe to in order to connect.

If the player is allowed to join, it is recommended that you use this function
to set up that players initial state and add them to some kind of list. In a
racing game, this might set their initial position on the track and add them
to the list of racers.

By default the GameServer will always add two topics for the View to subscribe
to:
* **`:all`**: A topic subscribed to by all connected players.
* **`{:player, player_id}`**: A topic _specific_ to this one player.

However, `join_game()` can return additional topics to subscribe to. For example,
if this is an active "player", it can return the `:players` topic, as opposed to
all other joiners getting the `:audience` topic after the game has already
started. This way, the players and audience are getting different views of the
game by being subscribed to different topics.

(In practice, these topics are expanded strings such as `"game:<game_id>"` and
`"game:<game_id>:player:<player_id>"`. However, to condense the messages,
this shorthand is used and expanded by the `PubSubMessage` module when necessary.)

It is likely that a player may join multiple times. If the connection
is bad, or if the player refreshes their browser, their View will "join" as its
first action. In this case, implementations of this function should simply
return the topics as normal, but not update state since the player is already
listed.

`join_game()` can also outright reject a player by returning `{:error, reason}`.
This will tell the GameServer that the join was unsuccessful, and the error
will be returned to the calling process that was asking to join.

### `leave_game(state, player_id) :: {:ok, [msgs], new_state}`
The opposite of `join_game()`, this function should remove the given player
from the game state. For example, if this is a card game, the players hand can
be shuffled back into the deck before they are removed from the players list.

### `player_connected(state, player_id) :: {:ok, [msgs], new_state}`
Once a player has joined, the View will attempt to subscribe to the topics
it was given by `join_game()`. After it was successful, it will call this
function.

The purpose of this function is to "sync" the player into the current state by
returning a `:sync` message. This can be built via the `PubSubMessage.build()`
function, and is a special category of message that the view needs to wait for
before it will accept game events.

The `:sync` message should contain all the information about the game state
that the player would need to for an initial render of their view. In a card game,
this might include:
* That players hand of cards
* The number of cards left in the deck
* The number of cards in each players hand
* The card that is face-up in the discard pile

Other messages can also be sent, letting other players know that this player has
successfully connected.

In practice, this function likely won't do much to modify the actual game state,
but it can if it needs to. A connection message could work to unpause the
game if it pauses on disconnect, for example.

### `player_disconnected(state, player_id) :: {:ok, [msgs], new_state}`
The opposite of `player_connected()`, this is called by the GameServer when it
detects that a player's View process has crashed.

The player hasn't "left" the game in this case, but may have refreshed their
browser, closed the window, or otherwise disconnected. You may want to pause
events, or alert other players that a player has disconnected.

### `handle_event(state, from_id, event) :: {:ok, [msgs], new_state}`
This is the primary game method. This function is called whenever the GameServer
gets a `:game_event` from a player.

Essentially, a player did a thing, and this function updates the game state
accordingly.

Events can also be triggered internally - by using
`InternalComms.schedule_game_event()`, you can set events to happen in the
future via `Process.send_after()`. For example, when a players turn starts,
you can schedule a `:turn_timeout` for that player to send after several
seconds. Once that event arrives, the game can cancel that players turn and
move on with someone elses, setting a new `:turn_timeout` for that player.
If the player acts, however, the `:turn_timeout` can be cancelled via
`InternalComms.cancel_scheduled_message()` during this function.

Internal events coming from `InternalComms.schedule_game_event()` can be identified
by their `from` argument being `:game` instead of a player ID.

### `handle_game_shutdown(state) :: {:ok, [msgs], new_state}`
Once a game has been told to shut down, this is the last function called. This
should be used to clean up any external state that isn't being handled by
`Supervisor`s, as well as send any messages to any still-connected players.

No matter what this returns, the Server will halt after this point.

## An Example Game - Minesweeper

Minesweeper is a single-player game that involves clicking on tiles, and
trying not to blow up.

For our `join_game()` and `leave_game()` functions, we only need to keep
track of one player id. If the player id is already set and someone else
tries to join, they can be rejected with `{:errror, :game_full}`.

On `player_connected()`, the sync message should contain all "public" information
in the state - open cells and their contents, and which cells are closed.

For each cell, that public information includes:
* Whether or not the cell is flagged
* Whether or not the cell is open, and if it is, what number it displays
* Whether or not the cell has been clicked (different from opened for display reasons)
* If the game is over, whether or not the cell contains a mine

Other information, such as whether or not the game is ongoing (or if there is a
win/loss), how many total mines there are, etc, should also be included.

We don't need to implement `player_disconnected()` because nothing should happen.

Now the big one - `handle_event()` is the actual game logic. We have two actions
a player can take while the game is running: open a cell, and flag a cell.

Flagging a cell simply marks that cell as flagged. A message should be sent to
tell the player View which cell is now marked as flagged.

Opening a cell is trickier because of the cascade effect in Minesweeper - if a
cell has a value of 0 (meaning no adjacent cells have any mines), all cells
adjacent to that cell also open. This continues until we run out of non-0 cells
to open in that contiguous area

This is also made tricky by the fact that the first move is _always_ considered
safe. Therefore, mines should only be placed _after_ the first time a player
opens a cell.

So once all cells have been opened, which cells changed (and what values they
display) need to be sent to the player.

If a cell _does_ contain a mine, the game needs to immediately end in a loss.
However, if this was the last non-mined space to be opened, the game should end
in victory.

In either game-end case, all mine locations should be revealed to the player.

Actual implementation of this is in the `WebGames.Minesweeper.GameState` module.