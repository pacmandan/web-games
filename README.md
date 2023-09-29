# WebGames

This is an experiment, attempting to set up a "game engine" of sorts that can support multiple games using Elixir.

The idea is to have a common "framework" underlying multiple, diverse games that can be supported on the same server.
Single-player, two-player, multi-player, games with an "audience" (similar to Jackbox), games that are state-driven only,
games that are timer-driven, turn-based games, real-time games, I want this to support a bunch of different things.

Ideally, I want the "framework" to be a library or separate application that these games can build on top of, though
I may give up on that if it turns out I bit off more than I could chew. Either way, I'm using this as an excuse to
play around with PubSub, LiveView, and process registration techniques. (Things most database-driven applications
don't usually need to care about.)

To that end, I will probably end up migrating this to an umbrella application at some point.

## Starting the server

To start your Phoenix server:

  * Run `mix setup` to install and setup dependencies
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

  * Official website: https://www.phoenixframework.org/
  * Guides: https://hexdocs.pm/phoenix/overview.html
  * Docs: https://hexdocs.pm/phoenix
  * Forum: https://elixirforum.com/c/phoenix-forum
  * Source: https://github.com/phoenixframework/phoenix
