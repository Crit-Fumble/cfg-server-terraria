#!/usr/bin/env bash
#
# cfg-server-terraria entrypoint.
#
# Generates a minimal serverconfig.txt from TERRARIA_* env vars on first
# boot if /worlds/serverconfig.txt is absent, then launches the upstream
# TerrariaServer binary. tini (PID 1) reaps zombies and forwards SIGTERM
# so worlds save cleanly on `docker stop`.
#
# Env knobs:
#   TERRARIA_WORLD       — world file basename (default: cfg-world)
#   TERRARIA_PORT        — listen port (default: 7777)
#   TERRARIA_MAXPLAYERS  — player cap (default: 8)
#   TERRARIA_DIFFICULTY  — 0 classic / 1 expert / 2 master / 3 journey
#   TERRARIA_AUTOCREATE  — 1 small / 2 medium / 3 large; only on first boot
#   TERRARIA_PASSWORD    — server password (default: none)
#   TERRARIA_MOTD        — server motd
#   TERRARIA_SEED        — world seed; blank = random
#
# A user-supplied /worlds/serverconfig.txt (mounted in by core-server) wins
# over the env-driven template — letting the platform layer drive config
# precisely while still being usable standalone.

set -euo pipefail

WORLD_DIR=/worlds
CONFIG="$WORLD_DIR/serverconfig.txt"
WORLD_NAME="${TERRARIA_WORLD:-cfg-world}"
WORLD_FILE="$WORLD_DIR/${WORLD_NAME}.wld"

if [ -f "$CONFIG" ]; then
  echo "[cfg-server-terraria] using mounted serverconfig.txt at $CONFIG"
else
  echo "[cfg-server-terraria] generating serverconfig.txt from env"
  cat > "$CONFIG" <<EOF
world=$WORLD_FILE
worldpath=$WORLD_DIR
worldname=$WORLD_NAME
autocreate=${TERRARIA_AUTOCREATE:-2}
seed=${TERRARIA_SEED:-}
difficulty=${TERRARIA_DIFFICULTY:-0}
maxplayers=${TERRARIA_MAXPLAYERS:-8}
port=${TERRARIA_PORT:-7777}
password=${TERRARIA_PASSWORD:-}
motd=${TERRARIA_MOTD:-Crit-Fumble Terraria Server}
language=en/US
upnp=0
secure=1
EOF
fi

cd /opt/terraria

# IMPORTANT: don't use `-config` — autocreate is silently ignored when
# Terraria 1.4.5+ reads it via config file. The server boots into a
# "no world loaded" state, players see an empty void, and the next
# tile-related code path crashes with a fatal NullReferenceException.
# CLI flags are documented + reliable. The serverconfig.txt is kept
# on disk for human-readability + ops introspection, but the live
# server is driven by the flags below.

WORLD_SIZE="${TERRARIA_AUTOCREATE:-2}"
PORT_NUM="${TERRARIA_PORT:-7777}"
MAX_P="${TERRARIA_MAXPLAYERS:-16}"
DIFF="${TERRARIA_DIFFICULTY:-0}"
PASS_ARG=""
if [ -n "${TERRARIA_PASSWORD:-}" ]; then
  PASS_ARG="-password ${TERRARIA_PASSWORD}"
fi

echo "[cfg-server-terraria] starting Terraria server on port $PORT_NUM (world=$WORLD_FILE, autocreate=$WORLD_SIZE)"
# shellcheck disable=SC2086  # PASS_ARG must word-split
exec ./TerrariaServer.bin.x86_64 \
  -world "$WORLD_FILE" \
  -autocreate "$WORLD_SIZE" \
  -worldname "$WORLD_NAME" \
  -port "$PORT_NUM" \
  -players "$MAX_P" \
  -difficulty "$DIFF" \
  -secure \
  -noupnp \
  $PASS_ARG
