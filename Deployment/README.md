# Helios Console — Deployment Guide

Sign, package, and deploy the Helios Console macOS app (and its menu bar companion) via Jamf Pro.
This folder is self-contained:

```
Deployment/
  build-pkg.sh                       channel-based sign + package workflow
  sample.mobileconfig                ready-to-edit example profile (all 5 domains, testing only)
  OnDevice/
    ExtensionAttributes/
      EA_Helios_Console_Version.sh   reports installed version into inventory
    Scripts/
      uninstall_helios_console.sh    removes the app(s), receipts, and local prefs
```

The Jamf **Application & Custom Settings schemas** (managed config) live in the repo's
[`schemas/`](../schemas/) folder — one per preference domain (see section 3). The full
old-key → new-domain migration story is in
[`docs/ConfigProfileMigration.md`](../docs/ConfigProfileMigration.md).

The built `.pkg`s land in the repo's `dist/` folder (gitignored).

---

## 1. Build a release package (channel-based)

Versions follow a channel scheme, composed from the project's **Version** (`MARKETING_VERSION`)
and **Build** (`CURRENT_PROJECT_VERSION`):

| Channel | Example version | Audience |
|---|---|---|
| `dev`   | `1.0-d.5` | Dev team machines (exclusion groups) |
| `alpha` | `1.0-a.5` | Alpha testers |
| `beta`  | `1.0-b.5` | Beta group |
| `uat`   | `1.0-u.5` | UAT |
| `ga`    | `1.0`     | GA to all |

**One-time setup (required):** in Xcode, set the **HeliosConsole** target's **Build**
(`CURRENT_PROJECT_VERSION`) to a plain **integer** (e.g. `1`). It currently uses an alphanumeric
string (`a00201`), which the channel scheme can't increment — the build number is the `x` in
`…-d.x` and must be numeric (`CFBundleVersion` is numeric-only; the channel lives in
`CFBundleShortVersionString`). Also confirm **Version** = `1.0` (or your desired marketing version).

**Build a pkg** with `Deployment/build-pkg.sh` — it derives the app name, bundle id, and built
path from the project; you only pick the channel. It's driven by a **CONFIG block at the top of the
script** (no command-line flags — runs straight from CodeRunner or by double-click):

| Toggle | Purpose |
|---|---|
| `CHANNEL` | `dev` / `alpha` / `beta` / `uat` / `ga` |
| `SCHEME` | Pre-set to `HeliosConsole` (the project has two schemes, so this must be explicit). |
| `APP_IDENTITY` | Developer ID Application identity → signs the app + hardened runtime. Empty = the project's own signing (fine for dev machines). Example: `Developer ID Application: Your Name (TEAMIDXXXXXX)`. |
| `NOTARIZE` | `true` = notarize + staple the **app** (not the pkg); requires `APP_IDENTITY`. |
| `SIGN_PKG` | `true` = sign the pkg with your Developer ID Installer cert (auto-detected). |
| `BUMP` | `true` = increment the project's build number after a successful build. |
| `MIRROR_DIST` | If set, also copies the finished `.pkg` to this path (e.g. an iCloud archive folder). Empty = don't mirror. |

Set `CHANNEL`, run it → `dist/HeliosConsole-<version>.pkg`. The build is **universal**
(`arm64,x86_64`), so it installs natively on Apple Silicon and Intel. DerivedData is written to
`~/Library/Developer/HeliosConsole-build` — deliberately **outside iCloud**, because building inside
an iCloud-synced folder makes `codesign` fail on xattr detritus.

**Does the app need notarization?** Not for Jamf **policy** installs — `installer` runs locally and
the app lands with no quarantine flag, so a valid Developer ID signature is enough. Set
`NOTARIZE=true` only if the app may reach a Mac via download/AirDrop, or for MDM-command/manual
installs. Create the notary profile once:
`xcrun notarytool store-credentials "Helios-Notary" --apple-id … --team-id TEAMIDXXXXXX --password <app-specific>`.

> Note: Helios's Xcode team is **TEAMIDXXXXXX** (use a Developer ID under that team, or update
> `APP_IDENTITY`/`DEVELOPMENT_TEAM` if you sign under a different account).

---

## 2. Deploy via Jamf policy

**Jamf Pro → Settings → Packages** → upload the `.pkg`. Then a **Policy** with a **Packages**
payload (Install) scoped to the target Smart Group, trigger Recurring Check-in / Self Service as
appropriate. The companion **HeliosMenuBar** is bundled in the same app build but is a separate
target — package/scope it separately only if you ship it.

---

## 3. Configure the app (managed configuration — 5 domains)

Helios reads managed settings from **five preference domains**, each deployed as its
**own** Configuration Profile. The app's bundle id (`com.herojoneslabs.helios.console`) is **no longer a
managed-config domain** — a profile targeting it does nothing. Managed values take effect
at **app relaunch**. How they interact with the in-app Settings screen varies by key:

- **Profile-only** — the connection/credential values (`jamfPro.*`, `jamfProClientSecret`,
  `entra.*`) have **no editable in-app fields**; the profile is their only source.
- **MDM defaults, locally overridable** — the Cleanup tunables (`cleanup.staleDays`,
  `jamfProtect.enabled` / `url` / `clientID`) are profile-supplied **defaults**: an in-app
  Settings edit stores a local override that silently **wins over the profile** until
  cleared (`defaults delete com.herojoneslabs.helios.console Cleanup.StaleDays`, etc.).
- **Locks when delivered** — only the Jamf Protect **password** (`jamfProtectPassword`)
  locks its in-app field when profile-delivered.

Create five profiles, each via **Jamf Pro → Configuration Profiles → Application & Custom
Settings → External Applications → Custom Schema**, pasting the matching schema:

| # | Preference domain | Schema (in `schemas/`) | Contents | Scope |
|---|---|---|---|---|
| 1 | `com.herojoneslabs.helios.console.core` | `Helios_Core_SCHEMA.json` | Jamf Pro connection, ABM / Jamf Protect / Entra-pointer, local admin | All managed Macs |
| 2 | `com.herojoneslabs.helios.console.credentials` | `Helios_Credentials_SCHEMA.json` | **Secrets only** (`jamfProClientSecret`, `abmPrivateKey`, `jamfProtectPassword`) | All managed Macs (per variant) |
| 3 | `com.herojoneslabs.helios.console.access` | `Helios_Access_SCHEMA.json` | `role`, `cleanup`, `deviceActions` | **Admin Macs ONLY** |
| 4 | `com.herojoneslabs.helios.console.features` | `Helios_Features_SCHEMA.json` | computers / mobileDevices / healthScorecard / deviceHealth / reports | All managed Macs |
| 5 | `com.herojoneslabs.helios.console.ui` | `Helios_UI_SCHEMA.json` | branding, sidebarItems, authentication | All managed Macs |

Required for the app to be configured: **core** `jamfPro.serverURL` + `jamfPro.masterClientID`
AND **credentials** `jamfProClientSecret`. Partial delivery → the app reports itself
unconfigured and logs which domain is missing. `Deployment/sample.mobileconfig` bundles all
five payloads into one profile **for local/manual testing only** — in Jamf they must be five
separate profiles so they can be scoped (and rotated) independently.

> **Bundle-ID rebrand (2026-07):** all domains above use the rebranded
> `com.herojoneslabs.helios.console.*` prefix. Any profile created earlier under a
> `com.helios.console.*` domain silently delivers nothing — edit or re-create it with the
> new domain string. The **separate announcements profile** is affected too: it must be
> **re-created** under `com.herojoneslabs.helios.console.announcements`
> (`schemas/Helios_Announcements_SCHEMA.json`, same keys) — a profile still targeting the
> old announcements domain is ignored. Deployed **Entra pointer domains**
> (`entra.credentialDomain`, admin-chosen) can be reused as-is. Full rebrand fallout
> (local prefs reset, Protect password re-entry, PPPC / Smart Groups, notarization):
> [`docs/ConfigProfileMigration.md`](../docs/ConfigProfileMigration.md) §9.
>
> **Upgrading over the old app:** use a pkg built at **1.0-d.23 or later**. Older pkgs
> installed next to the pre-rebrand app land in `/Applications/HeliosConsole.localized/`
> (Finder shows it as "HeliosConsole") because the installer won't replace a bundle with a
> different bundle id; d.23+ pkgs remove the old app via a preinstall script and install
> cleanly to `/Applications`. See §9 of the migration guide for manual cleanup.

### Role-based access (Cleanup gate — access domain)

The destructive **Cleanup** feature (bulk unmanage / move / add-to-group / delete of stale device
records, plus Jamf Protect deletion) is **fail-closed**:

- It appears **only** when the access profile's `role` is exactly **`Admin`**.
- `Support`, `User`, blank, a missing key, a missing access profile, or any typo → Cleanup
  is **hidden**. The schema deliberately has **no default** for `role`.

**Because a config profile is delivered to the device, the role string alone is a UI gate, not a
security boundary.** Make it a real boundary with the paired-scoping rule in section 4.

### Jamf Protect (optional — core + credentials)

Set `jamfProtect.enabled`, `url`, and `clientID` **in the core profile** to surface Protect
counts and enable Protect-record deletion (these three act as **defaults** — in-app Settings
edits override them locally; see section 3). The Protect **password** is two-tier:

- Deliver it as `jamfProtectPassword` in the **credentials** profile → that value is used
  and the in-app password field **locks**; or
- Omit it → it is entered **in-app** and stored in the Keychain
  (`com.herojoneslabs.helios.console.protect.password`).

---

## 4. Create the Jamf API client (and pair it with the access profile)

**Jamf Pro → Settings → API Roles and Clients.**

- **Read-only operators (Support/User machines):** an API Role with **Read Computers / Read Computer
  Inventory Collection** (and Read Mobile Devices if used). Assign to an API Client; deliver its
  client_id in the **core** profile (`jamfPro.masterClientID`) and its client_secret in a
  **read-only credentials** profile variant (`jamfProClientSecret`).
- **Admin operators (Cleanup):** a role that additionally grants **Update Computers, Delete
  Computers, Read/Update Static Computer Groups, Read Sites,** and **Send Computer Unmanage
  Command** — the scopes the Cleanup actions require. Deliver this client's secret in a
  **write-capable credentials** profile variant.

**Paired-scoping rule:** the **write-capable credentials variant** and the **access profile
granting `role=Admin`** must be scoped to the **same Macs**. Never deliver write-capable
credentials to a Mac without the matching Admin access profile, and never grant `role=Admin`
to Macs carrying only read-only credentials. Non-admin Macs get the read-only credentials
variant and **no access profile at all** (fail-closed → `role=User`).

Splitting secrets into their own tiny profile is what makes **rotation** cheap: rotating a
leaked or expiring secret means editing and re-pushing only the credentials profile — core,
access, features, and ui are untouched. (Managed-pref plists are **world-readable** on disk;
scope tightly, use least-privilege roles, rotate on any suspected exposure.)

---

## 5. Create the version Extension Attribute (optional, recommended)

**Jamf Pro → Settings → Computer Management → Extension Attributes → New**

- Name: **Helios Console Version** (or your preference).
- Data Type: **String**, Input Type: **Script**.
- Paste `OnDevice/ExtensionAttributes/EA_Helios_Console_Version.sh`.

Populates at the next inventory collection (`jamf recon`). Use it to build Smart Groups for update
targeting (e.g. "Helios Console < 1.0").

---

## 6. Uninstall

Add `OnDevice/Scripts/uninstall_helios_console.sh` as a **Jamf script** and run it via a policy to
remove the app(s), forget pkg receipts, and clear the console user's local prefs + Helios Keychain
items (the Cleanup/Protect password plus the five auth/Jamf sign-in accounts, current and legacy
spellings). Separately **unscope/remove ALL FIVE Configuration Profiles** in Jamf — core, credentials,
access, features, ui — (the script does not touch managed profiles). If a Mac was ever configured
with the developer `defaults write` story (see `docs/ConfigProfileMigration.md` §6), user-level
`~/Library/Preferences/com.herojoneslabs.helios.console.{core,credentials,access,features,ui}.plist` files may
remain — remove them with `defaults delete <domain>`, especially the credentials domain.

---

## 7. End-to-end verification

1. Build a `dev` pkg → install on a test Mac → `/Applications/HeliosConsole.app` launches.
2. Push all five profiles → confirm the plists landed:
   `ls /Library/Managed\ Preferences/com.herojoneslabs.helios.console.{core,credentials,access,features,ui}.plist`
   (the access plist appears only on admin-scoped Macs — correct).
3. Relaunch Helios → it reports configured (core + credentials both present); if
   `jamfProtectPassword` was delivered, the in-app Protect password field locks (the only
   field that locks — connection/credential values have no in-app fields, and the Cleanup
   tunables show the profile values only as defaults; see section 3). Unscope only the
   credentials profile and relaunch → the app reports
   unconfigured and logs the missing domain; re-scope it afterwards.
4. Access profile with `role=Admin` → the **Cleanup** sidebar item appears. No access profile
   (or `role=Support`) → Cleanup is **hidden** (fail-closed).
5. `sudo jamf recon` → the **Helios Console Version** EA populates on the inventory record.
6. (Admin) Against a **test** Jamf instance, exercise a safe Cleanup action (move-to-site) on a
   throwaway record before trusting the delete path.
7. Run the uninstall policy → app removed; unscope the five profiles → the Protect password
   field unlocks / Cleanup hides at next launch.

The full multi-profile checklist (including relaunch-required behavior and partial-delivery
checks) lives in [`docs/ConfigProfileMigration.md`](../docs/ConfigProfileMigration.md) §4.
