#!/bin/bash
# Does a world go out through scripts/backup.sh and come back through
# scripts/restore.sh to the exact place the server reads it?
#
# The failure this exists for is quiet: a restore that lands one directory too
# deep succeeds, and the server, finding no world where it looks, generates a
# new one. So the assertions are about paths and bytes, not exit codes: every
# save file back at Vein/Saved/SaveGames with the bytes it had, nothing at
# Saved/Saved or at the volume's root, the game files never in the archive,
# and the world that was there before moved aside, not lost.
#
# No game download involved: a volume laid out the way the image lays it out,
# with save files of known content.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

PASSED=0; FAILED=0
pass() { echo "  PASS: $1"; PASSED=$((PASSED+1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED+1)); }

export VEIN_VOLUME="vein-test-data-$$"
export VEIN_PROJECT="vein-test-$$"
WORK="$(mktemp -d)"
export VEIN_BACKUP_DIR="$WORK/backups"
cleanup() {
  docker compose -p "$VEIN_PROJECT" -f "$WORK/fixture.yml" down -t 1 >/dev/null 2>&1
  docker volume rm -f "$VEIN_VOLUME" >/dev/null 2>&1
  docker run --rm -v "$WORK":/w alpine:3.20 sh -c 'rm -rf /w/* /w/.[!.]*' >/dev/null 2>&1
  rm -rf "$WORK"
}
trap cleanup EXIT

vol() { docker run --rm -v "$VEIN_VOLUME":/data alpine:3.20 sh -c "$1"; }

echo "=== backup and restore, by path and by byte ==="
echo

docker volume create "$VEIN_VOLUME" >/dev/null

# 1. No world yet: a server nobody has joined writes no save. Not a failure.
vol 'mkdir -p /data/Vein/Binaries && echo game > /data/VeinServer.sh'
out="$(scripts/backup.sh 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -q "no world in" <<<"$out" && [ -z "$(ls "$VEIN_BACKUP_DIR" 2>/dev/null)" ]; then
  pass "no world yet: says so, exits 0, writes nothing"
else
  fail "no world yet: exit $rc, said: $out"
fi

# A world, laid out the way the image lays it out, one save in a subdirectory.
vol 'mkdir -p /data/Vein/Saved/SaveGames/slot /data/Vein/Saved/Config/LinuxServer &&
     echo world-v1 > /data/Vein/Saved/SaveGames/Autosave_0.sav &&
     echo world-v1-slot > /data/Vein/Saved/SaveGames/slot/World.sav &&
     echo "[/Script/Vein]" > /data/Vein/Saved/Config/LinuxServer/Game.ini &&
     chown -R 1000:1000 /data/Vein'
sums_before="$(vol 'cd /data/Vein && find Saved -type f | sort | xargs sha256sum')"

# 2. The backup holds the world and nothing else.
out="$(scripts/backup.sh 2>&1)"; rc=$?
archives=("$VEIN_BACKUP_DIR"/vein-world-*.tar.gz)
archive="${archives[0]}"; [ -f "$archive" ] || archive=""
if [ "$rc" = 0 ] && [ -n "$archive" ]; then pass "backup: wrote $(basename "$archive")"; else fail "backup: exit $rc, said: $out"; fi
listing="$(tar -tzf "$archive" 2>/dev/null)"
if grep -qx "Saved/SaveGames/slot/World.sav" <<<"$listing" && grep -qx "Saved/Config/LinuxServer/Game.ini" <<<"$listing"; then
  pass "backup: the saves and the settings are in it, under Saved/"
else
  fail "backup: the archive holds: $(tr '\n' ' ' <<<"$listing")"
fi
if grep -q "VeinServer.sh\|Binaries" <<<"$listing"; then fail "backup: the game files went into the archive"; else pass "backup: the game files did not"; fi

# 3. THE CASE THIS FILE EXISTS FOR. The world is lost and a fresh one is
# generated in its place; the restore must bring the old one back to the
# exact path, byte for byte.
vol 'rm -rf /data/Vein/Saved && mkdir -p /data/Vein/Saved/SaveGames && echo fresh-world > /data/Vein/Saved/SaveGames/Autosave_0.sav'
out="$(scripts/restore.sh "$archive" 2>&1)"; rc=$?
if [ "$rc" = 0 ]; then pass "restore: exit 0"; else fail "restore: exit $rc, said: $out"; fi
sums_after="$(vol 'cd /data/Vein && find Saved -type f | sort | xargs sha256sum')"
if [ "$sums_after" = "$sums_before" ]; then
  pass "restore: every file is back at its live path with the bytes it had"
else
  fail "restore: what is at Vein/Saved differs from what was backed up"
fi
if vol 'test -e /data/Vein/Saved/Saved || test -e /data/Saved'; then
  fail "restore: a Saved directory landed one level too deep or at the volume's root"
else
  pass "restore: nothing landed one level too deep"
fi
if vol 'cat /data/Vein/Saved.before-restore-*/SaveGames/Autosave_0.sav' 2>/dev/null | grep -qx fresh-world; then
  pass "restore: the world that was there is kept aside, not lost"
else
  fail "restore: the world that was there before is gone"
fi
if [ "$(vol 'stat -c %u /data/Vein/Saved/SaveGames/slot/World.sav')" = 1000 ]; then
  pass "restore: the files belong to the server's user, uid 1000"
else
  fail "restore: the files do not belong to uid 1000"
fi

# 4. The naive restore, for contrast: the archive extracted at the volume's
# root. It "works", and the server would find no world. The check that the
# restore runs on itself must catch exactly this shape.
naive="$(docker run --rm -v "$(cd "$(dirname "$archive")" && pwd)":/in:ro alpine:3.20 sh -c "mkdir -p /v/Vein && tar -xzf /in/$(basename "$archive") -C /v && test -f /v/Vein/Saved/SaveGames/Autosave_0.sav && echo found || echo missing")"
if [ "$naive" = missing ]; then
  pass "contrast: the same archive extracted at the volume's root leaves no world where the server looks"
else
  fail "contrast: a root extract put the world in place, so this test proves less than it says"
fi

# 5. Refusals, each leaving the world untouched.
sums_now="$(vol 'cd /data/Vein && find Saved -type f | sort | xargs sha256sum')"
mkdir -p "$WORK/junk/other" && echo x > "$WORK/junk/other/file"
tar -czf "$WORK/junk.tar.gz" -C "$WORK/junk" other
out="$(scripts/restore.sh "$WORK/junk.tar.gz" 2>&1)"; rc=$?
if [ "$rc" = 1 ] && grep -q "is not a VEIN world archive" <<<"$out"; then pass "refuses an archive that is not a world"; else fail "a non-world archive: exit $rc, said: $out"; fi

cat >"$WORK/fixture.yml" <<'YAML'
services:
  vein-server:
    image: alpine:3.20
    command: ["sleep", "600"]
YAML
docker compose -p "$VEIN_PROJECT" -f "$WORK/fixture.yml" up -d >/dev/null 2>&1
out="$(scripts/restore.sh "$archive" 2>&1)"; rc=$?
if [ "$rc" = 1 ] && grep -q "the server is running" <<<"$out"; then pass "refuses while the server is running"; else fail "a running server: exit $rc, said: $out"; fi
docker compose -p "$VEIN_PROJECT" -f "$WORK/fixture.yml" down -t 1 >/dev/null 2>&1
if [ "$(vol 'cd /data/Vein && find Saved -type f | sort | xargs sha256sum')" = "$sums_now" ]; then
  pass "the refusals left the world untouched"
else
  fail "a refusal changed the world"
fi

echo
echo "passed: $PASSED   failed: $FAILED"
[ "$FAILED" -eq 0 ]
