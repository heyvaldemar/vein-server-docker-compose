#!/bin/bash
# start-server.sh - start VEIN with no password on its command line.
#
# The image starts the server as `VeinServer.sh -ServerPassword=… -AdminPassword=…`,
# so both passwords sit on the game's command line for as long as it runs:
# readable by every process in the container, shown by `ps` on the host, and
# written by the engine into its log ("LogInit: Command Line:"). The image
# runs START_COMMAND instead when it is set; the compose file sets it to this.
#
# THE JOIN PASSWORD goes into Game.ini, the file the image itself writes it to
# ([/Script/Vein.VeinGameSession] Password=), with bash builtins, so it is on
# no command line here either. Rewritten on every start from
# VEIN_JOIN_PASSWORD; empty removes it.
#
# THE ADMIN PASSWORD has no file the game reads. Set (VEIN_ADMIN_PASSWORD), it
# is passed as -AdminPassword and is visible where any argument is; the README
# says so. Admins by Steam id (VEIN_SERVER_ADMIN_STEAM_IDS) need no password.
#
# Read whole before it runs: one brace group, ending in exec.
{
set -u
dir=/home/steam/vein
ini="$dir/Vein/Saved/Config/LinuxServer/Game.ini"
sec='[/Script/Vein.VeinGameSession]'
pw="${VEIN_JOIN_PASSWORD:-}"

# FAIL CLOSED. A join password that cannot be written would start an open
# server, so with one set, a missing Game.ini is created, and the start stops
# unless the file holds the password afterwards.
if [ -n "$pw" ] && [ ! -f "$ini" ]; then
  mkdir -p "${ini%/*}" && printf '%s\n' "$sec" > "$ini"
fi
if [ -f "$ini" ]; then
  out=""; in=0; put=0
  while IFS= read -r line || [ -n "$line" ]; do
    l=${line%$'\r'}
    if [[ $l == \[*\] ]]; then
      in=0; [ "$l" = "$sec" ] && in=1
      out+="$line"$'\n'
      if [ "$in" = 1 ] && [ -n "$pw" ] && [ "$put" = 0 ]; then out+="Password=$pw"$'\n'; put=1; fi
      continue
    fi
    [ "$in" = 1 ] && [[ $l == Password=* ]] && continue
    out+="$line"$'\n'
  done < "$ini"
  [ -n "$pw" ] && [ "$put" = 0 ] && out+="$sec"$'\n'"Password=$pw"$'\n'
  printf '%s' "$out" > "$ini.new" && cat "$ini.new" > "$ini" && rm -f "$ini.new"
fi
if [ -n "$pw" ]; then
  have=0
  if [ -f "$ini" ]; then
    in=0
    while IFS= read -r line || [ -n "$line" ]; do
      l=${line%$'\r'}
      if [[ $l == \[*\] ]]; then in=0; [ "$l" = "$sec" ] && in=1; continue; fi
      [ "$in" = 1 ] && [ "$l" = "Password=$pw" ] && have=1
    done < "$ini"
  fi
  [ "$have" = 1 ] || { echo "start-server: the join password could not be written to Game.ini; not starting an open server" >&2; exit 1; }
  echo "start-server: the join password is in Game.ini"
else
  echo "start-server: no join password"
fi

# THE ADMIN PASSWORD, letters and digits only, so that the log filter, which
# masks Password=value up to the next space, always covers all of it.
if [ -n "${VEIN_ADMIN_PASSWORD:-}" ] && [[ ! $VEIN_ADMIN_PASSWORD =~ ^[A-Za-z0-9]+$ ]]; then
  echo "start-server: VEIN_SERVER_ADMIN_PASSWORD must be letters and digits only (see .env.example); not starting" >&2
  exit 1
fi

args=(
  "-ServerName=${SERVER_NAME:-VEIN Server}"
  "-Port=${SERVER_PORT:-7777}"
  "-QueryPort=${QUERY_PORT:-27015}"
  "-MaxPlayers=${MAX_PLAYERS:-16}"
)
[ -n "${VEIN_ADMIN_PASSWORD:-}" ] && args+=("-AdminPassword=$VEIN_ADMIN_PASSWORD")
cd "$dir" || exit 1
exec ./VeinServer.sh "${args[@]}"
}
