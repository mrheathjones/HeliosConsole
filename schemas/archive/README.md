# Archived schemas (superseded — do not deploy)

These schemas targeted the old **single-profile** managed configuration model (one
monolithic payload in the app's bundle-id preference domain `com.helios.console`). As of
2026-07-10 (`feature/config-domain-split`), Helios Console reads managed configuration
from **five separate preference domains**, each with its own schema in `schemas/`:

| Domain | Schema |
|---|---|
| `com.herojoneslabs.helios.console.core` | `../Helios_Core_SCHEMA.json` |
| `com.herojoneslabs.helios.console.credentials` | `../Helios_Credentials_SCHEMA.json` |
| `com.herojoneslabs.helios.console.access` | `../Helios_Access_SCHEMA.json` |
| `com.herojoneslabs.helios.console.features` | `../Helios_Features_SCHEMA.json` |
| `com.herojoneslabs.helios.console.ui` | `../Helios_UI_SCHEMA.json` |

(Domain strings reflect the 2026-07 bundle-ID rebrand `com.helios.console` →
`com.herojoneslabs.helios.console`; the old strings below are kept verbatim as the
historical record of what these archived schemas targeted.)

Migration guide: `../../docs/ConfigProfileMigration.md`. The cutover is HARD — 2.x apps
never read the old monolithic domain, so profiles built from these archived schemas do
nothing on 2.x.

## Contents

- **`Helios_Console_SCHEMA_v3.json`** — v3 of the monolithic `com.helios.console` schema.
  Superseded by the five schemas above. (Its immediate successor,
  `Deployment/HeliosConsole_SCHEMA.json`, was deleted on the same branch; see git history.)
- **`Helios_Console_SCHEMA_EntraID_v1.txt`** — an earlier draft of the monolithic schema
  that additionally described an **`entraID` user-login block and a `whatsNew` in-console
  block. Neither was ever implemented in the app**, and both are recorded as OUT OF SCOPE
  for the domain split — they were deliberately not carried into the new schemas. The
  draft's Entra Graph *cleanup* pointer idea did ship, in its final form as the `entra`
  block of `com.herojoneslabs.helios.console.core`.

## Still live (NOT archived)

- `../Helios_Announcements_SCHEMA.json` — now `com.herojoneslabs.helios.console.announcements`
  (same schema and keys; the domain string was renamed by the 2026-07 bundle-ID rebrand, so
  the Jamf profile must be re-created under the new domain — see
  `../../docs/ConfigProfileMigration.md` §9).
- `../JSON_SCHEMA/What's New/Whats_New_SCHEMA_v1.json` — separate domain, out of scope.
- `../JSON_SCHEMA/Auth/Helios_Entra_Graph_Credentials_SCHEMA_v1.json` — still the target
  of the `entra.credentialDomain` pointer in the core domain.
