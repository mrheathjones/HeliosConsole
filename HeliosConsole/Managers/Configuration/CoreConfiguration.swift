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
        var effectiveConnectionTimeout: Int { connectionTimeout ?? 30 }

        /// Request timeout with the documented default applied.
        var effectiveRequestTimeout: Int { requestTimeout ?? 60 }

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
        }

        /// Fail-safe cloud resolution: missing/unrecognized → global.
        var effectiveCloudInstance: CloudInstance {
            let raw = cloudInstance?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            return CloudInstance(rawValue: raw) ?? .global
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
