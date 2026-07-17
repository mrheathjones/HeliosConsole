//
//  AccessConfiguration.swift
//  HeliosConsole
//
//  Helios Console — Access (RBAC & destructive capability)
//  Managed-preference model for the access domain, deployed via
//  Jamf Pro > Configuration Profiles > Application & Custom Settings
//  and SCOPED TO ADMIN MACS ONLY.
//
//  Preference Domain MUST match the domain Helios reads:
//      com.herojoneslabs.helios.console.access
//  (Matches `AccessConfiguration.domain` below, the Jamf schema $id in
//   schemas/Helios_Access_SCHEMA.json, and the migration guide
//   docs/ConfigProfileMigration.md.)
//
//  Decoding: ManagedDomainLoader reads each top-level key out of
//  UserDefaults(suiteName: AccessConfiguration.domain) into a
//  [String: Any], then decodes it with PropertyListDecoder. Every stored
//  property is optional — a missing key must never fail the whole domain
//  decode. Defaults live in the computed `effective*` accessors, NOT inline.
//
//  Fail-closed: a Mac that never receives this profile resolves to no role
//  (every capability empty — see UserCapabilities.none) and no device-action
//  allow-list.
//

import Foundation

/// Codable model for the `com.herojoneslabs.helios.console.access` managed-preference
/// domain: the admin-authored role definitions (RBAC), this Mac's role name,
/// Cleanup defaults, and the device-action allow-list.
struct AccessConfiguration: Codable {

    /// Managed-preference domain this model is decoded from.
    static let domain = "com.herojoneslabs.helios.console.access"

    /// Schema/profile version stamp (informational — the loader logs it,
    /// nothing else reads it).
    var configurationVersion: String?

    /// Role name for this Mac, used ONLY when Entra sign-in is not
    /// configured (the Entra roles claim is authoritative when it is). A
    /// FREE-FORM string naming a `roles` entry's `name` — the app defines no
    /// roles of its own, so a value matching no entry grants nothing
    /// (fail-closed). Matched exactly, case-sensitively.
    var role: String?

    /// Admin-authored role definitions — an ARRAY of objects, each carrying
    /// its role name in the `name` field. The names are arbitrary and chosen
    /// entirely by the admin — they must match the Entra app-role values
    /// (roles claim) under Entra sign-in, or the `role` key above otherwise.
    /// A user holding several roles gets the UNION of their capabilities
    /// (see UserCapabilities.union).
    ///
    /// ARRAY, NOT A DICTIONARY, deliberately: an admin-keyed dictionary can
    /// only be expressed in JSON Schema as `additionalProperties`, which
    /// Jamf Pro's Application & Custom Settings form generator cannot render
    /// — admins would have to hand-edit XML. An array of objects with the
    /// name as a field renders as a repeatable form, matching the
    /// `deviceActions.computer.actions` precedent.
    ///
    /// Entries are indexed by name at composition time
    /// (MDMConfiguration.roleIndex(from:)), which SKIPS nameless entries and
    /// UNIONS duplicate names. Absent → no role is defined → EVERY user
    /// resolves to `UserCapabilities.none`. There is no built-in fallback role.
    var roles: [RoleDefinition]?

    /// Defaults for the Cleanup (stale device) feature.
    var cleanup: CleanupSettings?

    // MARK: - Effective accessors

    var effectiveConfigurationVersion: String { configurationVersion ?? "2.0" }
    var effectiveRoles: [RoleDefinition] { roles ?? [] }
    var effectiveCleanup: CleanupSettings { cleanup ?? CleanupSettings() }

    // MARK: - Domain decode (resilient by key)

    enum CodingKeys: String, CodingKey {
        case configurationVersion, role, roles, cleanup
    }

    init(
        configurationVersion: String? = nil,
        role: String? = nil,
        roles: [RoleDefinition]? = nil,
        cleanup: CleanupSettings? = nil
    ) {
        self.configurationVersion = configurationVersion
        self.role = role
        self.roles = roles
        self.cleanup = cleanup
    }

    /// Per-key resilient decode. ManagedDomainLoader catches a thrown decode
    /// and discards the ENTIRE domain — which would silently strip the
    /// device-action allow-list and every role definition over one typo'd
    /// value. So each key degrades on its own instead: a malformed key
    /// becomes nil, which every `effective*` accessor resolves fail-closed
    /// (nothing granted).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        configurationVersion = try? container.decode(String.self, forKey: .configurationVersion)
        role = try? container.decode(String.self, forKey: .role)
        roles = Self.decodeRoles(from: container)
        cleanup = try? container.decode(CleanupSettings.self, forKey: .cleanup)
    }

    /// Lenient `roles` decode over the array shape. Each element is decoded
    /// through `FailableRole`, whose init NEVER throws — so one undecodable
    /// entry (e.g. a role delivered as a string instead of an object) becomes
    /// nil and is SKIPPED rather than failing the array decode, which would
    /// discard every other role and, via the loader's catch, the whole access
    /// domain.
    ///
    /// `roles` present but not an array at all → `[]` (no roles defined;
    /// every user gets nothing, fail-closed).
    ///
    /// Nameless entries are NOT filtered here — names are resolved at
    /// composition time by `MDMConfiguration.roleIndex(from:)`, which skips
    /// them and unions duplicates, so every construction path gets the same
    /// treatment.
    private static func decodeRoles(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> [RoleDefinition]? {
        guard container.contains(.roles) else { return nil }

        guard let entries = try? container.decode([FailableRole].self, forKey: .roles) else {
            NSLog("⚠️ access.roles: 'roles' is not an array of role definitions — NO roles defined (every user gets no access, fail-closed)")
            return []
        }

        var decoded: [RoleDefinition] = []
        for (index, entry) in entries.enumerated() {
            guard let definition = entry.value else {
                NSLog("⚠️ access.roles: role entry at index %d is malformed — SKIPPED (other roles are unaffected)", index)
                continue
            }
            decoded.append(definition)
        }
        return decoded
    }

    /// Lossy element wrapper: absorbs an undecodable role entry instead of
    /// throwing, so the surrounding array decode always succeeds. Because the
    /// init never throws, the unkeyed container advances past every element
    /// normally.
    private struct FailableRole: Decodable {
        let value: RoleDefinition?

        init(from decoder: Decoder) throws {
            value = try? RoleDefinition(from: decoder)
        }
    }

    // MARK: - Role definition

    /// One admin-authored role: its NAME and the capabilities its holders
    /// receive. Every list is optional and resolves fail-closed when absent —
    /// a role that defines nothing grants nothing. Ids are matched EXACTLY:
    /// `modules` are sidebar/route ids, `computerActions` /
    /// `mobileDeviceActions` are DeviceAction raw values, and
    /// `cleanupActions` are CleanupAction configIDs.
    struct RoleDefinition: Codable {
        /// The admin-chosen role name. Optional at the type level because a
        /// missing key must never fail the decode — but a definition without
        /// a usable name is UNREACHABLE and gets skipped when the name index
        /// is built (see MDMConfiguration.roleIndex(from:)).
        var name: String?

        var modules: [String]?
        /// Devices-view tab ids this role may open (e.g. `abmLookup`,
        /// `prestage`). ORDERED like `modules`: array position is tab
        /// position after the app-defined base tab. The base device list is
        /// gated by the `devices` module, not listed here. Unknown ids are
        /// ignored so newer profiles deploy safely to older builds.
        var deviceTabs: [String]?
        var computerActions: [String]?
        var mobileDeviceActions: [String]?
        var cleanupActions: [String]?
        /// ABM MDM server names this role may assign devices TO (abmAssign)
        /// and unassign FROM (abmUnassign). Exact `serverName` match, plus
        /// the RESERVED literal `all` (any letter case) = every server.
        /// Absent/empty → the ABM actions are granted but have nothing to
        /// target (fail-closed). Gating is ROLE-ONLY.
        var allowedMdmServers: [String]?
        /// Jamf Computer PreStage displayNames this role may select — in the
        /// Pre-Stage tab AND the optional prestage-on-assign step. Exact
        /// names plus the RESERVED literal `all`. Absent/empty → no PreStage
        /// offered (fail-closed).
        var allowedPrestages: [String]?
        /// Whether abmAssign offers the optional PreStage registration step
        /// after a successful assignment. Absent → false (fail-closed).
        var allowPrestageOnAssign: Bool?
        /// Post-erase cleanup for returnToService. Both toggles default true
        /// (full decommission) so an absent object preserves the original
        /// behavior. The erase always runs and always waits for
        /// acknowledgment — only the cleanup steps are configurable.
        var returnToServiceOptions: ReturnToServiceOptions?
        var allowExport: Bool?

        /// The role name, trimmed. `""` when absent, blank, or malformed —
        /// which makes the definition unreachable (no role name can ever
        /// match it) and is what `roleIndex(from:)` skips on.
        var effectiveName: String {
            name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        /// Absent/malformed → [] (grants nothing); entries are trimmed and
        /// empties dropped so a stray space never becomes an unmatchable id.
        var effectiveModules: [String] { Self.normalizedList(modules) }
        var effectiveDeviceTabs: [String] { Self.normalizedList(deviceTabs) }
        var effectiveComputerActions: [String] { Self.normalizedList(computerActions) }
        var effectiveMobileDeviceActions: [String] { Self.normalizedList(mobileDeviceActions) }
        var effectiveCleanupActions: [String] { Self.normalizedList(cleanupActions) }
        var effectiveAllowedMdmServers: [String] { Self.normalizedList(allowedMdmServers) }
        var effectiveAllowedPrestages: [String] { Self.normalizedList(allowedPrestages) }

        /// Absent/malformed → false (fail-closed).
        var effectiveAllowPrestageOnAssign: Bool { allowPrestageOnAssign ?? false }
        var effectiveAllowExport: Bool { allowExport ?? false }

        enum CodingKeys: String, CodingKey {
            case name, modules, deviceTabs, computerActions, mobileDeviceActions, cleanupActions
            case allowedMdmServers, allowedPrestages, allowPrestageOnAssign, returnToServiceOptions, allowExport
        }

        init(
            name: String? = nil,
            modules: [String]? = nil,
            deviceTabs: [String]? = nil,
            computerActions: [String]? = nil,
            mobileDeviceActions: [String]? = nil,
            cleanupActions: [String]? = nil,
            allowedMdmServers: [String]? = nil,
            allowedPrestages: [String]? = nil,
            allowPrestageOnAssign: Bool? = nil,
            returnToServiceOptions: ReturnToServiceOptions? = nil,
            allowExport: Bool? = nil
        ) {
            self.name = name
            self.modules = modules
            self.deviceTabs = deviceTabs
            self.computerActions = computerActions
            self.mobileDeviceActions = mobileDeviceActions
            self.cleanupActions = cleanupActions
            self.allowedMdmServers = allowedMdmServers
            self.allowedPrestages = allowedPrestages
            self.allowPrestageOnAssign = allowPrestageOnAssign
            self.returnToServiceOptions = returnToServiceOptions
            self.allowExport = allowExport
        }

        /// Per-field resilient decode: a malformed list degrades to nil (that
        /// capability grants nothing) instead of failing the role — and a
        /// malformed `allowExport` degrades to false. One typo'd key never
        /// discards its correctly-typed siblings. Never throws for an object
        /// input, so a `[RoleDefinition]` decode only fails when an ENTRY
        /// isn't an object at all (absorbed by `FailableRole`/`decodeRoles`).
        ///
        /// A malformed `name` degrades to nil — i.e. an unreachable role that
        /// grants nobody anything, the fail-closed direction.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try? container.decode(String.self, forKey: .name)
            modules = Self.decodeList(container, .modules)
            deviceTabs = Self.decodeList(container, .deviceTabs)
            computerActions = Self.decodeList(container, .computerActions)
            mobileDeviceActions = Self.decodeList(container, .mobileDeviceActions)
            cleanupActions = Self.decodeList(container, .cleanupActions)
            allowedMdmServers = Self.decodeList(container, .allowedMdmServers)
            allowedPrestages = Self.decodeList(container, .allowedPrestages)
            allowPrestageOnAssign = Self.decodeBool(container, .allowPrestageOnAssign)
            returnToServiceOptions = try? container.decodeIfPresent(ReturnToServiceOptions.self, forKey: .returnToServiceOptions)
            allowExport = Self.decodeBool(container, .allowExport)
        }

        /// Present-but-malformed bool → false (fail-closed); absent → nil.
        private static func decodeBool(
            _ container: KeyedDecodingContainer<CodingKeys>,
            _ key: CodingKeys
        ) -> Bool? {
            guard container.contains(key) else { return nil }
            if let value = try? container.decode(Bool.self, forKey: key) { return value }
            NSLog("⚠️ access.roles: malformed '%@' — treated as FALSE (fail-closed)", key.rawValue)
            return false
        }

        private static func decodeList(
            _ container: KeyedDecodingContainer<CodingKeys>,
            _ key: CodingKeys
        ) -> [String]? {
            guard container.contains(key) else { return nil }
            if let values = try? container.decode([String].self, forKey: key) { return values }
            NSLog("⚠️ access.roles: malformed '%@' — treated as EMPTY (grants nothing, fail-closed)", key.rawValue)
            return []
        }

        /// Trims each entry and drops empties. Absent → [] (fail-closed):
        /// unlike the old tier lists there is no documented default to fall
        /// back to, because the app defines no roles of its own.
        private static func normalizedList(_ values: [String]?) -> [String] {
            (values ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
    }

    // MARK: - Cleanup settings (managed payload)

    /// The managed `cleanup` dictionary. Distinct from the app-local
    /// `CleanupSettings` service class (Cleanup/Services/CleanupSettings.swift);
    /// this nested type only carries the profile-delivered defaults.
    struct CleanupSettings: Codable {
        /// Stale threshold (days without check-in). Optional; see
        /// `effectiveStaleDays` for the default.
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
        /// integer or a string ("90"). Accept both — and never let a
        /// malformed value fail the whole domain decode.
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

    // MARK: - Return to Service cleanup options (role-scoped)

    /// Post-erase cleanup for the returnToService action. Both toggles
    /// default true (full decommission) so an absent object preserves the
    /// original behavior. The erase always runs and always waits for the
    /// device to acknowledge ERASE_DEVICE — only these cleanup steps are
    /// configurable. Multi-role note: unioned in UserCapabilities with OR
    /// (any granting role enabling a step enables it).
    struct ReturnToServiceOptions: Codable, Equatable {
        var deleteJamfRecord: Bool?
        var deleteEntraObject: Bool?

        var effectiveDeleteJamfRecord: Bool { deleteJamfRecord ?? true }
        var effectiveDeleteEntraObject: Bool { deleteEntraObject ?? true }

        static let empty = ReturnToServiceOptions()

        enum CodingKeys: String, CodingKey {
            case deleteJamfRecord, deleteEntraObject
        }

        init(deleteJamfRecord: Bool? = nil, deleteEntraObject: Bool? = nil) {
            self.deleteJamfRecord = deleteJamfRecord
            self.deleteEntraObject = deleteEntraObject
        }

        /// Per-field fail-closed decode: an absent toggle keeps its default
        /// (true), a present-but-undecodable toggle resolves to FALSE (skip
        /// the destructive step).
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            deleteJamfRecord = Self.decodeToggle(container, .deleteJamfRecord)
            deleteEntraObject = Self.decodeToggle(container, .deleteEntraObject)
        }

        private static func decodeToggle(
            _ container: KeyedDecodingContainer<CodingKeys>,
            _ key: CodingKeys
        ) -> Bool? {
            guard container.contains(key) else { return nil }
            if let value = try? container.decode(Bool.self, forKey: key) { return value }
            NSLog("⚠️ access.roles.returnToServiceOptions: malformed '%@' — treated as FALSE (skip step, fail-closed)", key.rawValue)
            return false
        }
    }

    // MARK: - ABM allow-list sentinel

    /// The reserved allow-list literal meaning "every server / PreStage",
    /// compared case-insensitively; real names compare exactly. Interpreted
    /// BEFORE any name match, so a server/PreStage literally named "all" can
    /// never be individually granted. Shared by UserCapabilities' ABM gates.
    enum ABMAllowList {
        static let sentinel = "all"

        static func containsSentinel(_ values: Set<String>) -> Bool {
            values.contains { $0.caseInsensitiveCompare(sentinel) == .orderedSame }
        }
    }
}