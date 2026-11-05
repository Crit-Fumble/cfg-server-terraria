#!/usr/bin/env bash
#
# Boots the image once per world-evil value and proves each one reaches
# "Listening on port", stops with a saved world, and exits 0. A fourth run
# proves a value outside the contract ends the container at once with exit 1.
#
# Docker is the only prerequisite. Builds the image unless IMAGE names one.
#
#   test/boot.sh                 # builds cfg-server-terraria:test, then runs
#   IMAGE=ghcr.io/crit-fumble/cfg-server-terraria:main test/boot.sh
#
# The three boots run at once: each generates a small world, which takes a
# minute or two of CPU, and the runs do not share anything.

set -euo pipefail

cd "$(dirname "$0")/.."
IMAGE="${IMAGE:-cfg-server-terraria:test}"
# How long one boot may take to reach "Listening on port", world generation included.
BOOT_TIMEOUT="${BOOT_TIMEOUT:-600}"
RUN="tt-boot-$$"
WORK="$(mktemp -d)"

cleanup() {
  docker rm -f "$RUN-m1" "$RUN-0" "$RUN-1" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

if [ -z "${IMAGE_PREBUILT:-}" ] && [ "$IMAGE" = "cfg-server-terraria:test" ]; then
  docker build -t "$IMAGE" .
fi

fail() { echo "FAIL: $*" >&2; exit 1; }

# A value outside -1/0/1 must end the container before TShock starts.
echo "== TERRARIA_WORLDEVIL=2 is refused"
rc=0
docker run --rm -e TERRARIA_WORLDEVIL=2 "$IMAGE" >"$WORK/bad.log" 2>&1 || rc=$?
[ "$rc" -eq 1 ] || { cat "$WORK/bad.log"; fail "expected exit 1 for TERRARIA_WORLDEVIL=2, got $rc"; }
grep -q 'TERRARIA_WORLDEVIL must be -1, 0 or 1' "$WORK/bad.log" || { cat "$WORK/bad.log"; fail "no refusal line for TERRARIA_WORLDEVIL=2"; }

# The engine's own "Creating world" line names the evil it generates: 0 corruption, 1 crimson.
# -1 lets the engine pick, so either is right there.
for evil in -1 0 1; do
  name="$RUN-${evil#-}"; [ "$evil" = "-1" ] && name="$RUN-m1"
  mkdir -p "$WORK/$name"
  # As the uid that owns the mount, the way the platform runs a member's server on that member's own volume. A
  # Linux host enforces the 0700 owner of a mktemp dir, which Docker Desktop's bind mounts hide.
  docker run -d --name "$name" --user "$(id -u):$(id -g)" -e TERRARIA_AUTOCREATE=1 -e "TERRARIA_WORLDEVIL=$evil" \
    -v "$WORK/$name:/worlds" "$IMAGE" >/dev/null
done

for evil in -1 0 1; do
  name="$RUN-${evil#-}"; [ "$evil" = "-1" ] && name="$RUN-m1"
  echo "== TERRARIA_WORLDEVIL=$evil boots"
  # The log is read into a variable, never piped into grep -q: under pipefail a
  # grep -q that exits at its first match fails the pipeline through SIGPIPE.
  SECONDS=0
  log=""
  while :; do
    status="$(docker inspect "$name" --format '{{.State.Status}}')"
    log="$(docker logs "$name" 2>&1)"
    [ "$status" = "running" ] || { printf '%s\n' "$log" | tail -30; fail "evil=$evil: container is $status before listening"; }
    case "$log" in
      *"Startup aborted"*) printf '%s\n' "$log" | tail -30; fail "evil=$evil: TShock aborted" ;;
      *"Listening on port"*) break ;;
    esac
    [ "$SECONDS" -lt "$BOOT_TIMEOUT" ] || { printf '%s\n' "$log" | tail -30; fail "evil=$evil: not listening after ${BOOT_TIMEOUT}s"; }
    sleep 2
  done
  case "$evil" in
    0|1) case "$log" in
           *"Creating world - "*"Evil: $evil,"*) ;;
           *) printf '%s\n' "$log" | grep 'Creating world' || true; fail "evil=$evil: the engine generated a different evil" ;;
         esac ;;
  esac

  docker stop -t 60 "$name" >/dev/null
  rc="$(docker inspect "$name" --format '{{.State.ExitCode}}')"
  [ "$rc" -eq 0 ] || { docker logs "$name" 2>&1 | tail -20; fail "evil=$evil: exit $rc on stop"; }
  [ -s "$WORK/$name/cfg-world.wld" ] || fail "evil=$evil: no saved world after stop"
done

echo "OK: -1, 0 and 1 boot, listen, save and exit 0; 2 is refused"
