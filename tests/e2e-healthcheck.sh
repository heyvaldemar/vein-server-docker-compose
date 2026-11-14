#!/bin/bash
# Does the health check go by the game's own answer, run in the pinned image?
#
# tools/healthcheck.sh sends a SteamNetworkingSockets ChallengeRequest, the
# first packet a client sends, to the game port and is healthy only on the
# server's ChallengeReply carrying back its connection id. Here it runs in the
# image the compose file pins, so bash, timeout, head, od and tr are proven to
# be there, against a stand-in that keeps the real server's rules
# (tests/fixtures/fake-gns.py: id 32, padded to 512 bytes, a non-zero
# connection id, or dropped), in the stand-in's network namespace:
#
#   ::          bound to every address of both families, as VEIN binds:
#               healthy, and the stand-in saw one valid 512-byte request
#   one address bound to the interface address: healthy
#   noloop      bound to :: and deaf to 127.0.0.1: healthy, asked at the
#               container's own address
#   wrongid     a reply carrying another connection id: not an answer to
#               this check, unhealthy
#   silent      a socket on the port that never answers, on one address and
#               on :: (two to ask): unhealthy, and the check is over within
#               8 seconds, inside the 10 Docker gives it
#   no socket   nothing bound to the port, which is a process that stands
#               without a network: unhealthy
#
# The stand-in is not a server. The real one is the boot job in CI
# (real-server.yml), which also stops the game process and requires the
# check to go red.
# shellcheck disable=SC2015   # pass and fail always exit 0, so "A && pass || fail" is if-then-else here
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

PASSED=0; FAILED=0
pass() { echo "  PASS: $1"; PASSED=$((PASSED+1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED+1)); }
IMAGE=$(grep -m1 -oE '\$\{VEIN_SERVER_IMAGE_TAG:-.*' vein-server-docker-compose.yml | sed -E -e ':a' -e 's/\$\{[A-Z0-9_]+:-([^{}]*)\}/\1/' -e 'ta')
PY=python:3.13-alpine@sha256:7984cf56ceaddebe4fefeb75d64000b9f45d8b77b11a09b24524da6cdc3af0c8
NET="vein-hc-net-$$"
cleanup() { docker rm -f "$NET" >/dev/null 2>&1; }
trap cleanup EXIT

standin() {  # mode bind: a fresh stand-in, waited for until it is bound
  docker rm -f "$NET" >/dev/null 2>&1
  docker run -d --name "$NET" -v "$PWD/tests/fixtures/fake-gns.py:/fake-gns.py:ro" "$PY" \
    python3 -u /fake-gns.py "$1" 7777 "$2" >/dev/null || return 1
  for _ in $(seq 1 40); do
    docker logs "$NET" 2>&1 | grep -q '^bound' && return 0
    sleep 0.25
  done
  return 1
}
empty() {  # a namespace with nothing bound to the port
  docker rm -f "$NET" >/dev/null 2>&1
  docker run -d --name "$NET" "$PY" sleep 300 >/dev/null
}
check() {  # run the health check in the pinned image, in the stand-in's namespace: sets rc, out, secs
  out=$(docker run --rm --platform linux/amd64 --network "container:$NET" --entrypoint bash \
    -v "$PWD/tools/healthcheck.sh:/healthcheck.sh:ro" "$IMAGE" \
    -c 's=$SECONDS; bash /healthcheck.sh 7777; rc=$?; echo "secs=$((SECONDS - s))"; exit $rc' 2>&1); rc=$?
  secs=$(sed -n 's/^secs=//p' <<<"$out"); out=$(grep -v '^secs=' <<<"$out")
}

echo "=== the health check, in the pinned image, against a stand-in ==="
echo

standin answers :: || { fail "the stand-in never bound its port"; echo; echo "passed: $PASSED   failed: $FAILED"; exit 1; }
check
[ "$rc" = 0 ] && grep -q "^healthy:" <<<"$out" && pass "bound to ::, as VEIN binds: healthy ($out)" || fail "answers on ::: exit $rc, $out"
seen=$(docker logs "$NET" 2>&1 | grep '^seen ')
[ "$seen" = "seen 512 True" ] && pass "the stand-in saw one request, 512 bytes, valid" || fail "the stand-in saw: ${seen:-nothing}"

# Two hundred checks in one container, every one healthy. A check that wrote
# its request with a newline byte in it sent two short datagrams the server
# drops: about one check in sixty-four, so the check v1.1.0 shipped fails this
# far more often than not.
many=$(docker run --rm --platform linux/amd64 --network "container:$NET" --entrypoint bash \
  -v "$PWD/tools/healthcheck.sh:/healthcheck.sh:ro" "$IMAGE" \
  -c 'n=0; for _ in $(seq 1 200); do bash /healthcheck.sh 7777 >/dev/null 2>&1 || n=$((n + 1)); done; echo "$n"' 2>/dev/null)
[ "$many" = 0 ] && pass "two hundred checks in a row: every one healthy" || fail "two hundred checks in a row: ${many:-?} failed"

standin answers iface || fail "the one-address stand-in never bound its port"
check
[ "$rc" = 0 ] && pass "bound to the interface address: healthy" || fail "one address: exit $rc, $out"

standin noloop :: || fail "the noloop stand-in never bound its port"
check
[ "$rc" = 0 ] && pass "bound to :: and deaf to 127.0.0.1: healthy, asked at the container's address" || fail "noloop: exit $rc, $out"

standin wrongid :: || fail "the wrongid stand-in never bound its port"
check
[ "$rc" = 1 ] && [[ $out == *"no challenge reply"* ]] && pass "a reply with another connection id: not this check's answer, unhealthy" || fail "wrongid: exit $rc, $out"

standin silent iface || fail "the silent stand-in never bound its port"
check
[ "$rc" = 1 ] && [[ $out == *"no challenge reply"* ]] && pass "a socket that never answers: unhealthy" || fail "silent: exit $rc, $out"
[ -n "$secs" ] && [ "$secs" -le 8 ] && pass "and the check was over in ${secs}s, inside Docker's 10" || fail "silent: the check took ${secs:-?}s"

standin silent :: || fail "the silent :: stand-in never bound its port"
check
[ "$rc" = 1 ] && [ -n "$secs" ] && [ "$secs" -le 8 ] && pass "silent on ::, two addresses asked: unhealthy in ${secs}s" || fail "silent ::: exit $rc in ${secs:-?}s, $out"

empty
check
[ "$rc" = 1 ] && [[ $out == *"nothing is bound"* ]] && pass "no socket on the port: unhealthy" || fail "no socket: exit $rc, $out"

echo
echo "passed: $PASSED   failed: $FAILED"
[ "$FAILED" -eq 0 ]
