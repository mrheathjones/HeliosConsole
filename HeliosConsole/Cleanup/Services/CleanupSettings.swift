//
//  CleanupSettings.swift
//  HeliosConsole
//
//  Configuration provider for the Cleanup feature. Jamf Pro credentials
//  come from Helios's MDM configuration (the master client); the
//  cleanup-specific tunables (stale threshold, Jamf Protect) are read from
//  the MDM configuration as defaults, overridable in-app via UserDefaults,
//  with the Protect password kept in the Keychain.
//

import Foundation

@MainActor
final class CleanupSettings {
    private let defaults = UserDefaults.standard

    // UserDefaults keys for in-app overrides.
    enum Key {
        static let staleDays = "Cleanup.StaleDays"
        static let protectEnabled = "Cleanup.ProtectEnabled"
        static let protectURL = "Cleanup.ProtectURL"
        static let protectClientID = "Cleanup.ProtectClientID"
        static let protectAutoCleanup = "Cleanup.ProtectAutoCleanup"
    }

    /// Keychain account for the Jamf Protect API password.
    static let protectPasswordKeychainKey = "com.helios.protect.password"

    private var mdm: MDMConfiguration { MDMConfigurationManager.shared.configuration }

    // MARK: - Jamf Pro (master client, MDM-supplied)

    var jamfClientID: String { mdm.masterClientID }
    var jamfClientSecret: String { mdm.masterClientSecret }
    var normalizedJamfURL: URL? { Self.normalize(mdm.jamfURL) }
    var pageSize: Int { 100 }

    var isConfigured: Bool {
        !mdm.jamfURL.isEmpty
            && !mdm.masterClientID.isEmpty
            && mdm.masterClientID != "your-master-client-id"
            && !mdm.masterClientSecret.isEmpty
            && mdm.masterClientSecret != "your-master-client-secret"
    }

    // MARK: - Stale threshold (MDM default, user-overridable)

    var staleDays: Int {
        get { defaults.object(forKey: Key.staleDays) as? Int ?? mdm.cleanupStaleDays }
        set { defaults.set(newValue, forKey: Key.staleDays) }
    }

    // MARK: - Default action targets (from MDM)

    var defaultStaticGroupID: Int { Int(mdm.cleanupDefaultStaticGroupID ?? "") ?? 0 }
    var defaultSiteID: Int { Int(mdm.cleanupDefaultSiteID ?? "") ?? -1 }

    // MARK: - Jamf Protect (MDM defaults, user-overridable; password in Keychain)

    var protectEnabled: Bool {
        get { defaults.object(forKey: Key.protectEnabled) as? Bool ?? mdm.protectEnabled }
        set { defaults.set(newValue, forKey: Key.protectEnabled) }
    }

    var protectURL: String {
        get { defaults.string(forKey: Key.protectURL) ?? mdm.protectURL ?? "" }
        set { defaults.set(newValue, forKey: Key.protectURL) }
    }

    var protectClientID: String {
        get { defaults.string(forKey: Key.protectClientID) ?? mdm.protectClientID ?? "" }
        set { defaults.set(newValue, forKey: Key.protectClientID) }
    }

    var protectClientPassword: String {
        get { KeychainManager.shared.loadString(forKey: Self.protectPasswordKeychainKey) ?? "" }
        set { KeychainManager.shared.saveString(newValue, forKey: Self.protectPasswordKeychainKey) }
    }

    /// When on, deleting a Jamf Pro record also deletes the matching Jamf
    /// Protect record (by serial).
    var protectAutoCleanup: Bool {
        get { defaults.bool(forKey: Key.protectAutoCleanup) }
        set { defaults.set(newValue, forKey: Key.protectAutoCleanup) }
    }

    var normalizedProtectURL: URL? { Self.normalize(protectURL) }

    var isProtectConfigured: Bool {
        protectEnabled
            && !protectURL.isEmpty
            && !protectClientID.isEmpty
            && !protectClientPassword.isEmpty
    }

    // MARK: - Helpers

    /// URL normalized: scheme added if missing, trailing slash stripped.
    static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.lowercased().hasPrefix("http") { s = "https://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        return URL(string: s)
    }
}
