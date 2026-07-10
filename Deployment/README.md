# Helios Console — Deployment Guide

Sign, package, and deploy the Helios Console macOS app (and its menu bar companion) via Jamf Pro.
This folder is self-contained:

```
Deployment/
  build-pkg.sh                       channel-based sign + package workflow
  JamfAppCustomSettingsSchema.json   Application & Custom Settings schema (managed config)
  sample.mobileconfig                ready-to-edit example configuration profile
  OnDevice/
    ExtensionAttributes/
      EA_Helios_Console_Version.sh   reports installed version into inventory
    Scripts/
      uninstall_helios_console.sh    removes the app(s), receipts, and local prefs
```

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

## 3. Configure the app (managed configuration)

Helios reads managed settings from a Configuration Profile whose **preference domain = the app's
bundle id, `com.helios.console`**. Managed values are **forced** and lock the matching in-app fields.

- **Jamf Pro → Configuration Profiles → Application & Custom Settings → External Applications →
  Custom Schema.**
- Preference domain: **`com.helios.console`**.
- Paste **`Deployment/JamfAppCustomSettingsSchema.json`** and fill in the values, or import
  **`Deployment/sample.mobileconfig`** as a starting point.

The schema is **nested** — keep the object groupings (`jamfPro`, `userInterface`,
`appleBusinessManager`, `cleanup`, `jamfProtect`) and the top-level `role`. Required:
`jamfPro.serverURL`, `jamfPro.masterClientID`, `jamfPro.masterClientSecret`.

### Role-based access (Cleanup gate)

The destructive **Cleanup** feature (bulk unmanage / move / add-to-group / delete of stale device
records, plus Jamf Protect deletion) is **fail-closed**:

- It appears **only** when `role` is exactly **`Admin`**.
- `Support`, `User`, blank, a missing key, or any typo → Cleanup is **hidden**.

**Because a config profile is delivered to the device, the role string alone is a UI gate, not a
security boundary.** Make it a real boundary by:

1. Giving the master API client **write/delete scopes only** where Cleanup is intended, and
2. **Scoping the `role=Admin` profile (and the write-scoped master client it carries) in Jamf to
   admin Macs only.** Non-admin Macs should receive a profile with `role` = `Support`/`User` and a
   read-only master client.

### Jamf Protect (optional)

Set `jamfProtect.enabled`, `url`, and `clientID` to surface Protect counts and enable Protect-record
deletion. The Protect **password is entered in the app and stored in the Keychain** — it is never
delivered in the profile.

---

## 4. Create the Jamf API client

**Jamf Pro → Settings → API Roles and Clients.**

- **Read-only operators (Support/User machines):** an API Role with **Read Computers / Read Computer
  Inventory Collection** (and Read Mobile Devices if used). Assign to an API Client; deliver its
  id/secret as the master client.
- **Admin operators (Cleanup):** a role that additionally grants **Update Computers, Delete
  Computers, Read/Update Static Computer Groups, Read Sites,** and **Send Computer Unmanage
  Command** — the scopes the Cleanup actions require. Deliver this client **only** to the
  `role=Admin`, admin-scoped profile.

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
remove the app(s), forget pkg receipts, and clear the console user's local prefs + Cleanup Keychain
item. Separately **unscope/remove the Configuration Profile** in Jamf (the script does not touch the
managed profile).

---

## 7. End-to-end verification

1. Build a `dev` pkg → install on a test Mac → `/Applications/HeliosConsole.app` launches.
2. Push the Configuration Profile (`role=Admin`) → the **Cleanup** sidebar item appears; the matching
   Settings fields lock. Push with `role=Support` → Cleanup is **hidden**.
3. `sudo jamf recon` → the **Helios Console Version** EA populates on the inventory record.
4. (Admin) Against a **test** Jamf instance, exercise a safe Cleanup action (move-to-site) on a
   throwaway record before trusting the delete path.
5. Run the uninstall policy → app removed; re-scope the profile away → fields unlock / Cleanup hides.
