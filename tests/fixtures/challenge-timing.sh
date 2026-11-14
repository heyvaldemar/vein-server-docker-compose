# challenge-timing.sh [addr] [count] [interval] [wait]: run inside the server's
# container (bash -s). SteamNetworkingSockets ChallengeRequests to addr:7777
# (default 127.0.0.1, 60 of them, 0.5 s apart), each with its own connection
# id: prints each round trip in ms or "lost" (after wait seconds, default 3),
# then the counts and the game port's socket drops.
addr=${1:-127.0.0.1} count=${2:-60} gap=${3:-0.5} wait=${4:-3}
pad=$(printf '\\x00%.0s' $(seq 1 493))
drops() { awk '$2 ~ /:1E61$/ { print $13 }' /proc/net/udp /proc/net/udp6 | head -1; }
d0=$(drops); lost=0; line=""
for k in $(seq 1 "$count"); do
  id=$(printf '%08x' "$((k + RANDOM * 65536))")
  id=$(sed -E 's/(..)/\1 /g; s/0a /0b /g; s/ //g' <<<"$id")   # no newline byte: see tools/healthcheck.sh
  esc=""; for i in 0 2 4 6; do esc+="\\x${id:$i:2}"; done
  exec 3<>"/dev/udp/$addr/7777"
  t0=$(date +%s%N)
  # shellcheck disable=SC2059
  printf "\\x20\\x10\\x00\\x0d${esc}\\x19\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x20\\x0b${pad}" >&3
  r=$(timeout "$wait" head -c 6 <&3 | od -An -v -tx1 | tr -d ' \n')
  exec 3>&-
  if [ "$r" = "210d$id" ]; then line+=" $(( ($(date +%s%N) - t0) / 1000000 ))"; else line+=" lost"; lost=$((lost + 1)); fi
  sleep "$gap"
done
echo "to $addr, $count requests $gap s apart; round trips (ms):$line"
echo "lost: $lost of $count; socket drops: ${d0:-?} -> $(drops)"
