# VEIN dedicated server using Docker Compose

[![Deployment Verification](https://github.com/heyvaldemar/vein-server-docker-compose/actions/workflows/deployment-verification.yml/badge.svg?branch=main)](https://github.com/heyvaldemar/vein-server-docker-compose/actions/workflows/deployment-verification.yml)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/15714/badge)](https://www.bestpractices.dev/projects/15714)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A VEIN dedicated server, pinned by digest, with a world this file is arranged around not losing and an update that never restarts the server under anybody.

VEIN is an early-access zombie survival game on Unreal Engine 5, patched often. A server one build behind Steam turns every player away while its container reports healthy, so most of what is here is about staying current without dropping the people on it.

```bash
git clone https://github.com/heyvaldemar/vein-server-docker-compose
cd vein-server-docker-compose
cp .env.example .env && $EDITOR .env          # a server name, your Steam64 id as admin
docker volume create vein-server-data         # the game and the world - see "the volume", below
docker compose -f vein-server-docker-compose.yml -p vein up -d
```

The first start downloads the game through SteamCMD, about 10 GB, then starts the server. Watch it:

```bash
docker compose -p vein logs -f vein-server
docker compose -p vein ps          # healthy once the server answers on its game port
```

Players find it in the server browser if `VEIN_SERVER_PUBLIC=true`, or join from the in-game console with `connect <IP>:7777`. An IP address, not a hostname; see below.

## What this file knows that a fresh one does not

**Join by IP address, not by name.** On the machine this template comes from, `connect <hostname>:<port>` joined once and then failed with no error at all. Packet captures on both ends of the path showed the client sending nothing when it was given a name, while DNS answered correctly; `connect <IP>:<port>` worked every time, from the internet and from the LAN. The same name works for everything else: a monitor's A2S query to the query port answers through it, and the in-game server search lists the server by its IP. Only joining fails. VEIN's networking runs over Steam's socket layer, which most likely takes addresses as numbers only. Give players the number, or the search.

**The ports are published under the numbers the server binds.** The server is told both ports and advertises them to Steam itself. Map 8888 on the host to 7777 in the container, as a quick edit often does, and Steam lists a port nobody can reach. `VEIN_SERVER_PORT` and `VEIN_SERVER_QUERY_PORT` move both sides at once.

**The image is the wrapper, not the game.** `mbround18/vein-docker` brings SteamCMD and a start script; the game is downloaded into the volume and brought up to date on every start. A new image tag is a change to the scripts. A VEIN patch arrives through `scripts/refresh.sh`, below.

**VEIN's Steam answer keeps players who left.** On the machine this template comes from, the server's A2S answer said "4 / 32" for hours after its own log showed all four disconnect. Anything that waits for an empty server before restarting would never find one, and a server that cannot update turns every player away after the next patch. So the refresh counts players from `Vein/Saved/Logs/Vein.log`, where every join and every disconnect is written, and a restart starts a new log, truthfully empty. Only when there is no log does it fall back to A2S, which can count too many but never too few. And a log with no join at all, while A2S says players are on, is not read as an empty server: phantoms come only after real joins, which the log records, so that log is one written in a shape the parser does not know, as a game update could make it. The count is then unknown, and the refresh waits.

**An unanswered player query is not an empty server.** Every restart drops everyone on the server, so the refresh asks who is on first. With no log to read, it asks A2S from inside the server's network namespace, three times; a server that never answers is skipped like a full one, and the script exits 1. On the same machine, an update roll that read "cannot count" as zero had three game stacks reading as empty whatever was happening on them.

**A private server never answers A2S.** VEIN answers the Steam query only as a public server. Private, this template's default, it binds the query port and never reads it (measured in CI: [private, ten minutes, no answer](https://github.com/heyvaldemar/vein-server-docker-compose/actions/runs/43531304566); [public, an answer ten seconds after the map loaded](https://github.com/heyvaldemar/vein-server-docker-compose/actions/runs/43534866273)). So for a server whose log shows no join since it started and that gives no Steam answer, the refresh watches its game port for 10 seconds from inside its network namespace: no packet at all is nobody on, and it updates (the health check's own packets, which travel the loopback interface, are not counted); any traffic is somebody who may have joined in a shape the parser does not know, and it waits. Up to v1.0.3 an idle private server never updated itself.

**The free Demo cannot join.** VEIN's Demo is a separate Steam app (2082470) from the game (1857950). A Demo player sees nothing in the server list and gets "connection failed" on Direct Connect, which from their side looks exactly like a dead server; the server's log says `Cert is not authorized for appid 1857950, only 2082470`, for every attempt. On the machine this template comes from, that line was the whole answer to "players in one country can't see or join", after packet captures had shown their packets arriving and the server answering. Tell players it takes the full game, and look for the line with `docker compose -p vein exec vein-server grep "Cert is not authorized" /home/steam/vein/Vein/Saved/Logs/Vein.log`.

**The restore path is the whole job.** The world lives in `Vein/Saved/SaveGames` inside the volume. A restore that lands one directory too deep succeeds, reports success, and the server, finding no world where it looks, generates a new one. On the server this template comes from, a test restore of a real world would have done exactly that: its backups are taken with restic, and a plain restore of the latest snapshot put the world one directory too deep. The test caught it before the backup was ever needed. `scripts/restore.sh` extracts at the one place the backup was taken from and then checks that every save file is at its live path.

**No world until somebody has played.** A server nobody has joined writes no save at all, not on its autosave and not on a clean stop. `scripts/backup.sh` says so and exits 0 rather than failing every night until the first player. Once people have played, that same line is the alarm.

**The passwordless sudo in the image does nothing here.** The image gives its steam user passwordless sudo. `no-new-privileges` stops setuid binaries raising anything, so sudo cannot either; the start script's own sudo calls become no-ops, which costs nothing because the volume already belongs to the steam user.

**The volume is external, so `docker compose down -v` cannot delete the world.** `down -v` is the command everyone reaches for when a stack misbehaves. On a project-managed volume it removes the world without asking. Creating the volume by hand once is the price of not losing it by accident.

**Two minutes to stop.** The image saves the world on the way out, and a SIGKILL in the middle of it is a world that loads from the last autosave, or does not load.

**Memory follows the slot count.** On the machine this template comes from the server idled at 3.3 GB with one player on, and ran 16 slots under an 8 GB ceiling, then 32 under 16 GB. Raise `VEIN_SERVER_MEMORY_LIMIT` with `VEIN_SERVER_MAX_PLAYERS`. There is no swap on top of the ceiling, because a game tick that pages is a stutter every player sees.

**Admins by Steam id; a password only as a fallback.** Put Steam64 ids in `VEIN_SERVER_ADMIN_STEAM_IDS` (and `VEIN_SERVER_SUPERADMIN_STEAM_IDS`): nothing secret, nothing to leak. `VEIN_SERVER_ADMIN_PASSWORD` is optional and empty by default, because VEIN reads the admin password only from its command line: the engine reads no `UECommandLine.txt` in any of five places tried ([run 43540804147](https://github.com/heyvaldemar/vein-server-docker-compose/actions/runs/43540804147)). Set, `VEIN_SERVER_ADMIN_PASSWORD` is visible on the game's command line (to every process in the container and to `ps` on the host) and in `Vein/Saved/Logs/Vein.log`, where the engine writes its own command line. It is masked in `docker compose logs`, and backups leave the logs out. Letters and digits only, so the mask covers all of it.

**No password on a command line or in `docker compose logs`.** The image starts the server with the join and admin passwords as arguments, prints its start command, and after the server exits prints the command lines of processes left behind; the engine writes its command line to stdout too. So the server is started by `tools/start-server.sh` (the image's `START_COMMAND`), which writes the join password into `Game.ini` with bash builtins, where the game reads it (a public server set up that way answers A2S with "password required", run 43540804147), and passes no password as an argument unless `VEIN_SERVER_ADMIN_PASSWORD` is set. Everything the image prints passes through a filter on its way to the logs that turns any `Password=value` into `Password=******`. `tests/secret-probe.sh` gives every password a value of its own and requires it in no `docker compose logs`, no command line in the containers or on the host, and no game log, except what this README names above.

**The health check asks the server, not its process.** `tools/healthcheck.sh`, mounted read-only, sends the first packet a client sends when it connects, a SteamNetworkingSockets ChallengeRequest, to the game port, and is healthy only on the server's reply carrying back the check's own connection id. Not A2S: a private server, the default, never answers it, and a check on the query port would be red forever. The challenge opens nothing on the server; in CI thirty checks in a row add no line to the game's log and write no file. Up to v1.0.3 it looked for `VeinServer` in `/proc`, and a hung or stopped server keeps its process. While SteamCMD downloads the game nothing is bound to the game port, so the check is red then. On a first start the image runs the server for up to 30 seconds to generate its config, kills it and starts it again; that first instance answers too, so the container can read healthy a minute or so before the real start. Each check ends within 7 seconds, inside the 10 Docker gives it. Up to v1.1.0 about one check in sixty-four failed outright, and the server was not why: bash writes printf's output line by line, and a request whose random connection id held a newline byte went out as two short datagrams the server drops. Timing sixty requests found it, the tenth (id ending 0x0a) lost in every run with nothing dropped by the kernel's socket ([run 43544507204](https://github.com/heyvaldemar/vein-server-docker-compose/actions/runs/43544507204)); the id now never holds one, and two hundred checks in a row against the stand-in are all healthy. The server answers in 11 to 12 ms. **It asks from inside the container**: healthy proves the server answers there, not that the ports are published on the host or open in your firewall; the server browser, or `connect <IP>:7777`, is the test of that.

**Docker Engine 29.4.2 stops SteamCMD, and only that release does.** Its default seccomp profile answers the 32-bit `socketcall` system call with "not implemented" ([moby/moby#52506](https://github.com/moby/moby/issues/52506); for GitHub Actions, the ubuntu-26.04 runner image ships it: [actions/runner-images#14790](https://github.com/actions/runner-images/issues/14790), with the move to 29.7.2 in [actions/runner-images#15205](https://github.com/actions/runner-images/pull/15205)), and SteamCMD is a 32-bit program that makes every socket with it. With Steam and the network both up, it prints `!!! Fatal Error: Steamcmd needs to be online to update.` or `CreateBoundSocket: failed to create socket, error [no name available] (38)`, and the game is never installed or updated. Measured in [a CI run on GitHub's ubuntu-26.04 runner, which ships 29.4.2](https://github.com/heyvaldemar/tf2-server-docker-compose/blob/main/docs/evidence/docker-29.4.2-socketcall.md): SteamCMD failed in this template's pinned image there, and logged in once the daemon had the profile Docker 29.4.3 ships. 29.4.3 reverted the rule, and Ubuntu 26.04's own `docker.io` (27.5.1) never had it. Check with `docker version --format '{{.Server.Version}}'` and upgrade; until you can, point [`seccomp-profile` in `daemon.json`](https://docs.docker.com/reference/cli/dockerd/#daemon-configuration-file) at [moby/profiles seccomp v0.2.3](https://github.com/moby/profiles/blob/836ae4d37ef2ec995c77c99fc55f5b5f3af3a897/seccomp/default.json) and restart Docker.

## Backups

```bash
scripts/backup.sh                     # archive Vein/Saved into ./backups
scripts/restore.sh backups/vein-world-20261018-043000.tar.gz
```

`scripts/backup.sh` archives `Vein/Saved` only: the world and the server's settings, not the 10 GB of game files SteamCMD can download again, and not `Saved/Logs`, which no restore needs and where the engine writes its command line. VEIN has no rcon to ask for a save first; what makes an archive of a running server consistent is its autosave, every 60 seconds with ten rotating files, which the compose file sets. The archive is written as `.partial` and renamed only once it is shown to hold save files. Run it from cron; `VEIN_BACKUP_DIR` says where archives go, `VEIN_BACKUP_KEEP` how many stay.

`scripts/restore.sh` refuses while the server is running, refuses an archive that is not a VEIN world, moves the current world aside to `Vein/Saved.before-restore-<time>` instead of overwriting it, and fails if any save file did not land at its live path.

## Updating

**The game:** `scripts/refresh.sh`, from cron or a timer, every hour or so. It reads the installed build from SteamCMD's app manifest and Steam's from `app_info_print`, and does nothing while they match. When the server is behind, it restarts it, which makes SteamCMD fetch the new build, only if nobody is on by the server's own log, after a backup, and then checks that the manifest names Steam's build. `--check` reports without changing anything, `--dry-run` goes as far as deciding, `--force` restarts with players on.

**The template:** the image pin lives in the `x-images` block at the top of the compose file, as an interpolation default, so a `git pull` delivers the version this repository has tested. The daily freshness check goes red when a newer image tag exists. `./update.sh` moves to the latest release tag on purpose: it refuses to cross a major version unattended, refuses to run over local changes, and names any new required variable before anything has moved.

## Testing

`.github/workflows/real-server.yml` installs the game from Steam and boots it on every push, about 10 GB, as a private server, then: samples the health check while SteamCMD downloads and needs it red with nothing bound; waits for it to go green on the server's challenge reply, restarts it and waits again; asks thirty times in a row and needs never three failures running (what Docker would call unhealthy), every failure counted, no new line in the game's log and no file written; runs the refresh against the idle server and needs it to read nobody on; **stops the server** with SIGSTOP and needs the check red while the old `/proc` check stays green, and green again after SIGCONT.

Without a game:

- `tests/secret-probe.sh`, run by `real-server.yml` on the real server after its first start and again after a restart: a random value for every password the compose file passes, and none in `docker compose logs`, the containers' command lines, `ps` on the host or `Vein.log`, except the admin password where the section above says it is visible. Its self-test plants a canary in all three and must find it. On the template as v1.1.0 shipped it, the probe is red.
- `tests/e2e-healthcheck.sh`: the health check in the pinned image against a stand-in that keeps the real server's rules for a ChallengeRequest (512 bytes, a connection id) and answers on `::`, on one address, only away from 127.0.0.1, with another connection id, never, or is not there: healthy, healthy, healthy, unhealthy, unhealthy within 8 seconds, unhealthy. The A2S check it replaces fails six of the nine assertions.
- `tests/e2e-refresh.sh`: eighteen cases of the refresh against a stand-in server that writes an app manifest, optionally a `Vein.log`, answers A2S with players, with nobody, behind the challenge, or not at all, and can send traffic to its game port. With an idle private server read as "?", as up to v1.0.3, case 14 fails. With "cannot count" read as zero instead, the silent case goes ahead and fails; with the count taken from A2S instead of the log, the log cases fail, the phantom players among them; with a log that matches nothing read as zero, the unknown-format cases go ahead.
- `tests/e2e-backup-restore.sh`: a world out and back in, by path and by byte, the refusals, and the contrast. The same archive extracted at the volume's root leaves no world where the server looks; a restore changed to do that fails four assertions.

CI also lints the shell and the workflows, scans the pinned image with Trivy, and checks daily that the pin still resolves to what upstream publishes.

## Supply chain trust

| Image | Source | Pinned |
|---|---|---|
| `mbround18/vein-docker` | [github.com/mbround18/vein-docker](https://github.com/mbround18/vein-docker), BSD-3-Clause | tag and digest, in the compose file |
| `python:3.13-alpine`, `alpine:3.20` | Docker Official Images | by tag, for the scripts' throwaway containers |

The game itself is Steam app 2131400, downloaded anonymously by SteamCMD inside the container.

### Verify what you deploy

Every release carries three files made on GitHub's runner with a short-lived identity and no stored key: `vein-server-docker-compose-<tag>.tar.gz`, a `git archive` of exactly the tree the tag points at; `vein-server-docker-compose-<tag>.tar.gz.sigstore.json`, a keyless [Sigstore](https://www.sigstore.dev/) signature over it; and `vein-server-docker-compose-<tag>.intoto.jsonl`, [SLSA](https://slsa.dev/) build provenance from the SLSA generator. To check them with nothing from this repository trusted:

```bash
cosign verify-blob vein-server-docker-compose-<tag>.tar.gz \
  --bundle vein-server-docker-compose-<tag>.tar.gz.sigstore.json \
  --certificate-identity-regexp '^https://github.com/heyvaldemar/vein-server-docker-compose/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

slsa-verifier verify-artifact vein-server-docker-compose-<tag>.tar.gz \
  --provenance-path vein-server-docker-compose-<tag>.intoto.jsonl \
  --source-uri github.com/heyvaldemar/vein-server-docker-compose \
  --source-tag <tag>
```

Each release was signed by the run that published it, so its provenance names the tag. The workflow that makes them is [`release-assets.yml`](.github/workflows/release-assets.yml).

---

## About the maintainer

<div align="center">

**Maintained by [Vladimir Mikhalev](https://github.com/heyvaldemar)** · Docker Captain · CNCF Ambassador · IBM Champion · AWS Community Builder

[YouTube](https://www.youtube.com/channel/UCf85kQ0u1sYTTTyKVpxrlyQ?sub_confirmation=1) · [Blog](https://heyvaldemar.com) · [LinkedIn](https://www.linkedin.com/in/heyvaldemar/)

</div>
