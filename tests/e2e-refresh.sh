#!/bin/bash
# Does scripts/refresh.sh restart only an empty server that is behind Steam?
#
# A restart drops everyone on the server, so the decisions are the whole
# script: up to date, leave it; behind with players on, wait; behind and the
# server does not answer the player query, wait AND exit 1, because "cannot
# count" read as zero is how a restart lands on a full server; behind and
# empty, restart. Each is asserted here, and so is the control: the stand-in
# was asked three times when it stayed silent, so the skip was the server's
# silence and not a probe that never reached it.
#
# VEIN's own Steam answer keeps players who have left, so the count comes
# from the server's log when there is one; with no log, from A2S, which can
# only count too many. Cases 9 to 11 hold the script to that.
#
# No game download and no Steam: the "server" is a few lines of Python that
# write an app manifest with a chosen build, optionally a Vein.log, and answer
# A2S_INFO with a chosen player count, behind the challenge or not, or not at
# all. Steam's build is
# given through VEIN_REMOTE_BUILD. Nothing here reaches the real restart: the
# cases that would go ahead run with --dry-run.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

PASSED=0; FAILED=0
pass() { echo "  PASS: $1"; PASSED=$((PASSED+1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED+1)); }

WORK="$(mktemp -d)"
PROJECTS=()
cleanup() {
  for p in ${PROJECTS[@]+"${PROJECTS[@]}"}; do docker compose -p "$p" -f "$WORK/fixture.yml" down -t 1 >/dev/null 2>&1; done
  rm -rf "$WORK"
}
trap cleanup EXIT

cat >"$WORK/fixture.yml" <<'YAML'
services:
  vein-server:
    image: python:3.13-alpine
    environment:
      MODE: ${MODE:-unset}
      BUILD: ${BUILD:-0}
      LOG: ${LOG:-}
    command:
      - python3
      - -c
      - |
        import os, socket, struct
        mode, build = os.environ["MODE"], os.environ["BUILD"]
        os.makedirs("/home/steam/vein/steamapps", exist_ok=True)
        open("/home/steam/vein/steamapps/appmanifest_2131400.acf", "w").write(
            '"AppState"\n{\n\t"appid"\t\t"2131400"\n\t"buildid"\t\t"%s"\n}\n' % build)
        if os.environ["LOG"]:
            os.makedirs("/home/steam/vein/Vein/Saved/Logs", exist_ok=True)
            open("/home/steam/vein/Vein/Saved/Logs/Vein.log", "w").write(os.environ["LOG"].replace("|", "\n") + "\n")
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.bind(("0.0.0.0", 27015))
        n = 0
        while True:
            d, a = s.recvfrom(4096)
            n += 1
            open("/tmp/queries", "w").write(str(n))
            if mode == "silent":
                continue
            players = int(mode.split(":")[-1])
            if mode.startswith("challenge:") and len(d) < 29:
                s.sendto(b"\xff\xff\xff\xffA" + struct.pack("<i", 1234), a)
                continue
            body = b"I\x11" + b"Fixture\x00map\x00vein\x00VEIN\x00" + struct.pack("<H", 0) + bytes([players, 16, 0]) + b"dl\x00\x00"
            s.sendto(b"\xff\xff\xff\xff" + body, a)
YAML

# start MODE BUILD [LOG]: a stand-in of its own per case; LOG is Vein.log's
# lines joined by "|". Sets $p rather than
# printing it, so the project reaches PROJECTS and the cleanup.
start() {
  p="vein-refresh-$$-${#PROJECTS[@]}"
  PROJECTS+=("$p")
  MODE="$1" BUILD="$2" LOG="${3:-}" docker compose -p "$p" -f "$WORK/fixture.yml" up -d >/dev/null 2>&1 || { echo "cannot start the stand-in"; exit 1; }
  # 27015 is 0x6987 in /proc/net/udp. Ready means listening and the manifest
  # written; the stand-in answers nothing until it is asked.
  for _ in $(seq 1 40); do
    docker compose -p "$p" -f "$WORK/fixture.yml" exec -T vein-server sh -c \
      'grep -q ":6987 " /proc/net/udp && test -f /home/steam/vein/steamapps/appmanifest_2131400.acf' 2>/dev/null && break
    sleep 0.5
  done
}
started() { docker inspect -f '{{.Id}} {{.State.StartedAt}}' "$(docker compose -p "$1" -f "$WORK/fixture.yml" ps -q vein-server)"; }
queries() { docker compose -p "$1" -f "$WORK/fixture.yml" exec -T vein-server cat /tmp/queries 2>/dev/null || echo 0; }
# A refresh that goes ahead when it should not restarts the server and waits
# up to ten minutes for a new build. Two minutes is far more than any
# decision here takes, so past it is a failure.
refresh() {
  if command -v timeout >/dev/null 2>&1; then
    VEIN_PROJECT="$p" timeout 120 scripts/refresh.sh "$@"
  else
    VEIN_PROJECT="$p" perl -e 'alarm 120; exec @ARGV' scripts/refresh.sh "$@"
  fi
}

echo "=== the refresh, the build and the players on the server ==="
echo

# 1. Up to date: nothing to do, and nobody is even asked.
start players:0 100
out="$(VEIN_REMOTE_BUILD=100 refresh 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -q "up to date: build 100" <<<"$out"; then pass "up to date: says so"; else fail "up to date: exit $rc, said: $out"; fi
if [ "$(queries "$p")" = 0 ]; then pass "up to date: the players were not even asked"; else fail "up to date: the server was queried anyway"; fi

# 2. --check reports a server that is behind and changes nothing.
start players:0 100
out="$(VEIN_REMOTE_BUILD=101 refresh --check 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -q "behind: running build 100, Steam ships 101" <<<"$out"; then pass "--check: reports behind"; else fail "--check: exit $rc, said: $out"; fi

# 3. Behind, with players on: wait.
start players:2 100; before="$(started "$p")"
out="$(VEIN_REMOTE_BUILD=101 refresh 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -q "but 2 player(s) are on" <<<"$out"; then pass "behind, two players on: waits"; else fail "behind, two players on: exit $rc, said: $out"; fi
if [ "$(started "$p")" = "$before" ]; then pass "behind, two players on: not restarted"; else fail "behind, two players on: restarted"; fi

# 4. Behind the A2S challenge, which newer servers answer with first.
start challenge:3 100
out="$(VEIN_REMOTE_BUILD=101 refresh 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -q "but 3 player(s) are on" <<<"$out"; then pass "behind the A2S challenge: three players counted"; else fail "behind the A2S challenge: exit $rc, said: $out"; fi

# 5. THE CASE THIS FILE EXISTS FOR: behind, and the server does not answer.
start silent 100; before="$(started "$p")"
out="$(VEIN_REMOTE_BUILD=101 refresh 2>&1)"; rc=$?
if [ "$rc" = 1 ] && grep -q "did not answer the player query three times" <<<"$out"; then pass "behind, no answer: waits, exit 1"; else fail "behind, no answer: exit $rc, said: $out"; fi
if [ "$(started "$p")" = "$before" ]; then pass "behind, no answer: not restarted"; else fail "behind, no answer: restarted"; fi
q="$(queries "$p")"
if [ "$q" = 3 ]; then pass "behind, no answer: the server was asked three times"; else fail "behind, no answer: asked $q time(s), expected 3"; fi

# 6. Behind and empty: it would restart.
start players:0 100
out="$(VEIN_REMOTE_BUILD=101 refresh --dry-run 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -q "would restart to update (100 -> 101): players online: 0" <<<"$out"; then pass "behind, nobody on: it would restart"; else fail "behind, nobody on: exit $rc, said: $out"; fi

# 7. --force overrides an unknown count, and says that it did.
start silent 100
out="$(VEIN_REMOTE_BUILD=101 refresh --dry-run --force 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -q "players online: ?, forced" <<<"$out"; then pass "behind, no answer, --force: it would restart"; else fail "behind, no answer, --force: exit $rc, said: $out"; fi

# 8. Steam's build unreadable: nothing is decided on a guess.
start players:0 100
out="$(VEIN_REMOTE_BUILD='' refresh 2>&1)"; rc=$?
if [ "$rc" = 1 ] && grep -q "could not read both builds" <<<"$out"; then pass "Steam's build unreadable: exit 1, nothing changed"; else fail "Steam's build unreadable: exit $rc, said: $out"; fi

# The lines VEIN writes, as on a live server: a login names the player and
# their Steam id, a join names the player, a disconnect names the id.
L1='[2026.10.19-22.01.10:100][  0]LogNet: Login request: ?Name=PlayerOne??ID=76561190000000001 userId: Steam:76561190000000001'
J1='[2026.10.19-22.01.12:200][  0]LogNet: Join succeeded: PlayerOne'
G1='[2026.10.19-23.02.40:300][  0]LogNet: UNetDriver::RemoveClientConnection - Removed address 76561190000000001:0 from UniqueSocketAddressToConnection list'
L2='[2026.10.19-22.05.00:100][  0]LogNet: Login request: ?Name=PlayerTwo??ID=76561190000000002 userId: Steam:76561190000000002'
J2='[2026.10.19-22.05.02:200][  0]LogNet: Join succeeded: PlayerTwo'
G2='[2026.10.19-23.03.01:300][  0]LogNet: UNetDriver::RemoveClientConnection - Removed address 76561190000000002:0 from UniqueSocketAddressToConnection list'

# 9. THE PHANTOMS. Steam's answer still says 4 hours after everyone left, as
# VEIN's did on the machine this template comes from; the log shows both
# players join and both leave. The server is empty, and it would restart.
start players:4 100 "$L1|$J1|$L2|$J2|$G1|$G2"
out="$(VEIN_REMOTE_BUILD=101 refresh --dry-run 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -q "would restart to update (100 -> 101): players online: 0" <<<"$out"; then pass "Steam says 4, the log says everyone left: it would restart"; else fail "Steam says 4, the log says everyone left: exit $rc, said: $out"; fi

# 10. The log outranks Steam's answer the other way too: one player joined and
# never left, whatever A2S says.
start players:0 100 "$L1|$J1|$L2|$J2|$G2"; before="$(started "$p")"
out="$(VEIN_REMOTE_BUILD=101 refresh 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -q "but 1 player(s) are on" <<<"$out"; then pass "Steam says 0, the log has one player on: waits"; else fail "Steam says 0, the log has one player on: exit $rc, said: $out"; fi
if [ "$(started "$p")" = "$before" ]; then pass "Steam says 0, the log has one player on: not restarted"; else fail "Steam says 0, the log has one player on: restarted"; fi

# 11. A log that exists and is empty is a server nobody has joined since it
# started: empty, whatever Steam says.
start players:2 100 " "
out="$(VEIN_REMOTE_BUILD=101 refresh --dry-run 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -q "would restart to update (100 -> 101): players online: 0" <<<"$out"; then pass "a log with no joins: empty, it would restart"; else fail "a log with no joins: exit $rc, said: $out"; fi

echo
echo "passed: $PASSED   failed: $FAILED"
[ "$FAILED" -eq 0 ]
