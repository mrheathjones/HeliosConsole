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
//  Fail-closed: a Mac that never receives this profile resolves to
//  role=User (Cleanup hidden) and the default device-action allow-list.
//

import Foundation

/// Codable model for the `com.herojoneslabs.helios.console.access` managed-preference
/// domain: operator role (RBAC), Cleanup defaults, and the device-action
/// allow-list.
struct AccessConfiguration: Codable {

    /// Managed-preference domain this model is decoded from.
    static let domain = "com.herojoneslabs.helios.console.access"

    /// Schema/profile version stamp (informational — the loader logs it,
    /// nothing else reads it).
    var configurationVersion: String?

    /// Operator role string as delivered by MDM ("Admin" / "Support" /
    /// "User"). Never compare this raw value directly — resolve it through
    /// `appRole`, which fails closed.
    var role: String?

    /// Defaults for the Admin-only Cleanup (stale device) feature.
    var cleanup: CleanupSettings?

    /// Per-action allow-list for device commands.
    var deviceActions: DeviceActionsSettings?

    // MARK: - Role (fail-closed)

    enum AppRole: String {
        case admin = "Admin"
        case support = "Support"
        case user = "User"
    }

    /// Resolves the operator role fail-closed: a missing, blank, or
    /// unrecognized value (including wrong case like "admin") is treated as
    /// the least-privileged `.user`, so the destructive Cleanup feature is
    /// never exposed by accident. Only the exact string "Admin" grants it.
    /// Mirrors `MDMConfiguration.appRole`.
    var appRole: AppRole {
        guard let role, let parsed = AppRole(rawValue: role) else { return .user }
        return parsed
    }

    /// Whether the Cleanup feature should be available to this operator.
    var isCleanupAdmin: Bool { appRole == .admin }

    // MARK: - Effective accessors

    var effectiveConfigurationVersion: String { configurationVersion ?? "2.0" }
    var effectiveCleanup: CleanupSettings { cleanup ?? CleanupSettings() }
    var effectiveDeviceActions: DeviceActionsSettings { deviceActions ?? DeviceActionsSettings() }

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

    /// The optional `options` object on an allow-list entry. Only consulted
    /// by the `returnToService` composite today — every other action ignores
    /// it. Each toggle defaults to true so an absent options object
    /// reproduces the original full-decommission behavior on
    /// already-deployed profiles. The erase itself is not optional and
    /// always waits for acknowledgment — only the post-ack cleanup steps are
    /// configurable here.
    struct DeviceActionOptions: Codable {
        /// Remove the Jamf computer record after the erase is acknowledged.
        var deleteJamfRecord: Bool?
        /// Delete the Entra device object after the erase is acknowledged
        /// (auto-skipped when Entra isn't configured).
        var deleteEntraObject: Bool?

        var effectiveDeleteJamfRecord: Bool { deleteJamfRecord ?? true }
        var effectiveDeleteEntraObject: Bool { deleteEntraObject ?? true }

        /// No keys delivered — every toggle resolves to its default (true).
        static let empty = DeviceActionOptions()

        enum CodingKeys: String, CodingKey {
            case deleteJamfRecord, deleteEntraObject
        }

        init(deleteJamfRecord: Bool? = nil, deleteEntraObject: Bool? = nil) {
            self.deleteJamfRecord = deleteJamfRecord
            self.deleteEntraObject = deleteEntraObject
        }

        /// Per-field fail-closed decode: an absent toggle keeps its default
        /// (true), but a present-but-undecodable toggle resolves to FALSE —
        /// the non-destructive direction (skip the cleanup step) — and one
        /// typo'd key never discards its correctly-typed sibling.
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
            NSLog("⚠️ deviceActions.options: malformed '%@' — treated as FALSE (skip step, fail-closed)", key.rawValue)
            return false
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
