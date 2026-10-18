# HoloChat

[![CI](https://github.com/FreeApophis/HoloChat/actions/workflows/ci.yml/badge.svg)](https://github.com/FreeApophis/HoloChat/actions/workflows/ci.yml)

A realtime group chat with rooms, presence and AI personas, built with Elixir,
Phoenix LiveView and PostgreSQL.

## Features

- **Rooms:** `#lobby` plus any room you open by name, a sidebar listing active
  rooms with online counts and unread markers, and history that loads as you
  scroll up.
- **Presence:** who is online in a room, and "… is typing" indicators.
- **Accounts without email:** sign up with a username and password. Ten
  single-use recovery codes replace "forgot password" emails. Login, sign-up
  and recovery are rate limited.
- **Guests can read:** posting requires an account.
- **Profiles:** image avatars (resized on the server, stored in the database)
  and a short description, shown on a profile card when you click someone's name.
- **AI personas:** admins create assistants with their own name, avatar,
  system prompt and rooms. A persona answers when mentioned as `@Name`. It
  talks to any OpenAI-compatible model server, such as
  [koboldcpp](https://github.com/LostRuins/koboldcpp), llama.cpp or Ollama.

## Requirements

- Erlang/OTP 29 and Elixir 1.20
- PostgreSQL (with the `citext` extension, included in standard installs)
- Optional: an OpenAI-compatible model server for the AI personas

## Getting started

1. Create the database role that development and tests use (it needs
   `CREATEDB`, not superuser rights):

   ```sh
   psql -U postgres -c "CREATE ROLE holo_chat WITH LOGIN PASSWORD 'holo_chat' CREATEDB;"
   ```

2. Install dependencies, create and migrate the database, and build the assets:

   ```sh
   mix setup
   ```

3. Start the server and open [localhost:4000](http://localhost:4000):

   ```sh
   mix phx.server        # or: iex -S mix phx.server
   ```

4. Register an account in the browser, then make it an admin:

   ```sh
   mix holo_chat.admin grant YOUR_USERNAME
   ```

## AI personas

1. Start a model server, e.g. koboldcpp on its default port 5001.
2. Open **/admin/assistant** (the wrench icon in the header for admins), check
   the endpoint (default `http://localhost:5001`), click **Test connection**,
   tick **Enabled** and save.
3. Create a persona, put it in a room such as `lobby`, and address it in that
   room as `@Name`.

All personas share one queue, because a local model server generates one reply
at a time. People's profile descriptions are never sent to the model.

## Development

The project is developed test-first: a failing test comes before every change.
The conventions, the architecture (contexts with compile-time boundaries
enforced by [Boundary](https://hexdocs.pm/boundary)) and the test rules are in
[CLAUDE.md](CLAUDE.md), and Phoenix-specific guidelines are in [AGENTS.md](AGENTS.md).

```sh
mix test        # run the test suite
mix precommit   # compile with warnings as errors, drop unused locks, format, credo --strict, test
```

CI runs the same gates on every push and pull request, checking formatting and
the lock file instead of fixing them.

## Deployment

There is no production setup yet. Before deploying, take care of at least:

- Configure `DATABASE_URL`, `SECRET_KEY_BASE` and `PHX_HOST` (see `config/runtime.exs`).
- Serve the app over HTTPS.
- If it runs behind a reverse proxy, read the real client IP from the proxy's
  forwarding headers, or the rate limits will treat all users as one client.
- Back up the database. It also holds the avatar images.

See the [Phoenix deployment guides](https://phoenix.hexdocs.pm/deployment.html).
