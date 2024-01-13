# The Player View

The View portion of WebGames takes advantage of Phoenix LiveView to provide a
real-time updatable view to the player. This is via a websocket that sends
partial HTML segments that are replaced inline in the browser as they are
received. (It's basically "what if server-side rendering was cool".)

The actual "socket" connections are all handled by LiveView, and are outside
the scope of this document.

What _is_ in scope is PlayerView, an implementation of LiveView that renders
a specific layout around a dynamically added LiveComponent called the
PlayerComponent.

## Plugs & PlayerView boilerplate

Like GameServer, the PlayerView (and surrounding Plugs) handles a lot
of the boilerplate setup around each game, such as connection logic and mounting.

### Setting a player_id
Before connecting, a Plug on the `/play` route will check if the player has a
`player_id` set in their session cookies. If they don't, one will be automatically
generated.

This ID persists across all games if they leave/re-join, or join multiple games.

### Fetching game information
After checking to see if the id in `/play/<game_id>` corresponds to an active
game (done via a Process Registry), the PlayerView will fetch some information
about what type of game this is from the server itself. This information will
include what module should be used for the PlayerComponent.

### Join/Connect
All join, PubSub topic subscription, connection, and syncing logic is handled
within the PlayerView.

After the PlayerComponent is mounted, the first function that gets called is
`handle_sync`, as all `:game_event`s are ignored until a `:sync` is received.

### "Leave Game" button
Outside the boundary of the PlayerComponent, several status messages are
displayed, as well as a "Leave Game" button. This immediately sends a "player_leave"
message to the server, and redirects back to the home page.

Clicking this is often preferable to just closing the tab, as the server
does not need to wait for a disconnect timeout to remove the player.

## PlayerComponent @behaviour

Any module that implements `PlayerComponent` will need to implement a module
as though they are implementing a `LiveComponent`. This includes:

* `mount()` to set an initial state on the component
* `render()` to render HTML to be sent to the browser.
  (You can also use `.html.heex` files for rendering.)
* `handle_event()` to handle incoming phoenix events like click and keydown.

> NOTE: You should avoid implementing a custom `update()` function, as `update()` is
used internally.

To create a new PlayerComponent, add the following to your module:
```elixir
  use GamePlatform.PlayerComponent
```

Beyond that and the LiveComponent functions, there are three unique functions
to implement, each representing the handling of incoming messages:

### `handle_sync(socket, payload) :: {:ok, updated_socket}`
This is called to handle `:sync` events from the server. After this message
is handled, `:game_event` messages will start to be processed.

This method should update the `socket` state of the component using the given
payload to get it to an initial view of the game.

### `handle_game_event(socket, payload) :: {:ok, updated_socket}`
Whenever the Server broadcasts a `:game_event` and it is picked up by the
PlayerView, it is sent here for processing.

The payload of this event should be used to update the `socket` make it display
the new state of the game.

### `handle_display_event(socket, payload) :: {:ok, updated_socket}`
This represents internal events inside the PlayerView that only affect
display, without changing anything in the actual game state.

Events of this nature are always triggered by `PlayerView.send_self_event_after()`,
allowing for delayed actions. For example, if a message should clear from the screen
after a certain number of seconds, you can use a display event.

## Example Game - Minesweeper

Minesweeper is a single-player game that involves clickin on tiles and trying
not to blow up.

The View in this game should display four things:
* A count-up timer that starts after the first click
* The game grid
* The total number of flags placed
* The total number of mines in the grid

The game grid in this case is a `grid` css layout of divs, each cell of which
corresponding to the x-y coordinates of a cell in the grid state. These cells
individually contain their own state for things like open/closed, flagged,
displaying mines, etc.

When handling sync, in this case we just want to take the payload given and
push it directly into the socket - no additional processing needed, just
a map merge.

Game events can come in many forms. In this case, since multiple things can
happen in a single click, each message contains a list of payloads, allowing those
payloads to be applied simultaneously between renders. Some examples are:
* `{:flag, cell}`: The flag on this cell has updated.
* `{:click, cell}`: The clicked? value on this cell has updated.
* `{:open, cells}`: A list of cells that should be marked as "open", along with
  their internal values.
* `{:game_over, %{status: status, end_time: time}}`: The game has ended, in
  either a win or loss, and the end_time to use for the game timer.

This game does not make use of `handle_display_event()`.

An example implementation can be found in `WebGamesWeb.Minesweeper.PlayerComponent`.