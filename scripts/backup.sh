#!/bin/bash
# Archive the VEIN world.
#
# WHAT IS ARCHIVED: Vein/Saved inside the volume, the world (SaveGames) and the
# server's own settings. Not the ~10 GB of game files beside it: SteamCMD
# downloads those again on the next start, and the archive would be a hundred
# times larger for nothing. The archive holds `Saved/...`, relative to `Vein/`,
# and scripts/restore.sh extracts it at exactly that place. A restore that
# lands one directory too deep finds no world, and the server generates a new
# one; on the machine this template comes from, the first restore of a real
# world did exactly that, and reported success.
#
# NO SAVE IS REQUESTED FIRST, AND WHY THAT IS SAFE. VEIN has no rcon, and the
# image's own attempt writes to a terminal that is not there. What makes an
# archive of a running server consistent is the game's autosave: every 60
# seconds, ten rotating files (the compose file sets both). An archive that
# lands mid-write still holds nine complete saves at most a few minutes apart.
#
# A BACKUP KILLED HALFWAY MUST NOT KEEP THE NAME A FINISHED ONE HAS. The
# archive is written as <name>.partial and renamed only once tar has succeeded
# AND the archive is shown to contain save files: tar's exit code says it ran,
# not that it kept a world.
#
# NO WORLD YET IS NOT A FAILURE; NO WORLD ANY MORE IS. A server nobody has
# joined writes no save at all, so this says so and exits 0. Once this script
# has archived a world, the same absence means the world is gone or is no
# longer where this looks, and it fails. Read as "nothing yet", that night's
# backup and every one after would have exited 0 over a lost world.
#
# Usage: scripts/backup.sh
#   VEIN_BACKUP_DIR   where archives go       (default ./backups)
#   VEIN_BACKUP_KEEP  how many to keep        (default 14)
#   VEIN_VOLUME       the data volume         (default vein-server-data)
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

BACKUP_DIR="${VEIN_BACKUP_DIR:-./backups}"
KEEP="${VEIN_BACKUP_KEEP:-14}"
VOLUME="${VEIN_VOLUME:-vein-server-data}"

if ! docker volume inspect "$VOLUME" >/dev/null 2>&1; then
  echo "$(date '+%F %T') no volume $VOLUME: nothing to back up" >&2
  exit 1
fi

# `test` answers 1 for "not there". Anything else is docker failing to ask,
# and reading that as "no world yet" would be a probe that lies by staying
# quiet.
docker run --rm -v "$VOLUME":/data:ro alpine:3.20 test -d /data/Vein/Saved/SaveGames
rc=$?
if [ "$rc" -gt 1 ]; then
  echo "$(date '+%F %T') could not look inside $VOLUME (docker exited $rc); nothing archived" >&2
  exit 1
fi
if [ "$rc" = 1 ]; then
  last="$(find "$BACKUP_DIR" -maxdepth 1 -name 'vein-world-*.tar.gz' 2>/dev/null | sort | tail -1)"
  if [ -n "$last" ]; then
    echo "$(date '+%F %T') FAILED: no world in $VOLUME (Vein/Saved/SaveGames does not exist), and $(basename "$last") holds one: the world this server had is gone, or is no longer where this script looks" >&2
    exit 1
  fi
  echo "$(date '+%F %T') no world in $VOLUME yet (Vein/Saved/SaveGames does not exist): nothing to back up. VEIN writes none until somebody has played."
  exit 0
fi

mkdir -p "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/vein-world-$(date +%Y%m%d-%H%M%S).tar.gz"
OUT="$(cd "$BACKUP_DIR" && pwd)"
NAME="$(basename "$BACKUP_FILE")"

# Written as .partial; renamed only if tar succeeded and the archive holds
# save files.
if docker run --rm -v "$VOLUME":/data:ro -v "$OUT":/out alpine:3.20 \
     tar -czf "/out/$NAME.partial" -C /data/Vein Saved; then
  saves="$(docker run --rm -v "$OUT":/out:ro alpine:3.20 tar -tzf "/out/$NAME.partial" 2>/dev/null | grep -c '^Saved/SaveGames/.')"
  if [ "${saves:-0}" -lt 1 ]; then
    mv "${BACKUP_FILE}.partial" "${BACKUP_FILE}.failed" 2>/dev/null
    echo "$(date '+%F %T') FAILED: the archive holds no save files, so it is not a backup of a world; see ${BACKUP_FILE}.failed" >&2
    exit 1
  fi
  mv "${BACKUP_FILE}.partial" "$BACKUP_FILE"
  echo "$(date '+%F %T') wrote $BACKUP_FILE ($(du -h "$BACKUP_FILE" | cut -f1), $saves file(s) under Saved/SaveGames)"
else
  mv "${BACKUP_FILE}.partial" "${BACKUP_FILE}.failed" 2>/dev/null
  echo "$(date '+%F %T') FAILED: tar did not complete; see ${BACKUP_FILE}.failed" >&2
  exit 1
fi

# Retention: the newest KEEP finished archives stay. .partial and .failed
# files are never counted and never kept.
# shellcheck disable=SC2012  # the names are this script's own, fixed pattern; no user input reaches them
ls -1t "$BACKUP_DIR"/vein-world-*.tar.gz 2>/dev/null | tail -n +"$((KEEP + 1))" | while IFS= read -r old; do
  rm -f -- "$old"
done
find "$BACKUP_DIR" -name 'vein-world-*.tar.gz.partial' -mmin +60 -delete 2>/dev/null
exit 0
