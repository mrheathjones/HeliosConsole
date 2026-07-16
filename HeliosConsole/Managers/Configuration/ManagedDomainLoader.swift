//
//  ManagedDomainLoader.swift
//  HeliosConsole
//
//  Uniform loader for the five Helios managed-preference domains
//  (5-domain config split — see docs/ConfigProfileMigration.md):
//      com.herojoneslabs.helios.console.core         → CoreConfiguration
//      com.herojoneslabs.helios.console.credentials  → CredentialsConfiguration
//      com.herojoneslabs.helios.console.access      → AccessConfiguration
//      com.herojoneslabs.helios.console.features    → FeaturesConfiguration
//      com.herojoneslabs.helios.console.ui          → UserInterfaceConfiguration
//
//  HOW IT READS (and why):
//  Domains are read via `UserDefaults(suiteName:)` — NEVER
//  `persistentDomain(forName:)` (Journal 2026-07-10 bug) and never with
//  suiteName == the app's own bundle ID (Foundation rejects it; all five
//  domains differ from both bundle IDs). Because BOTH apps are
//  non-sandboxed, a suite read transparently surfaces
//  /Library/Managed Preferences/<domain>.plist (MDM-forced, wins) AND
//  ~/Library/Preferences/<domain>.plist — so
//  `defaults write com.herojoneslabs.helios.console.core …` IS the dev story.
//
//  Each domain's known top-level keys are read individually with
//  `object(forKey:)` into a [String: Any] payload, round-tripped through
//  PropertyListSerialization, and decoded with PropertyListDecoder
//  (plist types like Date/Data decode natively; JSONSerialization would
//  choke on them). Domain models keep every stored property optional, so
//  a partial payload never throws the whole domain away.
//

import Foundation

/// Loads one Codable domain model per managed-preference domain, uniformly
/// in both apps (no per-process branching).
enum ManagedDomainLoader {

    // The five managed domain strings (each mirrors its model's `domain`).
    static let coreDomain = CoreConfiguration.domain
    static let credentialsDomain = CredentialsConfiguration.domain
    static let accessDomain = AccessConfiguration.domain
    static let featuresDomain = FeaturesConfiguration.domain
    static let uiDomain = UserInterfaceConfiguration.domain

    /// Per-domain top-level key lists — the exact keys read out of the
    /// suite. Must stay in sync with each model's stored properties and the
    /// matching schema in schemas/.
    static let coreKeys = [
        "configurationVersion", "jamfPro", "appleBusinessManager",
        "jamfProtect", "entra", "signIn", "localAdministration"
    ]
    static let credentialsKeys = [
        "configurationVersion", "jamfProClientSecret", "abmPrivateKey",
        "jamfProtectPassword"
    ]
    static let accessKeys = [
        "configurationVersion", "role", "roles", "cleanup", "deviceActions"
    ]
    static let featuresKeys = [
        "configurationVersion", "computers", "mobileDevices",
        "healthScorecard", "deviceHealth", "reports", "actionLog"
    ]
    static let uiKeys = [
        "configurationVersion", "userInterface", "sidebarItems",
        "authentication"
    ]

    /// Reads `domain` via UserDefaults(suiteName:), assembles the known
    /// top-level keys into a payload, and decodes it into `T`.
    ///
    /// Returns nil when the domain is entirely absent (no known key present)
    /// or — defensively — when the payload fails to decode. Logs
    /// found/absent plus the payload's `configurationVersion` per domain.
    static func load<T: Decodable>(
        _ type: T.Type,
        domain: String,
        topLevelKeys: [String]
    ) -> T? {
        guard let defaults = UserDefaults(suiteName: domain) else {
            print("⚠️ Config domain \(domain): could not open UserDefaults suite")
            return nil
        }

        var payload: [String: Any] = [:]
        for key in topLevelKeys {
            if let value = defaults.object(forKey: key) {
                payload[key] = value
            }
        }

        guard !payload.isEmpty else {
            print("ℹ️ Config domain \(domain): absent (no known keys delivered)")
            return nil
        }

        do {
            let data = try PropertyListSerialization.data(
                fromPropertyList: payload, format: .xml, options: 0
            )
            let model = try PropertyListDecoder().decode(T.self, from: data)
            let version = (payload["configurationVersion"] as? String)
                .flatMap { $0.isEmpty ? nil : $0 } ?? "2.0 (implied)"
            print("✅ Config domain \(domain): found (keys: \(payload.keys.sorted().joined(separator: ","))), configurationVersion=\(version)")
            return model
        } catch {
            print("⚠️ Config domain \(domain): delivered but failed to decode — \(error)")
            return nil
        }
    }

    // MARK: - Per-domain convenience loads

    static func loadCore() -> CoreConfiguration? {
        load(CoreConfiguration.self, domain: coreDomain, topLevelKeys: coreKeys)
    }

    static func loadCredentials() -> CredentialsConfiguration? {
        load(CredentialsConfiguration.self, domain: credentialsDomain, topLevelKeys: credentialsKeys)
    }

    static func loadAccess() -> AccessConfiguration? {
        load(AccessConfiguration.self, domain: accessDomain, topLevelKeys: accessKeys)
    }

    static func loadFeatures() -> FeaturesConfiguration? {
        load(FeaturesConfiguration.self, domain: featuresDomain, topLevelKeys: featuresKeys)
    }

    static func loadUI() -> UserInterfaceConfiguration? {
        load(UserInterfaceConfiguration.self, domain: uiDomain, topLevelKeys: uiKeys)
    }
}
