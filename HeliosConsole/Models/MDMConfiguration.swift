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

    // Network tuning (core domain jamfPro.connectionTimeout /
    // jamfPro.requestTimeout) — consumed via NetworkTuning at every
    // URLRequest/URLSession construction site.
    let connectionTimeoutSeconds: Int
    let requestTimeoutSeconds: Int

    // Erase-acknowledgment tuning (core domain jamfPro.eraseAckTimeoutSeconds /
    // jamfPro.eraseAckPollIntervalSeconds) — applied to EVERY erase (Erase
    // Device and Return to Service). The ack wait is mandatory by design;
    // no cleanup step runs without acknowledgment.
    let eraseAckTimeoutSeconds: Int
    let eraseAckPollIntervalSeconds: Int

    // DEPRECATED: the access domain's deviceActions allow-list is
    // authoritative for the screenShare action; no view reads this flag
    // anymore. Kept only until the core key is removed in a later major.
    let screenShareEnabled: Bool

    /// Jamf Extension Attribute name holding a device's VPN IP (core
    /// jamfPro.vpnIPExtensionAttributeName). nil = VPN-IP lookup disabled;
    /// Screen Share and the IP card use the reported LAN IP.
    let vpnIPExtensionAttribute: String?

    /// Lifetime (days) for per-user Jamf API credentials provisioned by the
    /// app (core jamfPro.userCredentialLifetimeDays, default 90).
    let userCredentialLifetimeDays: Int

    /// AxM API base URL (core appleBusinessManager.serviceType:
    /// business → api-business.apple.com, school → api-school.apple.com).
    let abmAPIBaseURL: String

    /// OAuth scope matching abmAPIBaseURL (business.api / school.api).
    let abmOAuthScope: String

    /// Azure endpoints for the Entra cleanup flow (core entra.cloudInstance:
    /// global / usgov / china).
    let entraAuthorityHost: String
    let entraGraphHost: String
    
    // Apple Business Manager API (optional)
    let abmClientId: String?
    let abmKeyId: String?
    let abmPrivateKey: String?

    // MARK: - Role-based access + Cleanup feature (Jamf stale-device cleanup)
    /// This Mac's role name, delivered by MDM in the access domain's `role`
    /// key. A FREE-FORM string naming a key in `roleDefinitions` — the app
    /// defines no roles of its own. Read it through `mdmRoleName` (trimmed);
    /// a value matching no definition grants nothing (fail-closed).
    let role: String?

    /// NAME INDEX over the access domain's `roles` array, built once at
    /// composition by `roleIndex(from:)` so lookup stays O(1). The value is a
    /// LIST because duplicate names are legal and UNION together — see
    /// `roleIndex(from:)` for why. `[:]` when the domain or the block is
    /// absent — in which case EVERY user resolves to `UserCapabilities.none`.
    /// Resolve through `capabilities(forRoleNames:)`, never by hand.
    let roleDefinitions: [String: [AccessConfiguration.RoleDefinition]]
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

    /// Interactive sign-in configuration (core domain `signIn` block) —
    /// how users sign into the app itself: built-in email flow (default)
    /// or Microsoft Entra ID via a separate PUBLIC-client app registration.
    /// Distinct from the app-only `entra*` cleanup credentials above.
    /// Consumed via the `signInMethod` / `entraSignIn*` accessors below.
    let signIn: CoreConfiguration.SignInSettings?

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

    // MARK: - Roles & capabilities (profile-defined; strict fail-closed)

    /// This Mac's role name from the access domain's `role` key, trimmed.
    /// `""` when absent. Used as the identity's role name ONLY when Entra
    /// sign-in is not configured — the Entra roles claim wins when it is.
    var mdmRoleName: String {
        role?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Resolves capabilities for a set of role names — the Entra roles claim
    /// under Entra sign-in, or `[mdmRoleName]` otherwise.
    ///
    /// Matching is EXACT and CASE-SENSITIVE: "Helios.Admin" and
    /// "helios.admin" are different roles. Names matching no definition
    /// contribute nothing (they are not an error — an Entra tenant may
    /// assign roles this app has never heard of). When no name matches, the
    /// result is `.none` — fail-closed, by construction of `union([])`.
    ///
    /// A user holding several defined roles gets the UNION of their
    /// capabilities — as does a user holding ONE name that the profile
    /// defines more than once (see `roleIndex(from:)`).
    func capabilities(forRoleNames names: [String]) -> UserCapabilities {
        let definitions = roleDefinitions
        return UserCapabilities.union(names.flatMap { definitions[$0] ?? [] })
    }

    /// True when at least one name matches a defined role — i.e. the
    /// identity has some Helios role at all. THE Entra sign-in eligibility
    /// gate (EntraAuthService calls it through a closure — see the overload
    /// below); this rule exists nowhere else. Same exact, case-sensitive
    /// matching as `capabilities(forRoleNames:)`.
    ///
    /// Note what it does NOT test: only that a name is DEFINED, never what
    /// that definition grants. A role defined as `{name = "Auditor";}` is
    /// eligible and resolves to `.none` — signed in, empty app.
    func hasAnyDefinedRole(in names: [String]) -> Bool {
        Self.hasAnyDefinedRole(in: names, definitions: roleDefinitions)
    }

    /// The rule itself, over the role index alone, so a caller that must not
    /// retain the whole configuration can still share this exact
    /// implementation rather than re-deriving it — EntraAuthService holds a
    /// closure over this, because the configuration carries Jamf/Entra
    /// secrets an auth service has no business retaining.
    static func hasAnyDefinedRole(
        in names: [String],
        definitions: [String: [AccessConfiguration.RoleDefinition]]
    ) -> Bool {
        names.contains { definitions[$0] != nil }
    }

    /// Indexes the access domain's `roles` ARRAY by role name, once, so
    /// `capabilities(forRoleNames:)` and `hasAnyDefinedRole(in:)` stay O(1)
    /// per name.
    ///
    /// Two edge cases the array shape introduces, both resolved fail-closed:
    ///
    /// • NAMELESS ENTRY (`name` missing, blank, or malformed) → SKIPPED and
    ///   logged. No role name can ever match it, so indexing it under `""`
    ///   would only risk an empty/whitespace `role` key accidentally
    ///   resolving to real capabilities.
    ///
    /// • DUPLICATE NAMES → UNIONED, not replaced. Later entries append rather
    ///   than overwrite, so `roleDefinitions[name]` holds every definition
    ///   carrying that name and `UserCapabilities.union` sums them. Union is
    ///   the direction that matches multi-role semantics (holding a name
    ///   grants everything that name is defined to grant) and it is the
    ///   predictable one: last-wins would make an admin's grant silently
    ///   vanish based on array order.
    static func roleIndex(
        from definitions: [AccessConfiguration.RoleDefinition]
    ) -> [String: [AccessConfiguration.RoleDefinition]] {
        var index: [String: [AccessConfiguration.RoleDefinition]] = [:]
        for definition in definitions {
            let name = definition.effectiveName
            guard !name.isEmpty else {
                NSLog("⚠️ access.roles: role entry with a missing or blank 'name' — SKIPPED (an unnamed role is unreachable; no role name can match it)")
                continue
            }
            index[name, default: []].append(definition)
        }
        return index
    }

    // MARK: - Interactive sign-in (core signIn block; strict fail-closed)

    /// How users sign into the app.
    enum SignInMethod: String {
        case email
        case entra
    }

    /// Resolved sign-in method. Case-insensitive: only "entra" selects the
    /// Entra flow; anything else — or an absent `signIn` block — is the
    /// built-in email flow (backward compatible: a fleet that never
    /// delivers `signIn` keeps the email flow unchanged).
    var signInMethod: SignInMethod {
        let raw = signIn?.method?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return raw == SignInMethod.entra.rawValue ? .entra : .email
    }

    /// Whether the Entra sign-in flow is selected AND usable: method is
    /// "entra" with non-empty tenantId and clientId. FAIL-CLOSED: when
    /// `signInMethod == .entra` but this is false, the login UI must show
    /// a configuration-error state — NEVER the email form (see
    /// `entraSignInRequired`); a misconfigured profile must not silently
    /// downgrade to the weaker email flow.
    var isEntraSignInConfigured: Bool {
        signInMethod == .entra
            && !entraSignInTenantId.isEmpty
            && !entraSignInClientId.isEmpty
    }

    /// Entra tenant id for interactive sign-in ("" when absent).
    var entraSignInTenantId: String {
        signIn?.entra?.tenantId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Application (client) id of the PUBLIC-client app registration for
    /// interactive sign-in ("" when absent). Not secret — and no secret
    /// is ever paired with it.
    var entraSignInClientId: String {
        signIn?.entra?.clientId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// OAuth token authority host for interactive sign-in, resolved from
    /// signIn.entra.cloudInstance via the shared CloudInstance mapping
    /// (default global → login.microsoftonline.com).
    var entraSignInAuthorityHost: String {
        (signIn?.entra?.effectiveCloudInstance ?? .global).authorityHost
    }

    /// Entra group OBJECT ids the signed-in user must be a member of
    /// (verified via the token's groups claim). Default [] = no group
    /// check. Prefer app roles — the groups claim is overage-limited.
    var effectiveEntraAllowedGroupIds: [String] {
        signIn?.entra?.effectiveAllowedGroupIds ?? []
    }

    /// Whether to still provision the per-user Jamf API client from the
    /// verified email after Entra sign-in (default true).
    var effectiveProvisionJamfCredentials: Bool {
        signIn?.entra?.effectiveProvisionJamfCredentials ?? true
    }

    /// Whether the Entra sign-in flow is REQUIRED: true whenever the
    /// method is "entra", even when misconfigured
    /// (`isEntraSignInConfigured == false`). The email path must be
    /// hidden in that case — the login UI shows a configuration error
    /// instead of falling back to the weaker email flow.
    var entraSignInRequired: Bool { signInMethod == .entra }

    // MARK: - Device action policies (strict fail-closed)

    /// Policy for the computer (macOS) Actions menu: access-domain
    /// allow-list + features-domain enableAPIActions kill switch,
    /// intersected with the signed-in user's role capabilities. No
    /// allow-list delivered → DeviceActionPolicy denies everything and the
    /// Actions menu is hidden; so does `.none` capabilities. NOTE: once an
    /// allow-list is delivered it is authoritative for Screen Share too —
    /// the legacy core-domain `jamfPro.screenShareEnabled` key is deprecated
    /// and ignored.
    ///
    /// Pass the CURRENT capabilities (UserSession.shared.capabilities) —
    /// the policy is a value, so it must be rebuilt when they change.
    func computerActionPolicy(capabilities: UserCapabilities) -> DeviceActionPolicy {
        deviceActionPolicy(
            grants: deviceActions?.computer?.grantsByID,
            apiActionsEnabled: features?.effectiveComputers.effectiveEnableAPIActions ?? true,
            capabilities: capabilities,
            platform: .computer
        )
    }

    /// Policy for mobile-device actions. No mobile actions menu exists yet
    /// (MobileDeviceView's "More" button is a stub); any future menu must be
    /// built from this policy from day one.
    func mobileDeviceActionPolicy(capabilities: UserCapabilities) -> DeviceActionPolicy {
        deviceActionPolicy(
            grants: deviceActions?.mobileDevice?.grantsByID,
            apiActionsEnabled: features?.effectiveMobileDevices.effectiveEnableAPIActions ?? true,
            capabilities: capabilities,
            platform: .mobileDevice
        )
    }

    /// Shared per-platform policy builder: machine layer (access-domain
    /// grants + features-domain kill switch) intersected with the user layer
    /// (role capabilities for that platform).
    private func deviceActionPolicy(
        grants: [String: AccessConfiguration.DeviceActionSetting]?,
        apiActionsEnabled: Bool,
        capabilities: UserCapabilities,
        platform: DeviceActionPolicy.Platform
    ) -> DeviceActionPolicy {
        DeviceActionPolicy(
            grants: grants,
            apiActionsEnabled: apiActionsEnabled,
            capabilities: capabilities,
            platform: platform
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
        connectionTimeoutSeconds: Int = 30,
        requestTimeoutSeconds: Int = 60,
        eraseAckTimeoutSeconds: Int = 180,
        eraseAckPollIntervalSeconds: Int = 15,
        screenShareEnabled: Bool,
        vpnIPExtensionAttribute: String? = nil,
        userCredentialLifetimeDays: Int = 90,
        abmAPIBaseURL: String = "https://api-business.apple.com/v1",
        abmOAuthScope: String = "business.api",
        entraAuthorityHost: String = "login.microsoftonline.com",
        entraGraphHost: String = "graph.microsoft.com",
        abmClientId: String?,
        abmKeyId: String?,
        abmPrivateKey: String?,
        role: String? = nil,
        roleDefinitions: [String: [AccessConfiguration.RoleDefinition]] = [:],
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
        userInterfaceExtras: UserInterfaceSettings? = nil,
        signIn: CoreConfiguration.SignInSettings? = nil
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
        self.connectionTimeoutSeconds = connectionTimeoutSeconds
        self.requestTimeoutSeconds = requestTimeoutSeconds
        self.eraseAckTimeoutSeconds = eraseAckTimeoutSeconds
        self.eraseAckPollIntervalSeconds = eraseAckPollIntervalSeconds
        self.screenShareEnabled = screenShareEnabled
        self.vpnIPExtensionAttribute = vpnIPExtensionAttribute
        self.userCredentialLifetimeDays = userCredentialLifetimeDays
        self.abmAPIBaseURL = abmAPIBaseURL
        self.abmOAuthScope = abmOAuthScope
        self.entraAuthorityHost = entraAuthorityHost
        self.entraGraphHost = entraGraphHost
        self.abmClientId = abmClientId
        self.abmKeyId = abmKeyId
        self.abmPrivateKey = abmPrivateKey
        self.role = role
        self.roleDefinitions = roleDefinitions
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
        self.signIn = signIn
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
        let deliveredSidebar = ui?.effectiveSidebarItems ?? []
        let managedSidebar = deliveredSidebar
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
        // Falling back to the built-in sidebar silently discards a delivered
        // order — say so, or an admin sees the default order with no clue why.
        if !deliveredSidebar.isEmpty && managedSidebar.isEmpty {
            print("⚠️ ui.sidebarItems: \(deliveredSidebar.count) item(s) delivered but none usable "
                  + "(each needs a non-empty id and isEnabled != false) — using the built-in sidebar, "
                  + "so any delivered order is IGNORED")
        } else if deliveredSidebar.count != managedSidebar.count {
            let dropped = deliveredSidebar.filter { !$0.isUsable }.map { $0.effectiveID.isEmpty ? "(no id)" : $0.effectiveID }
            print("⚠️ ui.sidebarItems: skipped \(dropped.count) unusable item(s): \(dropped.joined(separator: ", "))")
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
            requiredRoleName: jamfPro?.effectiveRequiredRoleName ?? "HeliosConsoleAPIRole",
            supportURL: uiSettings?.effectiveSupportURL,
            localAdminUsername: core?.localAdministration?.effectiveUsername ?? "macadmin",
            connectionTimeoutSeconds: jamfPro?.effectiveConnectionTimeout ?? 30,
            requestTimeoutSeconds: jamfPro?.effectiveRequestTimeout ?? 60,
            eraseAckTimeoutSeconds: jamfPro?.effectiveEraseAckTimeoutSeconds ?? 180,
            eraseAckPollIntervalSeconds: jamfPro?.effectiveEraseAckPollIntervalSeconds ?? 15,
            screenShareEnabled: jamfPro?.effectiveScreenShareEnabled ?? false,
            vpnIPExtensionAttribute: jamfPro?.effectiveVPNIPExtensionAttributeName,
            userCredentialLifetimeDays: jamfPro?.effectiveUserCredentialLifetimeDays ?? 90,
            abmAPIBaseURL: (core?.appleBusinessManager?.effectiveServiceType ?? .business).apiBaseURL,
            abmOAuthScope: (core?.appleBusinessManager?.effectiveServiceType ?? .business).oauthScope,
            entraAuthorityHost: (core?.entra?.effectiveCloudInstance ?? .global).authorityHost,
            entraGraphHost: (core?.entra?.effectiveCloudInstance ?? .global).graphHost,
            abmClientId: abmClientId,
            abmKeyId: abmKeyId,
            abmPrivateKey: abmPrivateKey,
            // Fail-closed: absent access domain → nil role name and no role
            // definitions → every user resolves to UserCapabilities.none.
            role: access?.role,
            roleDefinitions: MDMConfiguration.roleIndex(from: access?.effectiveRoles ?? []),
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
            userInterfaceExtras: uiSettings,
            // Interactive sign-in passthrough. Absent core domain (or an
            // absent signIn block) → nil → signInMethod resolves to .email,
            // so undelivered profiles keep the email flow unchanged.
            signIn: core?.signIn
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
    /// delivered by the ui domain. Ids MUST be NavigationDestination raw
    /// values — unknown ids are skipped by SidebarView. (The previous list
    /// referenced routes — enterprise/groundcontrol/depsearch — that never
    /// existed in this app.)
    ///
    /// INVARIANT: this list MUST enumerate EVERY module id a role can grant.
    /// SidebarView renders (this list, or the ui domain's sidebarItems
    /// override) ∩ (the user's role `modules`), so an id missing here can
    /// NEVER appear on a Mac that gets no sidebarItems override — the
    /// presentation layer would silently swallow a grant the admin made.
    /// This list is presentation only; it grants nothing on its own.
    /// (`cleanup` was missing and was unreachable exactly this way: it used
    /// to be appended outside the sidebarItems loop, so the default list
    /// never had to carry it.) `myDevice` is deliberately ABSENT — it is
    /// reserved for a follow-up PR and has no NavigationDestination case, so
    /// it would be skipped anyway.
    static let defaultSidebarItems: [SidebarItemConfig] = [
        SidebarItemConfig(id: "dashboard", icon: "square.grid.2x2", title: "Dashboard", order: 1),
        SidebarItemConfig(id: "devices", icon: "desktopcomputer", title: "Devices", order: 2),
        SidebarItemConfig(id: "announcements", icon: "megaphone", title: "Announcements", order: 3),
        SidebarItemConfig(id: "logs", icon: "doc.text.magnifyingglass", title: "Logs", order: 4),
        SidebarItemConfig(id: "reports", icon: "chart.bar.doc.horizontal", title: "Reports", order: 5),
        SidebarItemConfig(id: "enrollments", icon: "person.badge.plus", title: "Enrollments", order: 6),
        SidebarItemConfig(id: "cleanup", icon: "wand.and.sparkles", title: "Cleanup", order: 7),
        SidebarItemConfig(id: "settings", icon: "gearshape", title: "Settings", order: 8)
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
        requiredRoleName: "HeliosConsoleAPIRole",
        supportURL: nil,
        localAdminUsername: "macadmin",
        screenShareEnabled: false,
        abmClientId: nil,
        abmKeyId: nil,
        abmPrivateKey: nil
        // No role name and no role definitions: with nothing delivered,
        // every user resolves to UserCapabilities.none. The old DEBUG
        // `role: "Admin"` shim is gone — it named a role the app invented,
        // and roles are now defined ONLY by the profile, so it could not
        // grant anything anyway. For local dev, deliver a roles ARRAY (each
        // entry names itself) plus the `role` key that selects one of them:
        //   defaults write com.herojoneslabs.helios.console.access roles '(
        //     {
        //       name = "Dev";
        //       modules = (dashboard, devices);
        //       allowExport = 1;
        //     }
        //   )'
        //   defaults write com.herojoneslabs.helios.console.access role "Dev"
    )
}
