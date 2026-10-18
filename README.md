# VEIN dedicated server using Docker Compose

[![Deployment Verification](https://github.com/heyvaldemar/vein-server-docker-compose/actions/workflows/deployment-verification.yml/badge.svg?branch=main)](https://github.com/heyvaldemar/vein-server-docker-compose/actions/workflows/deployment-verification.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A VEIN dedicated server, pinned by digest, with a world this file is arranged around not losing and an update that never restarts the server under anybody.

VEIN is an early-access zombie survival game on Unreal Engine 5, patched often. A server one build behind Steam turns every player away while its container reports healthy, so most of what is here is about staying current without dropping the people on it.

```bash
git clone https://github.com/heyvaldemar/vein-server-docker-compose
cd vein-server-docker-compose
cp .env.example .env && $EDITOR .env          # an admin password, a server name
docker volume create vein-server-data         # the game and the world - see "the volume", below
docker compose -f vein-server-docker-compose.yml -p vein up -d
```

The first start downloads the game through SteamCMD, about 10 GB, then starts the server. Watch it:

```bash
docker compose -p vein logs -f vein-server
docker compose -p vein ps          # healthy once the VeinServer process is up
```

Players find it in the server browser if `VEIN_SERVER_PUBLIC=true`, or join from the in-game console with `connect <IP>:7777`. An IP address, not a hostname; see below.

## What this file knows that a fresh one does not

**Join by IP address, not by name.** On the machine this template comes from, `connect <hostname>:<port>` joined once and then failed with no error at all. Packet captures on both ends of the path showed the client sending nothing when it was given a name, while DNS answered correctly; `connect <IP>:<port>` worked every time, from the internet and from the LAN. VEIN's networking runs over Steam's socket layer, which most likely takes addresses as numbers only. Give players the number.

**The ports are published under the numbers the server binds.** The server is told both ports and advertises them to Steam itself. Map 8888 on the host to 7777 in the container, as a quick edit often does, and Steam lists a port nobody can reach. `VEIN_SERVER_PORT` and `VEIN_SERVER_QUERY_PORT` move both sides at once.

**The image is the wrapper, not the game.** `mbround18/vein-docker` brings SteamCMD and a start script; the game is downloaded into the volume and brought up to date on every start. A new image tag is a change to the scripts. A VEIN patch arrives through `scripts/refresh.sh`, below.

**An unanswered player query is not an empty server.** Every restart drops everyone on the server, so the refresh asks how many players are on first, over A2S from inside the server's network namespace, three times. A server that never answers is skipped like a full one, and the script exits 1. On the machine this template comes from, an update roll that read "cannot count" as zero had three game stacks reading as empty whatever was happening on them.

**The restore path is the whole job.** The world lives in `Vein/Saved/SaveGames` inside the volume. A restore that lands one directory too deep succeeds, reports success, and the server, finding no world where it looks, generates a new one. On the machine this template comes from, the first restore of a real world did exactly that. `scripts/restore.sh` extracts at the one place the backup was taken from and then checks that every save file is at its live path.

**No world until somebody has played.** A server nobody has joined writes no save at all, not on its autosave and not on a clean stop. `scripts/backup.sh` says so and exits 0 rather than failing every night until the first player. Once people have played, that same line is the alarm.

**The passwordless sudo in the image does nothing here.** The image gives its steam user passwordless sudo. `no-new-privileges` stops setuid binaries raising anything, so sudo cannot either; the start script's own sudo calls become no-ops, which costs nothing because the volume already belongs to the steam user.

**The volume is external, so `docker compose down -v` cannot delete the world.** `down -v` is the command everyone reaches for when a stack misbehaves. On a project-managed volume it removes the world without asking. Creating the volume by hand once is the price of not losing it by accident.

**Two minutes to stop.** The image saves the world on the way out, and a SIGKILL in the middle of it is a world that loads from the last autosave, or does not load.

**Memory follows the slot count.** On the machine this template comes from the server idled at 3.3 GB with one player on, and ran 16 slots under an 8 GB ceiling, then 32 under 16 GB. Raise `VEIN_SERVER_MEMORY_LIMIT` with `VEIN_SERVER_MAX_PLAYERS`. There is no swap on top of the ceiling, because a game tick that pages is a stutter every player sees.

## Backups

```bash
scripts/backup.sh                     # archive Vein/Saved into ./backups
scripts/restore.sh backups/vein-world-20261018-043000.tar.gz
```

`scripts/backup.sh` archives `Vein/Saved` only: the world and the server's settings, not the 10 GB of game files SteamCMD can download again. VEIN has no rcon to ask for a save first; what makes an archive of a running server consistent is its autosave, every 60 seconds with ten rotating files, which the compose file sets. The archive is written as `.partial` and renamed only once it is shown to hold save files. Run it from cron; `VEIN_BACKUP_DIR` says where archives go, `VEIN_BACKUP_KEEP` how many stay.

`scripts/restore.sh` refuses while the server is running, refuses an archive that is not a VEIN world, moves the current world aside to `Vein/Saved.before-restore-<time>` instead of overwriting it, and fails if any save file did not land at its live path.

## Updating

**The game:** `scripts/refresh.sh`, from cron or a timer, every hour or so. It reads the installed build from SteamCMD's app manifest and Steam's from `app_info_print`, and does nothing while they match. When the server is behind, it restarts it, which makes SteamCMD fetch the new build, only if nobody is on, after a backup, and then checks that the manifest names Steam's build. `--check` reports without changing anything, `--dry-run` goes as far as deciding, `--force` restarts with players on.

**The template:** the image pin lives in the `x-images` block at the top of the compose file, as an interpolation default, so a `git pull` delivers the version this repository has tested. The daily freshness check goes red when a newer image tag exists. `./update.sh` moves to the latest release tag on purpose: it refuses to cross a major version unattended, refuses to run over local changes, and names any new required variable before anything has moved.

## Testing

Three tests run in CI on every push, none of them with a game download:

- `tests/e2e-healthcheck.sh`: the health check in both directions. With the game process killed and the image's wrapper still running, it must go red.
- `tests/e2e-refresh.sh`: twelve decisions of the refresh against a stand-in server that writes an app manifest and answers A2S with players, with nobody, behind the challenge, or not at all. With "cannot count" read as zero instead, the silent case goes ahead and fails.
- `tests/e2e-backup-restore.sh`: a world out and back in, by path and by byte, the refusals, and the contrast. The same archive extracted at the volume's root leaves no world where the server looks; a restore changed to do that fails four assertions.

CI also lints the shell and the workflows, scans the pinned image with Trivy, and checks daily that the pin still resolves to what upstream publishes. CI does not boot the game: the first start is a 10 GB SteamCMD download, and a test that pretends a runner does that in time is a test that never runs.

## Supply chain trust

| Image | Source | Pinned |
|---|---|---|
| `mbround18/vein-docker` | [github.com/mbround18/vein-docker](https://github.com/mbround18/vein-docker), BSD-3-Clause | tag and digest, in the compose file |
| `python:3.13-alpine`, `alpine:3.20` | Docker Official Images | by tag, for the scripts' throwaway containers |

The game itself is Steam app 2131400, downloaded anonymously by SteamCMD inside the container.

---

## About the maintainer

<div align="center">

**Maintained by [Vladimir Mikhalev](https://github.com/heyvaldemar)** · Docker Captain · IBM Champion · AWS Community Builder

[YouTube](https://www.youtube.com/channel/UCf85kQ0u1sYTTTyKVpxrlyQ?sub_confirmation=1) · [Blog](https://heyvaldemar.com) · [LinkedIn](https://www.linkedin.com/in/heyvaldemar/)

</div>
