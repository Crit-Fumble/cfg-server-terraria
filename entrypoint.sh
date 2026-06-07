#!/usr/bin/env bash
#
# cfg-server-terraria entrypoint.
#
# Phase 1 (multi-world): the platform side maintains many CoreGameWorld
# records per installation; exactly one is active at a time. The
# launcher resolves it and hands its gen params here as env. The
# entrypoint translates them into TerrariaServer CLI flags and
# autocreates the .wld on first boot if it isn't already on disk.
#
# tini (PID 1) reaps zombies and forwards SIGTERM so worlds save
# cleanly on `docker stop`.
#
# Env knobs (set by core-server's launcher; defaults are for standalone
# `docker run` usage):
#   TERRARIA_WORLD       — world file basename (without .wld); the
#                          platform sends the world record's slug.
#                          Default: 'cfg-world'
#   TERRARIA_AUTOCREATE  — 1 small / 2 medium / 3 large (gen-time only;
#                          ignored if the .wld already exists)
#   TERRARIA_DIFFICULTY  — 0 classic / 1 expert / 2 master / 3 journey
#   TERRARIA_WORLDEVIL   — -1 random / 0 corruption / 1 crimson
#                          (gen-time only; ignored if .wld exists)
#   TERRARIA_SEED        — world seed string; blank = random (gen-time
#                          only). Special seeds like 'for the worthy',
#                          'drunk', 'notTheBees' are valid here.
#   TERRARIA_PORT        — listen port (default: 7777)
#   TERRARIA_MAXPLAYERS  — player cap (default: 16)
#   TERRARIA_PASSWORD    — server password (default: none)
#   TERRARIA_MOTD        — server motd (default: 'Crit-Fumble Terraria Server')
#
# `-config` is NOT used: Terraria 1.4.5+ silently ignores autocreate
# when it reads from a config file. CLI flags are the documented stable
# path. serverconfig.txt is still written for ops introspection (and
# manual recovery if needed), but the live server is driven by flags.

set -euo pipefail

WORLD_DIR=/worlds
CONFIG="$WORLD_DIR/serverconfig.txt"
WORLD_NAME="${TERRARIA_WORLD:-cfg-world}"
WORLD_FILE="$WORLD_DIR/${WORLD_NAME}.wld"

WORLD_SIZE="${TERRARIA_AUTOCREATE:-2}"
WORLD_EVIL="${TERRARIA_WORLDEVIL:--1}"
PORT_NUM="${TERRARIA_PORT:-7777}"
MAX_P="${TERRARIA_MAXPLAYERS:-16}"
DIFF="${TERRARIA_DIFFICULTY:-0}"
SEED="${TERRARIA_SEED:-}"
PASSWORD="${TERRARIA_PASSWORD:-}"
MOTD="${TERRARIA_MOTD:-Crit-Fumble Terraria Server}"

# Always re-emit serverconfig.txt — single source of truth for
# operators and rescue tooling. Cheap and idempotent.
echo "[cfg-server-terraria] writing serverconfig.txt (ops introspection)"
cat > "$CONFIG" <<EOF
world=$WORLD_FILE
worldpath=$WORLD_DIR
worldname=$WORLD_NAME
autocreate=$WORLD_SIZE
worldevil=$WORLD_EVIL
seed=$SEED
difficulty=$DIFF
maxplayers=$MAX_P
port=$PORT_NUM
password=$PASSWORD
motd=$MOTD
language=en/US
upnp=0
secure=1
EOF

cd /opt/terraria

# Build the optional flags carefully so empty values don't materialize
# as `-password ''` / `-seed ''` on the command line (Terraria treats
# `-seed ""` as a literal empty-string seed, not "use random").
EXTRA_FLAGS=()
if [ -n "$PASSWORD" ]; then
  EXTRA_FLAGS+=(-password "$PASSWORD")
fi
if [ -n "$SEED" ]; then
  EXTRA_FLAGS+=(-seed "$SEED")
fi
# `-worldevil` takes 0/1; -1 means "let Terraria pick", and the
# canonical way to express that on the CLI is to omit the flag.
if [ "$WORLD_EVIL" = "0" ] || [ "$WORLD_EVIL" = "1" ]; then
  EXTRA_FLAGS+=(-worldevil "$WORLD_EVIL")
fi

echo "[cfg-server-terraria] starting Terraria server on port $PORT_NUM (world=$WORLD_FILE, autocreate=$WORLD_SIZE, evil=$WORLD_EVIL, difficulty=$DIFF, seed=$([ -n "$SEED" ] && echo "set" || echo "random"))"

exec ./TerrariaServer.bin.x86_64 \
  -world "$WORLD_FILE" \
  -autocreate "$WORLD_SIZE" \
  -worldname "$WORLD_NAME" \
  -port "$PORT_NUM" \
  -players "$MAX_P" \
  -difficulty "$DIFF" \
  -secure \
  -noupnp \
  "${EXTRA_FLAGS[@]}"
