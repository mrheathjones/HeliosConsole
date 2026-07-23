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
/// HOME DOMAIN: `features.cleanup` — read from there and nowhere else. It
/// moved from `access.cleanup` in the schema-3.0 domain cleanup; the
/// transitional read of the access block has been REMOVED, so the block in a
/// stale access profile is ignored and the values fall to their defaults.
/// These values GRANT NOTHING — which roles may see the
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

}

/// The managed `localAdministration` block: the local admin account whose
/// LAPS password Helios looks up in DeviceView.
///
/// HOME DOMAIN: `features.localAdministration` — read from there and nowhere
/// else. It moved from `core.localAdministration` in the schema-3.0 domain
/// cleanup; the transitional read of the core copy has been REMOVED, so the
/// key in a stale core profile is ignored and the value falls to its default.
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
    /// cleanup: these turn FEATURES on and off — they are not branding.
    /// Read from here and nowhere else — the transitional read of the ui
    /// copies was REMOVED at schema 3.0, so the keys in a stale ui profile
    /// are ignored and the values fall to their defaults (both true).
    let userExperience: UserExperienceSettings?

    /// Cleanup module tunables (stale threshold, default static group and
    /// site). MOVED HERE from the access domain during the domain cleanup:
    /// the access domain is for GRANTS, and these grant nothing — they tune a
    /// feature. Which roles may SEE Cleanup and which sub-actions they may run
    /// stay in access (`roles[].modules` / `cleanupActions`). Read from here
    /// and nowhere else — the transitional read of the access block was
    /// REMOVED at schema 3.0.
    let cleanup: ManagedCleanupSettings?

    /// Local administrator account settings for the DeviceView LAPS lookup.
    /// MOVED HERE from the core domain: core is connection and integration
    /// identity, and this is a feature of a view. Read from here and nowhere
    /// else — the transitional read of the core copy was REMOVED at schema 3.0.
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
        /// Opt-in: surface the per-device "History" section (Jamf Policy Logs +
        /// MDM command history, from the Classic `computerhistory` endpoint).
        /// Defaults OFF — enable per org that wants it.
        let showDeviceHistory: Bool?
        /// Rows shown per page in the History section (Policy Logs / Management
        /// History). Client-side paging over the full fetched record.
        let historyPageSize: Int?

        var effectiveEnabled: Bool { enabled ?? true }
        var effectiveFetchInventory: Bool { fetchInventory ?? true }
        var effectiveShowDashboardCard: Bool { showDashboardCard ?? true }
        var effectiveEnableReports: Bool { enableReports ?? true }
        var effectiveInventoryRefreshInterval: Int { inventoryRefreshInterval ?? 15 }
        var effectiveShowDeviceHistory: Bool { showDeviceHistory ?? false }
        /// Clamped to at least 1 — a 0/negative page size would divide-by-zero
        /// the pagination math.
        var effectiveHistoryPageSize: Int { max(1, historyPageSize ?? 25) }
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
            inventoryRefreshInterval: nil, inventorySections: nil,
            showDeviceHistory: nil, historyPageSize: nil
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

    /// The scorecard is an INCLUSION model: the admin declares which cards they
    /// want and, per card, which Jamf sites or groups define the population.
    /// Helios hardcodes no site or group anywhere — it cannot know them.
    ///
    /// Everything is addressed by Jamf **id**, never name. A site or group can be
    /// renamed in Jamf; a rename must not silently change what is counted. Names
    /// are resolved from device records for display only.
    struct HealthScorecardSettings: Codable {
        let enabled: Bool?
        /// One entry per card. A card omitted here is not rendered at all —
        /// distinct from a card present but scoped to nothing.
        let cards: [HealthCard]?

        var effectiveEnabled: Bool { enabled ?? true }
        /// nil when the profile delivers no cards: every card renders its setup
        /// state. Deliberately NOT a default set of cards — shipping tenant
        /// specific sites or groups is exactly what this model removes.
        var effectiveCards: [HealthCard]? { cards }

        func card(id: String) -> HealthCard? { cards?.first { $0.id == id } }

        static let empty = HealthScorecardSettings(enabled: nil, cards: nil)

        init(enabled: Bool?, cards: [HealthCard]?) {
            self.enabled = enabled
            self.cards = cards
        }

        /// `HealthCard.init(from:)` needs a keyed container, so a `cards` array
        /// holding a bare string throws. ManagedDomainLoader discards the ENTIRE
        /// features domain on any throw, so that typo would take computers,
        /// mobileDevices, reports and cleanup with it. Decode element by element.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try? container.decode(Bool.self, forKey: .enabled)

            guard container.contains(.cards) else { cards = nil; return }
            if let rows = try? container.decode([FailableCard].self, forKey: .cards) {
                let kept = rows.compactMap(\.value)
                if kept.count != rows.count {
                    NSLog("⚠️ healthScorecard.cards: dropped %d malformed entr%@",
                          rows.count - kept.count, rows.count - kept.count == 1 ? "y" : "ies")
                }
                cards = kept
            } else {
                NSLog("⚠️ healthScorecard.cards: not an array of objects — ignoring")
                cards = nil
            }
        }

        private struct FailableCard: Decodable {
            let value: HealthCard?
            init(from decoder: Decoder) throws { value = try? HealthCard(from: decoder) }
        }
    }

    /// One scorecard card. `id` is the metric's stable config id
    /// (HealthMetricType.configID), never its display string.
    struct HealthCard: Codable {
        let id: String?
        let enabled: Bool?
        let thresholds: Thresholds?
        /// Platforms this card measures; omitted = all.
        let platforms: [String]?
        // --- Population: who this card measures ---
        //
        // Held directly on the card rather than on a nested target list. An
        // earlier shape wrapped these in `targets[]` so one card could hold two
        // populations with different requirements; that nests three array levels
        // deep and Jamf's Custom Schema form will not render the innermost one,
        // which makes it unauthorable. A card now measures ONE population against
        // ONE standard — express a second standard as a second card.
        /// Measure every device, ignoring sites and groups. Must be stated
        /// affirmatively: an empty selector set means measure NOTHING, because
        /// lenient decode turns malformed input into empty arrays and inferring
        /// "everything" from silence would let a typo rescope the whole fleet.
        let allDevices: Bool?
        let siteIds: [String]?
        /// Computer groups and mobile-device groups are SEPARATE Jamf id
        /// namespaces — one `groupIds` key would make computer-group-12 and
        /// mobile-group-12 silently interchangeable.
        let computerGroupIds: [String]?
        let mobileGroupIds: [String]?

        // --- Requirements: which apply depends on the metric ---
        let requiredApps: [RequiredApp]?
        /// `all` (default) | `any`
        let requireMode: String?
        /// firewall, sip, gatekeeper, managed, supervised, diskEncrypted,
        /// bootstrapToken, ddm
        let checks: [String]?
        let checkedInDays: Int?
        let minimumOSVersions: MinimumOSVersions?
        /// Subtractive carve-out applied before targeting. Exists because
        /// "this site except one group inside it" cannot be written as an
        /// inclusion without enumerating the complement, which would need a group
        /// directory the app does not fetch.
        let except: [ScopeSelector]?
        /// What a device matching no target scores: `excluded` (default) or
        /// `unknown`. Excluded is the point of the inclusion model — untargeted
        /// devices leave the metric rather than being enumerated. `unknown` turns
        /// the card into a coverage audit.
        let unmatchedVerdict: String?

        var effectiveEnabled: Bool { enabled ?? true }
        var effectiveThresholds: Thresholds { thresholds ?? .empty }
        var effectivePlatforms: [String] { platforms ?? [] }
        var effectiveExcept: [ScopeSelector] { except ?? [] }
        /// Unrecognised values fall back to `excluded` rather than being trusted.
        var effectiveUnmatchedVerdict: String {
            (unmatchedVerdict ?? "excluded").lowercased() == "unknown" ? "unknown" : "excluded"
        }

        var effectiveSiteIds: [String] { (siteIds ?? []).map(Self.normalizedID) }
        var effectiveComputerGroupIds: [String] { (computerGroupIds ?? []).map(Self.normalizedID) }
        var effectiveMobileGroupIds: [String] { (mobileGroupIds ?? []).map(Self.normalizedID) }
        var effectiveRequiredApps: [RequiredApp] { requiredApps ?? [] }
        var effectiveRequireMode: String {
            (requireMode ?? "all").lowercased() == "any" ? "any" : "all"
        }
        var effectiveChecks: [String] { checks ?? [] }
        var effectiveCheckedInDays: Int { min(max(checkedInDays ?? 7, 1), 3650) }
        var effectiveMinimumOSVersions: MinimumOSVersions { minimumOSVersions ?? .empty }
        var matchesAllDevices: Bool { allDevices == true }

        /// A card with no selectors measures nothing and renders a setup state
        /// rather than a percentage: 0/0 is 0% or 100% depending on which line of
        /// arithmetic you write, and both readings lie.
        var isConfigured: Bool {
            matchesAllDevices
                || !effectiveSiteIds.isEmpty
                || !effectiveComputerGroupIds.isEmpty
                || !effectiveMobileGroupIds.isEmpty
        }

        /// Jamf returns ids as strings in some payloads and integers in others,
        /// and admins hand-type them with stray whitespace.
        static func normalizedID(_ id: String?) -> String {
            (id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// Whether this card covers the given device.
        func covers(siteId: String?, groupIDs: [String], isMobile: Bool) -> Bool {
            if matchesAllDevices { return true }
            let site = Self.normalizedID(siteId)
            if !site.isEmpty, effectiveSiteIds.contains(site) { return true }
            let groupTargets = isMobile ? effectiveMobileGroupIds : effectiveComputerGroupIds
            guard !groupTargets.isEmpty else { return false }
            let normalized = Set(groupIDs.map(Self.normalizedID))
            return groupTargets.contains { normalized.contains($0) }
        }

        func appliesTo(platform: String) -> Bool {
            let list = effectivePlatforms
            guard !list.isEmpty else { return true }
            return list.contains { $0.caseInsensitiveCompare(platform) == .orderedSame }
        }

        init(
            id: String? = nil, enabled: Bool? = nil,
            thresholds: Thresholds? = nil, platforms: [String]? = nil,
            allDevices: Bool? = nil, siteIds: [String]? = nil,
            computerGroupIds: [String]? = nil, mobileGroupIds: [String]? = nil,
            requiredApps: [RequiredApp]? = nil, requireMode: String? = nil,
            checks: [String]? = nil, checkedInDays: Int? = nil,
            minimumOSVersions: MinimumOSVersions? = nil,
            except: [ScopeSelector]? = nil, unmatchedVerdict: String? = nil
        ) {
            self.id = id; self.enabled = enabled
            self.thresholds = thresholds; self.platforms = platforms
            self.allDevices = allDevices; self.siteIds = siteIds
            self.computerGroupIds = computerGroupIds; self.mobileGroupIds = mobileGroupIds
            self.requiredApps = requiredApps; self.requireMode = requireMode
            self.checks = checks; self.checkedInDays = checkedInDays
            self.minimumOSVersions = minimumOSVersions
            self.except = except; self.unmatchedVerdict = unmatchedVerdict
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try? c.decode(String.self, forKey: .id)
            enabled = try? c.decode(Bool.self, forKey: .enabled)
            thresholds = try? c.decode(Thresholds.self, forKey: .thresholds)
            platforms = try? c.decode([String].self, forKey: .platforms)
            unmatchedVerdict = try? c.decode(String.self, forKey: .unmatchedVerdict)
            allDevices = try? c.decode(Bool.self, forKey: .allDevices)
            siteIds = try? c.decode([String].self, forKey: .siteIds)
            computerGroupIds = try? c.decode([String].self, forKey: .computerGroupIds)
            mobileGroupIds = try? c.decode([String].self, forKey: .mobileGroupIds)
            requiredApps = (try? c.decode([FailableApp].self, forKey: .requiredApps))?
                .compactMap(\.value)
            requireMode = try? c.decode(String.self, forKey: .requireMode)
            checks = try? c.decode([String].self, forKey: .checks)
            checkedInDays = try? c.decode(Int.self, forKey: .checkedInDays)
            minimumOSVersions = try? c.decode(MinimumOSVersions.self, forKey: .minimumOSVersions)
            except = (try? c.decode([FailableSelector].self, forKey: .except))?.compactMap(\.value)
        }

        private struct FailableApp: Decodable {
            let value: RequiredApp?
            init(from decoder: Decoder) throws { value = try? RequiredApp(from: decoder) }
        }
        private struct FailableSelector: Decodable {
            let value: ScopeSelector?
            init(from decoder: Decoder) throws { value = try? ScopeSelector(from: decoder) }
        }

        struct Thresholds: Codable {
            let critical: Int?
            let warning: Int?
            var effectiveCritical: Int { critical ?? 50 }
            var effectiveWarning: Int { warning ?? 80 }
            static let empty = Thresholds(critical: nil, warning: nil)
        }
    }

    /// A single site or group reference, used by a card's `except` carve-out.
    struct ScopeSelector: Codable {
        /// `site` | `computerGroup` | `mobileGroup`
        let type: String?
        let id: String?
        let comment: String?

        enum Kind: String { case site, computerGroup, mobileGroup }

        var kind: Kind? {
            switch (type ?? "").lowercased() {
            case "site": return .site
            case "computergroup": return .computerGroup
            case "mobilegroup": return .mobileGroup
            default: return nil
            }
        }
        var effectiveID: String { HealthCard.normalizedID(id) }
        var label: String {
            if let comment, !comment.isEmpty { return comment }
            return "\(type ?? "?") \(effectiveID)"
        }

        init(type: String? = nil, id: String? = nil, comment: String? = nil) {
            self.type = type; self.id = id; self.comment = comment
        }

        func matches(siteId: String?, groupIDs: [String], isMobile: Bool) -> Bool {
            let target = effectiveID
            guard !target.isEmpty, let kind else { return false }
            switch kind {
            case .site:
                return HealthCard.normalizedID(siteId) == target
            case .computerGroup:
                guard !isMobile else { return false }
                return groupIDs.contains { HealthCard.normalizedID($0) == target }
            case .mobileGroup:
                guard isMobile else { return false }
                return groupIDs.contains { HealthCard.normalizedID($0) == target }
            }
        }
    }

    /// An app a target requires. `matchMode` is per-app so one token needing
    /// loose matching does not force every entry to be loose.
    struct RequiredApp: Codable {
        let name: String?
        /// `exact` (default, matches "Name" or "Name.app") | `substring`
        let matchMode: String?

        init(name: String? = nil, matchMode: String? = nil) {
            self.name = name; self.matchMode = matchMode
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

    /// Minimum compliant OS major version per platform.
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
