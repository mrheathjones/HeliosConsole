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

    /// True when the Protect password is delivered by the MDM profile, in
    /// which case the in-app field is locked and the managed value is used.
    var protectPasswordIsManaged: Bool {
        !(mdm.protectPassword ?? "").isEmpty
    }

    var protectClientPassword: String {
        get {
            // A profile-delivered password wins (like the master secret);
            // otherwise fall back to the in-app Keychain value.
            if let managed = mdm.protectPassword, !managed.isEmpty {
                return managed
            }
            return KeychainManager.shared.loadString(forKey: Self.protectPasswordKeychainKey) ?? ""
        }
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

// MARK: - Connection tests

/// Standalone Jamf Pro / Jamf Protect connection tests. Builds throwaway
/// clients from a `CleanupSettings`, so any screen (the main Settings view or
/// the Cleanup view model) can run a test without owning a full view model.
enum CleanupConnectionTester {
    @MainActor
    static func testJamf(_ settings: CleanupSettings) async -> Result<String, Error> {
        do {
            guard settings.isConfigured, let url = settings.normalizedJamfURL else {
                throw JamfCleanupError.notConfigured
            }
            let client = JamfCleanupClient(
                baseURL: url,
                clientID: settings.jamfClientID,
                clientSecret: settings.jamfClientSecret,
                pageSize: settings.pageSize
            )
            let version = try await client.testConnection()
            await client.invalidateToken()
            return .success("Connected — Jamf Pro \(version)")
        } catch {
            return .failure(error)
        }
    }

    @MainActor
    static func testProtect(_ settings: CleanupSettings) async -> Result<String, Error> {
        do {
            guard settings.isProtectConfigured, let url = settings.normalizedProtectURL else {
                throw JamfCleanupError.protectNotConfigured
            }
            let client = JamfProtectClient(
                baseURL: url,
                clientID: settings.protectClientID,
                password: settings.protectClientPassword
            )
            try await client.testConnection()
            await client.invalidate()
            return .success("Connected to Jamf Protect")
        } catch {
            return .failure(error)
        }
    }
}
