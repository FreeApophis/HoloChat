#!/bin/sh
# Builds the production release into _build/prod/rel/holo_chat.
#
#   scripts/build-release.sh
#
# Then, with the environment variables from the README's Deployment section set:
#
#   _build/prod/rel/holo_chat/bin/migrate
#   _build/prod/rel/holo_chat/bin/server
#
# The release only runs on the OS and CPU architecture it was built on.
set -eu

cd -P -- "$(dirname -- "$0")/.."

step() { printf '==> %s\n' "$1"; }

# The release has its own copy; the digested files would only clutter git status.
clean_digests() {
  step "Removing digested assets from priv/static"
  MIX_ENV=dev mix phx.digest.clean --all >/dev/null
}
trap clean_digests EXIT

step "Fetching dependencies"
MIX_ENV=prod mix deps.get --only prod
step "Compiling"
MIX_ENV=prod mix compile
step "Building assets"
MIX_ENV=prod mix assets.deploy
step "Building the release"
MIX_ENV=prod mix release --overwrite

printf '\nRelease ready in _build/prod/rel/holo_chat\n'
