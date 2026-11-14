# challenge-timing.sh: run inside the server's container (bash -s). Sixty
# SteamNetworkingSockets ChallengeRequests to 127.0.0.1:7777, half a second
# apart, each with its own connection id: prints each round trip in ms or
# "lost" (3-second wait), then the counts and the game port's socket drops.
pad=$(printf '\\x00%.0s' $(seq 1 493))
drops() { awk '$2 ~ /:1E61$/ { print $13 }' /proc/net/udp /proc/net/udp6 | head -1; }
d0=$(drops); lost=0; line=""
for k in $(seq 1 60); do
  id=$(printf '%08x' "$k")
  esc=""; for i in 0 2 4 6; do esc+="\\x${id:$i:2}"; done
  exec 3<>/dev/udp/127.0.0.1/7777
  t0=$(date +%s%N)
  # shellcheck disable=SC2059
  printf "\\x20\\x10\\x00\\x0d${esc}\\x19\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x20\\x0b${pad}" >&3
  r=$(timeout 3 head -c 6 <&3 | od -An -v -tx1 | tr -d ' \n')
  exec 3>&-
  if [ "$r" = "210d$id" ]; then line+=" $(( ($(date +%s%N) - t0) / 1000000 ))"; else line+=" lost"; lost=$((lost + 1)); fi
  sleep 0.5
done
echo "round trips (ms):$line"
echo "lost: $lost of 60; socket drops: ${d0:-?} -> $(drops)"
