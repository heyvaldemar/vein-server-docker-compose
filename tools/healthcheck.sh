#!/bin/bash
# healthcheck.sh - healthy only when the game itself answers on its game port.
#
# Sends the first packet a VEIN client sends when it connects: a
# SteamNetworkingSockets ChallengeRequest, to the game port inside the
# container, and exits 0 only on the server's ChallengeReply carrying back the
# connection id this check chose. VEIN's networking (the developer's
# RamjetSteamSockets plugin over Steam's SteamNetworkingSockets) answers it
# from inside the server's own process; a stopped or hung server answers
# nothing.
#
# NOT A2S. VEIN answers the Steam server query only as a public server.
# Private, the template's default, it binds the query port and never reads it
# (measured in CI on 2026-11-14: run 43531304566 private, ten minutes, no
# answer; run 43534866273 public, an answer ten seconds after the map loaded).
# A check that asked A2S would be red forever on a private server. A private
# server answers the challenge (run 43537003669) from the same listen socket
# players connect to.
#
# NOT THE PROCESS. Up to v1.0.3 the check looked for VeinServer in /proc. A
# hung or stopped server keeps its process; CI stops it with SIGSTOP and
# requires this check red while that one stays green.
#
# NOT THE LOG. An empty server writes nothing for hours while it is perfectly
# well.
#
# NO SIDE EFFECTS. A ChallengeRequest opens nothing: the server answers with a
# challenge it can verify later and keeps no state until a ConnectRequest
# follows, which this never sends. CI asks thirty times in a row and requires
# no new line in the game's log and no file written under Vein/Saved.
#
# THE PACKET, from ValveSoftware/GameNetworkingSockets
# (steamnetworkingsockets_udp.cpp): message id 32, the length of the protobuf
# body in two bytes, the body (connection_id, my_timestamp, protocol_version),
# zero-padded to 512 bytes, the least the server accepts for this message.
# The reply is id 33, then field 1, the connection id sent.
#
# A HICCUP can drop one answer, so one check tries twice, a second apart, and
# Docker's retries cover the rest: three misses in a row at the compose file's
# interval. Every read times out after 1.5 seconds (a running server answers
# in milliseconds); with two addresses to try, a silent server costs the whole
# check 7 seconds, inside the 10 Docker gives it.
#
# THE ADDRESS IT ANSWERS ON. The addresses come from /proc/net/udp and
# /proc/net/udp6, every socket bound to the game port; no socket there at all
# is unhealthy at once. VEIN binds [::]. Bound to every address (0.0.0.0 or
# ::), the container's own address from /etc/hosts first, then 127.0.0.1;
# bound to one IPv4 address (or an IPv4-mapped one), that address.
#
# INSIDE THE CONTAINER. This proves the server answers in its own network
# namespace. It does not prove the port is published on the host, nor that a
# firewall lets players in.
#
# Usage: healthcheck.sh [game port]   (default 7777). Needs bash, timeout, head,
# od and tr, which the image has (tests/e2e-healthcheck.sh runs it there).
#
# Read whole before it runs: one brace group, ending in exit
# (bash reads a script as it runs it, so a file rewritten under a running
# copy would otherwise run the new text from the middle).
{
set -u
port=${1:-7777}

addrs=()   # every address a UDP socket on the game port is bound to
want=$(printf '%04X' "$port")
add() { [[ " ${addrs[*]-} " == *" $1 "* ]] || addrs+=("$1"); }
any() {
  local me ip name _
  read -r me < /etc/hostname 2>/dev/null || me=
  while read -r ip name _; do
    [[ -n $me && $name == "$me" && $ip == *.*.*.* ]] && add "$ip"
  done < /etc/hosts
  add 127.0.0.1
}
v4() { printf '%d.%d.%d.%d' "0x${1:6:2}" "0x${1:4:2}" "0x${1:2:2}" "0x${1:0:2}"; }
while read -r _ local _; do
  [[ $local == *:"$want" ]] || continue
  h=${local%%:*}
  case "$h" in
    00000000|00000000000000000000000000000000) any ;;
    0000000000000000FFFF0000????????) add "$(v4 "${h:24:8}")" ;;
    ????????) add "$(v4 "$h")" ;;
    *) any ;;   # one IPv6 address: asked where an IPv4 client would ask
  esac
done < <(tail -q -n +2 /proc/net/udp /proc/net/udp6 2>/dev/null)
if [ "${#addrs[@]}" = 0 ]; then
  echo "unhealthy: nothing is bound to UDP port $port" >&2
  exit 1
fi

# A connection id of this check's own, never zero (the server ignores a
# request without one), so only a reply to this request counts.
id=$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')
[ "$id" = 00000000 ] && id=00000001
esc=""; for i in 0 2 4 6; do esc+="\\x${id:$i:2}"; done
pad=$(printf '\\x00%.0s' $(seq 1 493))
req="\\x20\\x10\\x00\\x0d${esc}\\x19\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x20\\x0b${pad}"

ask() {  # address -> the reply's first 6 bytes, in hex
  { exec 3<>"/dev/udp/$1/$port"; } 2>/dev/null || return 0
  # shellcheck disable=SC2059   # the request is a printf format on purpose: \xHH escapes, one 512-byte write
  printf "$req" >&3
  timeout 1.5 head -c 6 <&3 | od -An -v -tx1 | tr -d ' \n'
  exec 3>&-
}

for try in 1 2; do
  for a in "${addrs[@]}"; do
    if [ "$(ask "$a")" = "210d$id" ]; then
      echo "healthy: the game answered a SteamNetworkingSockets challenge on $a:$port"
      exit 0
    fi
  done
  [ "$try" = 1 ] && sleep 1
done
echo "unhealthy: a socket is bound to UDP port $port (${addrs[*]}), and no challenge reply came" >&2
exit 1
}
