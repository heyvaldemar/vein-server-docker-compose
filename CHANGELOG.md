# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- **A world backed up before and gone now fails the backup.** `scripts/backup.sh` exited 0 with "no world yet" whenever `Vein/Saved/SaveGames` was missing, which is right for a server nobody has joined and wrong for one whose world was lost: every night after would have passed over it. Once the backup directory holds an archive of a world, the same absence fails, names that archive, and exits 1. `tests/e2e-backup-restore.sh` removes the world after a backup and requires the failure: 14 checks.

## [1.0.0] - 2026-10-18

### Added

- **A VEIN dedicated server**, `mbround18/vein-docker` v0.0.4 pinned by digest, with the game (Steam app 2131400) downloaded into an external volume by SteamCMD and brought up to date on every start. Ports published under the numbers the server binds and advertises, never translated. `no-new-privileges`, which also turns the image's passwordless sudo into nothing. A memory ceiling with no swap on top, sized from what the machine this template comes from measured.
- **A health check on the game, not the wrapper**, anchored on the `VeinServer` process, with `tests/e2e-healthcheck.sh` proving it goes red when the game dies and the image's entrypoint does not.
- **`scripts/refresh.sh`**: reads the installed build from SteamCMD's app manifest and Steam's from `app_info_print`, and restarts the server to update only when it is behind and nobody is on. A player query that goes unanswered three times is skipped like a full server and exits 1. `--check`, `--dry-run`, `--force`. Twelve decisions proven in `tests/e2e-refresh.sh` against a stand-in server.
- **`scripts/backup.sh` and `scripts/restore.sh`**: the world (`Vein/Saved`) archived without the game files, written as `.partial` until the archive is shown to hold save files; restored at the exact path the server reads, with the previous world moved aside and every save file checked at its live path. `tests/e2e-backup-restore.sh` proves it by path and by byte, and shows that the same archive extracted at the volume's root leaves no world where the server looks.
- **`update.sh`**: moves between release tags, refuses to cross a major version unattended, refuses to run over local changes, names any new required variable before anything has moved.

[Unreleased]: https://github.com/heyvaldemar/vein-server-docker-compose/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/heyvaldemar/vein-server-docker-compose/releases/tag/v1.0.0
