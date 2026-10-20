# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/heyvaldemar/vein-server-docker-compose/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/heyvaldemar/vein-server-docker-compose/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/heyvaldemar/vein-server-docker-compose/releases/tag/v1.0.0
