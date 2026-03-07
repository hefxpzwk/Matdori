# Matdori

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.
Use `/` to share a post with title+link, and `/rooms` to browse created rooms.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Sync commands

* Run one sync cycle: `mix matdori.sync_rooms_once`
* Backfill dry-run: `mix matdori.backfill_rooms --dry-run --max-posts 50`
* Backfill resumable: `mix matdori.backfill_rooms --resume --max-posts 50 --batch-size 50 --sleep-ms 250`

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
