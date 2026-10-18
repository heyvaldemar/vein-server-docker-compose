# Security Policy

## Supported versions

| Version                                        | Status             |
|------------------------------------------------|--------------------|
| Current `main` and the latest tagged release   | :white_check_mark: |
| Older tags without a recent rebuild            | :x:                |

Fixes land on `main` and ship as a new tag; older tags are not patched in place.

## Reporting a vulnerability

Report privately through GitHub: **Security → Report a vulnerability** on this repository, or by email to v@valdemar.ai. The process is described at [heyvaldemar.com/security](https://heyvaldemar.com/security/).

You can expect an acknowledgment within 7 days. This project does not operate a bounty program; researchers who submit valid, responsibly disclosed reports receive public credit in the release notes and the changelog.

Please do not open public GitHub issues for security reports.

## Supply chain trust

This repository publishes a deployment template, not a custom software distribution. Upstream images are pinned by `tag@sha256:<digest>` as interpolation defaults in the compose file's `x-images` block, so a plain `git pull` delivers the exact combination this repository has tested. The Pin Freshness workflow re-resolves every pin daily and fails when one has drifted or a newer tag exists; the Deployment Verification workflow scans the pinned image, parses the compose file and runs the health-check, refresh and backup-restore tests on every change. It does not boot the game, which is a 10 GB download. Either one notifies the maintainer. GitHub Actions are pinned by commit SHA.

The README's "Supply chain trust" section lists the upstream images and where they come from. The game itself is downloaded from Steam by SteamCMD inside the container and is not pinned here: a server behind Steam's build cannot be joined.

## Credentials

`.env` is gitignored, and the required admin password fails fast at deploy time when it is missing. This repository has never tracked a credential. The scripts read nothing from `.env` but the query port.
