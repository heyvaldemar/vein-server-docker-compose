# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **The health check asks the server, not its process.** It looked for `VeinServer` in `/proc`, which a hung or stopped server keeps. `tools/healthcheck.sh`, mounted read-only, now sends A2S_INFO to the query port and is healthy only on the server's reply (challenge handled, two tries, within 7 seconds). It asks from inside the container, so it does not prove the ports are published on the host or open in a firewall; the README says so.
- **CI boots the real server on every push.** A new job installs the game, about 10 GB, and proves the health check against it: red while SteamCMD downloads with nothing bound, green on the server's A2S answer once the real server has settled (the image runs a first instance for up to 30 seconds to generate its config, which answers too), red with the owner of the query socket stopped by SIGSTOP while the old `/proc` check stays green, green again after SIGCONT. The stand-in test runs the check in the pinned image. The README said CI could not do this in time; it can.
- **The README names Docker Engine 29.4.2.** That release alone stops SteamCMD, which this image runs to install and update the game (measured on this template's pinned image in tf2-server-docker-compose run 42496129688): upgrade to 29.4.3 or later, which reverted the rule, or point the daemon's `seccomp-profile` at the profile 29.4.3 ships. Ubuntu 26.04's own `docker.io` (27.5.1) never had it; on GitHub Actions the ubuntu-26.04 runner image ships it ([actions/runner-images#14790](https://github.com/actions/runner-images/issues/14790), moving to 29.7.2 in [#15205](https://github.com/actions/runner-images/pull/15205)). Documentation only.
- **Helper containers take their values by name.** The A2S probe in `scripts/refresh.sh` was started with `-e PORT=…`, the restore helper with `-e STAMP=…` and `-e FILE=…`. None of them is a secret, but fleet conformance now flags any value expanded into `-e NAME=` (a name says nothing about what it carries), so each is set for that one command and passed as `-e NAME`. Nothing a deployment does changes.

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

[Unreleased]: https://github.com/heyvaldemar/vein-server-docker-compose/compare/v1.0.3...HEAD
[1.0.3]: https://github.com/heyvaldemar/vein-server-docker-compose/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/heyvaldemar/vein-server-docker-compose/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/heyvaldemar/vein-server-docker-compose/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/heyvaldemar/vein-server-docker-compose/releases/tag/v1.0.0
