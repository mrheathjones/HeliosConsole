# Helios Console — Managed Configuration Migration (v1 monolith → v2 domain split)

**Date:** 2026-07-10 · **Branch:** `feature/config-domain-split` · **Cutover:** HARD (no fallback)

Helios Console 2.x reads its managed configuration from **five preference domains**, each
deployed as its **own** Jamf Pro *Application & Custom Settings* configuration profile. The
old single-profile model (preference domain `com.helios.console` — the *pre-rebrand* bundle
id, kept verbatim here as the historical record; schema `Deployment/HeliosConsole_SCHEMA.json`)
is **gone** — the app no longer reads managed configuration from that domain at all, and
there is no legacy flat-key fallback. A Mac that still carries only the old profile behaves
exactly like an unconfigured Mac.

> `com.herojoneslabs.helios.console` (the app's bundle id) is still used by the apps for **local,
> unmanaged** state — deep-link IPC between the main app and the menu bar app, and in-app
> preferences. Do not deploy managed configuration to that domain anymore.
>
> **Untouched by the domain split itself:** the announcements domain
> `com.herojoneslabs.helios.console.announcements` (`schemas/Helios_Announcements_SCHEMA.json`) and the
> separate admin-chosen Entra Graph credentials domain
> (`schemas/JSON_SCHEMA/Auth/Helios_Entra_Graph_Credentials_SCHEMA_v1.json`) keep the same
> schemas and semantics. Note that the **bundle-ID rebrand (§9)** *did* rename the
> announcements domain string — the Jamf announcements profile must be **re-created under
> the new domain** — whereas already-deployed Entra pointer domains can be reused as-is.

---

## 1. The five domains

| # | Preference domain | Tier | Schema file | Scope |
|---|---|---|---|---|
| 1 | `com.herojoneslabs.helios.console.core` | Connection & integrations (no secrets) | `schemas/Helios_Core_SCHEMA.json` | **All managed Macs** running Helios |
| 2 | `com.herojoneslabs.helios.console.credentials` | Secrets only (rotate independently) | `schemas/Helios_Credentials_SCHEMA.json` | **All managed Macs** running Helios (per credential variant) |
| 3 | `com.herojoneslabs.helios.console.access` | RBAC & destructive capability | `schemas/Helios_Access_SCHEMA.json` | **Admin Macs ONLY** |
| 4 | `com.herojoneslabs.helios.console.features` | Feature modules & tuning | `schemas/Helios_Features_SCHEMA.json` | **All managed Macs** running Helios |
| 5 | `com.herojoneslabs.helios.console.ui` | Branding & UX | `schemas/Helios_UI_SCHEMA.json` | **All managed Macs** running Helios |

Every domain also accepts an optional `configurationVersion` (string, default `"2.0"`,
informational — the loader logs it; nothing else reads it).

The app is **valid/configured** only when BOTH the core profile (`jamfPro.serverURL` +
`jamfPro.masterClientID` non-empty) AND the credentials profile (`jamfProClientSecret`
non-empty) have landed. Partial delivery → the app reports itself unconfigured and logs
which domain is missing; there is no silent placeholder fallback.

---

## 2. Old key → new domain mapping

Every top-level key and nested section of the old monolithic schema
(`Deployment/HeliosConsole_SCHEMA.json`, preference domain `com.helios.console` — the
pre-rebrand bundle id, historical) maps as
follows. **Enforcement status** says whether the app acts on the value today, or only
parses and exposes it (a recorded decision — view-level enforcement is follow-up work).

| Old key (`com.helios.console`, historical) | New domain | New key | Enforcement status |
|---|---|---|---|
| `configurationVersion` | all five | `configurationVersion` (per domain, default `"2.0"`) | Logged only (informational) |
| `jamfPro.serverURL` | core | `jamfPro.serverURL` | **ENFORCED** — all Jamf services |
| `jamfPro.masterClientID` | core | `jamfPro.masterClientID` | **ENFORCED** — all Jamf services |
| `jamfPro.masterClientSecret` | **credentials** | `jamfProClientSecret` (moved + renamed, flat key) | **ENFORCED** — everything |
| `jamfPro.requiredRoleName` | core | `jamfPro.requiredRoleName` (default `SVC_WATCHER_USER`) | **ENFORCED** — per-user API client provisioning |
| `jamfPro.screenShareEnabled` | core | `jamfPro.screenShareEnabled` (default now **false**) | **ENFORCED** — DeviceView |
| `jamfPro.connectionTimeout` | core | `jamfPro.connectionTimeout` (default 30) | Parsed, **NOT yet enforced** (request timeouts are currently hardcoded in the networking layer) |
| `jamfPro.requestTimeout` | core | `jamfPro.requestTimeout` (default 60) | Parsed, **NOT yet enforced** (request timeouts are currently hardcoded in the networking layer) |
| `jamfPro.role` (mirror) | — | **DROPPED** — `access.role` is the only role key | n/a |
| `appleBusinessManager.enabled` | core | `appleBusinessManager.enabled` (default now **false**) | **ENFORCED** — AbmAPIService |
| `appleBusinessManager.clientID` | core | `appleBusinessManager.clientID` | **ENFORCED** — AbmAPIService |
| `appleBusinessManager.keyID` | core | `appleBusinessManager.keyID` | **ENFORCED** — AbmAPIService |
| `appleBusinessManager.privateKey` | **credentials** | `abmPrivateKey` (moved + renamed, flat key) | **ENFORCED** — AbmAPIService |
| `localAdministration.enabled` | core | `localAdministration.enabled` (default true) | Parsed — no view consumes the flag today (only `username` is used) |
| `localAdministration.username` | core | `localAdministration.username` (default `macadmin`) | **ENFORCED** — LAPS lookup, DeviceView |
| `computers.*` | features | `computers.*` (unchanged) | **ENFORCED**: `enabled` (unified search), `enableAPIActions` (DeviceActionPolicy), `inventorySections` (inventory fetch; default now matches the sections views render), `showDashboardCard` (dashboard). `fetchInventory`/`inventoryRefreshInterval` still unenforced (no scheduler exists) |
| `mobileDevices.*` | features | `mobileDevices.*` (unchanged) | **ENFORCED**: `enabled` (unified search), `inventorySections` (inventory fetch; default now matches the sections views render), `showDashboardCards.{iOS,iPadOS,visionOS}` (dashboard). `fetchInventory`/`inventoryRefreshInterval` still unenforced |
| `healthScorecard.*` | features | `healthScorecard.*` + NEW `metrics[].minimumOSVersions` | **ENFORCED**: `enabled` (dashboard section), `metrics[id=checkedIn].checkedInDays` (scorecard + device health panel), `metrics[].thresholds` schema DEFAULTS now drive all health color banding via one shared helper (Dashboard previously used 90/70, now 80/50 everywhere); per-metric threshold OVERRIDES from the profile are not yet consulted (no banded surface is metric-scoped today), `metrics[id=softwareUpdateCompliance].minimumOSVersions` (fixes drifted macOS baseline: scorecard said 15, drill-down said 26; both now default 26). Per-metric `enabled`/`displayName`/`platforms` still unenforced (schema metric ids don't match the implemented scorecard set) |
| `deviceHealth.*` | features | `deviceHealth.*` (unchanged) | Parsed, **NOT yet enforced** in views |
| `reports.*` | features | `reports.*` (unchanged) | **ENFORCED**: `enabled` hides the Reports module (sidebar). `availableReports` still unenforced — ReportsView is a filter-builder, not the schema's canned-report catalog; reconciling that model is future work |
| `deviceActions.computer.*` (18 bools) | **access** | **`deviceActions.computer.actions`** — array of `{id, enabled, displayName}` (SHAPE CHANGED; legacy boolean map still DECODED by the app, delivered keys only) | **ENFORCED** — DeviceView actionsMenu + executeAction (strict fail-closed allow-list) |
| `deviceActions.mobileDevice.*` (13 bools) | **access** | **`deviceActions.mobileDevice.actions`** — same array shape | Parsed + policy exposed (`mobileDeviceActionPolicy`) — no mobile actions menu exists yet |
| — (schema hygiene, 2.1) | **access** | `deviceActions.computer` / `.mobileDevice` now set `additionalProperties: false` | The legacy flat boolean keys (`computer.restart=true`, etc.) are still DECODED by the app when no `actions` array is delivered — that Swift-level fallback is unchanged — but this schema no longer declares them, so Jamf's schema-driven editor won't show or let you add them. Already-deployed pre-2.1 profiles keep working; delete any leftover flat keys from an instance's stored data via Jamf's "Add/Remove properties" once its `actions` array is populated |
| `deviceActions.computer.wipe` (bool) | **access** | `deviceActions.computer.actions[id=wipe]` | **ENFORCED — now IMPLEMENTED**: bare `ERASE_DEVICE` (recovery PIN, typed ERASE confirmation), MANDATORY acknowledgment wait, Jamf record and Entra object kept; schema default **disabled** |
| — (NEW in 2.1) | **access** | `deviceActions.computer.actions[id=returnToService].options.deleteJamfRecord` / `.deleteEntraObject` | **ENFORCED** — per-step cleanup toggles for Return to Service; defaults **true/true** preserve the original full-decommission behavior for already-deployed profiles; `deleteEntraObject` auto-skips when Entra isn't configured; NO cleanup step runs unless the erase is acknowledged |
| — (NEW in 2.1) | core | `jamfPro.eraseAckTimeoutSeconds` / `jamfPro.eraseAckPollIntervalSeconds` | **ENFORCED** — EVERY erase (Erase Device / Return to Service) waits for the `ERASE_DEVICE` acknowledgment (defaults 180 s timeout / 15 s poll interval; clamped 30–1800 / 5–120) |
| — (NEW in core 2.3) | core | `signIn.*` — interactive sign-in (method + public-client Entra settings) | **ENFORCED** — login flow + access-tier resolution; see the *Interactive sign-in* section below for the per-key table and fail-closed rules |
| — (NEW in access 2.3) | **access** | `deviceActions.*.actions[].requiredTier` — per-action minimum user tier (`Admin` / `Operator`) | **ENFORCED** — DeviceView actionsMenu + executeAction, active ONLY when `signIn.method=entra`; omitted = the action's built-in tier; unknown values fail closed to **Admin**; see the *User-tier gating* section below |
| `userInterface.supportURL` | ui | `userInterface.supportURL` | **ENFORCED** — LoginView |
| `userInterface.appTitle` / `appSubtitle` | ui | same keys (`appSubtitle` default now `"Console"`) | **ENFORCED** — all brand surfaces via the Branding helper (empty appSubtitle hides the badge) |
| `userInterface.companyName` / `logoURL` / `accentColor` / `defaultColorScheme` / `showEnrollments` / `showAnnouncements` / `showSettings` | ui | same keys + NEW `tagline` / `footerText` / `documentationURL` / `feedbackURL` | **ENFORCED** — Branding helper feeds every brand surface: appTitle/appSubtitle (login, welcome, sidebar, biometric prompt, menu bar, About, PDF footer, export filenames, logout/biometric copy), accentColor (brand gradients derive from it when delivered; built-in blue→cyan otherwise), logoURL (BrandMark replaces the built-in sun tile), companyName (fallback = product name), defaultColorScheme (seeds first-launch appearance; user's own choice wins thereafter), show* switches (sidebar). supportURL placeholder fallback removed — absent key hides the login help link and About row. documentationURL/feedbackURL wire the previously dead About links + welcome Learn More |
| `SidebarItems` (top-level, PascalCase) | ui | **`sidebarItems`** (RENAMED — camelCase) | **ENFORCED** — SidebarView renders from the configured list (presence/order/label/icon; ids must be route ids: dashboard, devices, announcements, logs, reports, enrollments, settings; unknown ids skipped; Cleanup stays role-gated; Settings pinned + gated by `showSettings`). Built-in default list fixed — it referenced routes (enterprise/groundcontrol/depsearch) that never existed |
| `authentication.*` | ui | `authentication.*` (unchanged) | **ENFORCED** (as of the Entra sign-in PR — previously parsed only) — `requireBiometric`, `allowBiometricSetup`, `sessionTimeout`, and `allowRememberMe` are enforced by the sign-in/session layer. Keys, types, and defaults unchanged |
| `role` (top-level) | **access** | `role` — **default `"Admin"` DROPPED**; no default, fail-closed | **ENFORCED** — Cleanup gate (SidebarView / SettingsView) |
| `cleanup.staleDays` | access | `cleanup.staleDays` (default now **90**; Int or String accepted) | **ENFORCED as a default** — CleanupSettings / CleanupDashboardView; an in-app edit stores a local override that wins (§4 step 6) |
| `cleanup.defaultStaticGroupID` / `defaultSiteID` | access | same keys (strings; parsed to Int downstream) | **ENFORCED** — CleanupSettings / CleanupDashboardView |
| `jamfProtect.enabled` | core | `jamfProtect.enabled` (default now **false**) | **ENFORCED as a default** — CleanupSettings / ReportsView; in-app edits override locally (§4 step 6) |
| `jamfProtect.url` / `clientID` | core | same keys | **ENFORCED as a default** — CleanupSettings / ReportsView; in-app edits override locally (§4 step 6) |
| `jamfProtect.password` | **credentials** | `jamfProtectPassword` (moved + renamed, flat key) | **ENFORCED** — two-tier chain (see §5) |
| `entra.*` (credentialDomain, tenantIdKey, clientIdKey, clientSecretKey, certPEMKey) | core | `entra.*` (VERBATIM — pointer semantics unchanged) | **ENFORCED** — EntraGraphService / Return to Service |

### Defaults deliberately changed (v1 schema → v2 schemas)

| Key | Old default | New default |
|---|---|---|
| `jamfPro.screenShareEnabled` | `true` | `false` (absent key means disabled) |
| `appleBusinessManager.enabled` | `true` | `false` (absent key means disabled) |
| `jamfProtect.enabled` | `true` | `false` (absent key means disabled) |
| `role` | `"Admin"` | **no default** — missing/blank/typo → `User`, Cleanup hidden (fail-closed) |
| `cleanup.staleDays` | `30` | `90` |
| `deviceActions` (whole block) | absent → per-key defaults (routine actions on) | **absent → Actions menu HIDDEN** — strict fail-closed allow-list; only listed ids with `enabled=true` appear. New ids: `restartSilent`, `returnToService`, `screenShare`, `unlockUserAccount`. Legacy boolean-map profiles: delivered keys are honored, undelivered keys are NO LONGER defaulted on |
| `jamfPro.screenShareEnabled` (core) | gate for the Screen Share menu item | **DEPRECATED** — the access `deviceActions` allow-list is authoritative for `screenShare`; the core key is ignored and will be removed in a later major |
| `jamfPro.connectionTimeout` / `requestTimeout` (core) | parsed, ignored (every call site hard-coded its own literal) | **ENFORCED** — all URLRequest/URLSession sites read them via NetworkTuning (quick calls → connectionTimeout, heavy/session-level → requestTimeout) |
| `jamfPro.requiredRoleName` default | `SVC_WATCHER_USER` (a real org's role name) | **`HeliosConsoleAPIRole`** (neutral) — deliver your org's actual API Role name in the profile; orgs relying on the old baked-in default must now set the key |
| `jamfPro.vpnIPExtensionAttributeName` (core, NEW) | EA name `EA_VPN_IP_ADDRESS` hard-coded in DeviceView | **ENFORCED** — Screen Share + IP card read the configured EA name; **absent/empty = VPN-IP lookup disabled (LAN IP only)**. Fleets that used the old hard-coded EA must add the key |
| `jamfPro.userCredentialLifetimeDays` (core, NEW) | 90 hard-coded | **ENFORCED** — per-user Jamf API credential expiry (default 90, clamped 1–365) |
| `appleBusinessManager.serviceType` (core, NEW) | ABM host hard-coded | **ENFORCED** — `business` (api-business.apple.com, default) or `school` (api-school.apple.com) for Apple School Manager orgs |
| `entra.cloudInstance` (core, NEW) | global Azure endpoints hard-coded | **ENFORCED** — `global` (default) / `usgov` (GCC High) / `china` (21Vianet) select the token authority + Graph hosts |
| `actionLog.retentionDays` / `maxEntries` (features, NEW) | audit log grew without bound | **ENFORCED** — pruned at launch and on every new entry (defaults 365 days / 10 000 entries; 0 = unlimited) |
| announcements domain behavior keys | only the `Announcements` array was read | **ENFORCED** — `announcementsEnabled` (master switch), `refreshInterval` (minutes; 0 = manual-only; was hard-coded 5 min), `allowLocalFile` (local JSON source now OFF by default per schema), `allowUserDismiss`, `showUnreadBadge` |
| `userInterface.appSubtitle` | `"Console - Admin"` | `"Console"` |
| `configurationVersion` | `"1.0"` | `"2.0"` |
| Return to Service — Entra cleanup on acknowledgment timeout | Entra device delete ran even when the erase acknowledgment timed out | **BEHAVIOR CHANGE (deliberate)** — NO cleanup step (Jamf record delete OR Entra delete) runs unless the device acknowledges the erase; a timeout stops the flow before cleanup |

If your old profile relied on an *absent* `screenShareEnabled`, `appleBusinessManager.enabled`,
or `jamfProtect.enabled` resolving to `true`, you must now deliver the key explicitly.

### Interactive sign-in (`signIn` block — NEW in core 2.3)

The core domain now configures **how users sign into Helios itself**. This is separate from
the `entra` cleanup pointer (app-only Graph credentials for Return to Service): `signIn.entra`
targets a **separate PUBLIC-client Entra app registration** — a public client has no client
secret, so no secret exists for it anywhere, by design. An absent `signIn` block (or
`method=email`) keeps the built-in email flow **unchanged** — existing deployments need no
profile change.

| Key | Type | Default | Enforced where |
|---|---|---|---|
| `signIn.method` | string enum `email` / `entra` (case-insensitive) | `email` | Login flow — `entra` replaces the email form with Entra ID sign-in |
| `signIn.entra.tenantId` | string (GUID) | — (required for Entra sign-in) | EntraAuthService — interactive token requests |
| `signIn.entra.clientId` | string (GUID; public client, never paired with a secret) | — (required for Entra sign-in) | EntraAuthService — interactive token requests |
| `signIn.entra.cloudInstance` | string enum `global` / `usgov` / `china` | `global` | EntraAuthService — token authority host (same mapping as `entra.cloudInstance`) |
| `signIn.entra.adminRoles` | array of strings (app-role values, roles claim) | `["Helios.Admin"]` | Access-tier resolution after sign-in — grants the **admin** tier |
| `signIn.entra.operatorRoles` | array of strings | `["Helios.Operator"]` | Access-tier resolution after sign-in — grants the **operator** tier |
| `signIn.entra.cleanupRoles` | array of strings (app-role values) | `[]` = admins only | Cleanup gate — listed roles grant the Cleanup module **in addition to** admin-tier users; grants **no** device-action tier (a cleanup-only user signs in at tier `None`); the Mac still needs access `role=Admin` |
| `signIn.entra.allowedGroupIds` | array of strings (group object ids) | `[]` = no group check | Optional extra client-side membership check via the token's groups claim |
| `signIn.entra.provisionJamfCredentials` | boolean | `true` | Per-user Jamf API client provisioning from the verified email after Entra sign-in |

**Fail-closed rules (deliberate — mirror the access domain's `role` gate):**

- `method=entra` with a missing/blank `tenantId` or `clientId` → sign-in is **blocked with a
  configuration-error state**. The app **never falls back to the email flow** — a
  misconfigured profile must not silently downgrade to the weaker sign-in path. (In code:
  `signInMethod` stays `.entra` while `isEntraSignInConfigured` is `false`.)
- A token carrying **none** of the admin, operator, or cleanup role values → **no access**.
  Roles absent means denied, never defaulted up. (A cleanup-only match is a valid sign-in
  at tier `None` — Cleanup plus read surfaces, nothing tier-gated.)
- A **delivered empty** `adminRoles` / `operatorRoles` array is honored verbatim: it grants
  that tier to no one. Only an *absent* key receives the documented default; entries are
  trimmed and empty strings dropped. `cleanupRoles` defaults to `[]` either way — absent or
  delivered-empty, it grants nothing beyond admins.
- Enforce the restriction **Entra-side too**: enable *Assignment required* on the enterprise
  application and assign only the intended users/groups — the client-side checks here are a
  UX gate, not a security boundary on their own.
- Prefer app roles over `allowedGroupIds`: the groups claim is subject to Entra's overage
  limit and can arrive **empty** for users in many groups, which the group check then fails.
  The roles claim is never subject to overage.

### User-tier gating (Entra sign-in — access 2.3)

When Entra sign-in is active (`signIn.method=entra` in the core domain), feature and
device-action gating becomes **two independent layers**. Both must allow — a fail-closed
intersection; neither layer can expand what the other denies:

| Layer | Scope | Source | Gates |
|---|---|---|---|
| 1 (existing) | **Machine** — which Mac the operator sits at | access domain `role` + `deviceActions` allow-list (+ features `enableAPIActions` kill switch) | Cleanup visibility; which action ids exist in the Actions menu at all |
| 2 (new) | **User** — who is signed in | User access tier resolved from the Entra token's roles claim (`signIn.entra.adminRoles` / `operatorRoles`) | Per-action minimum tier; Cleanup requires the **admin** tier or a `signIn.entra.cleanupRoles` role |

In **email sign-in mode layer 2 is inert** — every tier check passes and behavior is
byte-for-byte identical to pre-tier builds. Existing deployments that never deliver
`signIn` need no profile change and see no difference. In entra mode a user whose token
grants **no** tier (`None`) passes no tier check — nothing tier-gated shows. That state
is reachable only by a **cleanup-only** user (a token matching `cleanupRoles` but no tier
list): they see the Cleanup module and read surfaces, zero tier-gated device actions —
fail-closed by construction. Tokens matching no configured role at all are refused at
sign-in.

**Built-in per-action tiers** (the defaults when an entry omits `requiredTier`):

| Action id | Default tier | Why |
|---|---|---|
| `sendBlankPush` | Operator | Purely informational APNs check-in nudge |
| `enableBluetooth` | Operator | Peripheral-connectivity toggle; no data/security impact |
| `disableBluetooth` | Operator | Same — disruptive at most (disconnects peripherals) |
| `enableRemoteDesktop` | Admin | Opens remote access — security-state change |
| `disableRemoteDesktop` | Admin | Alters the same remote-access posture, kills active sessions; in-doubt cases resolve upward |
| `screenShare` | Admin | Opens an interactive screen-control session of the device |
| `restart` | Admin | Forced interruption; unsaved-work loss |
| `restartSilent` | Admin | Same, without even warning the user |
| `shutdown` | Admin | Takes the device offline until someone has physical access |
| `wipe` | Admin | Permanently destroys all data |
| `returnToService` | Admin | Destroys all data and deletes management records |
| `viewLocalAdminPassword` | Admin | Discloses the LAPS admin credential |
| `viewFileVaultKey` | Admin | Discloses the disk-encryption recovery key |
| `unlockUserAccount` | Admin | Changes account security state |

(Reserved ids — `lock`, `updateInventory`, `viewRecoveryLockPassword`, `renewMDMProfile`,
`sendCustomCommand`, `installPackage`, `runPolicy` — render nothing regardless of tier.)

**`requiredTier` override semantics + fail-closed rules (deliberate):**

- Each `deviceActions.*.actions[]` entry accepts an optional `requiredTier`
  (`"Admin"` / `"Operator"`) that **overrides** the built-in tier for that action —
  in either direction (you may open `restart` to operators, or lock `sendBlankPush`
  to admins).
- **Unknown value → Admin.** Anything other than exactly `"Admin"` or `"Operator"` —
  a typo, wrong case, or `"None"` — resolves to **Admin** (fail-closed **upward**:
  a malformed value must restrict, never expand; `"None"` is rejected precisely
  because it would pass every tier check).
- **Email mode → tier layer inert.** `requiredTier` keys are ignored entirely when
  `signIn.method` is not `entra`.
- **Cleanup is gated by a role set, not `requiredTier`** — it is not a device action
  and no `requiredTier` key touches it. Under entra sign-in Cleanup shows only for
  machine `role=Admin` **and** a user who either holds the admin tier (admin roles
  always qualify) or carries an app role listed in the core domain's
  `signIn.entra.cleanupRoles` (default empty = admins only). Email mode is unchanged —
  machine `role=Admin` alone decides.
- The machine allow-list stays authoritative for **existence**: an action that is not
  granted (or is `enabled=false`) in layer 1 stays hidden and blocked no matter what
  tier the user holds.

**Revocation:** the tier is resolved from the token at sign-in. Removing a user's Entra
app-role assignment (or the whole assignment) takes effect at the user's **next launch /
sign-in and at the next idle-lock unlock** (both redeem the refresh token and re-derive
the tier from the fresh token) — an actively-used session is not re-evaluated mid-flight.
For immediate lockout, disable the user or revoke sessions in Entra and enforce
*Assignment required* on the enterprise application.

---

## 3. Jamf Pro deployment steps

Create **five** configuration profiles, one per domain. For each:

1. **Jamf Pro → Configuration Profiles → New**.
2. Add an **Application & Custom Settings → External Applications** payload, source
   **Custom Schema**.
3. Set **Preference Domain** to the exact domain string from the table in §1
   (e.g. `com.herojoneslabs.helios.console.core` — a typo here silently delivers nothing).
4. Paste the matching schema file from `schemas/` (e.g. `Helios_Core_SCHEMA.json`) into the
   Custom Schema editor and fill in the values. Replace every `REPLACE-WITH-…` placeholder
   with the real value **in Jamf** — never commit real values to the repo.
5. Scope per the matrix below.

### Scoping matrix

| Profile (domain) | Scope |
|---|---|
| `com.herojoneslabs.helios.console.core` | All managed Macs running Helios |
| `com.herojoneslabs.helios.console.credentials` | All managed Macs running Helios — per variant (see paired-scoping rule) |
| `com.herojoneslabs.helios.console.access` | **Admin Macs only** |
| `com.herojoneslabs.helios.console.features` | All managed Macs running Helios |
| `com.herojoneslabs.helios.console.ui` | All managed Macs running Helios |

### Paired-scoping rule (access ⟷ credentials)

The `role` string is a UI gate; the API client's permissions are the real boundary. Keep
them aligned:

- A **write-capable variant** of the credentials profile (one whose `jamfProClientSecret`
  belongs to an API role with write/destructive permissions) and the access profile
  granting `role=Admin` **must be scoped to the same Macs**.
- Never deliver write-capable credentials to a Mac without the matching Admin access
  profile, and never grant `role=Admin` to Macs carrying only read-only credentials.
- Non-admin Macs get a credentials variant whose secret belongs to a **read-only** API
  role, and **no access profile at all** (fail-closed → `role=User`, Cleanup hidden).

### Security notes

- Managed-preference plists are written **world-readable** to
  `/Library/Managed Preferences/<domain>.plist` — any local user or process can read them.
  Scope the credentials profile tightly, use least-privilege API roles, and rotate
  immediately on suspected exposure. Rotating a secret = edit + re-push the one small
  credentials profile; core/features/ui/access are untouched.
- The access profile is **fail-closed**: a Mac that never receives it runs as `role=User`
  with the default device-action set and Cleanup hidden. Under-scoping is safe;
  over-scoping is not.

### Relaunch required

Helios reads the domains at launch and on explicit reload; there are **no live profile
observers**. After pushing or changing any of the five profiles, **relaunch the app**
(both the main app and the menu bar app) for the new values to take effect.

---

## 4. Verification checklist (multi-profile)

Run on a test Mac after deploying the five profiles:

1. **Profiles landed** — confirm all five plists exist:
   ```sh
   ls /Library/Managed\ Preferences/com.herojoneslabs.helios.console.{core,credentials,access,features,ui}.plist
   ```
   (The access plist exists only on admin-scoped Macs — that is correct.)
2. **Domain values readable** — spot-check each domain the way the app reads it:
   ```sh
   defaults read com.herojoneslabs.helios.console.core jamfPro
   defaults read com.herojoneslabs.helios.console.credentials jamfProClientSecret
   defaults read com.herojoneslabs.helios.console.access role
   ```
3. **App configured** — launch Helios; the login flow reaches Jamf (no "not configured"
   state). If unconfigured, check the app log: it names the **missing domain**.
4. **Partial-delivery check** — temporarily unscope ONLY the credentials profile, relaunch:
   the app must report unconfigured and log that credentials are missing (core alone is
   not enough). Re-scope afterwards.
5. **Role gate** — on an admin Mac (`role=Admin`): the **Cleanup** sidebar item appears.
   On a Mac without the access profile (or `role=Support`): Cleanup is **hidden**.
6. **Managed vs. overridable fields** — a delivered `jamfProtectPassword` locks the in-app
   Protect password field (the **only** field that locks). The connection/credential values
   (`jamfPro.*`, `jamfProClientSecret`, `entra.*`) have no editable in-app fields and are
   profile-only. The Cleanup tunables (`cleanup.staleDays`, `jamfProtect.enabled`/`url`/
   `clientID`) are MDM **defaults**: an in-app Settings edit stores a local override
   (`Cleanup.StaleDays` etc. in `com.herojoneslabs.helios.console`) that silently **wins over the
   profile** until cleared with `defaults delete com.herojoneslabs.helios.console <key>`.
7. **Version EA** — `sudo jamf recon` → the *Helios Console Version* EA populates.
8. **Relaunch behavior** — change a value in one profile (e.g. `cleanup.staleDays`),
   re-push, relaunch the app, confirm the new value; confirm it did NOT change while the
   app stayed running. If you use `cleanup.staleDays` (or any other locally overridable
   Cleanup tunable — see step 6), **first clear any local override** or the profile value
   will never surface: `defaults delete com.herojoneslabs.helios.console Cleanup.StaleDays` (likewise
   `Cleanup.ProtectEnabled` / `Cleanup.ProtectURL` / `Cleanup.ProtectClientID`).
9. **(Admin)** Against a **test** Jamf instance, exercise a safe Cleanup action
   (move-to-site) on a throwaway record before trusting the delete path.

---

## 5. Jamf Protect password — two-tier rule

The Protect API password **MAY** be delivered via the credentials domain
(`jamfProtectPassword` in `com.herojoneslabs.helios.console.credentials`):

- **Delivered in the profile** → that value is used and the in-app password field locks.
- **Omitted** → the app falls back to in-app entry, storing the value in the Keychain item
  `com.herojoneslabs.helios.console.protect.password`.

Both tiers are supported; delivery is the admin's choice. (Older docs claimed the password
was "never delivered in the profile" — that was wrong; this section is the truth.)

---

## 6. Developer / unmanaged configuration

The loader reads each domain via `UserDefaults(suiteName:)`, which surfaces **both**
`/Library/Managed Preferences/<domain>.plist` (forced, wins) **and**
`~/Library/Preferences/<domain>.plist`. So on a dev Mac, plain `defaults write` against the
**suite domains** is the supported dev story — no profile needed:

```sh
defaults write com.herojoneslabs.helios.console.core jamfPro -dict \
  serverURL "https://yourorg.jamfcloud.com" masterClientID "REPLACE-WITH-MASTER-CLIENT-ID"
defaults write com.herojoneslabs.helios.console.credentials jamfProClientSecret "REPLACE-WITH-jamf-pro-client-secret"
defaults write com.herojoneslabs.helios.console.access role Admin
```

Notes:

- The app **no longer seeds placeholder values** at launch (the old
  `setupDevelopmentConfiguration()` is gone), and `MDMConfiguration.default` uses empty
  strings — an unconfigured dev Mac is genuinely unconfigured.
- In DEBUG builds only, an absent access profile defaults to `role=Admin` so Cleanup stays
  visible during development; RELEASE builds fail closed to `User`.
- Writing to `com.herojoneslabs.helios.console` (the bundle id) does nothing for managed config anymore.

## 7. Uninstall residue

`Deployment/OnDevice/Scripts/uninstall_helios_console.sh` removes the apps, receipts, and
the `com.herojoneslabs.helios.console` / `com.herojoneslabs.helios.console.menubar` local prefs. Two things it does
not cover:

- **Managed profiles** — unscope/remove all five configuration profiles in Jamf (the
  script never touches profiles).
- **Dev-written suite plists** — if anyone used the §6 dev story on that Mac, user-level
  `~/Library/Preferences/com.herojoneslabs.helios.console.{core,credentials,access,features,ui}.plist`
  files may remain. Remove with `defaults delete <domain>` per domain. The credentials
  domain especially should be deleted, since it can contain a real secret in a
  world-readable-by-that-user file.

## 8. Rollback

This is a **hard cutover**: 2.x binaries only read the five new domains, and 1.x binaries
only read the old `com.helios.console` monolith (1.x predates the bundle-ID rebrand, so a
rolled-back binary literally reads that old string — do not "modernize" it). Rolling back
therefore means rolling back **both** the app and the profiles together:

1. Redeploy the previous app package (pre-`feature/config-domain-split` build).
2. Re-scope the old single `com.helios.console` profile (the old schema,
   `Deployment/HeliosConsole_SCHEMA.json`, was deleted on this branch but is available in
   git history / the PR).
3. Optionally unscope the five new profiles (a 1.x app ignores them; they are inert).

There is no mixed mode — do not try to run a 2.x app against the old profile or vice
versa.

---

## 9. Bundle-ID rebrand (`com.helios.console` → `com.herojoneslabs.helios.console`)

On the same branch as the domain split, every app identifier was rebranded: the main app
bundle id is now `com.herojoneslabs.helios.console`, the menu bar app is
`com.herojoneslabs.helios.console.menubar`, and **all derived identifiers follow** — the
five managed-config domains in §1, the announcements domain, the deep-link notification
name, the IPC suite, logger subsystems, and the Protect Keychain item. Product, app, and
target names ("Helios Console", `HeliosConsole`, scheme names, file names) are
**unchanged**, as are all key names *inside* the domains (including the `helios.*` and
`Cleanup.*` UserDefaults keys) — this is an identifier-prefix rebrand, not an app rename.

Operational fallout an admin must plan for:

- **Local UserDefaults reset on first launch.** `UserDefaults.standard` is keyed by bundle
  id, so the rebranded app starts with a fresh local domain
  (`com.herojoneslabs.helios.console`). Everything the old app stored under
  `com.helios.console` is orphaned, not migrated: the `Cleanup.*` local overrides
  (`Cleanup.StaleDays`, `Cleanup.ProtectEnabled`, `Cleanup.ProtectURL`,
  `Cleanup.ProtectClientID`, `Cleanup.ProtectAutoCleanup`), the `helios.*` in-app
  preferences (`helios.appearanceMode`, etc.), and the welcome/first-run flags
  (`hasSeenWelcome`) all reset — users see the welcome flow again, and profile-delivered
  Cleanup defaults apply until someone edits them in-app. Side benefit: any stale
  `Cleanup.*` override that was silently masking a profile value (§4 step 6) is cleared.
- **Jamf Protect password must be re-entered once** (if it was entered in-app). The app now
  reads/writes the Keychain item `com.herojoneslabs.helios.console.protect.password`; the
  old `com.helios.protect.password` item is ignored (and left behind). Alternatives: deliver
  the password via the credentials profile (`jamfProtectPassword`, §5) and no one has to
  touch a keyboard, or have each admin re-enter it once in Settings.
- **Users must sign in again once.** The five auth/Jamf Keychain accounts were rebranded
  the same way (`com.helios.authToken` / `.refreshToken` / `.userEmail` / `.userName` /
  `.jamfCredentials` → `com.herojoneslabs.helios.console.authToken` / `.refreshToken` /
  `.userEmail` / `.userName` / `.jamfCredentials`). Items under the old names are orphaned,
  not migrated, so the rebranded app starts signed out and users re-authenticate once
  (same accepted behavior as the Protect password above). The uninstall script removes
  both the new and the old spellings of all six Keychain items.
- **Announcements profile must be re-created in Jamf** under the new domain
  `com.herojoneslabs.helios.console.announcements` (same schema,
  `schemas/Helios_Announcements_SCHEMA.json`, same keys). A profile still targeting
  `com.helios.console.announcements` delivers nothing to the rebranded app.
- **The five §1 profiles must target the new domain strings.** If any split-domain profile
  was created before the rebrand under a `com.helios.console.*` domain, edit or re-create
  it with the `com.herojoneslabs.helios.console.*` domain — the old spelling silently
  delivers nothing.
- **Anything in Jamf keyed on the old bundle id needs updating:** Smart Groups that match
  on bundle id / application title criteria, PPPC (Privacy Preferences) profiles whose
  Identifier is `com.helios.console`, restricted-software rules, and notarization/signing
  automation that references the bundle id. Re-notarize under the new bundle id if you
  distribute outside Jamf policy installs.
- **Installing over the old app shunts the payload aside (fixed in pkgs ≥ 1.0-d.23).**
  PackageKit refuses to replace a bundle whose `CFBundleIdentifier` differs from the
  package's, so on a Mac that still has the pre-rebrand app at
  `/Applications/HeliosConsole.app`, the installer quietly lands the new app in
  `/Applications/HeliosConsole.localized/HeliosConsole.app` — a folder Finder displays
  as just "HeliosConsole", leaving the old app launchable and looking like the update
  never happened. Pkgs built from `build-pkg.sh` ≥ d.23 carry a preinstall script that
  removes the mismatched old app (and any `.localized` shunt) first, and pin the payload
  non-relocatable. If a Mac was hit by an older pkg, clean it up with:
  `sudo rm -rf /Applications/HeliosConsole.app "/Applications/HeliosConsole.localized"`
  then reinstall.
- **The installer pkg identifier follows automatically** — `Deployment/build-pkg.sh`
  derives the pkg identifier from the project's bundle id, so newly built pkgs are correct
  with no script changes. Note the rebranded pkg does not "upgrade" the old receipt: old
  `com.helios.console`-era receipts remain until the uninstall script (which knows the
  current ids) or manual cleanup removes them.
- **Deployed Entra pointer domains can be reused as-is.** The `entra.credentialDomain`
  value in the core profile is **admin-chosen**; `com.herojoneslabs.helios.console.entra`
  in the schema descriptions is only an *example*. If your Graph credentials plist is
  already deployed under any domain (including the old example
  `com.helios.console.entra`), keep it — just make sure `entra.credentialDomain` still
  points at whatever domain you actually deployed. No re-deployment is required.

---

*Sync points: the five domain strings above must match each model's `static let domain`
(`HeliosConsole/Managers/Configuration/*.swift`), each schema's `$id` (`schemas/*.json`),
and this guide.*
