# Helios Console

A native macOS MDM console for **Jamf Pro** environments. Provides fleet health dashboards,
device inventory management, unified search, and compliance monitoring — with a menu bar
companion app for quick access.

> Status: **v0.2 alpha** · macOS 14.0+ · SwiftUI

## Features

- **Fleet health dashboard** — scorecard, device counts, compliance at a glance
- **Device inventory** — computers (Jamf V1) and mobile devices (Jamf V2), with detail views
- **Unified search** across the fleet
- **Compliance monitoring** with site-based rules (Enterprise vs GroundControl)
- **Announcements feed**, report builder, and DEP enrollment tracking
- **Menu bar companion** for quick search and status

## Architecture

- **UI:** SwiftUI with selective AppKit bridging
- **Data flow:** Services → disk/memory caches → `ObservableObject` → Views
- **Auth:** Master API credentials (from MDM config) mint per-user Jamf API clients
- **APIs:** Jamf Pro V1 (computers), V2 (mobile devices), ABM (AppleCare via ES256 JWT)

See [`docs/CLAUDE.md`](docs/CLAUDE.md) and [`docs/Journal.md`](docs/Journal.md) for the full
architecture narrative, conventions, and gotchas.

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 16 or later
- A Jamf Pro instance for live data (or use mock auth for development)

## Build & Run

```sh
open HeliosConsole.xcodeproj
```

Two schemes are available:

- **HeliosConsole** — the main app
- **HeliosMenuBar** — the menu bar companion

Or build from the command line (no code signing):

```sh
xcodebuild build -project HeliosConsole.xcodeproj -scheme HeliosConsole \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

## Configuration

The app reads MDM configuration from four sources in priority order:
**MDM profile → UserDefaults → app defaults → hardcoded placeholders**.
For local development, the placeholder credentials in `HeliosConsoleApp.swift`
(`https://yourinstance.jamfcloud.com`, `your-client-id`, `your-client-secret`) let you run
against mock data without a live Jamf instance. **Never commit real credentials** — supply them
via an MDM configuration profile at runtime.

Schemas for the MDM configuration and announcements payloads live in [`schemas/`](schemas/).

## Repository workflow

Day-to-day git/GitHub operations are wrapped by a single helper script:

```sh
./scripts/helios-repo.sh <command>
```

| Command            | Action                                                      |
| ------------------ | ----------------------------------------------------------- |
| `status`           | Show branch, ahead/behind, and working-tree status          |
| `update` / `pull`  | Fast-forward pull from `origin`, then mirror to iCloud       |
| `branch <name>`    | Create (or switch to) a feature branch                      |
| `commit "<msg>"`   | Stage all changes and commit                                |
| `push`             | Push the current branch (sets upstream on first push)       |
| `pr [title]`       | Open a pull request from the current branch                 |
| `sync`             | Mirror the working tree into the iCloud folder (no `.git`)   |

The **working git repo lives outside iCloud Drive** (under `~/Developer`) to avoid `.git`
corruption from background sync. `sync` keeps the original iCloud folder updated as a read-only
mirror of what's on GitHub.

## Contributing

`main` is protected — changes land via pull request and must pass CI (builds both schemes on a
macOS runner). See [`.github/PULL_REQUEST_TEMPLATE.md`](.github/PULL_REQUEST_TEMPLATE.md).

## License

Proprietary — all rights reserved. See [`LICENSE`](LICENSE).
