# Helios Console — Managed Configuration Migration (v1 monolith → v2 domain split)

**Date:** 2026-07-10 · **Branch:** `feature/config-domain-split` · **Cutover:** HARD (no fallback)

> **Updated 2026-07-16 (`feature/entra-auth`, schemas: core **2.4**, access **2.6**, ui **2.2**):** access control was reworked
> from fixed tiers to **admin-defined role capability sets**. Nothing about access is
> hardcoded in the app any more. `signIn.entra.adminRoles`/`operatorRoles`/`cleanupRoles`
> and `deviceActions.*.actions[].requiredTier` are **removed**; the access domain's new
> `roles` block is the sole source of capability, and the access profile's **scope changes
> from admin Macs to all Macs**. This is another HARD cutover — see
> *Role-capability model* and *BREAKING: migrating from the 2.3 tier model* in §2.
>
> **Sidebar order moved to the access domain (access 2.6, ui 2.2).** `ui.sidebarItems[].order`
> is **REMOVED**: a role's **`modules` array order IS its sidebar order** (first = topmost), so
> enabling a module and placing it are one edit in one place, and each role orders its own
> rows. `ui.sidebarItems` now carries **presence (`isEnabled`), label, and icon only** — its
> own list position means nothing. A profile still delivering `order` decodes fine and the key
> is **IGNORED**; the app logs once:
> `⚠️ ui.sidebarItems: 'order' is ignored — sidebar order now comes from each role's modules list order (access domain).`
> See *Sidebar order (access 2.6 / ui 2.2)* in §2.

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
> (`schemas/Helios_Entra_Credentials_SCHEMA.json`) keep the same
> schemas and semantics. Note that the **bundle-ID rebrand (§9)** *did* rename the
> announcements domain string — the Jamf announcements profile must be **re-created under
> the new domain** — whereas already-deployed Entra pointer domains can be reused as-is.

---

## 1. The five domains

| # | Preference domain | Tier | Schema file | Scope |
|---|---|---|---|---|
| 1 | `com.herojoneslabs.helios.console.core` | Connection & integrations (no secrets) | `schemas/Helios_Core_SCHEMA.json` | **All managed Macs** running Helios |
| 2 | `com.herojoneslabs.helios.console.credentials` | Secrets only (rotate independently) | `schemas/Helios_Credentials_SCHEMA.json` | **All managed Macs** running Helios (per credential variant) |
| 3 | `com.herojoneslabs.helios.console.access` | Role capabilities & destructive capability | `schemas/Helios_Access_SCHEMA.json` | **All managed Macs** running Helios — **CHANGED in 2.4** (was admin Macs only); per-population variants differ by `role` / `deviceActions` |
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
| `localAdministration.enabled` | core → **features** (MOVED) | **`features.localAdministration.enabled`** (default true) | Parsed — no view consumes the flag today (only `username` is used) |
| `localAdministration.username` | core → **features** (MOVED) | **`features.localAdministration.username`** (default `macadmin`) | **ENFORCED** — LAPS lookup, DeviceView. **The transitional core fallback has been REMOVED** (schemas 3.0): a core profile still delivering `localAdministration` is now IGNORED and the username falls back to `macadmin`. Deliver it in **features** |
| `computers.*` | features | `computers.*` (unchanged) | **ENFORCED**: `enabled` (unified search), `enableAPIActions` (DeviceActionPolicy), `inventorySections` (inventory fetch; default now matches the sections views render), `showDashboardCard` (dashboard), `showDeviceHistory` (device History section — Policy Logs + MDM command history via Classic `computerhistory`; **default off**), `historyPageSize` (rows per page in the History section; default 25, min 1). `fetchInventory`/`inventoryRefreshInterval` still unenforced (no scheduler exists) |
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
| — (NEW in core 2.3) | core | `signIn.*` — interactive sign-in (method + public-client Entra settings) | **ENFORCED** — login flow + **identity only**; see the *Interactive sign-in* section below for the per-key table and fail-closed rules |
| — (NEW in access **2.4**; **array in 2.5**) | **access** | **`roles`** — array of admin-named capability-set objects, each with a `name` (`modules`, `computerActions`, `mobileDeviceActions`, `cleanupActions`, `allowExport`) | **ENFORCED** — the sole source of every user capability; see the *Role-capability model* section below |
| — (**access 2.6**) | **access** | `roles[].modules` — **array order is now SIGNIFICANT** | **ENFORCED** — a role's `modules` array order IS its sidebar order (first = topmost). No key or profile change is required: an existing `modules` list keeps working and simply renders in the order it is already written. Reorder the array to reorder that role's sidebar; see *Sidebar order (access 2.6 / ui 2.2)* below |
| — (access 2.3, **REMOVED in 2.4**) | **access** | ~~`deviceActions.*.actions[].requiredTier`~~ — **DELETED**, superseded by per-role action lists | **BREAKING** — the key is gone from the schema and ignored by the app. Move each action's grant into the `computerActions` / `mobileDeviceActions` list of every role that should have it |
| — (core 2.3, **REMOVED in 2.4**) | core | ~~`signIn.entra.adminRoles` / `operatorRoles` / `cleanupRoles`~~ — **DELETED**, role names are now the `roles` entries' `name` fields | **BREAKING** — the keys are gone from the schema and ignored. An Entra app-role **Value** is matched directly against a `roles` entry's `name` |
| `userInterface.supportURL` | ui | `userInterface.supportURL` | **ENFORCED** — LoginView |
| `userInterface.appTitle` / `appSubtitle` | ui | same keys (`appSubtitle` default now `"Console"`) | **ENFORCED** — all brand surfaces via the Branding helper (empty appSubtitle hides the badge) |
| `userInterface.companyName` / `logoURL` / `accentColor` / `defaultColorScheme` (`showAnnouncements` / `showSettings` MOVED to features — see their own row below) | ui | same keys + NEW `tagline` / `footerText` / `documentationURL` / `feedbackURL` | **ENFORCED** — Branding helper feeds every brand surface: appTitle/appSubtitle (login, welcome, sidebar, biometric prompt, menu bar, About, PDF footer, export filenames, logout/biometric copy), accentColor (brand gradients derive from it when delivered; built-in blue→cyan otherwise), logoURL (BrandMark replaces the built-in sun tile), companyName (fallback = product name), defaultColorScheme (seeds first-launch appearance; user's own choice wins thereafter), show* switches (sidebar). supportURL placeholder fallback removed — absent key hides the login help link and About row. documentationURL/feedbackURL wire the previously dead About links + welcome Learn More |
| `SidebarItems` (top-level, PascalCase) | ui | **`sidebarItems`** (RENAMED — camelCase) | **ENFORCED for presence/label/icon ONLY** — this list decides whether a row exists on this Mac (`isEnabled`) and what it looks like; ids must be route ids: dashboard, devices, announcements, logs, reports, cleanup, settings; unknown ids skipped; Cleanup stays role-gated; Settings pinned + gated by `showSettings`. **It does NOT control order** (see the `order` row below) and its own list position is meaningless. Built-in default list fixed — it referenced routes (enterprise/groundcontrol/depsearch) that never existed |
| `SidebarItems[].order` → `sidebarItems[].order` (**REMOVED in ui 2.2**) | ui | ~~`sidebarItems[].order`~~ — **DELETED**, superseded by each role's `modules` array order (access domain) | **BREAKING (cosmetic only — never fails a decode)** — the key is gone from the schema and IGNORED by the app; a profile still delivering it decodes fine (extra plist keys are ignored) and logs once: `⚠️ ui.sidebarItems: 'order' is ignored — sidebar order now comes from each role's modules list order (access domain).` Arrange each role's `modules` array instead — first id = topmost row |
| `authentication.*` | ui → **core** (MOVED) | **`core.authentication.*`** — same keys, types, and defaults | **ENFORCED** — `requireBiometric`, `allowBiometricSetup`, `sessionTimeout`, `allowRememberMe`, enforced by the sign-in/session layer. **The transitional ui fallback has been REMOVED** (schemas 3.0): a ui profile still delivering `authentication` is now IGNORED and the keys fall to their defaults. Deliver it in **core** |
| `role` (top-level) | **access** | `role` — **enum DROPPED in 2.4**: now a FREE-FORM string naming a `roles` entry's `name`; still no default, still fail-closed. Consulted **only** when Entra sign-in is not configured | **ENFORCED** — resolves the user's single role in MDM sign-in mode; ignored entirely when `signIn.method=entra` |
| `cleanup.staleDays` | access → **features** (MOVED) | **`features.cleanup.staleDays`** (default **90**; Int or String accepted) | **ENFORCED as a default** — CleanupSettings / CleanupDashboardView; an in-app edit stores a local override that wins (§4 step 6). **The transitional access fallback has been REMOVED** (schemas 3.0): an access profile still delivering `cleanup` is now IGNORED and the tunables fall to their defaults. Deliver them in **features** |
| `cleanup.defaultStaticGroupID` / `defaultSiteID` | access → **features** (MOVED) | **`features.cleanup.*`** — same keys (strings; parsed to Int downstream) | **ENFORCED** — CleanupSettings / CleanupDashboardView. Legacy access fallback REMOVED, as above. Which roles SEE the Cleanup module and which sub-actions they may run stay in **access** (`roles[].modules` / `roles[].cleanupActions`) — only the tunables moved |
| `userInterface.showAnnouncements` / `showSettings` | ui → **features** (MOVED) | **`features.userExperience.showAnnouncements` / `.showSettings`** — same types, default **true** | **ENFORCED** — SidebarView route gate, INTERSECTED with the role's module grant (they only hide an area a role already grants; they never reveal one it withholds). **The transitional ui fallback has been REMOVED** (schemas 3.0): ui copies are now IGNORED and both default to true. Deliver them in **features** |
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
| `jamfPro.vpnIPExtensionAttributeEnabled` / `…ID` (core, NEW) | `jamfPro.vpnIPExtensionAttributeName` matched the EA by name (itself replacing a hard-coded `EA_VPN_IP_ADDRESS`) | **ENFORCED** — the lookup is off unless `…Enabled=true`, and the EA is identified by its numeric `…ID` (stable across renames in Jamf; the name is not). Off = LAN IP only. **`…Name` is DEPRECATED but honored for one release**: if it is set and `…Enabled` is absent, the lookup stays on, so existing profiles keep working until re-pushed. An explicit `…Enabled=false` always wins. Migrate to the id — `…Name` is removed in the next major |
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

The core domain configures **how users sign into Helios itself** — **identity only**. It
decides *who the user is* and *which role names they carry*; it grants **no** capabilities.
What each role name can do lives entirely in the access domain's `roles` block (next
section). This is separate from the `entra` cleanup pointer (app-only Graph credentials for
Return to Service): `signIn.entra` targets a **separate PUBLIC-client Entra app
registration** — a public client has no client secret, so no secret exists for it anywhere,
by design. An absent `signIn` block (or `method=email`) keeps the built-in email flow, in
which case the access domain's `role` key names the user's role instead.

| Key | Type | Default | Enforced where |
|---|---|---|---|
| `signIn.method` | string enum `email` / `entra` (case-insensitive) | `email` | Login flow — `entra` replaces the email form with Entra ID sign-in |
| `signIn.entra.tenantId` | string (GUID) | — (required for Entra sign-in) | EntraAuthService — interactive token requests |
| `signIn.entra.clientId` | string (GUID; public client, never paired with a secret) | — (required for Entra sign-in) | EntraAuthService — interactive token requests |
| `signIn.entra.cloudInstance` | string enum `global` / `usgov` / `china` | `global` | EntraAuthService — token authority host (same mapping as `entra.cloudInstance`) |
| `signIn.entra.allowedGroupIds` | array of strings (group object ids) | `[]` = no group check | Optional extra client-side membership check via the token's groups claim |
| `signIn.entra.provisionJamfCredentials` | boolean | `true` | Per-user Jamf API client provisioning from the verified email after Entra sign-in |

**Fail-closed rules (deliberate — mirror the access domain's `role` gate):**

- `method=entra` with a missing/blank `tenantId` or `clientId` → sign-in is **blocked with a
  configuration-error state**. The app **never falls back to the email flow** — a
  misconfigured profile must not silently downgrade to the weaker sign-in path. (In code:
  `signInMethod` stays `.entra` while `isEntraSignInConfigured` is `false`.)
- A token whose `roles` claim matches **no entry `name`** in the access domain's `roles` array →
  **sign-in refused**. Roles absent means denied, never defaulted up. There is no built-in
  role name to fall back to.
- Enforce the restriction **Entra-side too**: enable *Assignment required* on the enterprise
  application and assign only the intended users/groups — the client-side checks here are a
  UX gate, not a security boundary on their own.
- Prefer app roles over `allowedGroupIds`: the groups claim is subject to Entra's overage
  limit and can arrive **empty** for users in many groups, which the group check then fails.
  The roles claim is never subject to overage.
- `allowedGroupIds` is a **sign-in** gate only — it never grants capabilities. Group
  membership maps to nothing; only role names do.

### Role-capability model (access 2.6 — REPLACES tier gating)

**Nothing about access is hardcoded in the app any more.** There are no built-in tiers, no
built-in role names, and no built-in capability defaults. The app reads the access domain's
`roles` block and renders exactly what it finds. Roles are **arbitrary, admin-named
capability sets**.

#### Identity precedence — where the role names come from

Resolved in this order; the first configured source wins outright (no merging across
sources):

1. **Entra sign-in** — core `signIn.method=entra`. The role names are the values in the ID
   token's `roles` claim. The access `role` key is **ignored entirely** in this mode.
2. **Access domain `role`** — when Entra sign-in is not configured. A single free-form
   string naming one `roles` entry's `name`. This is the machine-scoped identity: every user of
   that Mac holds that one role.
3. **User-level plist (dev/unmanaged only)** — the loader reads each domain via
   `UserDefaults(suiteName:)`, so standard CFPreferences precedence applies: the MDM-forced
   `/Library/Managed Preferences/<domain>.plist` **wins**, and a user-level
   `~/Library/Preferences/com.herojoneslabs.helios.console.access.plist` is consulted only
   where the managed profile delivers nothing. This is the §6 developer story, not a
   deployment mechanism — on a managed Mac the profile always wins.

#### The `roles` block

An **ARRAY of role objects**, each carrying its own name in `name`:

```
roles = (
  {
    name                = "<RoleName>";  // the role's name — REQUIRED
    modules             = [ ids ];   // sidebar / route ids
    computerActions     = [ ids ];   // DeviceAction ids, intersected with deviceActions
    mobileDeviceActions = [ ids ];   // same, mobile side
    cleanupActions      = [ ids ];   // cleanup sub-actions
    allowExport         = <bool>;    // every export surface (Reports, Cleanup, Logs)
  },
  // ...more role objects
)
```

> **Why an array and not a dictionary keyed by role name?** Role names are admin-chosen, so
> a dictionary can only be expressed in JSON Schema as `additionalProperties` — which
> **Jamf Pro's Application & Custom Settings form generator cannot render**, forcing admins
> to hand-edit profile XML. A list of objects renders as a form in the Jamf schema editor.
> Same idiom as `deviceActions.computer.actions` (`{id, enabled, displayName}`), which
> already renders there.

| Key | Type | Absent = | Valid ids |
|---|---|---|---|
| `name` | string | **entry SKIPPED** (see below) | **Admin-chosen.** Must equal an Entra app-role **Value** (Entra mode) or the `role` key (MDM mode), **exactly, case-sensitively** |
| `modules` | array of string | no modules | `dashboard`, `devices`, `myDevices`, `announcements`, `logs`, `reports`, `cleanup`, `settings` (the legacy spelling `myDevice` is accepted and treated as `myDevices` — see below). **Array order = sidebar order** — see *Sidebar order* below |
| `computerActions` | array of string | no computer actions | the `deviceActions.computer.actions[].id` set (`sendBlankPush`, `restart`, `restartSilent`, `shutdown`, `returnToService`, `enableRemoteDesktop`, `disableRemoteDesktop`, `enableBluetooth`, `disableBluetooth`, `viewFileVaultKey`, `viewLocalAdminPassword`, `screenShare`, `unlockUserAccount`, `wipe`; the reserved ids render nothing) |
| `mobileDeviceActions` | array of string | no mobile actions | the `deviceActions.mobileDevice.actions[].id` set — forward-looking, no mobile actions menu exists yet |
| `cleanupActions` | array of string | no cleanup actions | `unmanage`, `addToGroup`, `moveToSite`, `deleteFromProtect`, `deleteRecord` |
| `allowExport` | bool | `false` | — (a single switch over **every** export surface — see below) |

**`allowExport` is app-wide, not Reports-only.** It gates every path that moves data out of
the app, and each control is simply **not rendered** without it:

| Surface | Control | Hosting module |
|---|---|---|
| Reports | the Export menu (CSV / Excel / PDF / Markdown), both the toolbar menu and the prominent Run-Report button | `reports` |
| Cleanup | the Export menus on the **stale-device** and **protected-device** lists (CSV / Markdown / PDF) | `cleanup` |
| Logs | **Export CSV** — copies the whole audit trail to the pasteboard | `logs` |

So a role's `modules` decide which export surfaces the user can *reach*, and `allowExport`
decides whether any of them work. The sample profile's `Helios.CleanupTech` role omits
`allowExport`, so its holders get the Cleanup module **with no export control** — add
`allowExport = 1` to that entry (or hold another role that sets it, since it is OR'd across
matched roles) if cleanup technicians should be able to export their device lists.

#### `myDevices` — the self-service module

`myDevices` **has shipped** (it was previously reserved, and documented as `myDevice`). It is
a **read-only** view of the devices assigned to the person signed in: their Macs, iPhones,
iPads and Vision Pros, each with serial, OS version, last check-in, free space, encryption
state and battery. It renders **no action control of its own** — opening a device pushes the
same detail views the Devices module uses, and those gate every action on `computerActions` /
`mobileDeviceActions`, so a role granting `myDevices` and no actions is information-only.
That makes it the one module that is safe to give to everybody.

- The old singular id **`myDevice` still works** — it is normalized to `myDevices` when
  capabilities resolve, so a profile pre-staged against the previous docs lights the module
  up instead of silently granting nothing.
- **Granting `myDevices` does NOT grant `devices`.** A user with only `myDevices` can see
  their own devices and cannot search the fleet.

**How a user is matched to their devices.** Helios knows the operator by email (the Entra UPN,
or the address used at sign-in); Jamf inventory records are keyed by
`userAndLocation.username`, which in most tenants is a directory short name. Helios does not
guess the mapping — it asks Jamf: `GET /api/v1/users?filter=email=="<sign-in address>"`
returns the user record(s) for that address, and inventory is then searched for **every**
username those records carry (one person routinely holds both an `hea08299`-style record and
a UPN-style one). Tune this in `features.myDevices`:

| Key | Default | Effect |
|---|---|---|
| `enabled` | `true` | Machine-layer kill switch for the module |
| `resolveDirectoryUsers` | `true` | Use `/api/v1/users` to learn the tenant's username(s) for the sign-in address. **Needs the Read Users privilege** — a denial is non-fatal and the app falls back to the switches below, with a note in the view |
| `matchEmail` | `true` | Match `userAndLocation.email` / mobile `emailAddress` against the sign-in address |
| `matchUsernameFromEmail` | `true` | Match a username equal to the full sign-in address |
| `matchUsernameLocalPart` | `false` | Also try the part before the `@`. Off by default: it matches nothing in short-name tenants and is the one candidate that could match a *different* person where mailboxes are shared |
| `matchRealName` | `false` | Match real name against the display name. Off by default — Jamf's formatting (`Doe, Jane A.`) rarely equals the token's |
| `showLocalDeviceFallback` | `true` | When nothing matches, show the Mac Helios is running on (matched by hardware serial), **labelled as this Mac**, not as an assignment |
| `maxDevices` | `50` | Cap, so a mis-scoped match cannot pull in the fleet |

**API role privileges:** `Read Computers`, `Read Mobile Devices`, and — for the accurate
identity match — `Read Users`. Reads route on the existing `deviceSearch` credential scope;
no new routing key was added.

#### Sidebar order (access 2.6 / ui 2.2)

**A role's `modules` array order IS its sidebar order.** The first id is the topmost row;
the rest follow in listed order. There is no `order` key anywhere — when you set a module,
you set its position in the same edit, in the same place, and each role gets its own
ordering for free:

```
roles = (
  {
    name    = "Helios.Support";
    modules = ( devices, dashboard, logs, settings );   // Devices renders FIRST
  },
  {
    name    = "Helios.Admin";
    modules = ( dashboard, devices, cleanup, settings ); // Dashboard renders first
  },
)
```

Rules:

- **`settings` is pinned** below the sidebar divider wherever you list it. Listing it grants
  it; its position is ignored. (Sign Out sits below it and is never gated.)
- **Unknown / not-yet-implemented ids are skipped** with no error and no gap. Ordering
  around a pre-staged id is safe — that is what lets a newer profile deploy to an older
  build. (`myDevice` is the one exception: it is an alias, not an unknown id.)
- **The machine layer still prunes.** A module a role grants but this Mac disables — via
  `ui.sidebarItems[].isEnabled`, `ui.userInterface.showAnnouncements` /
  `showSettings`, `features.reports.enabled`, or `features.myDevices.enabled` — renders
  **no row**, and the rows after it simply close up. Order never widens access; the two
  layers still intersect.
- **`ui.sidebarItems` no longer orders anything.** It supplies presence (`isEnabled`), label,
  and icon for an id; its own list position is meaningless. Its `order` key is **removed in
  ui 2.2** — a profile still delivering it decodes fine (extra plist keys are ignored) and
  the key is **IGNORED**, logged once at load:
  `⚠️ ui.sidebarItems: 'order' is ignored — sidebar order now comes from each role's modules list order (access domain).`

**Union order (multi-role users).** One merged list, resolved deterministically:

1. Walk the `roles` **array in the order it is authored in the profile** — *not* the order
   the Entra token's `roles` claim lists them. The claim's order is Entra's to choose and can
   change between sign-ins; the profile is the admin's version-controlled statement of
   intent, so it is the one that decides layout.
2. Within each matched role, append its `modules` in listed order.
3. **First appearance wins.** A module an earlier role already contributed keeps its earlier
   position — a later role listing it again is ignored. Never re-ordered, never duplicated.

So for a user holding both roles in the example above, `Helios.Support` is authored first and
its order leads: **devices, dashboard, logs**, then `Helios.Admin` contributes only what is
new — **cleanup** — and `settings` stays pinned. To change that, reorder the `roles` array
itself.

#### Naming and union semantics

- **Exact, case-sensitive matching.** An Entra app-role `Value` must equal a `roles` entry's
  `name` character-for-character; likewise the access `role` string. `helios.admin` does not
  match `Helios.Admin`. There is no fuzzy match, no aliasing, no normalization to lean on.
  (The `name` is whitespace-trimmed before matching, so a stray trailing space is forgiven —
  nothing else is.)
- **Multiple roles → UNION.** A user whose token carries several matching role values
  receives the union of every matched role's lists; `allowExport` is **OR**'d (one role
  granting it is enough). MDM mode resolves exactly one role name, so union across
  *different* names only ever matters under Entra sign-in.
- **A nameless entry is SKIPPED** (and logged). An entry whose `name` is missing, blank, or
  malformed is unreachable — no role name could ever match it — so it is dropped rather
  than indexed under the empty string, where a blank `role` key could otherwise resolve to
  real capabilities. Fail-closed.
- **Duplicate `name`s UNION together** — they do **not** replace one another. Every entry
  carrying a name contributes to that name, so splitting one role across two entries is
  equivalent to writing one merged entry, and a duplicate can only ever **widen** what the
  name grants. Last-wins was rejected deliberately: it would make an admin's grant vanish
  silently based on array order. This applies in **both** modes — unlike the multi-role
  union above, a single MDM `role` string hitting two same-named entries unions them too.
- **Cleanup is not special-cased.** It is simply the `cleanup` id in a role's `modules`
  list, with its sub-actions in `cleanupActions`. A **cleanup-only role** (e.g.
  `Helios.CleanupTech` with `modules = (cleanup)`) is a supported, ordinary pattern: assign
  it in Entra *alongside* another role and the union gives that user their normal surface
  plus Cleanup.
- **Sign-out is safe to omit `settings` around.** Sign Out lives in the sidebar, not inside
  Settings, so a role without the `settings` module is not stranded.

#### Two layers — device actions only

| Layer | Scope | Source | Decides |
|---|---|---|---|
| 1 | **Machine** — which Mac the operator sits at | access `deviceActions.{computer,mobileDevice}.actions` (+ features `enableAPIActions` kill switch) | which actions **exist** on this Mac: `enabled` state, menu `displayName`, Return-to-Service `options` |
| 2 | **User** — who is signed in | the union of matched roles' `computerActions` / `mobileDeviceActions` | which of those existing actions **this role may see and run** |

An action renders and executes **only when both layers allow it** — a fail-closed
intersection; neither layer can expand what the other denies. An id a role lists but the
machine allow-list omits (or sets `enabled=false`) stays hidden and blocked; an id the
allow-list grants that no matched role lists likewise stays hidden and blocked.

**`modules`, `cleanupActions`, and `allowExport` have no machine layer — they are
role-driven only.** (The `cleanup` block in the access domain is *tunables only*:
`staleDays`, `defaultStaticGroupID`, `defaultSiteID`. It grants nothing.)

#### Fail-closed rules

- **No `roles` block → no capabilities.** Nothing is defaulted on, ever.
- **Role name matches no entry `name` → no capabilities.** In **Entra mode** that user is
  **refused sign-in** outright. In **MDM mode** the user still **signs in but sees an empty
  app** — no modules, no actions, no export.
- That MDM asymmetry is **deliberate**: a missing, mis-scoped, or malformed access profile
  must not hard-lock an org out of its own app. An empty app is diagnosable from the
  inside; a refused sign-in on every Mac is not.
- Unknown ids inside a role's lists are ignored, not fatal — forward compatibility.
- There is deliberately **no default** for `roles`, and none for `role`. A default would be
  a hardcoded capability, which is exactly what this model removes.

---

### BREAKING: migrating from the 2.3 tier model

This is a **hard cutover**, consistent with the domain-split precedent (§8). 2.4+ binaries
read only the role model; the tier keys are gone from the schemas and ignored by the app.
**Profiles are not auto-migrated and there is no compatibility shim.**

| If your 2.3 profile… | …it now does this | Migration |
|---|---|---|
| delivers `deviceActions.*.actions[].requiredTier` | the key is **ignored** (removed from the schema) | Delete it. Put each action id into the `computerActions` / `mobileDeviceActions` list of every role that should be able to run it |
| delivers `signIn.entra.adminRoles` / `operatorRoles` / `cleanupRoles` | the keys are **ignored** (removed from the schema) | Delete them. Set your `roles` entries' **`name`** fields to the Entra app-role **Values** you already assign (e.g. an entry with `name = "Helios.Admin"`), so the claim matches directly |
| relies on the built-in per-action tiers (Operator: `sendBlankPush`/`enableBluetooth`/`disableBluetooth`; Admin: everything else) | **gone** — no built-in classification remains | Re-express the classification as explicit per-role action lists. `Deployment/sample.mobileconfig` ships a worked three-role example |
| is MDM-only (no `signIn` block) and relies on `role = "Admin"` + `deviceActions` | **users see nothing** — `"Admin"` matches no `roles` entry, and there is no `roles` block | Add a `roles` array, and set `role` to one entry's `name`. `role = "Admin"` keeps working **only if** you define an entry with `name = "Admin"` |
| uses `role = "Support"` / `"User"` | same — no `roles` entry with that `name` exists | Same fix. The old enum values have no built-in meaning any more; they are just strings |
| scopes the access profile to **admin Macs only** | non-admin Macs run an **empty app** (previously: a usable app at `role=User` with Cleanup hidden) | **Re-scope to all Macs running Helios.** Differentiate populations with per-variant `role` and `deviceActions`, not by withholding the profile — see the revised scoping matrix in §3 |

The last two rows are the sharp edges. Under 2.3 an absent access profile still yielded a
working app; under 2.4+ the profile carries **every** capability, so an absent profile yields
an empty one. Plan the profile push **before** the pkg rollout, exactly as the domain split
required.

**Revocation:** role names are resolved from the token at sign-in. Removing a user's Entra
app-role assignment (or the whole assignment) takes effect at the user's **next launch /
sign-in and at the next idle-lock unlock** (both redeem the refresh token and re-derive the
role set from the fresh token) — an actively-used session is not re-evaluated mid-flight.
For immediate lockout, disable the user or revoke sessions in Entra and enforce
*Assignment required* on the enterprise application. Changing a **capability** (editing the
`roles` block) is a profile push and takes effect at the next **app relaunch**.

---

## 3. Jamf Pro deployment steps

> **Two Jamf Custom Schema limits, both confirmed by probing. Design within them —
> a plist upload is not an acceptable fallback for this app.**
>
> 1. **Array nesting stops at two levels.** `array of objects → array of strings` and
>    `array of objects → array of objects` both render. A third level gives **no editable
>    field** for the innermost value, so the key is unauthorable even though the schema is
>    valid and the app decodes it fine. This is why `healthScorecard.cards[]` carries its
>    `siteIds` / `requiredApps` / `checks` directly rather than nesting them under a
>    `targets[]` list.
> 2. **The root `title` must be ASCII.** A non-ASCII character there — an em-dash, across
>    all eight schemas — makes Jamf render its generic property editor: a `root` label with
>    an `object` type dropdown and a type picker beside every property, instead of a clean
>    form. `description` may contain any characters; only `title` matters. A bare
>    reverse-DNS `$id` (not a URI) is fine, so the domain-as-`$id` convention below stands.

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
| `com.herojoneslabs.helios.console.access` | **All managed Macs running Helios — per variant** (CHANGED in 2.4; see below) |
| `com.herojoneslabs.helios.console.features` | All managed Macs running Helios |
| `com.herojoneslabs.helios.console.ui` | All managed Macs running Helios |

### Access-profile scoping (CHANGED in 2.4)

Through 2.3 the access profile was scoped to **admin Macs only**, because withholding it
still left a usable app (`role=User`, Cleanup hidden). From 2.4 on the profile carries **every
capability**, so a Mac without it runs an **empty app**. Scope it to **all Macs running
Helios**, and differentiate populations with **per-variant values**, not by withholding:

- **Entra sign-in mode** — one variant is usually enough: the same `roles` block everywhere
  (the token decides who is who), with `deviceActions` narrowed on any Mac population that
  should not be able to run destructive actions *at all*, regardless of who signs in.
- **MDM mode** — one variant per population, identical `roles` block, differing `role`:
  `role = "Helios.Admin"` on admin Macs, `role = "Helios.Support"` on support Macs, and so
  on. The `role` key is the machine-scoped identity.
- Under-scoping is still **safe** (an empty app, never an over-privileged one) — it is just
  no longer *useful*. Over-scoping is still the dangerous direction.

### Paired-scoping rule (access ⟷ credentials)

Role capabilities are a UI gate; the API client's permissions are the real boundary. Keep
them aligned:

- A **write-capable variant** of the credentials profile (one whose `jamfProClientSecret`
  belongs to an API role with write/destructive permissions) and any access variant whose
  reachable roles grant **destructive** capabilities (`wipe` / `returnToService` in
  `computerActions`, or `unmanage` / `deleteRecord` in `cleanupActions`) **must be scoped to
  the same Macs**.
- Never deliver write-capable credentials to a Mac whose access variant does not intend
  those capabilities, and never grant destructive capabilities on Macs carrying only
  read-only credentials.
- Read-only Mac populations get a credentials variant whose secret belongs to a
  **read-only** API role, plus an access variant whose `deviceActions` allow-list omits (or
  disables) the destructive ids — layer 1 then blocks them no matter which role signs in.

### Security notes

- Managed-preference plists are written **world-readable** to
  `/Library/Managed Preferences/<domain>.plist` — any local user or process can read them.
  Scope the credentials profile tightly, use least-privilege API roles, and rotate
  immediately on suspected exposure. Rotating a secret = edit + re-push the one small
  credentials profile; core/features/ui/access are untouched.
- The access profile is **fail-closed**: a Mac that never receives it grants **nothing** —
  no modules, no device actions, no cleanup, no export. Under-scoping is safe;
  over-scoping is not.
- Every role name and capability list is delivered in that world-readable plist, so the
  `roles` block is **public knowledge on every Mac that receives it**. Treat it as
  documentation of your access model, not as a secret — the real boundary is the Jamf API
  role behind the provisioned credentials.

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
   (As of 2.4 the access plist should exist on **every** Mac running Helios — a Mac without
   it runs an empty app.)
2. **Domain values readable** — spot-check each domain the way the app reads it:
   ```sh
   defaults read com.herojoneslabs.helios.console.core jamfPro
   defaults read com.herojoneslabs.helios.console.credentials jamfProClientSecret
   defaults read com.herojoneslabs.helios.console.access role
   defaults read com.herojoneslabs.helios.console.access roles
   ```
3. **App configured** — launch Helios; the login flow reaches Jamf (no "not configured"
   state). If unconfigured, check the app log: it names the **missing domain**.
4. **Partial-delivery check** — temporarily unscope ONLY the credentials profile, relaunch:
   the app must report unconfigured and log that credentials are missing (core alone is
   not enough). Re-scope afterwards.
5. **Role gate** — MDM mode: with `role` set to a `roles` entry whose `modules` include
   `cleanup`, the **Cleanup** sidebar item appears; point `role` at an entry without it (or
   at a name matching **no** entry, or remove the access profile) and the app renders
   **empty**.
   Entra mode: sign in as a user assigned an app role whose **Value** equals a `roles`
   entry's `name`
   and confirm exactly that role's modules render; a user assigned to the app with **no**
   matching role must be **refused sign-in**.
   - **Union check (Entra mode)** — assign one test user two roles (e.g. a support role and
     a cleanup-only role) and confirm they see the union of both, and that `allowExport` is
     granted if **either** role grants it.
   - **Two-layer check** — pick an id that a role lists but `deviceActions` sets
     `enabled=false` (the sample ships `wipe`, `returnToService`, and `screenShare` that
     way): it must stay **hidden** even for the fullest role. Then flip `enabled` to
     `true`, re-push, relaunch, and confirm it appears only for roles listing it.
   - **Case-sensitivity check** — deliberately mis-case one role name (`helios.admin` vs
     `Helios.Admin`) and confirm it matches **nothing**. This is the single most likely
     production misconfiguration.
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

This is also the third rung of the identity precedence chain (Entra → managed access `role`
→ user-level access `role`): standard CFPreferences precedence means the managed plist wins
wherever it delivers a value, so a user-level write only surfaces on a Mac where the profile
delivers nothing. It is a **dev story, not a deployment mechanism**.

```sh
defaults write com.herojoneslabs.helios.console.core jamfPro -dict \
  serverURL "https://yourorg.jamfcloud.com" masterClientID "REPLACE-WITH-MASTER-CLIENT-ID"
defaults write com.herojoneslabs.helios.console.credentials jamfProClientSecret "REPLACE-WITH-jamf-pro-client-secret"

# 2.4: a role NAME alone grants nothing — you must also define what it means.
defaults write com.herojoneslabs.helios.console.access role "Dev.Admin"
# `roles` is an ARRAY of role objects, each naming itself — write the whole list at once.
defaults write com.herojoneslabs.helios.console.access roles '(
  {
    name = "Dev.Admin";
    modules = (dashboard, devices, announcements, logs, reports, cleanup, settings);
    computerActions = (sendBlankPush, restart, restartSilent, shutdown, enableBluetooth, disableBluetooth);
    cleanupActions = (addToGroup, moveToSite);
    allowExport = 1;
  }
)'

# Layer 1 must ALSO grant the ids above, or nothing renders:
defaults write com.herojoneslabs.helios.console.access deviceActions -dict-add computer '{
  actions = (
    { id = sendBlankPush; enabled = 1; },
    { id = restart; enabled = 1; },
    { id = restartSilent; enabled = 1; },
    { id = shutdown; enabled = 1; },
    { id = enableBluetooth; enabled = 1; },
    { id = disableBluetooth; enabled = 1; }
  );
}'
```

Notes:

- The app **no longer seeds placeholder values** at launch (the old
  `setupDevelopmentConfiguration()` is gone), and `MDMConfiguration.default` uses empty
  strings — an unconfigured dev Mac is genuinely unconfigured.
- **The old DEBUG `role=Admin` convenience no longer means anything.** No role names are
  built into the app, so there is nothing for a debug default to name — a dev Mac with no
  `roles` block renders an empty app in every build configuration. Define the block above
  once and it persists.
- Remember the **two-layer** rule when a dev-Mac action stubbornly refuses to appear: it
  must be granted in **both** the role's `computerActions` and `deviceActions.computer.actions`
  (with `enabled = 1`). Forgetting layer 1 is the usual cause.
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
