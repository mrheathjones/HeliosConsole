//
//  MDMConfiguration.swift
//  test
//
//  Created by heath on 1/19/26.
//


import Foundation

struct MDMConfiguration: Codable {
    let jamfURL: String
    let masterClientID: String
    let masterClientSecret: String
    let appTitle: String
    let appSubtitle: String
    let sidebarItems: [SidebarItemConfig]
    let requiredRoleName: String
    let supportURL: String?
    let localAdminUsername: String
    
    // Screen Share feature (enabled via Config Profile)
    // NOTE: The extension attribute name "EA_VPN_IP_ADDRESS" is currently hardcoded.
    // A future enhancement will make this configurable via Config Profile.
    let screenShareEnabled: Bool
    
    // Apple Business Manager API (optional)
    let abmClientId: String?
    let abmKeyId: String?
    let abmPrivateKey: String?

    // MARK: - Role-based access + Cleanup feature (Jamf stale-device cleanup)
    /// Operator role delivered by MDM (Admin / Support / User). The Cleanup
    /// feature is Admin-only. Absent → treated as Admin.
    let role: String?
    /// Stale threshold (days without check-in) used by Cleanup.
    let cleanupStaleDays: Int
    let cleanupDefaultStaticGroupID: String?
    let cleanupDefaultSiteID: String?

    // Jamf Protect (optional, gated)
    let protectEnabled: Bool
    let protectURL: String?
    let protectClientID: String?
    /// Jamf Protect API password, optionally delivered via the profile.
    /// Sensitive — managed-pref plists are world-readable; scope tightly.
    let protectPassword: String?

    // MARK: - Microsoft Entra (Graph) cleanup for Return to Service
    /// Preference domain (bundle identifier) that carries the Entra Graph
    /// credentials. The Helios profile only stores this pointer; the actual
    /// tenant/client/secret/PEM live in a separate managed-pref domain so the
    /// Entra secrets are not duplicated into the Helios domain. Absent → Entra
    /// cleanup is skipped.
    let entraCredentialDomain: String?
    /// Microsoft Entra tenant id (resolved from `entraCredentialDomain`).
    let entraTenantId: String?
    /// Entra app registration client id.
    let entraClientId: String?
    /// Entra app client secret — fallback auth when no certificate is present.
    let entraClientSecret: String?
    /// PEM (certificate + private key) for PS256 client-assertion auth
    /// (preferred). Sensitive — the source managed-pref plist is world-readable.
    let entraCertPEM: String?

    /// Whether Entra device cleanup can run: tenant + client id must be present
    /// along with at least one credential (certificate PEM or client secret).
    var isEntraConfigured: Bool {
        guard let tenant = entraTenantId, !tenant.isEmpty,
              let client = entraClientId, !client.isEmpty else {
            return false
        }
        let hasCert = (entraCertPEM?.isEmpty == false)
        let hasSecret = (entraClientSecret?.isEmpty == false)
        return hasCert || hasSecret
    }

    var isABMConfigured: Bool {
        guard let clientId = abmClientId, !clientId.isEmpty,
              let keyId = abmKeyId, !keyId.isEmpty,
              let privateKey = abmPrivateKey, !privateKey.isEmpty else {
            return false
        }
        return true
    }

    enum AppRole: String {
        case admin = "Admin"
        case support = "Support"
        case user = "User"
    }

    /// Resolves the operator role fail-closed: a missing, blank, or
    /// unrecognized value (including wrong case like "admin") is treated as
    /// the least-privileged `.user`, so the destructive Cleanup feature is
    /// never exposed by accident. Only the exact string "Admin" grants it.
    var appRole: AppRole {
        guard let role, let parsed = AppRole(rawValue: role) else { return .user }
        return parsed
    }

    /// Whether the Cleanup feature should be available to this operator.
    var isCleanupAdmin: Bool { appRole == .admin }

    init(
        jamfURL: String,
        masterClientID: String,
        masterClientSecret: String,
        appTitle: String,
        appSubtitle: String,
        sidebarItems: [SidebarItemConfig],
        requiredRoleName: String,
        supportURL: String?,
        localAdminUsername: String,
        screenShareEnabled: Bool,
        abmClientId: String?,
        abmKeyId: String?,
        abmPrivateKey: String?,
        role: String? = nil,
        cleanupStaleDays: Int = 90,
        cleanupDefaultStaticGroupID: String? = nil,
        cleanupDefaultSiteID: String? = nil,
        protectEnabled: Bool = false,
        protectURL: String? = nil,
        protectClientID: String? = nil,
        protectPassword: String? = nil,
        entraCredentialDomain: String? = nil,
        entraTenantId: String? = nil,
        entraClientId: String? = nil,
        entraClientSecret: String? = nil,
        entraCertPEM: String? = nil
    ) {
        self.jamfURL = jamfURL
        self.masterClientID = masterClientID
        self.masterClientSecret = masterClientSecret
        self.appTitle = appTitle
        self.appSubtitle = appSubtitle
        self.sidebarItems = sidebarItems
        self.requiredRoleName = requiredRoleName
        self.supportURL = supportURL
        self.localAdminUsername = localAdminUsername
        self.screenShareEnabled = screenShareEnabled
        self.abmClientId = abmClientId
        self.abmKeyId = abmKeyId
        self.abmPrivateKey = abmPrivateKey
        self.role = role
        self.cleanupStaleDays = cleanupStaleDays
        self.cleanupDefaultStaticGroupID = cleanupDefaultStaticGroupID
        self.cleanupDefaultSiteID = cleanupDefaultSiteID
        self.protectEnabled = protectEnabled
        self.protectURL = protectURL
        self.protectClientID = protectClientID
        self.protectPassword = protectPassword
        self.entraCredentialDomain = entraCredentialDomain
        self.entraTenantId = entraTenantId
        self.entraClientId = entraClientId
        self.entraClientSecret = entraClientSecret
        self.entraCertPEM = entraCertPEM
    }
    
    struct SidebarItemConfig: Codable, Identifiable {
        let id: String
        let icon: String
        let title: String
        let isEnabled: Bool
        let order: Int
        
        init(id: String, icon: String, title: String, isEnabled: Bool = true, order: Int) {
            self.id = id
            self.icon = icon
            self.title = title
            self.isEnabled = isEnabled
            self.order = order
        }
    }
    
    // Default configuration (fallback if no MDM profile)
    static let `default` = MDMConfiguration(
        jamfURL: "https://myorg.jamfcloud.com",
        masterClientID: "your-master-client-id",
        masterClientSecret: "your-master-client-secret",
        appTitle: "Helios",
        appSubtitle: "Console",
        sidebarItems: [
            SidebarItemConfig(id: "dashboard", icon: "chart.bar.fill", title: "Dashboard", order: 1),
            SidebarItemConfig(id: "enterprise", icon: "building.2.fill", title: "Enterprise", order: 2),
            SidebarItemConfig(id: "groundcontrol", icon: "apps.iphone", title: "GroundControl", order: 3),
            SidebarItemConfig(id: "depsearch", icon: "magnifyingglass", title: "DEP Search", order: 4),
            SidebarItemConfig(id: "announcements", icon: "bolt.fill", title: "Announcements", order: 5),
            SidebarItemConfig(id: "settings", icon: "gearshape.fill", title: "Settings", order: 6)
        ],
        requiredRoleName: "SVC_WATCHER_USER",
        supportURL: "https://support.yourcompany.com",
        localAdminUsername: "macadmin",
        screenShareEnabled: false,
        abmClientId: nil,
        abmKeyId: nil,
        abmPrivateKey: nil,
        // No-config (local dev) fallback shows Cleanup. Real deployments must
        // set role=Admin in the profile; an absent key fails closed (hidden).
        role: "Admin"
    )
}
