# Helios Console — Microsoft Entra ID Sign-In Setup

**Date:** 2026-07-16 · **Branch:** `feature/entra-auth` · **Config domains:**
`com.herojoneslabs.helios.console.core` (`signIn` block — identity) +
`com.herojoneslabs.helios.console.access` (`roles` block — capabilities)

Helios Console can authenticate operators interactively against **Microsoft Entra ID**
(OpenID Connect authorization-code flow + PKCE via `ASWebAuthenticationSession` — no MSAL,
no embedded web view). Access is **group-gated in Entra**, and each user's **capabilities**
come from Entra **app roles** whose names are defined by you in Helios's managed
configuration. This guide walks an admin through the Entra portal setup and the matching
Helios managed configuration.

> **Nothing about access is hardcoded in Helios.** The app ships **no** built-in role names
> and **no** built-in tiers. An Entra app-role **Value** is looked up against the **`name`**
> of an entry in the **access** domain's `roles` array, which defines exactly what that role
> can see and do.
> Define your capability sets there first (`schemas/Helios_Access_SCHEMA.json`,
> `docs/ConfigProfileMigration.md` → *Role-capability model*); this guide is about wiring
> Entra identity to those names.

> This sign-in registration is **NOT** the same thing as the existing Entra **Graph
> credentials** registration (the `entra.*` pointer block in the core domain, used by
> Return to Service / device cleanup — see `docs/ConfigProfileMigration.md`). That one is a
> confidential client with a secret or certificate delivered via its own credential domain.
> The registration described here is a **public client with no secret, ever**. Keep them
> as two separate app registrations.

---

## 1. Overview — how a role becomes a capability

Sign-in is enforced twice, by different parties:

1. **Entra-side sign-in gating** (§4). The enterprise application has *Assignment
   required = Yes*, so Entra itself refuses to issue a token to anyone who is not a member
   of an assigned group. Unassigned users never get past Microsoft's login page
   (`AADSTS50105`). This is the actual gate.
2. **App-side role resolution** (fail-closed). Helios reads the `roles` claim from the
   signed v2.0 ID token and looks each value up against the `name` of every entry in the
   access domain's `roles` array. No matching name → sign-in is refused in-app even if Entra
   issued a token.

The chain, end to end:

```
Entra app role Value  ──exact, case-sensitive──▶  roles entry `name`  ──▶  that role's
  e.g. "Helios.Support"                            "Helios.Support"       modules,
                                                                          computerActions,
  (roles claim in the ID token)                    (access domain,        mobileDeviceActions,
                                                    managed config)       cleanupActions,
                                                                          allowExport
```

So the **only** thing Entra decides is *which names a user carries*. Everything those names
mean is admin-defined config. To add a capability tier, invent a name, define it in `roles`,
create the matching app role, assign a group — no app change, no Helios release.

| | **Role Value matches a `roles` entry `name`** | **Several match** | **Assigned to the app, no Helios role** | **Unassigned** |
|---|---|---|---|---|
| Sign-in | ✅ | ✅ | ❌ refused by Helios | ❌ refused by Entra (`AADSTS50105`) |
| Capabilities | exactly that role's lists, intersected with the Mac's `deviceActions` for device actions | the **UNION** of every matched role's lists; `allowExport` is OR'd | none | none |

`Helios.Admin` / `Helios.Operator` are **no longer app defaults** — they are merely the
naming convention used by `Deployment/sample.mobileconfig` (which ships `Helios.Admin`,
`Helios.Support`, and `Helios.User`). Any names work; `HelpDesk.Tier1` is just as valid.

Three rules to keep in mind throughout:

- **Fail-closed everywhere.** No matching role → no sign-in. Groups-overage token → no
  sign-in. Missing `tenantId`/`clientId` → no sign-in (the app never falls back to the
  legacy email flow). No `roles` block → no capabilities. Ambiguity always resolves to
  *less* access.
- **Exact, case-sensitive matching.** `helios.admin` does not match `Helios.Admin`. This is
  the most common misconfiguration — see §8.
- **A role is a ceiling within the machine's config, not a bypass of it.** Device actions
  are a **two-layer** gate: the Mac's `deviceActions` allow-list says which actions *exist*
  there, the role says which of those the user may *use*, and only the intersection renders.
  See §9.

---

## 2. Create the app registration

In the **Microsoft Entra admin center** (`entra.microsoft.com`) → **Identity → Applications
→ App registrations → New registration**:

1. **Name:** e.g. `Helios Console Sign-In` (any name; it is what users see on the consent
   and sign-in screens).
2. **Supported account types:** *Accounts in this organizational directory only*
   (**single tenant**).
3. **Redirect URI:** select platform **Mobile and desktop applications** — *not* Web —
   and add exactly:
   ```
   heliosauth://callback
   ```
   The scheme, host, and (lack of) trailing slash must match character-for-character;
   Entra rejects mismatches with `AADSTS50011` (§8).
4. Register, then note the **Application (client) ID** and **Directory (tenant) ID** from
   the Overview page — these become `clientId` and `tenantId` in the Helios config (§6).
5. **Authentication → Advanced settings → Allow public client flows:** **Yes**
   (`allowPublicClient: true` in the manifest).

> **Never create a client secret or certificate for this registration.** It is a public
> client: the app runs on end-user Macs and proves nothing with a secret — PKCE protects
> the code exchange instead. A secret added here would have to ship inside the app or a
> world-readable managed-preferences plist, turning it into a liability with zero security
> benefit. If someone has added one, delete it. (The existing Helios cleanup/Graph
> credentials registration keeps its secret/certificate — that is a different, confidential
> app registration.)

### API permissions

**API permissions → Add a permission → Microsoft Graph → Delegated permissions**, then add:

| Permission | Type | Admin consent required |
|---|---|---|
| `openid` | Delegated | No |
| `profile` | Delegated | No |
| `email` | Delegated | No |
| `offline_access` | Delegated | No |

This is the default OpenID Connect set and nothing more — Helios only needs identity and
a refresh token. **No admin-consent-requiring permission is needed**; do not add Graph
application permissions or anything beyond the four above. (You may still click *Grant
admin consent* to suppress the one-time per-user consent prompt — optional.)

The app requests scopes `openid profile email offline_access` and runs the
authorization-code + PKCE flow against
`https://login.microsoftonline.com/{tenantId}` (host varies with `cloudInstance`, §6).

---

## 3. Define app roles

> **Do the access domain first.** An app role whose **Value** does not exactly equal the
> `name` of an entry in the access domain's `roles` array grants **nothing** and gets its
> holder **refused at sign-in**. Decide your role names and their capability sets there
> (`docs/ConfigProfileMigration.md` → *Role-capability model*), then mirror the names here.

App roles are how Helios learns which capability sets a user holds. In the registration:
**App roles → Create app role**, once per role entry in your `roles` array. The example below
mirrors `Deployment/sample.mobileconfig` — **a convention, not a requirement**:

| Field | Role 1 | Role 2 | Role 3 (optional) |
|---|---|---|---|
| Display name | `Helios Admin` | `Helios Support` | `Helios Cleanup Technician` |
| Allowed member types | Users/Groups | Users/Groups | Users/Groups |
| **Value** | `Helios.Admin` | `Helios.Support` | `Helios.CleanupTech` |
| Description | Full Helios Console access (within the Mac's managed configuration). | Day-to-day Helios access — no Cleanup module, no credential disclosure. | Cleanup module only — stale-device cleanup, no device actions. |
| Enabled | ✅ | ✅ | ✅ |
| **Must exist as a `roles` entry `name`** | ✅ | ✅ | ✅ |

The **Value** strings are what land in the token's `roles` claim and what the app looks up
in the `roles` block — they must match **exactly (case-sensitive)**, character for
character. There are **no default values baked into the app** any more: `Helios.Admin` and
`Helios.Operator` used to be config defaults (`adminRoles` / `operatorRoles`) and are not
special in any way now. Name your roles whatever your org calls them; just keep the app-role
Value and the `roles` entry's `name` identical.

### Additive roles and the cleanup-only pattern

A user assigned **several** app roles receives the **union** of those roles' capabilities,
and `allowExport` is OR'd. This makes narrow, composable roles the natural design:

- Define a `Helios.CleanupTech` entry in `roles` with `modules = (cleanup)` and whatever
  `cleanupActions` you want to delegate — and nothing else.
- Assign it to a technician **alongside** `Helios.Support`. They get the full support
  surface **plus** Cleanup, with no new role definition needed for the combination.
- Assign it **alone** and they get a Cleanup-only app: the module and nothing else. That is
  a supported, ordinary configuration — Cleanup is no longer special-cased in the app; it
  is just the `cleanup` module id in a role's `modules` list.

Prefer composing narrow roles over defining one role per combination — the union does the
combining for you.

Equivalent manifest snippet (**Manifest → appRoles**), with placeholder GUIDs — generate
your own (`uuidgen`) if editing the manifest directly:

```json
"appRoles": [
    {
        "allowedMemberTypes": [ "User" ],
        "description": "Full Helios Console access (within the Mac's managed configuration).",
        "displayName": "Helios Admin",
        "id": "12345678-aaaa-0000-0000-000000000001",
        "isEnabled": true,
        "value": "Helios.Admin"
    },
    {
        "allowedMemberTypes": [ "User" ],
        "description": "Day-to-day Helios access — no Cleanup module, no credential disclosure.",
        "displayName": "Helios Support",
        "id": "12345678-aaaa-0000-0000-000000000002",
        "isEnabled": true,
        "value": "Helios.Support"
    },
    {
        "allowedMemberTypes": [ "User" ],
        "description": "Cleanup module only — stale-device cleanup, no device actions.",
        "displayName": "Helios Cleanup Technician",
        "id": "12345678-aaaa-0000-0000-000000000003",
        "isEnabled": true,
        "value": "Helios.CleanupTech"
    }
]
```

> The `roles` claim appears in **v2.0 ID tokens automatically** once a user (or their
> group) is assigned to a role — no *Token configuration* / optional-claims setup is
> needed. If a signed-in user has no Helios role, the claim is simply absent and the app
> refuses the sign-in (§8, "not authorized"). Each `value` above must appear **verbatim**
> as an entry `name` in the access domain's `roles` block; a `value` with no matching name is
> indistinguishable, to Helios, from having no role at all.

---

## 4. Gate sign-in by group (the actual gate)

Defining roles does nothing until you **require assignment** and **assign your groups to
the roles**. In **Entra admin center → Identity → Applications → Enterprise applications →
*Helios Console Sign-In***:

1. **Properties → Assignment required?** → **Yes** → Save.
   This is the real sign-in gate: with it set, **Entra refuses to issue a token to any
   user who is not assigned** (directly or via an assigned group). They fail at
   Microsoft's login page with `AADSTS50105` before Helios ever sees them. Without it,
   *every* user in the tenant can obtain a token and the only thing keeping them out is
   the app's role check — set it to Yes.
2. **Users and groups → Add user/group:**
   - assign your **admin security group** → role **Helios Admin**
   - assign your **support security group** → role **Helios Support**
   - (optionally) assign your **cleanup technicians group** → role **Helios Cleanup
     Technician**

   A user covered by several assignments carries **all** of those roles, and Helios grants
   the **union** of their capabilities — there is no "highest wins" precedence any more,
   because roles are not ranked. Adding a role can therefore only ever **add** capability;
   it can never take one away.

Group-assignment caveats:

- **Direct membership only.** App role assignment through a group honors **direct**
  members — users in a *nested* group inside the assigned group are **not** assigned and
  will be refused. Assign flat **security groups** (recommended), or assign each nested
  group explicitly.
- **Licensing.** Assigning *groups* (rather than individual users) to an enterprise app
  requires **Microsoft Entra ID P1** or higher; if you use **dynamic membership groups**
  for the admin/operator populations, those likewise require P1/P2. Individual user
  assignments work on any license.
- Membership changes take effect on the **next token issuance** — a removed user keeps
  working until their session re-validates. Helios re-validates at **every launch** by
  redeeming the refresh token and re-deriving the role set, so revocation lands at the next
  app launch at the latest (revoke the user's sessions in Entra to force it sooner).

---

## 5. Optional: group-ID gating (`allowedGroupIds`)

In addition to (never instead of) app roles, Helios can require that the token's `groups`
claim intersect an allow-list:

1. In the app registration **Manifest**, set:
   ```json
   "groupMembershipClaims": "SecurityGroup"
   ```
   so security-group object IDs are emitted in the ID token's `groups` claim.
2. Deliver the group **object IDs** (GUIDs, not display names) in the config (§6):
   `allowedGroupIds = ["12345678-2222-0000-0000-000000000000", …]`.
   Default is `[]` = feature **off** (no group check).

**Know the limitation before you rely on this:** Entra caps the `groups` claim at **200
groups** for JWTs. A user in more than 200 groups gets an **overage token** — no `groups`
list, just a `hasgroups`/`_claim_names` indirection pointing at Graph. Helios does **not**
chase the Graph lookup; per the fail-closed rule it **refuses the sign-in outright**
(§8). So a perfectly legitimate admin who happens to be in 201 groups is locked out by
this mechanism.

> **Recommendation: prefer app roles (§3–§4) and leave `allowedGroupIds` empty.** Role
> assignment is evaluated by Entra at issuance, produces a tiny deterministic `roles`
> claim, and has no overage failure mode. Use `allowedGroupIds` only as a
> belt-and-braces second check in environments that mandate it.

---

## 6. Configure Helios

Sign-in is configured in **two different domains**, and the split is the whole point of the
model:

| Domain | Answers | Schema |
|---|---|---|
| **core** (`com.herojoneslabs.helios.console.core`), `signIn` block | *Who is this user, and which role names do they carry?* — **identity only** | `schemas/Helios_Core_SCHEMA.json` |
| **access** (`com.herojoneslabs.helios.console.access`), `roles` array | *What can each role name actually do?* — **every capability** | `schemas/Helios_Access_SCHEMA.json` |

**No role names are configured in the core domain.** The keys that used to live there —
`adminRoles`, `operatorRoles`, `cleanupRoles` — have been **removed**; a role's name is
simply the `name` of its entry in the access domain's `roles` array.

### 6a. Core domain — identity

| Key | Type | Default | Meaning |
|---|---|---|---|
| `signIn.method` | string | `"email"` | `"email"` = legacy flow (the access `role` key then names the user's role); `"entra"` = Microsoft sign-in only (login screen shows a single *Sign in with Microsoft* button; the access `role` key is ignored) |
| `signIn.entra.tenantId` | string | — (**required** for `entra`) | Directory (tenant) ID from §2. Must be the tenant **GUID** — `common`/`organizations` are **not supported** (issuer validation is an exact match against the tenant-specific issuer) |
| `signIn.entra.clientId` | string | — (**required** for `entra`) | Application (client) ID from §2 |
| `signIn.entra.cloudInstance` | string | `"global"` | `global` / `usgov` (GCC High) / `china` (21Vianet) — selects the login host |
| `signIn.entra.allowedGroupIds` | array of string | `[]` (off) | optional group-object-ID gate (§5) — a **sign-in** check only; group membership grants no capability |
| `signIn.entra.provisionJamfCredentials` | bool | `true` | after Entra sign-in, still provision the per-user Jamf API client using the Entra-verified email |

With `method = "entra"` but a missing/blank `tenantId` or `clientId`, sign-in is
**blocked entirely** — the app reports the sign-in configuration as invalid and **never
falls back to the email flow** (§8).

Payload fragment for the core-domain Jamf *Application & Custom Settings* payload (all
GUIDs below are placeholders — substitute your own from §2):

```xml
<key>signIn</key>
<dict>
	<key>method</key>
	<string>entra</string>
	<key>entra</key>
	<dict>
		<key>tenantId</key>
		<string>12345678-0000-0000-0000-000000000000</string>
		<key>clientId</key>
		<string>12345678-1111-1111-1111-111111111111</string>
		<key>cloudInstance</key>
		<string>global</string>
		<!-- optional; empty/omitted = group gate OFF (recommended — see §5) -->
		<key>allowedGroupIds</key>
		<array/>
		<key>provisionJamfCredentials</key>
		<true/>
	</dict>
</dict>
```

### 6b. Access domain — capabilities

This is where the role names from §3 acquire meaning. `roles` is an **array of role
objects**, each naming itself in `name`; each `name` must equal an app-role **Value**
exactly. Abbreviated — see `Deployment/sample.mobileconfig` for the full three-role
example, and `schemas/Helios_Access_SCHEMA.json` for every valid id:

```xml
<key>roles</key>
<array>
	<dict>
		<key>name</key>
		<string>Helios.Support</string>
		<key>modules</key>
		<array>
			<string>dashboard</string>
			<string>devices</string>
			<string>reports</string>
			<string>settings</string>
		</array>
		<!-- Intersected with the Mac's deviceActions allow-list: an id here
		     that the Mac does not enable stays hidden and blocked. -->
		<key>computerActions</key>
		<array>
			<string>sendBlankPush</string>
			<string>restart</string>
		</array>
		<key>allowExport</key>
		<true/>
	</dict>

	<!-- Assign ALONGSIDE Helios.Support in Entra: the user gets the union. -->
	<dict>
		<key>name</key>
		<string>Helios.CleanupTech</string>
		<key>modules</key>
		<array>
			<string>cleanup</string>
		</array>
		<key>cleanupActions</key>
		<array>
			<string>addToGroup</string>
			<string>moveToSite</string>
		</array>
	</dict>
</array>
```

> **Why an array and not a dictionary keyed by role name?** Because role names are
> admin-chosen, a dictionary can only be expressed in JSON Schema as
> `additionalProperties` — which Jamf Pro's **Application & Custom Settings** form
> generator cannot render, forcing you to hand-edit the profile XML. A list of objects
> renders as a form, the same way `deviceActions.computer.actions` does.
>
> Two rules follow from the array shape, both fail-closed:
> - An entry with a **missing or blank `name`** is **skipped** (and logged) — no role
>   name could ever match it, so it grants nobody anything.
> - Two entries sharing a `name` are **unioned**, not replaced. A later entry adds to the
>   earlier one, so a duplicate can only ever widen that name's grants — never silently
>   drop a grant based on array order.
>
> A third follows as of **access 2.6**: this array's **order is significant** — it decides
> the sidebar order for users holding more than one role. See *Sidebar order* below.

#### Sidebar order (access 2.6 / ui 2.2)

**Each role's `modules` array order IS that role's sidebar order** — first id = topmost row.
There is no `order` key: `ui.sidebarItems` carries presence (`isEnabled`), label, and icon
only, and its `order` key was **removed in ui 2.2**. A profile still delivering `order`
decodes fine and the key is **IGNORED**, logged once at load:

```
⚠️ ui.sidebarItems: 'order' is ignored — sidebar order now comes from each role's modules list order (access domain).
```

In the example above a `Helios.Support` holder sees **Dashboard, Devices, Reports**, with
Settings pinned below the divider (`settings` is pinned wherever you list it). Reorder that
`modules` array and the sidebar reorders — nothing else to touch, and a second role can order
the same modules differently.

**Union order.** This matters most here: Entra is the mode where a user can hold several
roles at once. `Helios.Support` + `Helios.CleanupTech` above resolves to **Dashboard,
Devices, Reports, Cleanup**:

1. The **profile's `roles` array order** decides which role's ordering leads — **not** the
   order the ID token's `roles` claim happens to list them. That claim's order is Entra's to
   choose and can differ between sign-ins; ordering by it would shuffle a user's sidebar for
   no reason you could see or control. `Helios.Support` is authored first above, so its
   modules lead.
2. Within each matched role, its `modules` append in listed order.
3. **First appearance wins** — a module an earlier role already contributed keeps its
   position; a later role listing it again is ignored, never moved and never duplicated.

To change a multi-role user's layout, reorder the `roles` array itself.

> **Scope the access profile to every Mac running Helios.** Through 2.3 it was admin-Macs-
> only; from 2.4 on it carries every capability, so a Mac without it renders an **empty app**.
> See `docs/ConfigProfileMigration.md` §3.

For local testing on a dev Mac (no profile needed — the loader also reads the user-level
suite plist, see `docs/ConfigProfileMigration.md` §6):

```sh
defaults write com.herojoneslabs.helios.console.core signIn \
  '{ method = entra; entra = { tenantId = "12345678-0000-0000-0000-000000000000"; clientId = "12345678-1111-1111-1111-111111111111"; }; }'

# Remember the access side — without a role entry whose `name` matches, sign-in is
# REFUSED. `roles` is an ARRAY, so write the whole list at once:
defaults write com.herojoneslabs.helios.console.access roles '(
  {
    name = "Helios.Support";
    modules = (dashboard, devices, reports, settings);
    computerActions = (sendBlankPush, restart);
    allowExport = 1;
  }
)'
```

A full manually-installable multi-payload profile for test Macs lives at
`Deployment/sample.mobileconfig` — its access payload already ships a worked `roles` block;
add the `signIn` dict to its core payload. As always, profile changes take effect at app
**relaunch**.

Session behavior: after the first interactive sign-in, the session persists via the
**refresh token**; on **every launch** — and on **every idle-lock unlock** — the app
redeems it and **re-derives the role set** from the fresh token, so role/group revocation
takes effect at the next launch or unlock. Changing what a role *means* (editing the access
`roles` block) is a profile push and lands at the next **relaunch**. With
`provisionJamfCredentials = true` (default), the Entra-verified email then drives the same
per-user Jamf API client provisioning as the email flow — the Jamf side is unchanged.

---

## 7. Conditional Access & SSO notes

Helios uses `ASWebAuthenticationSession` in its default (**non-ephemeral**) mode, i.e. the
**system browser's shared session**, not an isolated cookie jar. Two useful consequences:

- **Silent SSO.** If the **Microsoft Enterprise SSO extension** is deployed via Jamf (an
  *Extensible Single Sign-On* payload, per Microsoft's macOS SSO plug-in docs), the
  extension intercepts the `login.microsoftonline.com` request and signs the user in
  silently with the device's existing Entra session — typically no password prompt at all.
- **Device-based Conditional Access works.** Because the request carries the device
  identity from the SSO extension / PSSO registration, CA policies that require a
  **compliant** or **Entra-joined** device evaluate correctly. A CA policy scoped to the
  Helios sign-in app requiring a compliant device effectively adds a **third gate**: even
  a correctly assigned admin can only sign in **from a managed Mac**. Recommended for
  defense in depth — Helios itself neither knows nor cares; it just sees Entra refuse the
  token on unmanaged hardware.

No Helios configuration is involved in either — both are pure Entra/Jamf-side controls
layered on top of §2–§4.

---

## 8. Troubleshooting

| Symptom | Meaning | Fix |
|---|---|---|
| `AADSTS50105` on the Microsoft page ("…not assigned to a role for the application") | *Assignment required* is Yes and the user is not an assigned member | Add the user's group under **Users and groups** (§4); remember nested membership does not count |
| `AADSTS700016` ("Application … was not found in the directory") | `clientId` in the profile is wrong, or points at a registration in a different tenant | Re-copy the Application (client) ID from the registration Overview (§2) into the core profile |
| `AADSTS90002` ("Tenant … not found") | `tenantId` is wrong, or `cloudInstance` points at the wrong cloud for that tenant | Re-copy the Directory (tenant) ID; check `cloudInstance` matches where the tenant actually lives |
| `AADSTS50011` (redirect URI mismatch) | The registration's redirect URI is not exactly `heliosauth://callback`, or it was added under the wrong platform | Add it under **Mobile and desktop applications** (§2), exact string, no trailing slash |
| Microsoft sign-in **succeeds**, then Helios shows **"not authorized"** | Entra issued a token but **no** role value in it matches an entry `name` in the access domain's `roles` block — user assigned to the app without a Helios role, a role `value` typo, or the `roles` block uses different names | Assign the group **to a role**, not just to the app (§4); then compare the manifest `value` strings (§3) against the `roles` entry `name` values **character for character**: `defaults read com.herojoneslabs.helios.console.access roles` |
| Signed in fine, but the app is **empty** (no sidebar items, no actions) | The role name matched **nothing**, or matched a role whose `modules` list is empty. In **Entra mode** a total mismatch refuses sign-in, so an empty app here usually means a role key exists but grants nothing. In **MDM mode** (no `signIn` block) an unmatched `role` value signs in to an empty app by design | Check for a **case mismatch** first (`helios.admin` ≠ `Helios.Admin`) — the single most common cause. Then confirm the access profile actually landed (`ls /Library/Managed\\ Preferences/com.herojoneslabs.helios.console.access.plist`) and that the matched role's `modules` list is non-empty |
| Sidebar looks right, but a **device action is missing** for a role that lists it | The **two-layer** gate: the Mac's `deviceActions` allow-list does not grant that id, or grants it with `enabled=false` (the sample ships `wipe`/`returnToService`/`screenShare` disabled) | Grant the id in **both** layers — the role's `computerActions` **and** `deviceActions.computer.actions` with `enabled=true` — then relaunch (§9) |
| A user has **more** access than their "main" role should give | They hold **several** app roles and Helios grants the **union** — roles are additive and unranked, so a second assignment can only add | Check **Users and groups** for every assignment covering that user (including via groups), not just the intended one (§4) |
| Sign-in refused with a groups-overage message | User is in >200 groups, so the token had `hasgroups`/`_claim_names` instead of a `groups` list; the app fails closed | Expected with `allowedGroupIds` set for heavily-grouped users — switch that user's gating to app roles, or clear `allowedGroupIds` (§5) |
| Login screen shows a **sign-in configuration error** instead of the Microsoft button ("signIn misconfigured") | `method = entra` but `tenantId` or `clientId` is missing/blank — the app deliberately blocks rather than falling back to email | Fix the core profile (§6), re-push, relaunch. Verify delivery: `defaults read com.herojoneslabs.helios.console.core signIn` |
| Token validation fails with an **issuer mismatch** ("The Microsoft identity token failed validation: issuer mismatch…") | `tenantId` is not the directory (tenant) ID **GUID** — e.g. `common` or `organizations` — so the token's tenant-specific issuer can never equal the expected issuer built from the config | Set `signIn.entra.tenantId` to the tenant GUID from the registration Overview (§2, §6); multi-tenant authority aliases are not supported |
| Old role/group still in effect after revocation | Sessions re-validate at launch and at idle-lock unlock, not live | Relaunch the app or let the idle lock engage and unlock (or revoke the user's Entra sessions and relaunch) — see §4/§6 |
| Edited the `roles` block, but nothing changed | Managed config is read at launch; there are no live profile observers | Re-push the access profile and **relaunch** the app. On a dev Mac, check that a user-level `defaults write` isn't being shadowed by a managed profile (managed always wins) |

---

## 9. Security model summary

Fail-closed rules, in one place:

- No `roles`-claim value matching an **entry `name` in the access domain's `roles` array** →
  sign-in refused (there is no default role, and no built-in role name to fall back to).
- A `roles` entry with **no `name`** is skipped as unreachable; two entries sharing a
  `name` are **unioned**, never replaced (a duplicate can only widen, never shrink).
- **No `roles` block at all → no capabilities.** Nothing is ever defaulted on. Under Entra
  sign-in that means nobody can sign in; under MDM sign-in the user reaches an **empty
  app** (deliberate — a missing profile must not hard-lock an org out of its own app).
- **Matching is exact and case-sensitive**, both for Entra app-role Values and for the MDM
  `role` key. A mis-cased name grants nothing; it never falls back to a looser match.
- **Multiple roles → union** (`allowExport` OR'd). Roles are additive and unranked: an
  extra assignment can only ever **add** capability, never remove one. Revoking access
  means removing assignments, not adding a restrictive role.
- **Device actions need both layers**; `modules`, `cleanupActions`, and `allowExport` are
  role-driven only.
- `allowedGroupIds` set and no `groups` intersection → refused. Group membership is a
  sign-in check only and grants **no** capability.
- Groups-overage token (`hasgroups` / `_claim_names`) → refused, never resolved via Graph.
- `method = entra` with missing `tenantId`/`clientId` → sign-in blocked; **no** fallback
  to the email flow.
- Every launch — and every idle-lock unlock — re-validates: refresh token redeemed,
  role set re-derived from the fresh token — revocation is effective at the next launch
  or unlock.

What each layer does — and does not — protect against:

| Layer | Enforced by | Protects against | Does NOT protect against |
|---|---|---|---|
| Entra assignment + CA (§4, §7) | Microsoft, server-side, at token issuance | unassigned users, revoked users (at next validation), unmanaged devices (with a compliant-device CA policy) | what an *authorized* user can do once signed in |
| App role check (§1, §6) | Helios, **client-side**, on the signed token's `roles` claim | role-less users using the app at all; a role seeing modules, actions, cleanup sub-actions, or exports its `roles` entry does not list | a tampered/patched client — it is UI/feature gating, not a server boundary |
| Machine `deviceActions` allow-list (access domain, layer 1) | MDM-forced managed preferences | **any** user of that Mac running an action the Mac does not enable — regardless of role. This is the layer that survives a role misconfiguration | mis-scoped profiles; it cannot restrict modules/cleanup/export, which are role-driven only |
| Jamf API role behind the provisioned client (see `docs/ConfigProfileMigration.md`) | Jamf Pro, **server-side** API permissions | any user exceeding what the provisioned per-user API client is permitted to do — the real boundary | over-scoping write-capable credentials (that is on you) |

The role check is honest about what it is: **client-side feature gating on a
cryptographically signed token**. The authoritative boundary remains server-side — the
permissions of the Jamf API role behind the provisioned per-user client — with the Mac's
MDM-forced `deviceActions` allow-list as the local backstop that a role definition cannot
override.

Two consequences worth internalizing:

- **The `roles` block is not a secret.** It is delivered in a world-readable
  managed-preferences plist, so every user of a Mac can read the full access model. It
  documents your intent; it does not defend it.
- **Keep the paired-scoping rule** from `docs/ConfigProfileMigration.md` §3 in force: Macs
  whose reachable roles grant destructive capabilities must be the same Macs that receive
  write-capable credentials. A role name alone must never be the only thing standing
  between a user and a write-capable API client — and since roles are now free-form
  strings, that discipline matters more, not less: a typo in a `roles` entry `name` is a silent
  grant of *nothing*, but a stray extra role in the block is a silent grant of *something*.

---

*Sync points: the `signIn` keys above must match `schemas/Helios_Core_SCHEMA.json`; the
`roles` block shape and its module / action / cleanup ids must match
`schemas/Helios_Access_SCHEMA.json` and `Deployment/sample.mobileconfig`; both must match
the domain decoding in `HeliosConsole/Managers/Configuration/`. No role names are baked
into the app — `Helios.Admin` / `Helios.Support` / `Helios.User` appear here and in the
sample profile purely as a naming convention.*
