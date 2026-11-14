# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_(no unreleased changes yet)_

## [1.2.0] - 2026-11-14

### Security

- **Passwords no longer show in `docker compose logs` or on the server's command line.** Up to v1.1.0 the image started the game with the join password and the admin password as arguments, and both reached `docker compose logs` (the engine prints its command line) and `ps` on the host. If you ever posted those logs, change both passwords.

### Fixed

- **About one health check in sixty-four no longer fails for nothing.** bash writes printf's output line by line, so a request whose random connection id held a newline byte (0x0a) went out as two datagrams shorter than the 512 bytes the server accepts, and all four tries of that check went unanswered. The id never holds one now. `tests/e2e-healthcheck.sh` runs two hundred checks in a row and needs every one healthy; v1.1.0's check fails it (2 of 200).
- **The README no longer blames the server for a lost answer.** v1.1.0's README said the server leaves about one challenge in sixty unanswered. It did not: the check had sent that request as two datagrams, cut at a newline byte in its id. The line now says so.

### Changed

- **The server is started by `tools/start-server.sh`.** The image runs it as `START_COMMAND`. It writes the join password (`VEIN_SERVER_PASSWORD`) into `Game.ini`, where the game reads it, with bash builtins, and passes no password as an argument. With a join password set, it creates a missing `Game.ini` and refuses to start unless the file holds the password afterwards, so a failed write cannot start an open server. A public server set up this way answers A2S with "password required" (CI run 43540804147).
- **The admin password is optional, and admins by Steam id come first.** VEIN reads `VEIN_SERVER_ADMIN_PASSWORD` only from its command line: the engine reads no `UECommandLine.txt` in any of five places tried (run 43540804147). It is now empty by default, and the README recommends `VEIN_SERVER_ADMIN_STEAM_IDS` instead. Set, it must be letters and digits only, so the log filter covers all of it; the start refuses anything else. Set, it is visible on the game's command line and in `Vein/Saved/Logs/Vein.log`, and the README says so.
- **Everything the image prints passes a filter.** `Password=value` reads `Password=******` in `docker compose logs`, a quoted value or one with escaped spaces included, whatever printed it: the image's start line, its list of processes left behind after an exit, or the engine's own command line.
- **Backups leave out `Vein/Saved/Logs`.** No restore needs the logs, and the engine writes its command line there.
- **CI proves it on the real server.** `tests/secret-probe.sh` gives every password the compose file passes a random value and requires it in no `docker compose logs`, no command line in the containers, no `ps` on the host and no `Vein.log`, except the admin password where the README names it. It runs after the first start and again after a restart, and a self-test plants a canary in all three places and must find it. On v1.1.0 as released, the probe is red (run 43541457647: both passwords in the logs, the container's command lines and the host's `ps`).
## [1.1.0] - 2026-11-14

### Fixed

- **An idle private server updates itself again.** VEIN answers the Steam (A2S) query only as a public server; private, the template's default, it never answers (measured in CI). `scripts/refresh.sh` read a private server whose log showed no join since its start as "nobody can say who is on" and never restarted it to update. With no join in the log and no Steam answer, it now watches the game port for 10 seconds from a helper in the server's network namespace (`NET_RAW` only): no packet at all is nobody on, and the server's own health check, on the loopback interface, does not count; any traffic is someone who may have joined in a shape the parser does not know, and it waits as before. `tests/e2e-refresh.sh` cases 14 to 16; the released script fails case 14, and CI runs the refresh against the real idle private server.
- **An index pushed again over the same build is no longer reported as drift.** The daily pin check compared each pin with the digest the tag's index has now and failed on any difference, so a publisher re-pushing the index over the very same images (a platform added, an attestation rewritten) turned it red for an image nobody rebuilt, and no pin would ever move to turn it green. It now also compares the linux/amd64 build under both digests, the one CI runs and proves: the same build passes with a notice naming both digests, a new build fails as drift exactly as before, and a build that cannot be read still fails.

### Changed

- **The health check asks the server, not its process.** It looked for `VeinServer` in `/proc`, which a hung or stopped server keeps. `tools/healthcheck.sh`, mounted read-only, now sends the first packet a client sends when it connects, a SteamNetworkingSockets ChallengeRequest, to the game port, and is healthy only on the server's reply carrying back the check's own connection id (two tries, within 7 seconds). Not A2S: a private server, the default, never answers it, so a check on the query port would be red forever. The challenge opens nothing on the server. It asks from inside the container, so it does not prove the ports are published on the host or open in a firewall; the README says so.
- **CI boots the real server on every push.** A new job installs the game, about 10 GB, as a private server, and proves the health check against it: red while SteamCMD downloads with nothing bound, green on the server's challenge reply once the real server has settled and again after a restart (the image runs a first instance for up to 30 seconds to generate its config, which answers too), thirty checks in a row with never three failures running and every failure counted, no new line in the game's log and no file written, red with the owner of the game port's socket stopped by SIGSTOP while the old `/proc` check stays green, green again after SIGCONT. The stand-in test runs the check in the pinned image. The README said CI could not do this in time; it can.
- **The README names Docker Engine 29.4.2.** That release alone stops SteamCMD, which this image runs to install and update the game (measured on this template's pinned image in tf2-server-docker-compose run 42496129688): upgrade to 29.4.3 or later, which reverted the rule, or point the daemon's `seccomp-profile` at the profile 29.4.3 ships. Ubuntu 26.04's own `docker.io` (27.5.1) never had it; on GitHub Actions the ubuntu-26.04 runner image ships it ([actions/runner-images#14790](https://github.com/actions/runner-images/issues/14790), moving to 29.7.2 in [#15205](https://github.com/actions/runner-images/pull/15205)). Documentation only.
- **Helper containers take their values by name.** The A2S probe in `scripts/refresh.sh` was started with `-e PORT=…`, the restore helper with `-e STAMP=…` and `-e FILE=…`. None of them is a secret, but fleet conformance now flags any value expanded into `-e NAME=` (a name says nothing about what it carries), so each is set for that one command and passed as `-e NAME`. Nothing a deployment does changes.

### Removed

- **The Steam game server login token.** `VEIN_SERVER_STEAM_GSLT` is gone from the compose file and `.env.example`: VEIN does not read one. The image hands it to the server as `+sv_setsteamaccount`, a Source-engine setting; the VEIN binary has no such string, and with a token on its command line the server still logged on to Steam as an anonymous game server (measured in CI). The image's start line printed the token in clear in `docker compose logs`; without one there is nothing to print. If you set it and ever posted those logs, revoke that token on Steam's game server account page.
## [1.0.3] - 2026-11-02

### Fixed

- **A log read that Docker cut off is no longer counted, or blamed on the log's format.** `scripts/refresh.sh` piped `docker exec cat Vein.log` straight into its parser, so an exec cut off by a restart (exit 137 after part of the file, measured on Docker 29.7.2) was counted as the whole log. A read that stops before the last join counts a player who is on as gone; here it came back as "no joins at all" and the message said the log's format may have changed. The log is now copied first, and a copy from an exec that did not end with 0 is not counted: the Steam answer, which can only count too many, decides alone, and the run says so.
- **Docker's own message is no longer read as the installed build.** When the container stops under the exec, Docker prints "cannot exec in a stopped state" on stdout with exit 128, and the refresh took that text for the build and went on to "would restart to update (cannot exec in a stopped state -> 101)". The build is now a number from an exec that ended with 0, or unknown.
- `tests/e2e-refresh.sh` cases 14 and 15 break those two reads through a wrapper around the real `docker`; the released script fails both. On the server this template comes from, a chat bot read a Docker error on stdout as part of a game's log.

## [1.0.2] - 2026-10-20

### Fixed

- **A log the refresh cannot read no longer counts as an empty server.** v1.0.1 counted players from `Vein.log`; a log with no join in the shape it knows read as zero players, and the refresh would restart the server under whoever Steam's answer said was on. Phantom players come only after real joins, which the log records, so a log with no joins at all while A2S says players are on is a log in an unknown format (a game update could change it). That count is now "?": the refresh waits, exits 1, and says the log's format may have changed. An empty log on a server A2S also calls empty is still empty. `tests/e2e-refresh.sh` adds a log with no joins and one with joins in an unknown shape, both with A2S at 2, and a log with no joins with A2S at 0; on v1.0.1 the first two said "the log is believed" and would have restarted. 18 checks.
- **The README says what a Demo player actually sees**: nothing in the server list, and "connection failed" on Direct Connect. v1.0.1 said the player finds the server and is refused, which the source server's record does not support.

## [1.0.1] - 2026-10-20

### Fixed

- **An update is no longer blocked by players who left.** VEIN does not drop a player from its Steam (A2S) answer when they disconnect: on the machine this template comes from it reported "4 / 32" for hours after its log showed all four leave. `scripts/refresh.sh` counted players over A2S, so after the first session it would have found the server occupied on every run and never updated it, and a server one build behind turns every player away. It now counts from `Vein/Saved/Logs/Vein.log` (logins, joins, disconnects), falling back to A2S only when there is no log, and says so when the two disagree. `tests/e2e-refresh.sh` adds three cases, 16 checks; on the old script all three fail: the phantom case waits ("4 player(s) are on"), a player in the log with A2S at 0 went ahead to a restart, and an empty log read as 2 players.
- **The README says the free Demo cannot join**, and which log line says so (`Cert is not authorized for appid 1857950, only 2082470`).
- **The README no longer says a restore on the source server generated a new world.** It would have: a test restore there, with restic rather than this template's tar, put the world one directory too deep, and was caught before the backup was needed. The README said it happened.
- **A world backed up before and gone now fails the backup.** `scripts/backup.sh` exited 0 with "no world yet" whenever `Vein/Saved/SaveGames` was missing, which is right for a server nobody has joined and wrong for one whose world was lost: every night after would have passed over it. Once the backup directory holds an archive of a world, the same absence fails, names that archive, and exits 1. `tests/e2e-backup-restore.sh` removes the world after a backup and requires the failure: 14 checks.

## [1.0.0] - 2026-10-18

### Added

- **A VEIN dedicated server**, `mbround18/vein-docker` v0.0.4 pinned by digest, with the game (Steam app 2131400) downloaded into an external volume by SteamCMD and brought up to date on every start. Ports published under the numbers the server binds and advertises, never translated. `no-new-privileges`, which also turns the image's passwordless sudo into nothing. A memory ceiling with no swap on top, sized from what the machine this template comes from measured.
- **A health check on the game, not the wrapper**, anchored on the `VeinServer` process, with `tests/e2e-healthcheck.sh` proving it goes red when the game dies and the image's entrypoint does not.
- **`scripts/refresh.sh`**: reads the installed build from SteamCMD's app manifest and Steam's from `app_info_print`, and restarts the server to update only when it is behind and nobody is on. A player query that goes unanswered three times is skipped like a full server and exits 1. `--check`, `--dry-run`, `--force`. Twelve decisions proven in `tests/e2e-refresh.sh` against a stand-in server.
- **`scripts/backup.sh` and `scripts/restore.sh`**: the world (`Vein/Saved`) archived without the game files, written as `.partial` until the archive is shown to hold save files; restored at the exact path the server reads, with the previous world moved aside and every save file checked at its live path. `tests/e2e-backup-restore.sh` proves it by path and by byte, and shows that the same archive extracted at the volume's root leaves no world where the server looks.
- **`update.sh`**: moves between release tags, refuses to cross a major version unattended, refuses to run over local changes, names any new required variable before anything has moved.

[Unreleased]: https://github.com/heyvaldemar/vein-server-docker-compose/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/heyvaldemar/vein-server-docker-compose/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/heyvaldemar/vein-server-docker-compose/compare/v1.0.3...v1.1.0
[1.0.3]: https://github.com/heyvaldemar/vein-server-docker-compose/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/heyvaldemar/vein-server-docker-compose/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/heyvaldemar/vein-server-docker-compose/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/heyvaldemar/vein-server-docker-compose/releases/tag/v1.0.0
