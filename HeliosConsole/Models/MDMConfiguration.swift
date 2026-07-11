//
//  MDMConfiguration.swift
//  HeliosConsole
//
//  Aggregated app-facing configuration, composed from the five managed
//  preference domains (com.herojoneslabs.helios.console.core / .credentials / .access /
//  .features / .ui — see docs/ConfigProfileMigration.md). The flat fields
//  below are the stable consumer surface; the optional domain-model
//  properties expose the newer, not-yet-flattened surface (device actions,
//  feature modules, authentication, UI extras).
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
    
    // DEPRECATED: the access domain's deviceActions allow-list is
    // authoritative for the screenShare action; no view reads this flag
    // anymore. Kept only until the core key is removed in a later major.
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

    // MARK: - New (not-yet-flattened) domain surface
    // Parsed and exposed by the config layer; per-view enforcement status is
    // tracked in docs/ConfigProfileMigration.md. All optional — absent when
    // the delivering domain/profile is absent.

    /// Per-action device-command allow-list (access domain).
    let deviceActions: AccessConfiguration.DeviceActionsSettings?

    /// Feature modules & tuning (features domain, whole model).
    let features: FeaturesConfiguration?

    /// Sign-in behavior preferences (ui domain).
    let authentication: AuthenticationSettings?

    /// Full branding/UX section (ui domain) — companyName, logoURL,
    /// accentColor, defaultColorScheme, show* switches beyond the flattened
    /// appTitle/appSubtitle/supportURL.
    let userInterfaceExtras: UserInterfaceSettings?

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

    /// Whether the required connection settings were delivered: core-domain
    /// serverURL + masterClientID non-empty AND credentials-domain
    /// jamfProClientSecret non-empty. The manager logs exactly which
    /// domain/keys are missing when this is false.
    var isConfigured: Bool {
        !jamfURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !masterClientID.trimmingCharacters(in: .whitespaces).isEmpty
            && !masterClientSecret.trimmingCharacters(in: .whitespaces).isEmpty
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

    // MARK: - Device action policies (strict fail-closed)

    /// Policy for the computer (macOS) Actions menu: access-domain
    /// allow-list + features-domain enableAPIActions kill switch. No
    /// allow-list delivered → DeviceActionPolicy denies everything and the
    /// Actions menu is hidden. NOTE: once an allow-list is delivered it is
    /// authoritative for Screen Share too — the legacy core-domain
    /// `jamfPro.screenShareEnabled` key is deprecated and ignored.
    var computerActionPolicy: DeviceActionPolicy {
        DeviceActionPolicy(
            grants: deviceActions?.computer?.grantsByID,
            apiActionsEnabled: features?.effectiveComputers.effectiveEnableAPIActions ?? true
        )
    }

    /// Policy for mobile-device actions. No mobile actions menu exists yet
    /// (MobileDeviceView's "More" button is a stub); any future menu must be
    /// built from this policy from day one.
    var mobileDeviceActionPolicy: DeviceActionPolicy {
        DeviceActionPolicy(
            grants: deviceActions?.mobileDevice?.grantsByID,
            apiActionsEnabled: features?.effectiveMobileDevices.effectiveEnableAPIActions ?? true
        )
    }

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
        entraCertPEM: String? = nil,
        deviceActions: AccessConfiguration.DeviceActionsSettings? = nil,
        features: FeaturesConfiguration? = nil,
        authentication: AuthenticationSettings? = nil,
        userInterfaceExtras: UserInterfaceSettings? = nil
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
        self.deviceActions = deviceActions
        self.features = features
        self.authentication = authentication
        self.userInterfaceExtras = userInterfaceExtras
    }

    // MARK: - Composition from the five managed domains

    /// Resolved Entra Graph credentials (pointer domain → values), produced
    /// by the aggregation layer's resolver from `CoreConfiguration.entra`.
    struct ResolvedEntraCredentials {
        var domain: String?
        var tenantId: String?
        var clientId: String?
        var clientSecret: String?
        var certPEM: String?

        static let none = ResolvedEntraCredentials()
    }

    /// Composes the flat consumer surface from the five domain models.
    /// Any absent domain contributes its documented defaults; validity
    /// (isConfigured) is judged by the aggregation layer, never here.
    init(
        core: CoreConfiguration?,
        credentials: CredentialsConfiguration?,
        access: AccessConfiguration?,
        features: FeaturesConfiguration?,
        ui: UserInterfaceConfiguration?,
        resolvedEntra: ResolvedEntraCredentials = .none
    ) {
        let jamfPro = core?.jamfPro
        let uiSettings = ui?.userInterface

        // ABM identity is only surfaced when the block is delivered AND
        // enabled (parity with the pre-split loader); the private key rides
        // along from the credentials domain.
        var abmClientId: String? = nil
        var abmKeyId: String? = nil
        var abmPrivateKey: String? = nil
        if let abm = core?.appleBusinessManager, abm.effectiveEnabled {
            abmClientId = abm.clientID
            abmKeyId = abm.keyID
            abmPrivateKey = credentials?.abmPrivateKey
        }

        // Managed sidebar override: usable ui-domain items win; otherwise
        // keep the built-in default sidebar.
        let managedSidebar = (ui?.effectiveSidebarItems ?? [])
            .filter { $0.isUsable }
            .map {
                SidebarItemConfig(
                    id: $0.effectiveID,
                    icon: $0.effectiveIcon,
                    title: $0.effectiveTitle,
                    isEnabled: $0.effectiveIsEnabled,
                    order: $0.effectiveOrder
                )
            }
        let sidebarItems = managedSidebar.isEmpty
            ? MDMConfiguration.defaultSidebarItems
            : managedSidebar

        self.init(
            jamfURL: jamfPro?.serverURL ?? "",
            masterClientID: jamfPro?.masterClientID ?? "",
            masterClientSecret: credentials?.jamfProClientSecret ?? "",
            appTitle: uiSettings?.effectiveAppTitle ?? "Helios",
            appSubtitle: uiSettings?.effectiveAppSubtitle ?? "Console",
            sidebarItems: sidebarItems,
            requiredRoleName: jamfPro?.effectiveRequiredRoleName ?? "SVC_WATCHER_USER",
            supportURL: uiSettings?.effectiveSupportURL,
            localAdminUsername: core?.localAdministration?.effectiveUsername ?? "macadmin",
            screenShareEnabled: jamfPro?.effectiveScreenShareEnabled ?? false,
            abmClientId: abmClientId,
            abmKeyId: abmKeyId,
            abmPrivateKey: abmPrivateKey,
            // Fail-closed: absent access domain → nil role → .user.
            role: access?.role,
            cleanupStaleDays: access?.effectiveCleanup.effectiveStaleDays ?? 90,
            cleanupDefaultStaticGroupID: access?.cleanup?.defaultStaticGroupID,
            cleanupDefaultSiteID: access?.cleanup?.defaultSiteID,
            protectEnabled: core?.jamfProtect?.effectiveEnabled ?? false,
            protectURL: core?.jamfProtect?.url,
            protectClientID: core?.jamfProtect?.clientID,
            protectPassword: credentials?.jamfProtectPassword,
            entraCredentialDomain: resolvedEntra.domain,
            entraTenantId: resolvedEntra.tenantId,
            entraClientId: resolvedEntra.clientId,
            entraClientSecret: resolvedEntra.clientSecret,
            entraCertPEM: resolvedEntra.certPEM,
            deviceActions: access?.deviceActions,
            features: features,
            authentication: ui?.authentication,
            userInterfaceExtras: uiSettings
        )
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
    
    /// The app's built-in sidebar, used when no usable managed override is
    /// delivered by the ui domain.
    static let defaultSidebarItems: [SidebarItemConfig] = [
        SidebarItemConfig(id: "dashboard", icon: "chart.bar.fill", title: "Dashboard", order: 1),
        SidebarItemConfig(id: "enterprise", icon: "building.2.fill", title: "Enterprise", order: 2),
        SidebarItemConfig(id: "groundcontrol", icon: "apps.iphone", title: "GroundControl", order: 3),
        SidebarItemConfig(id: "depsearch", icon: "magnifyingglass", title: "DEP Search", order: 4),
        SidebarItemConfig(id: "announcements", icon: "bolt.fill", title: "Announcements", order: 5),
        SidebarItemConfig(id: "settings", icon: "gearshape.fill", title: "Settings", order: 6)
    ]

    // Default configuration (fallback when no managed domain is delivered).
    // Deliberately EMPTY connection strings — no placeholder values that a
    // consumer could mistake for real configuration; validity checks are
    // plain non-empty tests.
    static let `default` = MDMConfiguration(
        jamfURL: "",
        masterClientID: "",
        masterClientSecret: "",
        appTitle: "Helios",
        appSubtitle: "Console",
        sidebarItems: defaultSidebarItems,
        requiredRoleName: "SVC_WATCHER_USER",
        supportURL: nil,
        localAdminUsername: "macadmin",
        screenShareEnabled: false,
        abmClientId: nil,
        abmKeyId: nil,
        abmPrivateKey: nil,
        // DEBUG keeps Cleanup visible for local dev without profiles; a
        // RELEASE build with no access profile fails closed (role nil →
        // .user, Cleanup hidden).
        role: { () -> String? in
            #if DEBUG
            return "Admin"
            #else
            return nil
            #endif
        }()
    )
}
