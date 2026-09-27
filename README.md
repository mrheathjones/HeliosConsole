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
- **Auth:** Master API credentials (from MDM config) mint per-user Jamf API clients; each
  call category is routed to the master **or** the per-user client per profile config
  (see [Jamf API role privileges](#jamf-api-role-privileges))
- **APIs:** Jamf Pro V1 (computers), V2 (mobile devices), ABM (AppleCare via ES256 JWT)

See [`docs/CLAUDE.md`](docs/CLAUDE.md) for the full architecture narrative,
conventions, and gotchas.

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

The app reads managed configuration from **five preference domains**, each delivered as its
own Jamf *Application & Custom Settings* profile (read via `UserDefaults(suiteName:)` by both
targets; changes take effect at relaunch):

| Domain | Contents | Scope |
| --- | --- | --- |
| `com.herojoneslabs.helios.console.core` | Jamf Pro connection, ABM / Jamf Protect / Entra pointer, local admin | All managed Macs |
| `com.herojoneslabs.helios.console.credentials` | Secrets only (rotate independently) | All managed Macs |
| `com.herojoneslabs.helios.console.access` | `role`, Cleanup, device-action allow-list (fail-closed) | **Admin Macs only** |
| `com.herojoneslabs.helios.console.features` | Feature modules & tuning | All managed Macs |
| `com.herojoneslabs.helios.console.ui` | Branding & UX | All managed Macs |

Per-domain schemas live in [`schemas/`](schemas/) (plus the separate announcements domain);
deployment steps are in [`Deployment/README.md`](Deployment/README.md) and the full
old-key → new-domain migration story is in
[`docs/ConfigProfileMigration.md`](docs/ConfigProfileMigration.md).

For local development there are **no seeded placeholder credentials anymore** (the old
placeholder-seeding path and the dead `ConfigurationManager`/`AppConfiguration` layer were
removed) — write values straight into the suite domains, e.g.
`defaults write com.herojoneslabs.helios.console.core jamfPro -dict serverURL "https://yourorg.jamfcloud.com" …`,
or use mock auth. **Never commit real credentials** — supply them via the credentials profile
at runtime.

## Jamf API role privileges

Helios authenticates to Jamf Pro with API Clients (OAuth 2.0 client credentials). Two identities
are involved:

- **Master client** — from the `core` / `credentials` profiles. It is the default for every
  call and the fallback whenever a scope isn't routed to the user, so its **API role must hold
  the union of every privilege below**.
- **Per-user client** — provisioned per signed-in operator so Jamf's own audit log names the
  person. Its API role only needs the privileges for the scopes you route to `user` via
  `core → authentication → credentialRouting` (see [`schemas/Helios_Core_SCHEMA.json`](schemas/Helios_Core_SCHEMA.json)).
  A scope routed to `user` is **fail-closed** — the call errors if the operator's role lacks the
  privilege (master would have worked), so widen the per-user role before routing a scope to it.

> The OAuth token endpoints (`/api/v1/oauth/token`, `/api/v1/auth/invalidate-token`) need **no**
> privilege — only a valid API Client with a role attached.

Privileges are the exact strings from the Jamf Pro **API Roles and Clients** privilege picker.
Verified against the Jamf Pro API OpenAPI (`developer.jamf.com`) 2026-07.

| Routing scope | Jamf Pro API privileges | Backing endpoints |
| --- | --- | --- |
| `mdmCommands` — restart, shut down, lock, unlock account, Bluetooth, remote desktop, blank push | **Send MDM command information in Jamf Pro API**, **View MDM command information in Jamf Pro API**, **Read Computers**, **plus one `Send Computer …` privilege per command** (table below) | `POST/GET /api/v2/mdm/commands`, `POST /api/v2/mdm/blank-push` |
| `returnToService` — erase + Jamf record delete | **Send MDM command information in Jamf Pro API**, **View MDM command information in Jamf Pro API**, **Send Computer Remote Wipe Command**, **Delete Computers**, **Read Computers** | `POST/GET /api/v2/mdm/commands` (`ERASE_DEVICE` + ack poll), `DELETE /api/v1/computers-inventory/{id}` |
| `sensitiveReads` — LAPS password + FileVault key | **View Local Admin Password**, **View Disk Encryption Recovery Key** | `GET /api/v2/local-admin-password/{mgmtId}/account/{user}/password`, `GET /api/v3/computers-inventory/{id}/filevault` |
| `moveToSite` | **Read Sites**, **Read Computers**, **Update Computers** (computers); **Read Mobile Devices**, **Update Mobile Devices** (mobile) | `GET /api/v1/sites`, `PATCH /api/v3/computers-inventory-detail/{id}`, `PATCH /api/v2/mobile-devices/{id}` |
| `prestage` — register/assign + Inventory Preload | **Read Computer PreStage Enrollments**, **Update Computer PreStage Enrollments**, **Read Inventory Preload Records**, **Create Inventory Preload Records**, **Update Inventory Preload Records** | `GET /api/v3/computer-prestages`, `GET/POST /api/v2/computer-prestages/{id}/scope`, `GET/POST/PUT /api/v2/inventory-preload/records`, `GET /api/v2/inventory-preload/csv-template`, `POST /api/v2/inventory-preload/csv-validate` |
| `cleanup` — stale listing + deletes | **Read Computers**, **Delete Computers**, **Read Sites**, **Read Static Computer Groups**, **Update Static Computer Groups** | `GET /api/v3/computers-inventory[-detail]`, `DELETE /api/v3/computers-inventory/{id}`, `GET /api/v1/sites`, `GET /api/v3/computer-groups/static-groups`, `PUT /JSSResource/computergroups/id/{id}` |
| `deviceSearch` — search + device detail + **My Devices** | **Read Computers**, **Read Mobile Devices**, plus **Read Users** for My Devices' identity match (optional — without it that module matches on the sign-in address alone) | `GET /api/v1/computers-inventory`, `GET /api/v2/mobile-devices`, `GET /api/v2/mobile-devices/detail`, `GET /api/v1/users` |
| `inventory` — dashboard counts + health | **Read Computers**, **Read Mobile Devices** | `GET /api/v1|v3/computers-inventory`, `GET /api/v2/mobile-devices/detail` |
| `reports` | **Read Computers**, **Read Mobile Devices** | `GET /api/v2/mobile-devices/detail` (+ inventory reads) |

### Master-only: provisioning per-user API clients

When `core → authentication → autoCreateUserApiClient` is **true** (the default), the master
client creates a Jamf API client for each operator who doesn't have one and assigns it the role
named in `core → jamfPro → requiredRoleName`. That is a **master-role-only** capability and needs:

| Privilege | Why |
| --- | --- |
| **Read API Integrations** | Find an operator's existing client (`GET /api/v1/api-integrations`) |
| **Create API Integrations** | Create the client (`POST /api/v1/api-integrations`) |
| **Update API Integrations** | Enable it, assign/repair its role, rename it, and mint its secret (`PUT /api/v1/api-integrations/{id}`, `POST .../client-credentials`) |
| **Read API Roles** | Resolve the configured role name (`GET /api/v1/api-roles`) |

Clients are named **`<UPN> (<clientId>)`** — Jamf's audit log records the *client id* that ran a
command, so carrying the id in the name is what maps an audited action back to a person. Clients
created before this behavior are renamed on the operator's next sign-in. The UPN stays the name's
prefix, which is how Helios looks the client up.

Set `autoCreateUserApiClient` to **false** to forbid Helios from ever minting API clients — then
operators need a pre-created client, and any scope routed to `user` fails closed without one.
(The built-in **email** sign-in flow depends on this creation path, so leave it on if you use it.)

**Not part of these Jamf roles** (separate credentials): Apple Business Manager lookup (ABM API
client), Jamf Protect cleanup (Protect API client), and the Return-to-Service **Entra**
device-object delete (Microsoft Graph app registration — `Device.ReadWrite.All` + Cloud Device
Administrator).

### MDM commands: one privilege per command type

The `/api/v2/mdm/commands` OpenAPI lists only *View MDM command information in Jamf Pro API*, but
that is **not sufficient**. Jamf enforces three layers, and the role needs all of them:

1. **Send MDM command information in Jamf Pro API** — permission to POST a command at all.
2. **View MDM command information in Jamf Pro API** — read command status (the Return-to-Service
   flow polls for the erase acknowledgment).
3. **A `Send Computer …` privilege matching the specific command type.**

Missing #3 yields a 403 whose bracketed token names the command type — e.g. the Bluetooth toggle
is sent as a `SETTINGS` command:

```json
{ "httpStatus": 403, "errors": [ { "code": "INVALID_PRIVILEGE",
  "description": "User <clientId> not privileged for [SETTINGS]" } ] }
```

Command types Helios sends, and the privilege each needs (names verified against a Jamf Pro
instance's `GET /api/v1/api-role-privileges`, 2026-07):

| Helios action | MDM command type | Required privilege |
| --- | --- | --- |
| Enable/Disable Bluetooth | `SETTINGS` | **Send Computer Bluetooth Command** |
| Enable/Disable Remote Desktop | `ENABLE_/DISABLE_REMOTE_DESKTOP` | **Send Computer Remote Desktop Command** |
| Restart | `RESTART_DEVICE` | **Send Computer Restart Command** |
| Shut Down | `SHUT_DOWN_DEVICE` | **Send Computer Shut Down Command** |
| Wipe / Return-to-Service erase | `ERASE_DEVICE` | **Send Computer Remote Wipe Command** |
| Lock | `DEVICE_LOCK` | **Send Computer Remote Lock Command** (+ **View Computer Device Lock Pin** to display the PIN) |
| Unlock User Account | `UNLOCK_USER_ACCOUNT` | **Send Computer Unlock User Account Command** |
| Blank Push | `POST /api/v2/mdm/blank-push` | **Send MDM command information in Jamf Pro API** (the `Send Blank Pushes to Mobile Devices` privilege is mobile-only) |

Privilege strings vary by Jamf version — list the exact set your instance offers with:

```sh
curl -s "$JAMF_URL/api/v1/api-role-privileges" \
  -H "Authorization: Bearer $TOKEN" -H "Accept: application/json" \
  | jq -r '.privileges[]' | grep -iE "bluetooth|send computer|mdm command"
```

Role changes apply immediately, but Helios caches the per-user token for up to an hour — sign out
and back in to force a fresh one. As a stop-gap, route `credentialRouting.mdmCommands` to
`master` until the per-user role is widened.

**Minimal per-user role for full attribution** (route every scope to `user`): the union of the
table above — Read/Update/Delete Computers, Read/Update Mobile Devices, Read Sites, Read/Update
Static Computer Groups, Read/Update Computer PreStage Enrollments, Read/Create/Update Inventory
Preload Records, View MDM command information in Jamf Pro API, View Local Admin Password, and
View Disk Encryption Recovery Key. Trim to only the scopes you actually route to `user`.

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
