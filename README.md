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

Personas and scene characters share one queue. By default they answer one at a
time, which is what a local model server on one GPU usually manages. If the
server can generate several replies in parallel (koboldcpp's
`--parallelrequests N`, llama.cpp's `--parallel N`), set **Replies at once** to
the same number. Different rooms are then answered at the same time, while each
room still gets one reply after another, so every reply sees the ones before it.
People's profile descriptions are never sent to the model.

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

HoloChat ships as an Elixir release. The `Dockerfile` builds it into an image,
or you can build the release yourself on the target machine. Either way you need:

- **PostgreSQL 13 or newer.** The migrations create the `citext` extension
  themselves. It is a trusted extension, so the database owner can do that
  without superuser rights.
- **A reverse proxy that terminates TLS**, such as Caddy or nginx. The app
  redirects plain HTTP to HTTPS and reads `X-Forwarded-Proto` to tell the two
  apart. The proxy must also pass WebSockets through (LiveView uses `/live`).
  On a trusted intranet you can skip it and serve plain HTTP (see below).
- **One instance.** The AI personas share a single queue and the rate limits
  are kept in memory, so don't run several nodes.

### 1. Create the database

Run this once as the PostgreSQL superuser, with a password of your own:

```sh
psql -U postgres -c "CREATE ROLE holo_chat_prod WITH LOGIN PASSWORD 'change-me';"
psql -U postgres -c "CREATE DATABASE holo_chat_prod OWNER holo_chat_prod;"
```

The role needs nothing beyond owning its database: no `CREATEDB` and no
superuser rights. The tables are created by the migrations in step 3.

### 2. Configure

The release reads its settings from environment variables (see
`config/runtime.exs`):

| Variable | Required | Meaning |
| --- | --- | --- |
| `SECRET_KEY_BASE` | yes | Signs and encrypts cookies. Generate one with `mix phx.gen.secret` or `openssl rand -base64 48`, and keep it: changing it logs everyone out. |
| `PHX_HOST` | yes | The public host name, e.g. `chat.example.com`. Used for links and to check the origin of WebSocket connections, so it must match the browser's address bar. |
| `DATABASE_URL` | one of the two | `ecto://USER:PASSWORD@HOST:PORT/DATABASE`. URL-encode special characters in the password. |
| `DATABASE_HOST`, `DATABASE_PORT`, `DATABASE_NAME`, `DATABASE_USER`, `DATABASE_PASSWORD` | one of the two | The same as separate parts, used when `DATABASE_URL` is not set. Defaults: `localhost`, `5432`, `holo_chat_prod`. |
| `DATABASE_SSL` | no | `true` connects over TLS and verifies the server's certificate against the system CAs. |
| `DATABASE_SSL_CA_CERT` | no | Path to a PEM file to verify the server's certificate against instead, for a private CA. |
| `POOL_SIZE` | no | Database connections, default `10`. |
| `ECTO_IPV6` | no | `true` to reach the database over IPv6. |
| `PORT` | no | The HTTP port the app listens on, default `4000`. |
| `PHX_IP` | no | The address to listen on, e.g. `127.0.0.1` for this machine only. Default: all interfaces (`::` on Linux, `0.0.0.0` on Windows). |
| `PHX_SCHEME` | no | `https` (default) redirects plain HTTP to HTTPS and needs the TLS proxy. `http` serves plain HTTP; see "Plain HTTP on an intranet". |
| `TRUSTED_PROXIES` | behind a proxy | Comma-separated addresses or CIDR ranges of your reverse proxies, e.g. `127.0.0.1` or `172.16.0.0/12`. Only their `X-Forwarded-For` header is believed. Without it, every user seems to come from the proxy's address and the sign-up and login rate limits lock everyone out together. |

For Docker, put them in a file, e.g. `holo_chat.env` (keep it out of git):

```sh
SECRET_KEY_BASE=paste-the-generated-secret-here
PHX_HOST=chat.example.com
DATABASE_HOST=host.docker.internal
DATABASE_USER=holo_chat_prod
DATABASE_PASSWORD=change-me
TRUSTED_PROXIES=172.16.0.0/12
```

### 3. Build, migrate and run

**With Docker:**

```sh
docker build -t holo_chat .

# Create or update the tables (run before every start of a new version)
docker run --rm --env-file holo_chat.env --add-host=host.docker.internal:host-gateway holo_chat bin/migrate

docker run -d --name holo_chat --restart unless-stopped --env-file holo_chat.env \
  --add-host=host.docker.internal:host-gateway -p 127.0.0.1:4000:4000 holo_chat
```

`--add-host` lets the container reach a PostgreSQL running on the host as
`host.docker.internal`; PostgreSQL must then listen on the Docker bridge
(`listen_addresses` in `postgresql.conf`) and allow the role in `pg_hba.conf`.
With a database in another container on the same Docker network, use its
container name as `DATABASE_HOST` instead.

**Without Docker,** on a machine with the same OS and CPU architecture as the
server and Erlang/OTP and Elixir installed (see Requirements):

```sh
scripts/build-release.sh

# With the environment variables from step 2 set:
_build/prod/rel/holo_chat/bin/migrate
_build/prod/rel/holo_chat/bin/server
```

On Windows, build with
`powershell -ExecutionPolicy Bypass -File scripts\build-release.ps1` and run
`bin\migrate.bat` and `bin\server.bat`. Stop a running release before
rebuilding it: Windows can't replace files that are in use, so the script
refuses to start while the release is still running (a leftover `epmd`
from a stopped release it stops by itself).

The script fetches the dependencies, compiles, builds the assets and the
release, and then removes the digested assets from `priv/static` again.
Copy `_build/prod/rel/holo_chat` to the server if you built it elsewhere; it
contains the Erlang runtime and needs no Elixir there. Run `bin/server` from
systemd or a similar service manager.

### Plain HTTP on an intranet

Without a TLS proxy, set `PHX_SCHEME=http` and `PHX_HOST` to the address
people type, e.g. `192.168.1.100`. The app then serves plain HTTP on `PORT`
(open `http://192.168.1.100:4000`) and accepts live connections from whichever
address the page was opened with, so `localhost` keeps working on the server.
Skip step 4 and leave `TRUSTED_PROXIES` unset.

Passwords and session cookies then cross the network unencrypted. Do this
only on a network you trust, never on the internet. On Windows, allow the
app through the firewall when asked (or add an inbound rule for its port).

### 4. Put the proxy in front

With [Caddy](https://caddyserver.com), which fetches certificates and sets
the forwarding headers by itself, the whole configuration is:

```text
chat.example.com {
    reverse_proxy 127.0.0.1:4000
}
```

With nginx, forward `Host`, `X-Forwarded-For` and `X-Forwarded-Proto`, and the
WebSocket `Upgrade` and `Connection` headers.

Set `TRUSTED_PROXIES` to the address the app sees the proxy connecting from:
`127.0.0.1` for a proxy on the same machine talking to a bare release, or the
Docker bridge range (`172.16.0.0/12`) when the app runs in a container with a
published port.

### 5. First start

1. Register your account in the browser, then make it an admin:

   ```sh
   docker exec holo_chat bin/admin grant YOUR_USERNAME
   # or, without Docker: _build/prod/rel/holo_chat/bin/admin grant YOUR_USERNAME
   ```

2. Set up the AI personas at **/admin/assistant** as described above. The
   model server must be reachable from the server running HoloChat: inside a
   container, `localhost` is the container itself, so use the model server's
   network address (or `http://host.docker.internal:5001` with the
   `--add-host` option above).

### Updating and backups

To update, build the new version, run `bin/migrate` with it, then restart the
app. Back up the database regularly. It also holds all images (avatars,
scenarios), so it is the only thing to back up:

```sh
pg_dump -U holo_chat_prod -Fc holo_chat_prod > holo_chat-$(date +%F).dump
pg_restore -U holo_chat_prod -d holo_chat_prod --clean holo_chat-2026-10-20.dump
```

Other release commands: `bin/admin revoke USERNAME`, `bin/holo_chat remote`
(an IEx shell inside the running app) and `bin/holo_chat stop`.
