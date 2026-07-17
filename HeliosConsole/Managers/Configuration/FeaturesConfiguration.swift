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

    // MARK: - Effective accessors (defaults per schemas/Helios_Features_SCHEMA.json)

    var effectiveConfigurationVersion: String { configurationVersion ?? "2.0" }
    var effectiveComputers: ComputersSettings { computers ?? .empty }
    var effectiveMobileDevices: MobileDevicesSettings { mobileDevices ?? .empty }
    var effectiveHealthScorecard: HealthScorecardSettings { healthScorecard ?? .empty }
    var effectiveDeviceHealth: DeviceHealthSettings { deviceHealth ?? .empty }
    var effectiveReports: ReportsSettings { reports ?? .empty }
    var effectiveActionLog: ActionLogSettings { actionLog ?? .empty }

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
        actionLog: nil
    )

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

        var effectiveEnabled: Bool { enabled ?? true }
        var effectiveMetrics: [HealthMetricSetting] { metrics ?? Self.defaultMetrics }

        /// Lookup for a single metric's settings: the configured row wins,
        /// otherwise the built-in default row — so a profile that delivers
        /// only some metrics never blanks the tuning of the others.
        func effectiveMetric(id: String) -> HealthMetricSetting? {
            effectiveMetrics.first { $0.id == id }
                ?? Self.defaultMetrics.first { $0.id == id }
        }

        static let empty = HealthScorecardSettings(enabled: nil, metrics: nil)

        /// The 8 default scorecard metrics (mirrors the schema's `metrics` default).
        static let defaultMetrics: [HealthMetricSetting] = [
            HealthMetricSetting(id: "checkedIn", enabled: true, displayName: "Recent Check-Ins",
                                thresholds: .init(critical: 50, warning: 80), checkedInDays: 7,
                                platforms: ["macOS", "iOS", "iPadOS", "visionOS"]),
            HealthMetricSetting(id: "managed", enabled: true, displayName: "",
                                thresholds: .init(critical: 50, warning: 80), checkedInDays: 7,
                                platforms: ["macOS", "iOS", "iPadOS", "visionOS"]),
            HealthMetricSetting(id: "supervised", enabled: true, displayName: "",
                                thresholds: .init(critical: 50, warning: 80), checkedInDays: 7,
                                platforms: ["macOS", "iOS", "iPadOS", "visionOS"]),
            HealthMetricSetting(id: "fileVaultEnabled", enabled: true, displayName: "",
                                thresholds: .init(critical: 50, warning: 80), checkedInDays: 7,
                                platforms: ["macOS"]),
            HealthMetricSetting(id: "firewallEnabled", enabled: true, displayName: "",
                                thresholds: .init(critical: 50, warning: 80), checkedInDays: 7,
                                platforms: ["macOS"]),
            HealthMetricSetting(id: "gatekeeperEnabled", enabled: true, displayName: "",
                                thresholds: .init(critical: 50, warning: 80), checkedInDays: 7,
                                platforms: ["macOS"]),
            HealthMetricSetting(id: "sipEnabled", enabled: true, displayName: "",
                                thresholds: .init(critical: 50, warning: 80), checkedInDays: 7,
                                platforms: ["macOS"]),
            HealthMetricSetting(id: "softwareUpdateCompliance", enabled: true, displayName: "",
                                thresholds: .init(critical: 50, warning: 80), checkedInDays: 7,
                                platforms: ["macOS", "iOS", "iPadOS", "visionOS"])
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
        /// on the `softwareUpdateCompliance` metric.
        let minimumOSVersions: MinimumOSVersions?

        var effectiveEnabled: Bool { enabled ?? true }
        var effectiveDisplayName: String { displayName ?? "" }
        var effectiveThresholds: Thresholds { thresholds ?? .empty }
        /// Clamped 1...3650 — an absurd profile value must not break
        /// Calendar date math downstream.
        var effectiveCheckedInDays: Int { min(max(checkedInDays ?? 7, 1), 3650) }
        var effectivePlatforms: [String] { platforms ?? [] }
        var effectiveMinimumOSVersions: MinimumOSVersions { minimumOSVersions ?? .empty }

        init(
            id: String? = nil,
            enabled: Bool? = nil,
            displayName: String? = nil,
            thresholds: Thresholds? = nil,
            checkedInDays: Int? = nil,
            platforms: [String]? = nil,
            minimumOSVersions: MinimumOSVersions? = nil
        ) {
            self.id = id
            self.enabled = enabled
            self.displayName = displayName
            self.thresholds = thresholds
            self.checkedInDays = checkedInDays
            self.platforms = platforms
            self.minimumOSVersions = minimumOSVersions
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
