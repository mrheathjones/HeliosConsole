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

    /// The managed `deviceActions` dictionary. Parsed and exposed by the
    /// configuration layer; view-level enforcement status is documented in
    /// docs/ConfigProfileMigration.md. Defaults (destructive actions off)
    /// match schemas/Helios_Access_SCHEMA.json.
    struct DeviceActionsSettings: Codable {
        var computer: ComputerActions?
        var mobileDevice: MobileDeviceActions?

        var effectiveComputer: ComputerActions { computer ?? ComputerActions() }
        var effectiveMobileDevice: MobileDeviceActions { mobileDevice ?? MobileDeviceActions() }

        /// Allow-list for computer (macOS) actions.
        struct ComputerActions: Codable {
            var sendBlankPush: Bool?
            var restart: Bool?
            var shutdown: Bool?
            var lock: Bool?
            var wipe: Bool?
            var enableRemoteDesktop: Bool?
            var disableRemoteDesktop: Bool?
            var enableBluetooth: Bool?
            var disableBluetooth: Bool?
            var viewRecoveryLockPassword: Bool?
            var viewFileVaultKey: Bool?
            var viewLocalAdminPassword: Bool?
            var unlockUserAccount: Bool?
            var renewMDMProfile: Bool?
            var sendCustomCommand: Bool?
            var updateInventory: Bool?
            var installPackage: Bool?
            var runPolicy: Bool?

            var effectiveSendBlankPush: Bool { sendBlankPush ?? true }
            var effectiveRestart: Bool { restart ?? true }
            var effectiveShutdown: Bool { shutdown ?? true }
            var effectiveLock: Bool { lock ?? false }
            var effectiveWipe: Bool { wipe ?? false }
            var effectiveEnableRemoteDesktop: Bool { enableRemoteDesktop ?? true }
            var effectiveDisableRemoteDesktop: Bool { disableRemoteDesktop ?? true }
            var effectiveEnableBluetooth: Bool { enableBluetooth ?? true }
            var effectiveDisableBluetooth: Bool { disableBluetooth ?? true }
            var effectiveViewRecoveryLockPassword: Bool { viewRecoveryLockPassword ?? false }
            var effectiveViewFileVaultKey: Bool { viewFileVaultKey ?? true }
            var effectiveViewLocalAdminPassword: Bool { viewLocalAdminPassword ?? true }
            var effectiveUnlockUserAccount: Bool { unlockUserAccount ?? true }
            var effectiveRenewMDMProfile: Bool { renewMDMProfile ?? false }
            var effectiveSendCustomCommand: Bool { sendCustomCommand ?? false }
            var effectiveUpdateInventory: Bool { updateInventory ?? false }
            var effectiveInstallPackage: Bool { installPackage ?? false }
            var effectiveRunPolicy: Bool { runPolicy ?? false }
        }

        /// Allow-list for mobile device (iOS / iPadOS / visionOS) actions.
        struct MobileDeviceActions: Codable {
            var sendBlankPush: Bool?
            var restart: Bool?
            var shutdown: Bool?
            var lock: Bool?
            var wipe: Bool?
            var clearPasscode: Bool?
            var enableLostMode: Bool?
            var disableLostMode: Bool?
            var playLostModeSound: Bool?
            var updateInventory: Bool?
            var renewMDMProfile: Bool?
            var enableActivationLock: Bool?
            var clearActivationLock: Bool?

            var effectiveSendBlankPush: Bool { sendBlankPush ?? true }
            var effectiveRestart: Bool { restart ?? true }
            var effectiveShutdown: Bool { shutdown ?? true }
            var effectiveLock: Bool { lock ?? true }
            var effectiveWipe: Bool { wipe ?? false }
            var effectiveClearPasscode: Bool { clearPasscode ?? true }
            var effectiveEnableLostMode: Bool { enableLostMode ?? true }
            var effectiveDisableLostMode: Bool { disableLostMode ?? true }
            var effectivePlayLostModeSound: Bool { playLostModeSound ?? true }
            var effectiveUpdateInventory: Bool { updateInventory ?? true }
            var effectiveRenewMDMProfile: Bool { renewMDMProfile ?? true }
            var effectiveEnableActivationLock: Bool { enableActivationLock ?? false }
            var effectiveClearActivationLock: Bool { clearActivationLock ?? false }
        }
    }
}
