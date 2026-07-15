# Helios Console — Microsoft Entra ID Sign-In Setup

**Date:** 2026-07-14 · **Branch:** `feature/entra-auth` · **Config domain:** `com.herojoneslabs.helios.console.core` (`signIn` block)

Helios Console can authenticate operators interactively against **Microsoft Entra ID**
(OpenID Connect authorization-code flow + PKCE via `ASWebAuthenticationSession` — no MSAL,
no embedded web view). Access is **group-gated in Entra** and **tiered in the app** via
Entra **app roles**. This guide walks an admin through the Entra portal setup and the
matching Helios managed configuration.

> This sign-in registration is **NOT** the same thing as the existing Entra **Graph
> credentials** registration (the `entra.*` pointer block in the core domain, used by
> Return to Service / device cleanup — see `docs/ConfigProfileMigration.md`). That one is a
> confidential client with a secret or certificate delivered via its own credential domain.
> The registration described here is a **public client with no secret, ever**. Keep them
> as two separate app registrations.

---

## 1. Overview — two enforcement layers

Sign-in access is enforced twice, by different parties:

1. **Entra-side sign-in gating** (§4). The enterprise application has *Assignment
   required = Yes*, so Entra itself refuses to issue a token to anyone who is not a member
   of an assigned group. Unassigned users never get past Microsoft's login page
   (`AADSTS50105`). This is the actual gate.
2. **App-side feature tiers** (fail-closed). Helios reads the `roles` claim from the
   signed v2.0 ID token and maps it to a tier. No matching role → sign-in is refused
   in-app even if Entra issued a token.

| | **Admin tier** | **Operator tier** | **Cleanup-only role** | **Unassigned / no role** |
|---|---|---|---|---|
| Entra app role | any role in `adminRoles` (default `Helios.Admin`) | any role in `operatorRoles` (default `Helios.Operator`) | any role in `cleanupRoles` (no default — opt-in, e.g. `Helios.CleanupTech`) | none |
| Sign-in | ✅ | ✅ | ✅ — tier is `None` | ❌ refused (by Entra if unassigned; by Helios if assigned without a Helios role) |
| Feature access | full access — everything the **machine's** managed profiles allow | no Cleanup module (unless a `cleanupRoles` role is also held); no destructive device actions (Erase Device, Return to Service, etc.) | Cleanup module + read surfaces only — **zero** tier-gated device actions | n/a |

Admin-tier users always have Cleanup; `cleanupRoles` (§6) only **extends** the grant. And
in every case the **Mac** must still carry access-domain `role=Admin` for Cleanup to
appear at all (§9).

Two rules to keep in mind throughout:

- **Fail-closed everywhere.** No role → no sign-in. Groups-overage token → no sign-in.
  Missing `tenantId`/`clientId` → no sign-in (the app never falls back to the legacy
  email flow). Ambiguity always resolves to *less* access.
- **The tier is a ceiling within the machine's config, not a bypass of it.** An Admin-tier
  user on a Mac without the access profile still has no Cleanup and no destructive
  actions. See §9.

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

App roles are how Helios distinguishes Admins from Operators. In the registration:
**App roles → Create app role**, twice — plus an optional third role if you want to grant
the Cleanup module to non-admins:

| Field | Role 1 | Role 2 | Role 3 (optional) |
|---|---|---|---|
| Display name | `Helios Admin` | `Helios Operator` | `Helios Cleanup Technician` |
| Allowed member types | Users/Groups | Users/Groups | Users/Groups |
| **Value** | `Helios.Admin` | `Helios.Operator` | `Helios.CleanupTech` |
| Description | Full Helios Console access (within the Mac's managed configuration). | Day-to-day Helios access — no Cleanup module, no destructive device actions. | Cleanup module only — stale-device cleanup, no device actions. |
| Enabled | ✅ | ✅ | ✅ |

The **Value** strings are what land in the token's `roles` claim and what the app compares
against `adminRoles` / `operatorRoles` / `cleanupRoles` (§6) — they must match exactly
(case-sensitive). `Helios.Admin` and `Helios.Operator` are the app's defaults; if you
invent different values, deliver them in the config. The cleanup role has **no** built-in
default: it does nothing until its value is delivered in `cleanupRoles` (§6), and its
holders sign in with **no** device-action tier — Cleanup and read surfaces only.

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
        "description": "Day-to-day Helios access — no Cleanup module, no destructive device actions.",
        "displayName": "Helios Operator",
        "id": "12345678-aaaa-0000-0000-000000000002",
        "isEnabled": true,
        "value": "Helios.Operator"
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
> refuses the sign-in (§8, "not authorized").

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
   - assign your **operator security group** → role **Helios Operator**

   A user covered by both assignments gets both roles; the app resolves the highest tier
   (Admin wins).

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
  redeeming the refresh token and re-deriving the tier, so revocation lands at the next
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

Sign-in behavior is managed configuration in the **core** domain
(`com.herojoneslabs.helios.console.core`), new `signIn` dictionary:

| Key | Type | Default | Meaning |
|---|---|---|---|
| `signIn.method` | string | `"email"` | `"email"` = legacy flow; `"entra"` = Microsoft sign-in only (login screen shows a single *Sign in with Microsoft* button) |
| `signIn.entra.tenantId` | string | — (**required** for `entra`) | Directory (tenant) ID from §2. Must be the tenant **GUID** — `common`/`organizations` are **not supported** (issuer validation is an exact match against the tenant-specific issuer) |
| `signIn.entra.clientId` | string | — (**required** for `entra`) | Application (client) ID from §2 |
| `signIn.entra.cloudInstance` | string | `"global"` | `global` / `usgov` (GCC High) / `china` (21Vianet) — selects the login host |
| `signIn.entra.adminRoles` | array of string | `["Helios.Admin"]` | `roles`-claim values granting the Admin tier |
| `signIn.entra.operatorRoles` | array of string | `["Helios.Operator"]` | `roles`-claim values granting the Operator tier |
| `signIn.entra.cleanupRoles` | array of string | `[]` (admins only) | `roles`-claim values granting the **Cleanup module** in addition to admins (§3); grants **no** device-action tier, and the Mac still needs access `role=Admin` |
| `signIn.entra.allowedGroupIds` | array of string | `[]` (off) | optional group-object-ID gate (§5) |
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
		<key>adminRoles</key>
		<array>
			<string>Helios.Admin</string>
		</array>
		<key>operatorRoles</key>
		<array>
			<string>Helios.Operator</string>
		</array>
		<!-- optional; empty/omitted = Cleanup stays admins-only (§3) -->
		<key>cleanupRoles</key>
		<array>
			<string>Helios.CleanupTech</string>
		</array>
		<!-- optional; empty/omitted = group gate OFF (recommended — see §5) -->
		<key>allowedGroupIds</key>
		<array/>
		<key>provisionJamfCredentials</key>
		<true/>
	</dict>
</dict>
```

For local testing on a dev Mac (no profile needed — the loader also reads the user-level
suite plist, see `docs/ConfigProfileMigration.md` §6):

```sh
defaults write com.herojoneslabs.helios.console.core signIn \
  '{ method = entra; entra = { tenantId = "12345678-0000-0000-0000-000000000000"; clientId = "12345678-1111-1111-1111-111111111111"; }; }'
```

A full manually-installable multi-payload profile for test Macs lives at
`Deployment/sample.mobileconfig` — add the `signIn` dict to its core payload. As always,
profile changes take effect at app **relaunch**.

Session behavior: after the first interactive sign-in, the session persists via the
**refresh token**; on **every launch** — and on **every idle-lock unlock** — the app
redeems it and **re-derives the tier** from the fresh token, so role/group revocation
takes effect at the next launch or unlock. With
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
| Microsoft sign-in **succeeds**, then Helios shows **"not authorized"** | Entra issued a token but it carries no role matching `adminRoles`/`operatorRoles`/`cleanupRoles` — user assigned to the app without a Helios role, role `value` typo, or config overrides don't match the manifest values | Assign the group **to a role**, not just to the app (§4); compare the manifest `value` strings (§3) against the delivered role lists (case-sensitive) |
| Sign-in refused with a groups-overage message | User is in >200 groups, so the token had `hasgroups`/`_claim_names` instead of a `groups` list; the app fails closed | Expected with `allowedGroupIds` set for heavily-grouped users — switch that user's gating to app roles, or clear `allowedGroupIds` (§5) |
| Login screen shows a **sign-in configuration error** instead of the Microsoft button ("signIn misconfigured") | `method = entra` but `tenantId` or `clientId` is missing/blank — the app deliberately blocks rather than falling back to email | Fix the core profile (§6), re-push, relaunch. Verify delivery: `defaults read com.herojoneslabs.helios.console.core signIn` |
| Token validation fails with an **issuer mismatch** ("The Microsoft identity token failed validation: issuer mismatch…") | `tenantId` is not the directory (tenant) ID **GUID** — e.g. `common` or `organizations` — so the token's tenant-specific issuer can never equal the expected issuer built from the config | Set `signIn.entra.tenantId` to the tenant GUID from the registration Overview (§2, §6); multi-tenant authority aliases are not supported |
| Old role/group still in effect after revocation | Sessions re-validate at launch and at idle-lock unlock, not live | Relaunch the app or let the idle lock engage and unlock (or revoke the user's Entra sessions and relaunch) — see §4/§6 |

---

## 9. Security model summary

Fail-closed rules, in one place:

- No `roles` claim match against `adminRoles` / `operatorRoles` / `cleanupRoles` →
  sign-in refused (never a default tier).
- A **cleanup-only** role match signs in at tier `None`: Cleanup module and read
  surfaces, **zero** tier-gated device actions. `cleanupRoles` defaults to empty —
  absent or delivered-empty grants nothing beyond admins.
- `allowedGroupIds` set and no `groups` intersection → refused.
- Groups-overage token (`hasgroups` / `_claim_names`) → refused, never resolved via Graph.
- `method = entra` with missing `tenantId`/`clientId` → sign-in blocked; **no** fallback
  to the email flow.
- Every launch — and every idle-lock unlock — re-validates: refresh token redeemed,
  tier re-derived from the fresh token — revocation is effective at the next launch
  or unlock.

What each layer does — and does not — protect against:

| Layer | Enforced by | Protects against | Does NOT protect against |
|---|---|---|---|
| Entra assignment + CA (§4, §7) | Microsoft, server-side, at token issuance | unassigned users, revoked users (at next validation), unmanaged devices (with a compliant-device CA policy) | what an *authorized* user can do once signed in |
| App tier check (§1, §6) | Helios, **client-side**, on the signed token's `roles` claim | Operators seeing Cleanup (unless granted via `cleanupRoles`) or destructive device actions; role-less users using the app | a tampered/patched client — it is UI/feature gating, not a server boundary |
| Machine config profiles + Jamf API role (see `docs/ConfigProfileMigration.md`) | MDM-forced managed preferences + Jamf Pro server-side API permissions | any user on that Mac exceeding what the Mac's access profile and the provisioned Jamf API role allow | mis-scoped profiles (over-scoping write-capable credentials is on you) |

The tier check is honest about what it is: **client-side feature gating on a
cryptographically signed token**. The authoritative boundary remains server-side — the
Mac's managed profiles (fail-closed access domain, device-action allow-list) and the
permissions of the Jamf API role behind the provisioned per-user client. Keep the
**paired-scoping rule** from `docs/ConfigProfileMigration.md` §3 in force: Operator-tier
users should be working on Macs scoped to read-only credential variants; the Entra role
alone must never be the only thing standing between a user and a write-capable API client.

---

*Sync points: the `signIn` keys above must match `schemas/Helios_Core_SCHEMA.json`, the
core-domain decoding in `HeliosConsole/Managers/Configuration/`, and the default role
values `Helios.Admin` / `Helios.Operator` baked into the app.*
