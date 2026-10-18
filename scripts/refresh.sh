#!/bin/bash
# Keep the server on the build Steam ships, and only ever restart an empty one.
#
#   scripts/refresh.sh             update if behind and nobody is on
#   scripts/refresh.sh --check     say whether it is behind, change nothing
#   scripts/refresh.sh --dry-run   go as far as deciding, change nothing
#   scripts/refresh.sh --force     restart even with players on, or unknown
#
# WHY. VEIN is in early access and patched often. Steam updates every
# player's client by itself, and a server one build behind turns all of them
# away, with a healthy container and an answering port to say otherwise. The
# image runs SteamCMD on every start, so the fix is a restart; this decides
# when one is due and when one would hurt somebody.
#
# BOTH BUILD NUMBERS ARE READ, NEITHER IS ASSUMED: the installed one from the
# app manifest SteamCMD writes into the volume, Steam's from app_info_print,
# asked anonymously in a throwaway container of the same image, the way the
# server installs itself. An update counts only when the manifest afterwards
# names Steam's build.
#
# AN UNANSWERED PLAYER QUERY IS NOT AN EMPTY SERVER. The count comes from A2S
# on the query port, from inside the server's network namespace, asked three
# times. A server that never answers is "?" and is skipped like an occupied
# one, and this exits 1, because a probe that can never tell is a probe
# somebody should look at. On the machine this template comes from, an update
# roll that read "cannot count" as zero had three game stacks reading as empty
# whatever was happening on them.
#
# tests/e2e-refresh.sh proves the decisions against a stand-in server.
#   VEIN_PROJECT        the compose project   (default vein)
#   VEIN_REMOTE_BUILD   Steam's build, if known another way; set but empty
#                       means "could not be read" (tests use both)
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

MODE=""
FORCE=false
for arg in "$@"; do
  case "$arg" in
    --check) MODE=check ;;
    --dry-run) MODE=dry-run ;;
    --force) FORCE=true ;;
    *) echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done

PROJECT="${VEIN_PROJECT:-vein}"
COMPOSE="vein-server-docker-compose.yml"
APP=2131400
MANIFEST="/home/steam/vein/steamapps/appmanifest_$APP.acf"
QPORT="$(grep -E '^VEIN_SERVER_QUERY_PORT=' .env 2>/dev/null | head -1 | cut -d= -f2-)"
QPORT="${QPORT:-27015}"
say() { echo "$(date '+%F %T') $*"; }

cid="$(docker compose -p "$PROJECT" ps -q --status running vein-server 2>/dev/null || true)"
[ -n "$cid" ] || { say "the server is not running; nothing to refresh"; exit 0; }

local_build() {
  docker exec "$cid" sh -c "grep -oE '\"buildid\"[[:space:]]+\"[0-9]+\"' $MANIFEST 2>/dev/null | grep -oE '[0-9]+' | head -1" 2>/dev/null
}
remote_build() {
  if [ -n "${VEIN_REMOTE_BUILD+x}" ]; then echo "$VEIN_REMOTE_BUILD"; return; fi
  local image
  image="$(docker inspect -f '{{.Config.Image}}' "$cid")"
  docker run --rm --entrypoint steamcmd --security-opt no-new-privileges:true "$image" \
      +login anonymous +app_info_update 1 +app_info_print "$APP" +quit 2>/dev/null \
    | tr -d '\r' | awk '/"branches"/{b=1} b && /"public"/{p=1} p && /"buildid"/{gsub(/[^0-9]/,""); print; exit}'
}

installed="$(local_build)"
latest=""
for attempt in 1 2; do
  latest="$(remote_build)"
  [ -n "$latest" ] && break
  [ "$attempt" = 1 ] && [ -z "${VEIN_REMOTE_BUILD+x}" ] && sleep 20
done
if [ -z "$installed" ] || [ -z "$latest" ]; then
  say "could not read both builds: installed '${installed:-?}', Steam '${latest:-?}'; nothing changed" >&2
  exit 1
fi
if [ "$installed" = "$latest" ]; then
  say "up to date: build $installed"
  exit 0
fi
if [ "$MODE" = check ]; then
  say "behind: running build $installed, Steam ships $latest"
  exit 0
fi

players="$(docker run --rm --network "container:$cid" -e PORT="$QPORT" python:3.13-alpine python3 -c '
import os, socket
port = int(os.environ["PORT"])
req = b"\xff\xff\xff\xff\x54Source Engine Query\x00"
for _ in range(3):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(6)
    try:
        s.sendto(req, ("127.0.0.1", port)); d, _ = s.recvfrom(4096)
        if d[4:5] == b"\x41":
            s.sendto(req + d[5:9], ("127.0.0.1", port)); d, _ = s.recvfrom(4096)
        b = d[6:]; p = b.split(b"\x00", 4)
        print(b[len(p[0]) + len(p[1]) + len(p[2]) + len(p[3]) + 4:][2])
        break
    except Exception:
        continue
    finally:
        s.close()
else:
    print("?")
' 2>/dev/null || echo "?")"
case "$players" in ''|*[!0-9]*) players="?" ;; esac
if [ "$players" = "?" ] && [ "$FORCE" != "true" ]; then
  say "behind ($installed -> $latest), and the server did not answer the player query three times, so nobody can say who is on; not restarting. --force restarts anyway" >&2
  exit 1
fi
if [ "$players" != "?" ] && [ "$players" -gt 0 ] && [ "$FORCE" != "true" ]; then
  say "behind ($installed -> $latest), but $players player(s) are on; trying again next run"
  exit 0
fi
if [ "$MODE" = dry-run ]; then
  say "would restart to update ($installed -> $latest): players online: $players$([ "$FORCE" = "true" ] && echo ', forced')"
  exit 0
fi

scripts/backup.sh >/dev/null 2>&1 || say "the backup did not complete; updating anyway" >&2
say "behind ($installed -> $latest), players online: $players; restarting so SteamCMD fetches it"
docker compose -f "$COMPOSE" -p "$PROJECT" restart vein-server >/dev/null
# SteamCMD runs before the server starts; give it the time a patch takes.
for _ in $(seq 1 60); do
  sleep 10
  [ "$(local_build)" = "$latest" ] && break
done
now="$(local_build)"
if [ "$now" = "$latest" ]; then
  say "updated: build $installed -> $now"
  exit 0
fi
say "FAILED: still on build ${now:-unknown} ten minutes after the restart; players on the new client cannot join until it updates. docker compose -p $PROJECT logs --tail 200 vein-server" >&2
exit 1
