//
//  FeaturesConfiguration.swift
//  HeliosConsole
//
//  Helios Console — Features tier (managed-preferences domain model).
//
//  Preference Domain MUST match the domain Helios reads:
//      com.herojoneslabs.helios.console.features
//  (Matches `FeaturesConfiguration.domain` below, the schema $id in
//   schemas/Helios_Features_SCHEMA.json, and the domain table in
//   docs/ConfigProfileMigration.md — keep all three in sync.)
//
//  Loaded by ManagedDomainLoader: the domain's top-level keys are read out of
//  UserDefaults(suiteName: FeaturesConfiguration.domain) into a [String: Any],
//  serialized with PropertyListSerialization, and decoded here via
//  PropertyListDecoder. ALL stored properties are optional so a missing (or
//  partially delivered) key never fails the whole domain decode; defaults live
//  in the computed `effective*` accessors.
//
//  These keys are parsed and exposed by the app config layer; per-view
//  enforcement status is tracked in docs/ConfigProfileMigration.md.
//

import Foundation

/// The managed `cleanup` dictionary: profile-delivered defaults for the
/// Cleanup module. Distinct from the app-local `CleanupSettings` service
/// class (Cleanup/Services/CleanupSettings.swift).
///
/// HOME DOMAIN: `features.cleanup`. It is still decoded from `access.cleanup`
/// for backward compatibility (aliased as `AccessConfiguration.CleanupSettings`)
/// because deployed access profiles carry it; the composition layer prefers
/// the features copy. These values GRANT NOTHING — which roles may see the
/// Cleanup module and which sub-actions they may run stay in the access
/// domain.
struct ManagedCleanupSettings: Codable {
    /// Stale threshold (days without check-in). See `effectiveStaleDays`.
    var staleDays: Int?
    /// Jamf static group ID (string in the profile; parsed to Int downstream).
    var defaultStaticGroupID: String?
    /// Jamf site ID (string in the profile; parsed to Int downstream).
    var defaultSiteID: String?

    /// Stale threshold with the schema default applied.
    var effectiveStaleDays: Int { staleDays ?? 90 }

    enum CodingKeys: String, CodingKey {
        case staleDays
        case defaultStaticGroupID
        case defaultSiteID
    }

    init(
        staleDays: Int? = nil,
        defaultStaticGroupID: String? = nil,
        defaultSiteID: String? = nil
    ) {
        self.staleDays = staleDays
        self.defaultStaticGroupID = defaultStaticGroupID
        self.defaultSiteID = defaultSiteID
    }

    /// Custom decode: deployed profiles deliver `staleDays` as either an
    /// integer or a string ("90"). Accept both — and never let a malformed
    /// value fail the whole domain decode.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intValue = try? container.decode(Int.self, forKey: .staleDays) {
            staleDays = intValue
        } else if let stringValue = try? container.decode(String.self, forKey: .staleDays) {
            staleDays = Int(stringValue)
        } else {
            staleDays = nil
        }
        defaultStaticGroupID = try container.decodeIfPresent(String.self, forKey: .defaultStaticGroupID)
        defaultSiteID = try container.decodeIfPresent(String.self, forKey: .defaultSiteID)
    }

    /// True when the profile delivered no cleanup values at all — the signal
    /// the composition layer uses to fall back to the legacy access copy.
    var isEmpty: Bool {
        staleDays == nil && defaultStaticGroupID == nil && defaultSiteID == nil
    }
}

/// The managed `localAdministration` block: the local admin account whose
/// LAPS password Helios looks up in DeviceView.
///
/// HOME DOMAIN: `features.localAdministration`. It is still decoded from
/// `core.localAdministration` for backward compatibility (aliased as
/// `CoreConfiguration.LocalAdminSettings`) because deployed core profiles
/// carry it; the composition layer prefers the features copy.
struct ManagedLocalAdminSettings: Codable {

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

    /// True when the profile delivered no values at all — the signal the
    /// composition layer uses to fall back to the legacy core copy.
    var isEmpty: Bool { enabled == nil && username == nil }
}

/// Feature modules & tuning for Helios Console — delivered via the
/// `com.herojoneslabs.helios.console.features` managed-preferences domain (all managed Macs).
struct FeaturesConfiguration: Codable {

    /// Managed-preferences domain this model is decoded from.
    static let domain = "com.herojoneslabs.helios.console.features"

    // MARK: - Stored properties (all optional — missing keys never fail decode)

    /// Informational version stamp; the loader logs it, nothing else reads it.
    let configurationVersion: String?
    let computers: ComputersSettings?
    let mobileDevices: MobileDevicesSettings?
    let healthScorecard: HealthScorecardSettings?
    let deviceHealth: DeviceHealthSettings?
    let reports: ReportsSettings?
    let actionLog: ActionLogSettings?

    /// Top-level UI area visibility switches (`showAnnouncements`,
    /// `showSettings`). MOVED HERE from the ui domain during the domain
    /// cleanup: these turn FEATURES on and off — they are not branding. The
    /// ui domain still decodes its legacy copies; the composition layer
    /// (MDMConfiguration.build) prefers these and falls back, so already-
    /// deployed ui profiles keep working untouched.
    let userExperience: UserExperienceSettings?

    /// Cleanup module tunables (stale threshold, default static group and
    /// site). MOVED HERE from the access domain during the domain cleanup:
    /// the access domain is for GRANTS, and these grant nothing — they tune a
    /// feature. Which roles may SEE Cleanup and which sub-actions they may run
    /// stay in access. The access domain still decodes its legacy block; the
    /// composition layer prefers this one and falls back.
    let cleanup: ManagedCleanupSettings?

    /// Local administrator account settings for the DeviceView LAPS lookup.
    /// MOVED HERE from the core domain: core is connection and integration
    /// identity, and this is a feature of a view. The core domain still
    /// decodes its legacy copy; the composition layer prefers this one.
    let localAdministration: ManagedLocalAdminSettings?

    // MARK: - Effective accessors (defaults per schemas/Helios_Features_SCHEMA.json)

    var effectiveConfigurationVersion: String { configurationVersion ?? "2.0" }
    var effectiveComputers: ComputersSettings { computers ?? .empty }
    var effectiveMobileDevices: MobileDevicesSettings { mobileDevices ?? .empty }
    var effectiveHealthScorecard: HealthScorecardSettings { healthScorecard ?? .empty }
    var effectiveDeviceHealth: DeviceHealthSettings { deviceHealth ?? .empty }
    var effectiveReports: ReportsSettings { reports ?? .empty }
    var effectiveActionLog: ActionLogSettings { actionLog ?? .empty }
    var effectiveUserExperience: UserExperienceSettings { userExperience ?? .empty }
    var effectiveCleanup: ManagedCleanupSettings { cleanup ?? ManagedCleanupSettings() }
    var effectiveLocalAdministration: ManagedLocalAdminSettings {
        localAdministration ?? ManagedLocalAdminSettings()
    }

    /// Normalizes and validates a configured section list for a Jamf
    /// inventory endpoint: upper-cases + trims each entry, keeps only the
    /// values the endpoint accepts (de-duplicated, order preserved), and
    /// returns `fallback` when a delivered profile leaves nothing valid.
    /// Jamf 400s the entire request on a single unrecognized section, so
    /// this guarantees the wire only ever sees accepted values. Dropped
    /// entries are logged once so a bad profile is diagnosable.
    static func validate(
        _ sections: [String],
        against valid: Set<String>,
        fallback: [String]
    ) -> [String] {
        var seen = Set<String>()
        var kept: [String] = []
        var dropped: [String] = []
        for raw in sections {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard valid.contains(name) else {
                if !name.isEmpty { dropped.append(name) }
                continue
            }
            if seen.insert(name).inserted { kept.append(name) }
        }
        if !dropped.isEmpty {
            print("⚠️ features: dropped invalid inventory section(s) \(dropped) — not accepted by this Jamf endpoint")
        }
        return kept.isEmpty ? fallback : kept
    }

    /// A fully-absent payload; every `effective*` accessor then yields the
    /// schema defaults.
    static let empty = FeaturesConfiguration(
        configurationVersion: nil,
        computers: nil,
        mobileDevices: nil,
        healthScorecard: nil,
        deviceHealth: nil,
        reports: nil,
        actionLog: nil,
        userExperience: nil,
        cleanup: nil,
        localAdministration: nil
    )

    // MARK: - User experience (top-level area switches)

    /// The `userExperience` dictionary: kill switches for whole app areas.
    ///
    /// These are INTERSECTED with the role grant, never a substitute for it:
    /// a false here hides an area the role would otherwise show, but a true
    /// never reveals one the role withholds (fail-closed preserved).
    struct UserExperienceSettings: Codable {
        /// Show the Announcements area. Default true.
        let showAnnouncements: Bool?
        /// Show the Settings area. Default true.
        let showSettings: Bool?

        var effectiveShowAnnouncements: Bool { showAnnouncements ?? true }
        var effectiveShowSettings: Bool { showSettings ?? true }

        static let empty = UserExperienceSettings(
            showAnnouncements: nil,
            showSettings: nil
        )
    }

    // MARK: - Action Log

    /// Retention policy for the local MDM-action audit trail. Without a
    /// cap the log file grows forever (it previously had NO limit).
    struct ActionLogSettings: Codable {
        /// Days to keep entries; 0 = keep forever.
        let retentionDays: Int?
        /// Maximum number of entries; 0 = unlimited.
        let maxEntries: Int?

        var effectiveRetentionDays: Int { max(0, retentionDays ?? 365) }
        var effectiveMaxEntries: Int { max(0, maxEntries ?? 10000) }

        static let empty = ActionLogSettings(retentionDays: nil, maxEntries: nil)
    }

    // MARK: - Computers

    struct ComputersSettings: Codable {
        let enabled: Bool?
        let fetchInventory: Bool?
        let showDashboardCard: Bool?
        let enableReports: Bool?
        let inventoryRefreshInterval: Int?
        let inventorySections: [String]?

        var effectiveEnabled: Bool { enabled ?? true }
        var effectiveFetchInventory: Bool { fetchInventory ?? true }
        var effectiveShowDashboardCard: Bool { showDashboardCard ?? true }
        var effectiveEnableReports: Bool { enableReports ?? true }
        var effectiveInventoryRefreshInterval: Int { inventoryRefreshInterval ?? 15 }
        /// Configured sections, or the built-in list when the key is absent
        /// OR empty — an empty section list would break every detail view.
        var effectiveInventorySections: [String] {
            guard let inventorySections, !inventorySections.isEmpty else {
                return Self.defaultInventorySections
            }
            return inventorySections
        }

        /// The sections actually sent to `/api/v1/computers-inventory`:
        /// normalized, restricted to the values that endpoint accepts, and
        /// falling back to the default when a delivered profile leaves
        /// nothing valid. Jamf rejects the WHOLE request with a 400 if any
        /// single section is unrecognized, so a stale or hand-edited
        /// profile must never reach the wire with a bad value.
        var validatedInventorySections: [String] {
            FeaturesConfiguration.validate(
                effectiveInventorySections,
                against: Self.validSections,
                fallback: Self.defaultInventorySections
            )
        }

        /// Must stay in sync with the sections the detail views actually
        /// render (and the schema default in Helios_Features_SCHEMA.json).
        static let defaultInventorySections = [
            "GENERAL", "HARDWARE", "OPERATING_SYSTEM", "USER_AND_LOCATION",
            "DISK_ENCRYPTION", "SECURITY", "APPLICATIONS", "SOFTWARE_UPDATES",
            "PURCHASING", "GROUP_MEMBERSHIPS"
        ]

        /// Every section `/api/v1/computers-inventory` accepts (Jamf Pro
        /// developer reference). Any other value 400s the request.
        static let validSections: Set<String> = [
            "GENERAL", "DISK_ENCRYPTION", "PURCHASING", "APPLICATIONS",
            "STORAGE", "USER_AND_LOCATION", "CONFIGURATION_PROFILES",
            "PRINTERS", "SERVICES", "HARDWARE", "LOCAL_USER_ACCOUNTS",
            "CERTIFICATES", "ATTACHMENTS", "PLUGINS", "PACKAGE_RECEIPTS",
            "FONTS", "SECURITY", "OPERATING_SYSTEM", "LICENSED_SOFTWARE",
            "IBEACONS", "SOFTWARE_UPDATES", "EXTENSION_ATTRIBUTES",
            "CONTENT_CACHING", "GROUP_MEMBERSHIPS"
        ]

        static let empty = ComputersSettings(
            enabled: nil, fetchInventory: nil, showDashboardCard: nil,
            enableReports: nil,
            inventoryRefreshInterval: nil, inventorySections: nil
        )
    }

    // MARK: - Mobile Devices

    struct MobileDevicesSettings: Codable {
        let enabled: Bool?
        let fetchInventory: Bool?
        let showDashboardCards: ShowDashboardCards?
        let enableReports: Bool?
        let inventoryRefreshInterval: Int?
        let inventorySections: [String]?

        var effectiveEnabled: Bool { enabled ?? true }
        var effectiveFetchInventory: Bool { fetchInventory ?? true }
        var effectiveShowDashboardCards: ShowDashboardCards { showDashboardCards ?? .empty }
        var effectiveEnableReports: Bool { enableReports ?? true }
        var effectiveInventoryRefreshInterval: Int { inventoryRefreshInterval ?? 15 }
        /// Configured sections, or the built-in list when the key is absent
        /// OR empty — an empty section list would break every detail view.
        var effectiveInventorySections: [String] {
            guard let inventorySections, !inventorySections.isEmpty else {
                return Self.defaultInventorySections
            }
            return inventorySections
        }

        /// The sections actually sent to `/api/v2/mobile-devices/detail`:
        /// normalized and restricted to the values that endpoint accepts.
        /// NOTE the mobile vocabulary differs from computers — it uses
        /// PROFILES / GROUPS, NOT CONFIGURATION_PROFILES / GROUP_MEMBERSHIPS;
        /// a profile carrying the computer spellings (an easy mistake, and
        /// the pre-2.1 schema default did exactly this) would otherwise 400
        /// the whole fetch.
        var validatedInventorySections: [String] {
            FeaturesConfiguration.validate(
                effectiveInventorySections,
                against: Self.validSections,
                fallback: Self.defaultInventorySections
            )
        }

        /// Must stay in sync with the sections the detail views actually
        /// render (and the schema default in Helios_Features_SCHEMA.json).
        static let defaultInventorySections = [
            "GENERAL", "HARDWARE", "USER_AND_LOCATION", "SECURITY",
            "NETWORK", "PURCHASING", "APPLICATIONS", "CERTIFICATES",
            "PROFILES", "GROUPS", "EXTENSION_ATTRIBUTES"
        ]

        /// Every section `/api/v2/mobile-devices/detail` accepts (Jamf Pro
        /// developer reference). Any other value 400s the request.
        static let validSections: Set<String> = [
            "GENERAL", "HARDWARE", "USER_AND_LOCATION", "PURCHASING",
            "SECURITY", "APPLICATIONS", "EBOOKS", "NETWORK",
            "SERVICE_SUBSCRIPTIONS", "CERTIFICATES", "PROFILES",
            "USER_PROFILES", "PROVISIONING_PROFILES", "SHARED_USERS",
            "GROUPS", "EXTENSION_ATTRIBUTES"
        ]

        static let empty = MobileDevicesSettings(
            enabled: nil, fetchInventory: nil, showDashboardCards: nil,
            enableReports: nil,
            inventoryRefreshInterval: nil, inventorySections: nil
        )

        /// Per-platform dashboard-card visibility. Keys are the exact platform
        /// spellings from the schema (`iOS`, `iPadOS`, `visionOS`).
        struct ShowDashboardCards: Codable {
            let iOS: Bool?
            let iPadOS: Bool?
            let visionOS: Bool?

            var effectiveIOS: Bool { iOS ?? true }
            var effectiveIPadOS: Bool { iPadOS ?? true }
            var effectiveVisionOS: Bool { visionOS ?? true }

            static let empty = ShowDashboardCards(iOS: nil, iPadOS: nil, visionOS: nil)
        }
    }

    // MARK: - Health Scorecard

    struct HealthScorecardSettings: Codable {
        let enabled: Bool?
        let metrics: [HealthMetricSetting]?

        init(enabled: Bool?, metrics: [HealthMetricSetting]?) {
            self.enabled = enabled
            self.metrics = metrics
        }

        /// `HealthMetricSetting.init(from:)` is lenient about its own fields but
        /// still requires a keyed container, so a `metrics` array holding a bare
        /// string — or `metrics` delivered as a dict — throws. ManagedDomainLoader
        /// decodes the whole features domain in one call and discards ALL of it on
        /// any throw, so that typo would take computers, mobileDevices, reports and
        /// cleanup down with it. Decode elements individually and drop the bad ones.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try? container.decode(Bool.self, forKey: .enabled)

            if container.contains(.metrics) {
                if let rows = try? container.decode([FailableMetric].self, forKey: .metrics) {
                    let kept = rows.compactMap(\.value)
                    if kept.count != rows.count {
                        NSLog("⚠️ healthScorecard.metrics: dropped %d malformed entr%@",
                              rows.count - kept.count, rows.count - kept.count == 1 ? "y" : "ies")
                    }
                    metrics = kept
                } else {
                    NSLog("⚠️ healthScorecard.metrics: not an array of objects — ignoring, defaults apply")
                    metrics = nil
                }
            } else {
                metrics = nil
            }
        }

        private struct FailableMetric: Decodable {
            let value: HealthMetricSetting?
            init(from decoder: Decoder) throws { value = try? HealthMetricSetting(from: decoder) }
        }

        var effectiveEnabled: Bool { enabled ?? true }
        var effectiveMetrics: [HealthMetricSetting] { metrics ?? Self.defaultMetrics }

        /// Lookup for a single metric's settings: the configured row wins,
        /// otherwise the built-in default row — so a profile that delivers
        /// only some metrics never blanks the tuning of the others.
        ///
        /// Legacy ids are accepted for one release. The metric ids used to be a
        /// separate namespace from the scorecard's actual metrics, so a profile
        /// written against the old schema addresses `softwareUpdateCompliance`
        /// where the metric is `upToDate`. Honouring both means the pkg can ship
        /// before the profile is re-pushed instead of the app going empty on
        /// anyone who installs in the wrong order.
        /// A configured row is merged FIELD BY FIELD over the default row rather
        /// than replacing it. Every schema field is optional, so a profile that
        /// sets only `displayName` on `protected` would otherwise arrive with
        /// siteRules nil — no rule would match any device and the metric would
        /// read 0/0/613. Policy and cosmetics share a row, and cosmetics are
        /// exactly what an admin edits first.
        func effectiveMetric(id: String) -> HealthMetricSetting? {
            let fallback = Self.defaultMetrics.first { $0.id == id }

            let candidates = [id] + Self.legacyIDAliases
                .filter { $0.value == id }
                .map(\.key)
            let configured = candidates.lazy
                .compactMap { candidate in effectiveMetrics.first { $0.id == candidate } }
                .first

            guard let configured else { return fallback }
            guard let fallback else { return configured }
            return configured.merged(over: fallback)
        }

        /// Old metric id -> current metric id.
        ///
        /// Only ids whose legacy row actually carried settings the current metric
        /// reads belong here. `softwareUpdateCompliance` qualifies: it held
        /// `minimumOSVersions`, which is the one field `upToDate` consumes.
        ///
        /// Deliberately NOT aliased: `fileVaultEnabled` -> `encrypted`. That
        /// legacy row never carried encryption policy — exclusion was a Swift
        /// literal when it was written — so aliasing it would let an old profile
        /// satisfy the lookup with a row that has no `excludedSites`, silently
        /// pulling every GroundControl Mac into the Encrypted denominator. A
        /// legacy row can only ever subtract policy here, never supply it.
        static let legacyIDAliases: [String: String] = [
            "softwareUpdateCompliance": "upToDate"
        ]

        static let empty = HealthScorecardSettings(enabled: nil, metrics: nil)

        /// The five scorecard metrics, keyed to the ids the scorecard actually
        /// renders (mirrors the schema's `metrics` default).
        ///
        /// These replace an earlier eight-row list whose ids — `managed`,
        /// `fileVaultEnabled`, `sipEnabled` and so on — described individual
        /// security *checks* rather than metrics and matched nothing the app
        /// displayed. Those checks now live where they always belonged, inside a
        /// site rule's `checks` array.
        ///
        /// Every value here reproduces the behavior that was hard-coded in Swift
        /// before this change, so a tenant with no healthScorecard profile sees
        /// exactly what they saw previously.
        static let defaultMetrics: [HealthMetricSetting] = [
            HealthMetricSetting(
                id: "checkedIn", enabled: true, displayName: "Checked-In",
                thresholds: .init(critical: 50, warning: 80), checkedInDays: 7,
                platforms: ["macOS", "iOS", "iPadOS", "visionOS"]
            ),
            HealthMetricSetting(
                id: "protected", enabled: true, displayName: "Protected",
                thresholds: .init(critical: 50, warning: 80),
                platforms: ["macOS", "iOS", "iPadOS", "visionOS"],
                siteRules: [
                    .init(siteName: "enterprise", siteMatchMode: "exact",
                          requiredApps: [
                              .init(name: "Cisco Secure Client"),
                              .init(name: "Zscaler"),
                              .init(name: "QualysCloudAgent"),
                              .init(name: "Falcon"),
                              .init(name: "JamfProtect")
                          ],
                          requireMode: "all"),
                    .init(siteName: "groundcontrol", siteMatchMode: "exact",
                          requiredApps: [.init(name: "Falcon")],
                          requireMode: "all")
                ],
                defaultVerdictForUnmatchedSite: "unknown"
            ),
            HealthMetricSetting(
                id: "encrypted", enabled: true, displayName: "Encrypted",
                thresholds: .init(critical: 50, warning: 80),
                platforms: ["macOS", "iOS", "iPadOS", "visionOS"],
                excludedSites: ["groundcontrol"]
            ),
            HealthMetricSetting(
                id: "secured", enabled: true, displayName: "Secured",
                thresholds: .init(critical: 50, warning: 80),
                platforms: ["macOS", "iOS", "iPadOS", "visionOS"],
                siteRules: [
                    .init(siteName: "enterprise", siteMatchMode: "exact",
                          checks: ["firewall", "sip", "gatekeeper", "managed",
                                   "supervised", "diskEncrypted", "bootstrapToken", "ddm"]),
                    .init(siteName: "groundcontrol", siteMatchMode: "exact",
                          checks: ["firewall", "sip", "managed",
                                   "supervised", "bootstrapToken", "ddm"])
                ],
                defaultVerdictForUnmatchedSite: "unknown"
            ),
            HealthMetricSetting(
                id: "upToDate", enabled: true, displayName: "Up to Date",
                thresholds: .init(critical: 50, warning: 80),
                platforms: ["macOS", "iOS", "iPadOS", "visionOS"],
                minimumOSVersions: .init(macOS: 26, iOS: 26, iPadOS: 26, visionOS: 2)
            )
        ]
    }

    /// One health-scorecard metric row.
    struct HealthMetricSetting: Codable {
        let id: String?
        let enabled: Bool?
        let displayName: String?
        let thresholds: Thresholds?
        let checkedInDays: Int?
        let platforms: [String]?
        /// Per-platform minimum compliant OS major version — only meaningful
        /// on the `upToDate` metric.
        let minimumOSVersions: MinimumOSVersions?

        /// Site-scoped requirements, evaluated in order; first match wins.
        /// Meaningful on `protected` (required apps) and `secured` (check list).
        let siteRules: [SiteRule]?
        /// Sites removed from this metric entirely — neither numerator nor
        /// denominator. Distinct from a rule that evaluates to non-compliant.
        let excludedSites: [String]?
        /// What a device whose site matches no rule scores.
        /// `compliant` | `nonCompliant` | `unknown`. Ships fail-closed.
        let defaultVerdictForUnmatchedSite: String?

        var effectiveEnabled: Bool { enabled ?? true }
        var effectiveDisplayName: String { displayName ?? "" }
        var effectiveThresholds: Thresholds { thresholds ?? .empty }
        /// Clamped 1...3650 — an absurd profile value must not break
        /// Calendar date math downstream.
        var effectiveCheckedInDays: Int { min(max(checkedInDays ?? 7, 1), 3650) }
        var effectivePlatforms: [String] { platforms ?? [] }
        var effectiveMinimumOSVersions: MinimumOSVersions { minimumOSVersions ?? .empty }
        var effectiveSiteRules: [SiteRule] { siteRules ?? [] }
        var effectiveExcludedSites: [String] { excludedSites ?? [] }
        /// Unrecognised values fall back to `unknown` rather than being trusted —
        /// a typo must not silently reinstate the fail-open behavior this
        /// replaced.
        var effectiveUnmatchedSiteVerdict: String {
            let raw = (defaultVerdictForUnmatchedSite ?? "unknown").lowercased()
            return ["compliant", "noncompliant", "unknown"].contains(raw) ? raw : "unknown"
        }

        init(
            id: String? = nil,
            enabled: Bool? = nil,
            displayName: String? = nil,
            thresholds: Thresholds? = nil,
            checkedInDays: Int? = nil,
            platforms: [String]? = nil,
            minimumOSVersions: MinimumOSVersions? = nil,
            siteRules: [SiteRule]? = nil,
            excludedSites: [String]? = nil,
            defaultVerdictForUnmatchedSite: String? = nil
        ) {
            self.id = id
            self.enabled = enabled
            self.displayName = displayName
            self.thresholds = thresholds
            self.checkedInDays = checkedInDays
            self.platforms = platforms
            self.minimumOSVersions = minimumOSVersions
            self.siteRules = siteRules
            self.excludedSites = excludedSites
            self.defaultVerdictForUnmatchedSite = defaultVerdictForUnmatchedSite
        }

        /// Lenient decode. ManagedDomainLoader decodes the whole features domain
        /// in one call and discards ALL of it on any throw, so a single typo in a
        /// hand-authored site rule would otherwise blank computers, mobileDevices,
        /// reports and cleanup too. Malformed array elements are dropped
        /// individually instead — same discipline as AccessConfiguration.decodeRoles.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try? c.decode(String.self, forKey: .id)
            enabled = try? c.decode(Bool.self, forKey: .enabled)
            displayName = try? c.decode(String.self, forKey: .displayName)
            thresholds = try? c.decode(Thresholds.self, forKey: .thresholds)
            checkedInDays = try? c.decode(Int.self, forKey: .checkedInDays)
            platforms = try? c.decode([String].self, forKey: .platforms)
            minimumOSVersions = try? c.decode(MinimumOSVersions.self, forKey: .minimumOSVersions)
            siteRules = (try? c.decode([FailableSiteRule].self, forKey: .siteRules))?
                .compactMap(\.value)
            excludedSites = try? c.decode([String].self, forKey: .excludedSites)
            defaultVerdictForUnmatchedSite =
                try? c.decode(String.self, forKey: .defaultVerdictForUnmatchedSite)
        }

        private struct FailableSiteRule: Decodable {
            let value: SiteRule?
            init(from decoder: Decoder) throws { value = try? SiteRule(from: decoder) }
        }

        /// Field-by-field overlay: any value this row omits is inherited from
        /// `base` rather than becoming nil.
        func merged(over base: HealthMetricSetting) -> HealthMetricSetting {
            HealthMetricSetting(
                id: id ?? base.id,
                enabled: enabled ?? base.enabled,
                displayName: displayName ?? base.displayName,
                thresholds: thresholds ?? base.thresholds,
                checkedInDays: checkedInDays ?? base.checkedInDays,
                platforms: platforms ?? base.platforms,
                minimumOSVersions: minimumOSVersions ?? base.minimumOSVersions,
                siteRules: siteRules ?? base.siteRules,
                excludedSites: excludedSites ?? base.excludedSites,
                defaultVerdictForUnmatchedSite:
                    defaultVerdictForUnmatchedSite ?? base.defaultVerdictForUnmatchedSite
            )
        }

        /// One site's requirements. `requiredApps` drives Protected; `checks`
        /// drives Secured. A rule may carry either or both.
        struct SiteRule: Codable {
            let siteName: String?
            /// `exact` (default) | `prefix`. Prefix exists because sites are
            /// commonly versioned — "Enterprise_NextVer" fell through an exact
            /// match and was silently scored as passing before this work.
            let siteMatchMode: String?
            let requiredApps: [RequiredApp]?
            /// `all` (default) | `any`
            let requireMode: String?
            /// Security check ids for Secured: firewall, sip, gatekeeper,
            /// managed, supervised, diskEncrypted, bootstrapToken, ddm.
            let checks: [String]?

            init(
                siteName: String? = nil,
                siteMatchMode: String? = nil,
                requiredApps: [RequiredApp]? = nil,
                requireMode: String? = nil,
                checks: [String]? = nil
            ) {
                self.siteName = siteName
                self.siteMatchMode = siteMatchMode
                self.requiredApps = requiredApps
                self.requireMode = requireMode
                self.checks = checks
            }

            var effectiveSiteName: String { (siteName ?? "").lowercased() }
            var effectiveSiteMatchMode: String {
                let raw = (siteMatchMode ?? "exact").lowercased()
                return raw == "prefix" ? "prefix" : "exact"
            }
            var effectiveRequiredApps: [RequiredApp] { requiredApps ?? [] }
            var effectiveRequireMode: String {
                (requireMode ?? "all").lowercased() == "any" ? "any" : "all"
            }
            var effectiveChecks: [String] { checks ?? [] }

            /// One normalizer, shared with the exclusion check. They previously
            /// differed by a `.trimmingCharacters` call, so a site name authored
            /// with a trailing space in the Jamf UI could be excluded from one
            /// metric while matching no rule on another.
            static func normalized(_ site: String?) -> String {
                (site ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }

            func matches(site: String?) -> Bool {
                let candidate = Self.normalized(site)
                let target = Self.normalized(siteName)
                guard !target.isEmpty else { return false }
                return effectiveSiteMatchMode == "prefix"
                    ? candidate.hasPrefix(target)
                    : candidate == target
            }
        }

        /// An app a site requires. `matchMode` is per-app so a token that needs
        /// loose matching does not force every other entry to be loose.
        struct RequiredApp: Codable {
            let name: String?
            /// `exact` (default, matches "Name" or "Name.app") | `substring`.
            let matchMode: String?

            init(name: String? = nil, matchMode: String? = nil) {
                self.name = name
                self.matchMode = matchMode
            }

            var effectiveName: String { name ?? "" }
            var effectiveMatchMode: String {
                (matchMode ?? "exact").lowercased() == "substring" ? "substring" : "exact"
            }

            func isInstalled(among installed: [String]) -> Bool {
                let needle = effectiveName.lowercased()
                guard !needle.isEmpty else { return false }
                if effectiveMatchMode == "substring" {
                    return installed.contains { $0.lowercased().contains(needle) }
                }
                return installed.contains {
                    let name = $0.lowercased()
                    return name == needle || name == "\(needle).app"
                }
            }
        }

        struct Thresholds: Codable {
            let critical: Int?
            let warning: Int?

            var effectiveCritical: Int { critical ?? 50 }
            var effectiveWarning: Int { warning ?? 80 }

            static let empty = Thresholds(critical: nil, warning: nil)
        }

        /// Minimum compliant OS major version per platform. Defaults track
        /// the current major releases (schema default; keep in sync with
        /// Helios_Features_SCHEMA.json).
        struct MinimumOSVersions: Codable {
            let macOS: Int?
            let iOS: Int?
            let iPadOS: Int?
            let visionOS: Int?

            var effectiveMacOS: Int { macOS ?? 26 }
            var effectiveIOS: Int { iOS ?? 26 }
            var effectiveIPadOS: Int { iPadOS ?? 26 }
            var effectiveVisionOS: Int { visionOS ?? 2 }

            static let empty = MinimumOSVersions(macOS: nil, iOS: nil, iPadOS: nil, visionOS: nil)
        }
    }

    // MARK: - Device Health

    struct DeviceHealthSettings: Codable {
        let metrics: [DeviceHealthMetricSetting]?

        var effectiveMetrics: [DeviceHealthMetricSetting] { metrics ?? Self.defaultMetrics }

        static let empty = DeviceHealthSettings(metrics: nil)

        /// The 16 default device-health metrics (mirrors the schema's `metrics` default).
        static let defaultMetrics: [DeviceHealthMetricSetting] = [
            DeviceHealthMetricSetting(id: "managementStatus", enabled: true, displayName: "",
                                      category: "management",
                                      platforms: ["macOS", "iOS", "iPadOS", "visionOS"]),
            DeviceHealthMetricSetting(id: "supervisionStatus", enabled: true, displayName: "",
                                      category: "management",
                                      platforms: ["macOS", "iOS", "iPadOS", "visionOS"]),
            DeviceHealthMetricSetting(id: "mdmCapability", enabled: true, displayName: "",
                                      category: "management", platforms: ["macOS"]),
            DeviceHealthMetricSetting(id: "userApprovedMDM", enabled: true, displayName: "",
                                      category: "management", platforms: ["macOS"]),
            DeviceHealthMetricSetting(id: "bootstrapToken", enabled: true, displayName: "",
                                      category: "management", platforms: ["macOS"]),
            DeviceHealthMetricSetting(id: "fileVault", enabled: true, displayName: "",
                                      category: "security", platforms: ["macOS"]),
            DeviceHealthMetricSetting(id: "firewall", enabled: true, displayName: "",
                                      category: "security", platforms: ["macOS"]),
            DeviceHealthMetricSetting(id: "gatekeeper", enabled: true, displayName: "",
                                      category: "security", platforms: ["macOS"]),
            DeviceHealthMetricSetting(id: "sip", enabled: true, displayName: "",
                                      category: "security", platforms: ["macOS"]),
            DeviceHealthMetricSetting(id: "secureToken", enabled: true, displayName: "",
                                      category: "security", platforms: ["macOS"]),
            DeviceHealthMetricSetting(id: "recoveryLock", enabled: true, displayName: "",
                                      category: "security", platforms: ["macOS"]),
            DeviceHealthMetricSetting(id: "activationLock", enabled: true, displayName: "",
                                      category: "security",
                                      platforms: ["macOS", "iOS", "iPadOS", "visionOS"]),
            DeviceHealthMetricSetting(id: "remoteDesktop", enabled: true, displayName: "",
                                      category: "status", platforms: ["macOS"]),
            DeviceHealthMetricSetting(id: "softwareUpdate", enabled: true, displayName: "",
                                      category: "compliance",
                                      platforms: ["macOS", "iOS", "iPadOS", "visionOS"]),
            DeviceHealthMetricSetting(id: "lastCheckIn", enabled: true, displayName: "",
                                      category: "status",
                                      platforms: ["macOS", "iOS", "iPadOS", "visionOS"]),
            DeviceHealthMetricSetting(id: "appleCare", enabled: true, displayName: "",
                                      category: "status",
                                      platforms: ["macOS", "iOS", "iPadOS", "visionOS"])
        ]
    }

    /// One device-health metric row. `category` is one of
    /// management / security / status / compliance (schema enum); kept as a
    /// raw string so an unrecognized value degrades gracefully instead of
    /// failing the domain decode.
    struct DeviceHealthMetricSetting: Codable {
        let id: String?
        let enabled: Bool?
        let displayName: String?
        let category: String?
        let platforms: [String]?

        var effectiveEnabled: Bool { enabled ?? true }
        var effectiveDisplayName: String { displayName ?? "" }
        var effectivePlatforms: [String] { platforms ?? [] }
    }

    // MARK: - Reports

    struct ReportsSettings: Codable {
        let enabled: Bool?
        let availableReports: [ReportSetting]?

        var effectiveEnabled: Bool { enabled ?? true }
        var effectiveAvailableReports: [ReportSetting] {
            availableReports ?? Self.defaultAvailableReports
        }

        static let empty = ReportsSettings(enabled: nil, availableReports: nil)

        /// The 8 default reports (mirrors the schema's `availableReports` default).
        static let defaultAvailableReports: [ReportSetting] = [
            ReportSetting(id: "deviceInventory", enabled: true, displayName: "",
                          category: "inventory",
                          platforms: ["macOS", "iOS", "iPadOS", "visionOS"],
                          exportFormats: ["csv", "json"]),
            ReportSetting(id: "securityCompliance", enabled: true, displayName: "",
                          category: "security", platforms: ["macOS"],
                          exportFormats: ["csv", "json"]),
            ReportSetting(id: "softwareUpdates", enabled: true, displayName: "",
                          category: "compliance",
                          platforms: ["macOS", "iOS", "iPadOS", "visionOS"],
                          exportFormats: ["csv", "json"]),
            ReportSetting(id: "applicationInventory", enabled: true, displayName: "",
                          category: "inventory", platforms: ["macOS", "iOS", "iPadOS"],
                          exportFormats: ["csv", "json"]),
            ReportSetting(id: "appleCareStatus", enabled: true, displayName: "",
                          category: "management",
                          platforms: ["macOS", "iOS", "iPadOS", "visionOS"],
                          exportFormats: ["csv", "json"]),
            ReportSetting(id: "certificateExpiration", enabled: true, displayName: "",
                          category: "security", platforms: ["macOS", "iOS", "iPadOS"],
                          exportFormats: ["csv", "json"]),
            ReportSetting(id: "fileVaultStatus", enabled: true, displayName: "",
                          category: "security", platforms: ["macOS"],
                          exportFormats: ["csv", "json"]),
            ReportSetting(id: "configurationProfiles", enabled: true, displayName: "",
                          category: "management",
                          platforms: ["macOS", "iOS", "iPadOS", "visionOS"],
                          exportFormats: ["csv", "json"])
        ]
    }

    /// One report definition row.
    struct ReportSetting: Codable {
        let id: String?
        let enabled: Bool?
        let displayName: String?
        let category: String?
        let platforms: [String]?
        let exportFormats: [String]?

        var effectiveEnabled: Bool { enabled ?? true }
        var effectiveDisplayName: String { displayName ?? "" }
        var effectivePlatforms: [String] { platforms ?? [] }
        var effectiveExportFormats: [String] { exportFormats ?? [] }
    }
}
