# udp-diag.sh <port>: run inside the server's container (sh -s) while the
# plant has the port's owners stopped. Prints every UDP socket, every process
# with its uid and state, and which address answers A2S_INFO on its own, so a
# check that stays green over a stopped game says who answered it.
echo "--- UDP sockets (local address, inode)"
awk 'NR > 1 { print $2, $10 }' /proc/net/udp /proc/net/udp6 2>/dev/null
echo "--- processes (pid uid state comm)"
for d in /proc/[0-9]*; do
  echo "${d#/proc/} $(awk '/^Uid:/ { print $2 }' "$d/status" 2>/dev/null) $(cut -d' ' -f3 "$d/stat" 2>/dev/null) $(cat "$d/comm" 2>/dev/null)"
done
echo "--- A2S_INFO to each address, alone"
for a in $(hostname -i 2>/dev/null) 127.0.0.1; do
  r=$(bash -c '{ exec 3<>"/dev/udp/$0/$1"; } 2>/dev/null || exit 0; printf "\xff\xff\xff\xffTSource Engine Query\x00" >&3; timeout 2 head -c 9 <&3 | od -An -v -tx1 | tr -d " \n"' "$a" "$1")
  echo "$a:$1 -> ${r:-no answer}"
done
