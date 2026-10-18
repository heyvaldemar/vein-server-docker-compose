#!/bin/bash
# Put a VEIN world archive from scripts/backup.sh back where the server reads it.
#
#   scripts/restore.sh backups/vein-world-20261018-043000.tar.gz
#
# THE PATH IS THE WHOLE JOB. The server looks for its world in
# Vein/Saved/SaveGames inside the volume and, finding none there, generates a
# new one without a word. A restore one directory too deep (Saved/Saved, or
# Saved at the volume's root) succeeds, reports success, and leaves players in
# a fresh world. On the machine this template comes from, the first restore of
# a real world did exactly that. So this extracts at the one anchor the backup
# was made from, and then checks that every save file in the archive is at its
# live path, and that nothing landed one level too deep.
#
# NOTHING IS OVERWRITTEN. The world the volume holds now is moved aside to
# Vein/Saved.before-restore-<time> first, so a restore of the wrong archive is
# undone by moving it back.
#
# The server must be stopped: it holds the world in memory and would write it
# over the restored one on its way out.
#
#   VEIN_VOLUME    the data volume      (default vein-server-data)
#   VEIN_PROJECT   the compose project  (default vein)
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

ARCHIVE="${1:-}"
VOLUME="${VEIN_VOLUME:-vein-server-data}"
PROJECT="${VEIN_PROJECT:-vein}"

if [ -z "$ARCHIVE" ] || [ ! -f "$ARCHIVE" ]; then
  echo "usage: scripts/restore.sh <archive from scripts/backup.sh>" >&2
  exit 2
fi
if ! docker volume inspect "$VOLUME" >/dev/null 2>&1; then
  echo "no volume $VOLUME: create it first (docker volume create $VOLUME)" >&2
  exit 1
fi

running="$(docker compose -p "$PROJECT" ps -q --status running vein-server 2>/dev/null || true)"
if [ -n "$running" ]; then
  echo "the server is running; stop it first, or it writes its world over the restored one on the way out:" >&2
  echo "  docker compose -f vein-server-docker-compose.yml -p $PROJECT stop vein-server" >&2
  exit 1
fi

DIR="$(cd "$(dirname "$ARCHIVE")" && pwd)"
FILE="$(basename "$ARCHIVE")"

# What the archive holds, read before anything moves. A VEIN world archive has
# save files under Saved/SaveGames and nothing outside Saved/.
listing="$(docker run --rm -v "$DIR":/in:ro alpine:3.20 tar -tzf "/in/$FILE" 2>/dev/null)" || {
  echo "$ARCHIVE is not a readable tar.gz; nothing changed" >&2
  exit 1
}
# Files at any depth below SaveGames; a directory entry ends in /.
SAVE_FILES='^(\./)?Saved/SaveGames/.*[^/]$'
saves="$(grep -E "$SAVE_FILES" <<<"$listing" | grep -c .)"
outside="$(grep -vE '^(\./)?Saved(/|$)' <<<"$listing" | grep -c .)"
if [ "$saves" -lt 1 ] || [ "$outside" -gt 0 ]; then
  echo "$ARCHIVE is not a VEIN world archive from scripts/backup.sh ($saves save file(s) under Saved/SaveGames, $outside entr(ies) outside Saved/); nothing changed" >&2
  exit 1
fi

stamp="$(date +%Y%m%d-%H%M%S)"
docker run --rm -v "$VOLUME":/data -v "$DIR":/in:ro -e STAMP="$stamp" -e FILE="$FILE" alpine:3.20 sh -euc '
  mkdir -p /data/Vein
  if [ -e /data/Vein/Saved ]; then mv /data/Vein/Saved "/data/Vein/Saved.before-restore-$STAMP"; fi
  tar -xzf "/in/$FILE" -C /data/Vein
  # The server runs as the image steam user, uid 1000.
  chown -R 1000:1000 /data/Vein/Saved
' || { echo "the extract failed; the previous world, if any, is in Vein/Saved.before-restore-$stamp" >&2; exit 1; }

# PROVE IT LANDED: every save file in the archive at its live path, and
# nothing one level too deep.
found="$(grep -E "$SAVE_FILES" <<<"$listing" | sed 's#^\./##' | docker run --rm -i -v "$VOLUME":/data:ro alpine:3.20 \
  sh -c 'n=0; while IFS= read -r f; do [ -f "/data/Vein/$f" ] && n=$((n + 1)) || echo "not at its live path: Vein/$f" >&2; done; echo "$n"')"
missing=0
if [ "${found:-0}" != "$saves" ]; then
  echo "${found:-0} of $saves save file(s) are at their live path" >&2
  missing=1
fi
if docker run --rm -v "$VOLUME":/data:ro alpine:3.20 sh -c 'test -e /data/Vein/Saved/Saved || test -e /data/Saved'; then
  echo "a Saved directory landed one level too deep or at the volume's root; the server would not find the world" >&2
  missing=$((missing + 1))
fi
if [ "$missing" -gt 0 ]; then
  echo "restore FAILED its check; the previous world, if any, is in Vein/Saved.before-restore-$stamp" >&2
  exit 1
fi
echo "restored $saves save file(s) to Vein/Saved/SaveGames from $FILE; the previous world, if any, is in Vein/Saved.before-restore-$stamp"
echo "start the server: docker compose -f vein-server-docker-compose.yml -p $PROJECT start vein-server"
