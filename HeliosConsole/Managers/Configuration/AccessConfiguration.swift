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

    /// Per-action allow-list for device commands.
    var deviceActions: DeviceActionsSettings?

    // MARK: - Effective accessors

    var effectiveConfigurationVersion: String { configurationVersion ?? "2.0" }
    var effectiveRoles: [RoleDefinition] { roles ?? [] }
    var effectiveCleanup: CleanupSettings { cleanup ?? CleanupSettings() }
    var effectiveDeviceActions: DeviceActionsSettings { deviceActions ?? DeviceActionsSettings() }

    // MARK: - Domain decode (resilient by key)

    enum CodingKeys: String, CodingKey {
        case configurationVersion, role, roles, cleanup, deviceActions
    }

    init(
        configurationVersion: String? = nil,
        role: String? = nil,
        roles: [RoleDefinition]? = nil,
        cleanup: CleanupSettings? = nil,
        deviceActions: DeviceActionsSettings? = nil
    ) {
        self.configurationVersion = configurationVersion
        self.role = role
        self.roles = roles
        self.cleanup = cleanup
        self.deviceActions = deviceActions
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
        deviceActions = try? container.decode(DeviceActionsSettings.self, forKey: .deviceActions)
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
        /// Jamf Computer PreStage displayNames selectable in the Pre-Stage
        /// tab. Same matching rules as DeviceActionOptions.allowedMdmServers:
        /// exact names, plus the RESERVED literal `all` (any letter case)
        /// meaning every PreStage. Absent/empty → the tab (if granted via
        /// deviceTabs) offers nothing — fail-closed. Distinct from the
        /// abmAssign option of the same name, which scopes the
        /// prestage-on-assign step, not this tab.
        var allowedPrestages: [String]?
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
        var effectiveAllowedPrestages: [String] { Self.normalizedList(allowedPrestages) }

        /// Absent/malformed → false (fail-closed).
        var effectiveAllowExport: Bool { allowExport ?? false }

        enum CodingKeys: String, CodingKey {
            case name, modules, deviceTabs, computerActions, mobileDeviceActions, cleanupActions, allowedPrestages, allowExport
        }

        init(
            name: String? = nil,
            modules: [String]? = nil,
            deviceTabs: [String]? = nil,
            computerActions: [String]? = nil,
            mobileDeviceActions: [String]? = nil,
            cleanupActions: [String]? = nil,
            allowedPrestages: [String]? = nil,
            allowExport: Bool? = nil
        ) {
            self.name = name
            self.modules = modules
            self.deviceTabs = deviceTabs
            self.computerActions = computerActions
            self.mobileDeviceActions = mobileDeviceActions
            self.cleanupActions = cleanupActions
            self.allowedPrestages = allowedPrestages
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
            allowedPrestages = Self.decodeList(container, .allowedPrestages)

            if container.contains(.allowExport) {
                if let value = try? container.decode(Bool.self, forKey: .allowExport) {
                    allowExport = value
                } else {
                    allowExport = false
                    NSLog("⚠️ access.roles: malformed 'allowExport' — treated as FALSE (fail-closed)")
                }
            } else {
                allowExport = nil
            }
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

    // MARK: - Device action allow-list

    /// One entry in the per-action allow-list. Mirrors the features domain's
    /// per-item idiom ({id, enabled, displayName} — see HealthMetricSetting).
    /// Listing an id IS the grant: `enabled` omitted → true. `displayName`
    /// overrides the Actions-menu label only — confirmation-dialog safety
    /// copy is never profile-controlled. `options` carries per-action tuning
    /// consumed only by composite actions (see DeviceActionOptions).
    struct DeviceActionSetting: Codable {
        var id: String?
        var enabled: Bool?
        var displayName: String?
        var options: DeviceActionOptions?

        var effectiveEnabled: Bool { enabled ?? true }
        var effectiveDisplayName: String { displayName ?? "" }
        var effectiveOptions: DeviceActionOptions { options ?? .empty }

        enum CodingKeys: String, CodingKey {
            case id, enabled, displayName, options
        }

        init(
            id: String? = nil,
            enabled: Bool? = nil,
            displayName: String? = nil,
            options: DeviceActionOptions? = nil
        ) {
            self.id = id
            self.enabled = enabled
            self.displayName = displayName
            self.options = options
        }

        /// Per-field resilient decode: a malformed value (e.g. `options`
        /// delivered as a string) degrades that field instead of failing the
        /// whole actions array — which would cascade into the strict
        /// fail-closed path and hide the entire Actions menu over one typo'd
        /// profile value. Degradation direction matters on this surface:
        /// a present-but-undecodable `enabled` is a DENY (never a grant),
        /// and a present-but-undecodable `options` disables every cleanup
        /// step (never "run everything"). Absent keys keep their normal
        /// defaults (listing an id IS the grant).
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try? container.decode(String.self, forKey: .id)

            if container.contains(.enabled) {
                if let value = try? container.decode(Bool.self, forKey: .enabled) {
                    enabled = value
                } else {
                    enabled = false
                    NSLog("⚠️ deviceActions: malformed 'enabled' for id '%@' — treated as DISABLED (fail-closed)", (try? container.decode(String.self, forKey: .id)) ?? "?")
                }
            } else {
                enabled = nil
            }

            displayName = try? container.decode(String.self, forKey: .displayName)

            if container.contains(.options) {
                if let value = try? container.decode(DeviceActionOptions.self, forKey: .options) {
                    options = value
                } else {
                    options = DeviceActionOptions(deleteJamfRecord: false, deleteEntraObject: false)
                    NSLog("⚠️ deviceActions: malformed 'options' for id '%@' — all cleanup steps DISABLED (fail-closed)", (try? container.decode(String.self, forKey: .id)) ?? "?")
                }
            } else {
                options = nil
            }
        }
    }

    /// The optional `options` object on an allow-list entry. Consulted by
    /// the `returnToService` composite (cleanup toggles) and the
    /// `abmAssign` / `abmUnassign` actions (MDM-server / PreStage scoping)
    /// — every other action ignores it. The RTS toggles default to true so
    /// an absent options object reproduces the original full-decommission
    /// behavior on already-deployed profiles; the ABM lists default to
    /// EMPTY (nothing assignable) because there is no safe default target.
    /// The erase itself is not optional and always waits for acknowledgment
    /// — only the post-ack cleanup steps are configurable here.
    struct DeviceActionOptions: Codable {
        /// Remove the Jamf computer record after the erase is acknowledged.
        var deleteJamfRecord: Bool?
        /// Delete the Entra device object after the erase is acknowledged
        /// (auto-skipped when Entra isn't configured).
        var deleteEntraObject: Bool?
        /// ABM MDM server names this grant may assign devices to (and, for
        /// `abmUnassign`, unassign from). Names match ABM's serverName
        /// EXACTLY (case-sensitive) — except the RESERVED literal `all`
        /// (any letter case), which grants every server. A server actually
        /// named "all" in ABM can therefore never be individually granted.
        /// Absent/empty → no server may be targeted (the grant is inert).
        var allowedMdmServers: [String]?
        /// Whether `abmAssign` may also offer the optional PreStage
        /// registration step after a successful ABM assignment.
        var allowPrestageOnAssign: Bool?
        /// Jamf PreStage displayNames offerable when
        /// `allowPrestageOnAssign` is true. Same matching rules as
        /// `allowedMdmServers`, including the reserved `all` literal.
        var allowedPrestages: [String]?

        var effectiveDeleteJamfRecord: Bool { deleteJamfRecord ?? true }
        var effectiveDeleteEntraObject: Bool { deleteEntraObject ?? true }

        /// Absent/malformed → [] (nothing may be targeted, fail-closed).
        var effectiveAllowedMdmServers: [String] { Self.normalizedList(allowedMdmServers) }
        /// Absent/malformed → false (fail-closed).
        var effectiveAllowPrestageOnAssign: Bool { allowPrestageOnAssign ?? false }
        var effectiveAllowedPrestages: [String] { Self.normalizedList(allowedPrestages) }

        /// The reserved allow-list literal meaning "every server/PreStage".
        /// Compared case-insensitively; real names are compared exactly.
        static let allSentinel = "all"

        var allowsAllMdmServers: Bool {
            Self.containsAllSentinel(effectiveAllowedMdmServers)
        }

        var allowsAllPrestages: Bool {
            Self.containsAllSentinel(effectiveAllowedPrestages)
        }

        /// Whether this grant permits targeting the named MDM server. The
        /// sentinel is interpreted BEFORE any name comparison, so a server
        /// literally named "all" can never be matched by name. The candidate
        /// is trimmed to match normalizedList's treatment of the allow-list
        /// entries — otherwise a whitespace-padded real name would be
        /// permanently inexpressible.
        func permitsMdmServer(named name: String) -> Bool {
            let candidate = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return allowsAllMdmServers || effectiveAllowedMdmServers.contains(candidate)
        }

        /// Whether this grant permits offering the named PreStage. Enforces
        /// its own gate: false whenever `allowPrestageOnAssign` is off, so a
        /// caller can never resurface a disabled offer by checking only the
        /// name list.
        func permitsPrestage(named name: String) -> Bool {
            guard effectiveAllowPrestageOnAssign else { return false }
            let candidate = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return allowsAllPrestages || effectiveAllowedPrestages.contains(candidate)
        }

        /// No keys delivered — every toggle resolves to its default.
        static let empty = DeviceActionOptions()

        enum CodingKeys: String, CodingKey {
            case deleteJamfRecord, deleteEntraObject
            case allowedMdmServers, allowPrestageOnAssign, allowedPrestages
        }

        init(
            deleteJamfRecord: Bool? = nil,
            deleteEntraObject: Bool? = nil,
            allowedMdmServers: [String]? = nil,
            allowPrestageOnAssign: Bool? = nil,
            allowedPrestages: [String]? = nil
        ) {
            self.deleteJamfRecord = deleteJamfRecord
            self.deleteEntraObject = deleteEntraObject
            self.allowedMdmServers = allowedMdmServers
            self.allowPrestageOnAssign = allowPrestageOnAssign
            self.allowedPrestages = allowedPrestages
        }

        /// Per-field fail-closed decode: an absent toggle keeps its default,
        /// but a present-but-undecodable value resolves in the denying
        /// direction — FALSE for toggles (skip the step / withhold the
        /// PreStage offer), EMPTY for the ABM lists (nothing may be
        /// targeted) — and one typo'd key never discards its
        /// correctly-typed siblings.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            deleteJamfRecord = Self.decodeToggle(container, .deleteJamfRecord)
            deleteEntraObject = Self.decodeToggle(container, .deleteEntraObject)
            allowedMdmServers = Self.decodeList(container, .allowedMdmServers)
            allowPrestageOnAssign = Self.decodeToggle(container, .allowPrestageOnAssign)
            allowedPrestages = Self.decodeList(container, .allowedPrestages)
        }

        private static func decodeToggle(
            _ container: KeyedDecodingContainer<CodingKeys>,
            _ key: CodingKeys
        ) -> Bool? {
            guard container.contains(key) else { return nil }
            if let value = try? container.decode(Bool.self, forKey: key) { return value }
            NSLog("⚠️ deviceActions.options: malformed '%@' — treated as FALSE (fail-closed)", key.rawValue)
            return false
        }

        private static func decodeList(
            _ container: KeyedDecodingContainer<CodingKeys>,
            _ key: CodingKeys
        ) -> [String]? {
            guard container.contains(key) else { return nil }
            if let values = try? container.decode([String].self, forKey: key) { return values }
            NSLog("⚠️ deviceActions.options: malformed '%@' — treated as EMPTY (nothing granted, fail-closed)", key.rawValue)
            return []
        }

        private static func normalizedList(_ values: [String]?) -> [String] {
            (values ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        private static func containsAllSentinel(_ values: [String]) -> Bool {
            values.contains { $0.caseInsensitiveCompare(allSentinel) == .orderedSame }
        }
    }

    /// The managed `deviceActions` dictionary — a STRICT FAIL-CLOSED
    /// allow-list enforced by DeviceActionPolicy (DeviceView actionsMenu +
    /// executeAction). No `actions` array delivered for a platform → no
    /// action is available and the Actions menu is hidden. An id not listed
    /// (or listed with enabled=false) is hidden and blocked. Unknown ids are
    /// ignored so newer profiles deploy safely to older app builds.
    /// Matches schemas/Helios_Access_SCHEMA.json.
    struct DeviceActionsSettings: Codable {
        var computer: PlatformActions?
        var mobileDevice: PlatformActions?

        /// Per-platform allow-list. `actions == nil` means the platform's
        /// allow-list was never delivered (fail-closed: nothing granted) —
        /// deliberately distinct from an explicit empty array, though the
        /// outcome is the same.
        struct PlatformActions: Codable {
            var actions: [DeviceActionSetting]?

            /// Grants keyed by action id (later duplicates win); nil when no
            /// allow-list was delivered. Consumed by DeviceActionPolicy.
            var grantsByID: [String: DeviceActionSetting]? {
                guard let actions else { return nil }
                var grants: [String: DeviceActionSetting] = [:]
                for setting in actions {
                    guard let id = setting.id, !id.isEmpty else { continue }
                    grants[id] = setting
                }
                return grants
            }

            init(actions: [DeviceActionSetting]? = nil) {
                self.actions = actions
            }

            /// Custom decode with a legacy shim: the v2.0 access schema
            /// shipped this block as a flat boolean map
            /// (e.g. `computer.restart = true`). If no `actions` array is
            /// present, synthesize one from any boolean keys that WERE
            /// delivered. Strict-cutover semantics apply to the legacy shape
            /// too: only explicitly delivered keys become grants — the old
            /// per-key defaults are not resurrected (they were never
            /// enforced by any released build). Never fails the domain
            /// decode.
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: DynamicKey.self)

                if let actionsKey = DynamicKey(stringValue: "actions"),
                   container.contains(actionsKey),
                   let decoded = try? container.decode([DeviceActionSetting].self, forKey: actionsKey) {
                    // A profile carrying BOTH shapes is a half-migrated v2.0
                    // profile: the flat booleans read like grants and do
                    // nothing, so an admin sees actions missing with no clue.
                    let strays = container.allKeys
                        .filter { $0.stringValue != "actions" }
                        .filter { (try? container.decode(Bool.self, forKey: $0)) != nil }
                        .map(\.stringValue)
                        .sorted()
                    if !strays.isEmpty {
                        print("⚠️ access.deviceActions: legacy flat action keys IGNORED — the 'actions' "
                              + "array is authoritative. Add these to it if they are meant to be "
                              + "available: \(strays.joined(separator: ", "))")
                    }
                    actions = decoded
                    return
                }

                var legacy: [DeviceActionSetting] = []
                for key in container.allKeys where key.stringValue != "actions" {
                    if let enabled = try? container.decode(Bool.self, forKey: key) {
                        legacy.append(DeviceActionSetting(id: key.stringValue, enabled: enabled))
                    }
                }
                actions = legacy.isEmpty ? nil : legacy
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: DynamicKey.self)
                if let actions, let key = DynamicKey(stringValue: "actions") {
                    try container.encode(actions, forKey: key)
                }
            }

            private struct DynamicKey: CodingKey {
                var stringValue: String
                var intValue: Int? { nil }
                init?(stringValue: String) { self.stringValue = stringValue }
                init?(intValue: Int) { return nil }
            }
        }
    }
}
