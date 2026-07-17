//
//  CoreConfiguration.swift
//  HeliosConsole
//
//  Helios Console — Core (connection & integrations tier of the 5-domain
//  config split). Delivered via Jamf Pro > Configuration Profiles >
//  Application & Custom Settings as its own profile, scoped to ALL managed
//  Macs running Helios.
//
//  Preference Domain MUST match the domain Helios reads:
//      com.herojoneslabs.helios.console.core
//  (Matches `CoreConfiguration.domain` below, the
//   schemas/Helios_Core_SCHEMA.json `$id`, and the domain table in
//   docs/ConfigProfileMigration.md — keep all three in sync.)
//
//  Decoded by ManagedDomainLoader: the domain's top-level keys are read out
//  of UserDefaults(suiteName: CoreConfiguration.domain) into a [String: Any],
//  then run through PropertyListSerialization → PropertyListDecoder. Every
//  stored property is optional so a missing key — or an entirely absent
//  profile — never fails the domain decode. Defaults live in the computed
//  `effective*` accessors, never in decode.
//
//  This domain carries NO secrets: the Jamf Pro client secret, ABM private
//  key, and Jamf Protect password live in com.herojoneslabs.helios.console.credentials,
//  and the `entra` block only POINTS at a separate admin-chosen credential
//  domain (pointer semantics preserved from the pre-split profile — deployed
//  plists rely on them).
//

import Foundation

/// Managed connection & integration settings for Helios Console, delivered
/// by the `com.herojoneslabs.helios.console.core` configuration profile.
///
/// Non-secret tier: Jamf Pro server + master client identity, optional Apple
/// Business Manager and Jamf Protect connections, the Microsoft Entra
/// credential pointer, and local administration settings. The secrets that
/// pair with these identities live in `com.herojoneslabs.helios.console.credentials`.
struct CoreConfiguration: Codable {

    /// The managed-preference domain this model is decoded from.
    /// Sync points: schemas/Helios_Core_SCHEMA.json `$id` and
    /// docs/ConfigProfileMigration.md.
    static let domain = "com.herojoneslabs.helios.console.core"

    /// Informational schema version (loader logs it, nothing else reads it).
    var configurationVersion: String?

    /// Jamf Pro server connection and master API client identity. Required
    /// for the app to be considered configured — validity is enforced at the
    /// aggregation layer (`MDMConfigurationManager.isConfigured`), never by
    /// decode failure.
    var jamfPro: JamfProSettings?

    /// Optional Apple Business Manager API connection (identity only; the
    /// PEM private key arrives via the credentials domain).
    var appleBusinessManager: ABMSettings?

    /// Optional Jamf Protect tenant connection (identity only; the API
    /// password arrives via the credentials domain or in-app + Keychain).
    var jamfProtect: JamfProtectSettings?

    /// Optional Microsoft Entra credential POINTER for Return to Service
    /// cleanup. Points at a separate managed-preferences domain that holds
    /// the Graph credentials; no Entra secrets live in this domain.
    var entra: EntraPointerSettings?

    /// Optional interactive sign-in configuration (`signIn` block): how
    /// users sign into Helios itself — the built-in email flow (default)
    /// or Microsoft Entra ID via a separate PUBLIC-client app registration.
    /// Distinct from `entra` above, which carries app-only cleanup
    /// credentials. An absent block keeps the email flow unchanged.
    var signIn: SignInSettings?

    /// Local administrator account settings (LAPS lookup in DeviceView).
    var localAdministration: LocalAdminSettings?

    // MARK: - Effective accessors (defaults live here, never in decode)

    /// Schema version with the documented default applied.
    var effectiveConfigurationVersion: String {
        let version = configurationVersion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return version.isEmpty ? "2.0" : version
    }

    /// The core-domain half of the app-level configured check: serverURL and
    /// masterClientID both delivered non-empty. The aggregation layer's
    /// `isConfigured` combines this with the credentials domain's
    /// `jamfProClientSecret` being non-empty.
    var isJamfProConnectionConfigured: Bool {
        let url = jamfPro?.serverURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let clientID = jamfPro?.masterClientID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !url.isEmpty && !clientID.isEmpty
    }

    // MARK: - Jamf Pro

    /// `jamfPro` block: server connection and master API client identity.
    /// The paired OAuth client secret is `jamfProClientSecret` in the
    /// credentials domain — deliberately NOT part of this model.
    struct JamfProSettings: Codable {

        /// Full HTTPS base URL, no trailing slash
        /// (e.g. `https://yourorg.jamfcloud.com`). Required in the profile.
        var serverURL: String?

        /// OAuth `client_id` of the Jamf API Client used by Helios.
        /// Not secret. Required in the profile.
        var masterClientID: String?

        /// Name of the Jamf API Role used when provisioning per-user API
        /// clients. Load-bearing — provisioning targets this role name.
        var requiredRoleName: String?

        /// DEPRECATED — the access domain's deviceActions allow-list is
        /// authoritative for the screenShare action; this key is ignored by
        /// the app and will be removed in a later major.
        var screenShareEnabled: Bool?

        /// URLSession connection timeout in seconds.
        var connectionTimeout: Int?

        /// URLSession request timeout in seconds.
        var requestTimeout: Int?

        /// Name of the Jamf Extension Attribute holding a device's VPN IP,
        /// used by Screen Share (and the device IP card) to prefer the VPN
        /// address. Org-specific — absent/empty disables the VPN-IP lookup
        /// and the app uses the reported LAN IP.
        var vpnIPExtensionAttributeName: String?

        /// Lifetime in days for per-user Jamf API client credentials
        /// provisioned by the app (expiry forces re-provisioning).
        var userCredentialLifetimeDays: Int?

        /// Seconds to wait for a device to acknowledge an ERASE_DEVICE
        /// command. Governs EVERY erase (Erase Device and Return to
        /// Service) — the acknowledgment wait is mandatory by design, and
        /// no cleanup step runs without acknowledgment.
        var eraseAckTimeoutSeconds: Int?

        /// Seconds between acknowledgment polls while waiting for an erase
        /// (see `eraseAckTimeoutSeconds`).
        var eraseAckPollIntervalSeconds: Int?

        /// Required role name with the documented default applied. The
        /// default is a NEUTRAL name — deliver your org's real API Role
        /// name in the profile.
        var effectiveRequiredRoleName: String {
            let name = requiredRoleName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? "HeliosConsoleAPIRole" : name
        }

        /// DEPRECATED Screen Share flag (see `screenShareEnabled`).
        var effectiveScreenShareEnabled: Bool { screenShareEnabled ?? false }

        /// Connection timeout with the documented default applied.
        /// Clamped 5...600 s — a profile typo (0, negative, huge) must
        /// never brick every network call app-wide.
        var effectiveConnectionTimeout: Int { min(max(connectionTimeout ?? 30, 5), 600) }

        /// Request timeout with the documented default applied.
        /// Clamped 5...3600 s (see effectiveConnectionTimeout).
        var effectiveRequestTimeout: Int { min(max(requestTimeout ?? 60, 5), 3600) }

        /// VPN-IP extension attribute — nil when not configured (feature off).
        var effectiveVPNIPExtensionAttributeName: String? {
            let name = vpnIPExtensionAttributeName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? nil : name
        }

        /// Credential lifetime with the documented default applied
        /// (clamped to 1...365 days).
        var effectiveUserCredentialLifetimeDays: Int {
            min(max(userCredentialLifetimeDays ?? 90, 1), 365)
        }

        /// Erase-acknowledgment timeout with the documented default applied
        /// (clamped to 30...1800 s). Governs EVERY erase — Erase Device and
        /// Return to Service alike. The ack wait is mandatory by design:
        /// no cleanup step (Jamf record or Entra object deletion) runs
        /// without acknowledgment.
        var effectiveEraseAckTimeoutSeconds: Int {
            min(max(eraseAckTimeoutSeconds ?? 180, 30), 1800)
        }

        /// Erase-acknowledgment poll interval with the documented default
        /// applied (clamped to 5...120 s). Applies to every erase alongside
        /// `effectiveEraseAckTimeoutSeconds`.
        var effectiveEraseAckPollIntervalSeconds: Int {
            min(max(eraseAckPollIntervalSeconds ?? 15, 5), 120)
        }
    }

    // MARK: - Apple Business Manager

    /// `appleBusinessManager` block: ABM API client identity. The PEM
    /// private key is `abmPrivateKey` in the credentials domain — ABM is
    /// considered configured only when clientID, keyID, AND that key are all
    /// present (cross-domain check at the aggregation layer).
    struct ABMSettings: Codable {

        /// Whether the ABM integration is enabled.
        var enabled: Bool?

        /// ABM API client identifier. Not secret.
        var clientID: String?

        /// Key ID of the ABM API private key. Not secret.
        var keyID: String?

        /// Which Apple service hosts the org: "business" (Apple Business
        /// Manager) or "school" (Apple School Manager). Same API, same
        /// tokens — different host.
        var serviceType: String?

        /// Enabled flag — absent key means disabled.
        var effectiveEnabled: Bool { enabled ?? false }

        enum ServiceType: String {
            case business
            case school

            /// AxM API base URL for this service.
            var apiBaseURL: String {
                switch self {
                case .business: return "https://api-business.apple.com/v1"
                case .school: return "https://api-school.apple.com/v1"
                }
            }

            /// OAuth scope paired with the host — ASM tokens must be
            /// requested with school.api or the API rejects them.
            var oauthScope: String {
                switch self {
                case .business: return "business.api"
                case .school: return "school.api"
                }
            }
        }

        /// Fail-safe service resolution: missing/unrecognized → business.
        var effectiveServiceType: ServiceType {
            let raw = serviceType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            return ServiceType(rawValue: raw) ?? .business
        }
    }

    // MARK: - Jamf Protect

    /// `jamfProtect` block: Protect tenant connection identity. The API
    /// password MAY arrive as `jamfProtectPassword` in the credentials
    /// domain (locks the in-app field); otherwise the app keeps today's
    /// in-app entry + Keychain (`com.herojoneslabs.helios.console.protect.password`) chain.
    struct JamfProtectSettings: Codable {

        /// Whether the Jamf Protect integration is enabled.
        var enabled: Bool?

        /// Full HTTPS tenant URL
        /// (e.g. `https://yourorg.protect.jamfcloud.com`).
        var url: String?

        /// Jamf Protect API client identifier. Not secret.
        var clientID: String?

        /// Enabled flag — absent key means disabled.
        var effectiveEnabled: Bool { enabled ?? false }
    }

    // MARK: - Microsoft Entra credential pointer

    /// `entra` block: POINTER to a separate admin-chosen managed-preferences
    /// domain that holds the Entra Graph credentials (tenant id, client id,
    /// and a certificate PEM string and/or client secret). Semantics are
    /// identical to the pre-split profile — deployed plists rely on them.
    ///
    /// Resolution (performed by the aggregation layer, unchanged): Helios
    /// (unsandboxed) reads `UserDefaults(suiteName: credentialDomain)`. Each
    /// `*Key` override names the EXACT key to read; when an override is
    /// omitted the resolver falls back through the alias lists below (which
    /// must stay in sync with the resolver and the schema descriptions):
    ///   - tenant id:     entra_tenant_id, tenantID, tenant_id, TenantID,
    ///                    entra_tenant
    ///   - client id:     entra_client_id, clientID, client_id, ClientID,
    ///                    entra_client
    ///   - client secret: entra_client_secret, clientSecret, client_secret,
    ///                    ClientSecret
    ///   - cert PEM:      entra_cert_pem, entra_certificate, cert_pem,
    ///                    certPEM, entra_cert, certificate_pem
    struct EntraPointerSettings: Codable {

        /// Preference domain (bundle identifier) of the separate payload
        /// holding the Entra Graph credentials. Required in the block when
        /// the block is present; an absent block disables Entra cleanup.
        var credentialDomain: String?

        /// Exact key name for the tenant id in the credential domain.
        var tenantIdKey: String?

        /// Exact key name for the client id in the credential domain.
        var clientIdKey: String?

        /// Exact key name for the client secret in the credential domain.
        var clientSecretKey: String?

        /// Exact key name for the certificate PEM string in the credential
        /// domain. Must be the PEM string itself, not a file path.
        var certPEMKey: String?

        /// Azure cloud instance: "global" (default), "usgov" (Azure
        /// Government / GCC High), or "china" (Azure operated by 21Vianet).
        /// Selects the token authority and Graph API hosts.
        var cloudInstance: String?

        /// Whether a usable (non-empty) credential domain pointer was
        /// delivered — the block is inert without one.
        var hasCredentialDomain: Bool {
            !(credentialDomain?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }

        enum CloudInstance: String {
            case global
            case usgov
            case china

            /// OAuth token authority host.
            var authorityHost: String {
                switch self {
                case .global: return "login.microsoftonline.com"
                case .usgov: return "login.microsoftonline.us"
                case .china: return "login.chinacloudapi.cn"
                }
            }

            /// Microsoft Graph API host (also used for the token scope).
            var graphHost: String {
                switch self {
                case .global: return "graph.microsoft.com"
                case .usgov: return "graph.microsoft.us"
                case .china: return "microsoftgraph.chinacloudapi.cn"
                }
            }

            /// Shared fail-safe resolution from a raw profile value:
            /// missing/unrecognized → global.
            static func resolve(_ raw: String?) -> CloudInstance {
                let normalized = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
                return CloudInstance(rawValue: normalized) ?? .global
            }
        }

        /// Fail-safe cloud resolution: missing/unrecognized → global.
        var effectiveCloudInstance: CloudInstance {
            CloudInstance.resolve(cloudInstance)
        }
    }

    // MARK: - Interactive sign-in

    /// `signIn` block: how users sign INTO Helios itself. Distinct from the
    /// `entra` block above — that one POINTS at app-only Graph credentials
    /// for Return to Service cleanup; this one configures the INTERACTIVE
    /// user OAuth flow against a separate PUBLIC-client Entra app
    /// registration (which has no client secret, ever, by design).
    /// Absent block → the built-in email sign-in flow, unchanged.
    struct SignInSettings: Codable {

        /// Sign-in method: "email" (default) or "entra", matched
        /// case-insensitively. FAIL-CLOSED direction: when "entra" is
        /// selected but misconfigured (missing tenant/client id), the app
        /// shows a configuration-error state — it NEVER silently falls
        /// back to the weaker email flow.
        var method: String?

        /// Entra ID interactive sign-in settings; required in practice
        /// when `method == "entra"`.
        var entra: EntraSignInSettings?
    }

    /// `signIn.entra` block: PUBLIC-client Entra app registration for the
    /// interactive user sign-in flow. Carries NO secrets, ever — a public
    /// client has none. Capabilities are granted by matching the token's
    /// roles claim against the role names defined in the ACCESS domain's
    /// `roles` block (no role names live here); sign-in restriction should
    /// ALSO be enforced Entra-side ("Assignment required" on the enterprise
    /// application) — the client-side checks are a UX gate, not a security
    /// boundary on their own.
    struct EntraSignInSettings: Codable {

        /// Entra tenant id (GUID). Required for Entra sign-in.
        var tenantId: String?

        /// Application (client) id of the PUBLIC-client app registration.
        /// Not secret — and no secret is ever paired with it.
        var clientId: String?

        /// Azure cloud instance: "global" (default), "usgov", or "china".
        /// Reuses the cleanup pointer's `CloudInstance` host mapping.
        var cloudInstance: String?

        /// Optional extra client-side check: Entra group OBJECT ids the
        /// user must be a member of (token groups claim). Empty/absent =
        /// no group check. Prefer app roles — the groups claim is subject
        /// to Entra's overage limit on large memberships.
        var allowedGroupIds: [String]?

        /// After Entra sign-in, still provision the per-user Jamf API
        /// client from the verified email (same provisioning the email
        /// flow performs).
        var provisionJamfCredentials: Bool?

        /// Fail-safe cloud resolution: missing/unrecognized → global.
        /// Reuses the cleanup pointer's `CloudInstance` mapping so both
        /// Entra features agree on hosts per cloud.
        var effectiveCloudInstance: EntraPointerSettings.CloudInstance {
            EntraPointerSettings.CloudInstance.resolve(cloudInstance)
        }

        /// Group-id allow-list; empty = no group check (default).
        var effectiveAllowedGroupIds: [String] {
            Self.normalizedList(allowedGroupIds, default: [])
        }

        /// Per-user Jamf provisioning flag with the documented default
        /// applied (default true).
        var effectiveProvisionJamfCredentials: Bool { provisionJamfCredentials ?? true }

        /// Trims each entry and drops empties. nil (key absent) → default;
        /// a delivered array — even one that trims to empty — is honored.
        private static func normalizedList(_ values: [String]?, default defaults: [String]) -> [String] {
            guard let values else { return defaults }
            return values
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
    }

    // MARK: - Local administration

    /// `localAdministration` block: the managed local admin account whose
    /// LAPS password Helios looks up (DeviceView).
    struct LocalAdminSettings: Codable {

        /// Whether local administration features are enabled.
        var enabled: Bool?

        /// Short name of the managed local administrator account.
        var username: String?

        /// Enabled flag with the documented default applied (default true).
        var effectiveEnabled: Bool { enabled ?? true }

        /// Local admin username with the documented default applied.
        var effectiveUsername: String {
            let name = username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? "macadmin" : name
        }
    }
}
