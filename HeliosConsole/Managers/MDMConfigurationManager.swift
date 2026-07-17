//
//  MDMConfigurationManager.swift
//  HeliosConsole
//
//  Aggregation layer over the five Helios managed-preference domains
//  (com.herojoneslabs.helios.console.core / .credentials / .access / .features / .ui —
//  see docs/ConfigProfileMigration.md). Loads each domain uniformly via
//  ManagedDomainLoader in BOTH apps (no per-process branching, no legacy
//  flat keys, no main-app-suite fallback) and composes the flat
//  MDMConfiguration consumer surface.
//
//  NOTE: no auto-observation of profile changes — configuration is loaded
//  at app init (and via reloadConfiguration()); profile pushes take effect
//  at relaunch.
//

import Foundation
import Combine

class MDMConfigurationManager: ObservableObject {
    static let shared = MDMConfigurationManager()

    @Published private(set) var configuration: MDMConfiguration

    /// Short names of the managed domains that were actually delivered
    /// (e.g. ["core", "credentials", "ui"]). Empty when running on defaults.
    @Published private(set) var loadedDomains: [String] = []

    /// Per-domain-aware summary: "mdm(core,credentials,…)" when at least one
    /// managed domain was delivered, "defaults" otherwise.
    @Published private(set) var configurationSource: String = "defaults"

    /// Whether the required connection settings were delivered (core
    /// serverURL + masterClientID non-empty AND credentials
    /// jamfProClientSecret non-empty).
    var isConfigured: Bool { configuration.isConfigured }

    private init() {
        let result = Self.loadConfiguration()
        self.configuration = result.configuration
        self.loadedDomains = result.loadedDomains
        self.configurationSource = result.source
    }

    // MARK: - Reload Configuration

    func reloadConfiguration() {
        let result = Self.loadConfiguration()
        self.configuration = result.configuration
        self.loadedDomains = result.loadedDomains
        self.configurationSource = result.source
    }

    // MARK: - Load Configuration (uniform 5-domain path)

    private static func loadConfiguration()
        -> (configuration: MDMConfiguration, loadedDomains: [String], source: String)
    {
        let core = ManagedDomainLoader.loadCore()
        let credentials = ManagedDomainLoader.loadCredentials()
        let access = ManagedDomainLoader.loadAccess()
        let features = ManagedDomainLoader.loadFeatures()
        let ui = ManagedDomainLoader.loadUI()

        var loaded: [String] = []
        if core != nil { loaded.append("core") }
        if credentials != nil { loaded.append("credentials") }
        if access != nil { loaded.append("access") }
        if features != nil { loaded.append("features") }
        if ui != nil { loaded.append("ui") }

        guard !loaded.isEmpty else {
            print("⚠️ No managed configuration domain delivered — using built-in defaults")
            return (.default, [], "defaults")
        }

        let source = "mdm(\(loaded.joined(separator: ",")))"
        let resolvedEntra = resolveEntraCredentials(from: core?.entra)

        let configuration = MDMConfiguration(
            core: core,
            credentials: credentials,
            access: access,
            features: features,
            ui: ui,
            resolvedEntra: resolvedEntra
        )

        print("✅ Loaded configuration from \(source)")
        logValidity(configuration, core: core, credentials: credentials)
        logDeviceActionsPolicy(configuration, core: core)

        return (configuration, loaded, source)
    }

    /// One clear line about the device-actions posture at load — the
    /// allow-list is strict fail-closed, so an absent block (hidden Actions
    /// menu) must be diagnosable from the log, not a mystery.
    private static func logDeviceActionsPolicy(
        _ configuration: MDMConfiguration,
        core: CoreConfiguration?
    ) {
        if let grants = configuration.deviceActions?.computer?.grantsByID {
            let enabled = grants.values.filter { $0.effectiveEnabled }.count
            print("✅ access: deviceActions.computer delivers \(grants.count) action(s), \(enabled) enabled")
            if core?.jamfPro?.screenShareEnabled != nil {
                print("⚠️ core: jamfPro.screenShareEnabled is DEPRECATED and ignored — the access deviceActions allow-list is authoritative for screenShare")
            }
        } else {
            print("⚠️ access: no deviceActions.computer allow-list delivered — Actions menu hidden (fail-closed); see docs/ConfigProfileMigration.md")
        }
    }

    /// Logs exactly which required domain/keys are missing when the composed
    /// configuration is not usable (partial profile delivery must be
    /// visible, never a silent placeholder fallback).
    private static func logValidity(
        _ configuration: MDMConfiguration,
        core: CoreConfiguration?,
        credentials: CredentialsConfiguration?
    ) {
        guard !configuration.isConfigured else { return }

        var missing: [String] = []
        if core == nil {
            missing.append("core domain (\(CoreConfiguration.domain)) absent")
        } else {
            if (core?.jamfPro?.serverURL ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                missing.append("core: jamfPro.serverURL")
            }
            if (core?.jamfPro?.masterClientID ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                missing.append("core: jamfPro.masterClientID")
            }
        }
        if credentials == nil {
            missing.append("credentials domain (\(CredentialsConfiguration.domain)) absent")
        } else if credentials?.hasJamfProClientSecret != true {
            missing.append("credentials: jamfProClientSecret")
        }

        print("⚠️ Configuration incomplete — missing: \(missing.joined(separator: "; "))")
    }

    // MARK: - Resolve Entra Credentials
    // The core domain's `entra` block carries only a POINTER
    // (`credentialDomain`) to the preference domain that holds the real
    // Entra Graph credentials, plus optional per-key overrides
    // (tenantIdKey / clientIdKey / clientSecretKey / certPEMKey) so an
    // already-deployed credential plist can be read under whatever keys it
    // already uses. Because Helios is not sandboxed,
    // UserDefaults(suiteName:) transparently reads that domain's managed
    // prefs from /Library/Managed Preferences/<domain>.plist. Never throws;
    // a missing pointer or creds simply yields nils and Entra cleanup stays
    // disabled. Semantics preserved exactly from the pre-split loader —
    // deployed plists rely on them.

    /// Alias fallback lists probed in the credential domain when no
    /// override key is set. The first non-empty match wins; the canonical
    /// key is listed first. MUST stay in sync with the lists documented in
    /// CoreConfiguration.EntraPointerSettings and the core schema.
    private enum EntraAliasKeys {
        static let tenantId = ["entra_tenant_id", "tenantID", "tenant_id", "TenantID", "entra_tenant"]
        static let clientId = ["entra_client_id", "clientID", "client_id", "ClientID", "entra_client"]
        static let clientSecret = ["entra_client_secret", "clientSecret", "client_secret", "ClientSecret"]
        static let certPEM = ["entra_cert_pem", "entra_certificate", "cert_pem", "certPEM", "entra_cert", "certificate_pem"]
    }

    private static func resolveEntraCredentials(
        from pointer: CoreConfiguration.EntraPointerSettings?
    ) -> MDMConfiguration.ResolvedEntraCredentials {
        guard let pointer, pointer.hasCredentialDomain,
              let resolvedDomain = pointer.credentialDomain?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !resolvedDomain.isEmpty else {
            return .none
        }
        guard let credDefaults = UserDefaults(suiteName: resolvedDomain) else {
            print("   ⚠️ Entra: could not open credential domain \(resolvedDomain)")
            return MDMConfiguration.ResolvedEntraCredentials(domain: resolvedDomain)
        }

        // An explicit override from the core profile is tried first; the
        // built-in alias list is kept as a fallback so a slightly-off
        // override still resolves.
        let tenant = firstNonEmpty(credDefaults, keyList(pointer.tenantIdKey, fallback: EntraAliasKeys.tenantId))
        let client = firstNonEmpty(credDefaults, keyList(pointer.clientIdKey, fallback: EntraAliasKeys.clientId))
        let secret = firstNonEmpty(credDefaults, keyList(pointer.clientSecretKey, fallback: EntraAliasKeys.clientSecret))
        let pem = firstNonEmpty(credDefaults, keyList(pointer.certPEMKey, fallback: EntraAliasKeys.certPEM))

        if tenant != nil && client != nil {
            print("   ✅ Entra: resolved credentials from domain \(resolvedDomain)")
        } else {
            print("   ⚠️ Entra: pointer set to \(resolvedDomain) but tenant/client missing")
        }
        return MDMConfiguration.ResolvedEntraCredentials(
            domain: resolvedDomain,
            tenantId: tenant,
            clientId: client,
            clientSecret: secret,
            certPEM: pem
        )
    }

    /// Builds the ordered key list to probe in the credential domain: the
    /// explicit override (when non-empty) first, then the alias fallbacks.
    private static func keyList(_ override: String?, fallback: [String]) -> [String] {
        var keys: [String] = []
        if let override, !override.isEmpty {
            keys.append(override)
        }
        keys.append(contentsOf: fallback)
        return keys
    }

    /// Returns the first non-empty string among the candidate keys in `defaults`.
    private static func firstNonEmpty(_ defaults: UserDefaults, _ keys: [String]) -> String? {
        for key in keys {
            if let value = defaults.string(forKey: key), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    // MARK: - Helper Methods

    /// The sidebar items this Mac enables. UNORDERED with respect to display:
    /// row order comes from the signed-in user's role `modules` (access
    /// domain) and is resolved by SidebarView, not here.
    func getEnabledSidebarItems() -> [MDMConfiguration.SidebarItemConfig] {
        return configuration.sidebarItems.filter { $0.isEnabled }
    }

    // MARK: - Debug

    func printDebugInfo() {
        print("=== MDMConfigurationManager Debug ===")
        print("Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")
        print("Configuration Source: \(configurationSource)")
        print("Loaded Domains: \(loadedDomains.isEmpty ? "none" : loadedDomains.joined(separator: ","))")
        print("Jamf URL: \(configuration.jamfURL)")
        print("Client ID: \(String(configuration.masterClientID.prefix(12)))...")
        print("Has Secret: \(!configuration.masterClientSecret.isEmpty)")
        print("Is Configured: \(configuration.isConfigured)")
        print("ABM Configured: \(configuration.isABMConfigured)")
        print("=====================================")
    }
}
