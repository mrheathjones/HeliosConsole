//
//  CredentialsConfiguration.swift
//  HeliosConsole
//
//  Helios Console — Credentials (secrets tier of the 5-domain config split).
//  Delivered via Jamf Pro > Configuration Profiles > Application & Custom
//  Settings as its own profile so secrets rotate independently of the
//  non-secret core/features/ui profiles.
//
//  Preference Domain MUST match the domain Helios reads:
//      com.herojoneslabs.helios.console.credentials
//  (Matches `CredentialsConfiguration.domain` below, the
//   schemas/Helios_Credentials_SCHEMA.json `$id`, and the domain table in
//   docs/ConfigProfileMigration.md — keep all three in sync.)
//
//  Decoded by ManagedDomainLoader: the domain's top-level keys are read out of
//  UserDefaults(suiteName: CredentialsConfiguration.domain) into a
//  [String: Any], then run through PropertyListSerialization →
//  PropertyListDecoder. Every stored property is optional so a missing key —
//  or an entirely absent profile — never fails the domain decode.
//
//  SECURITY: managed-preference plists land world-readable at
//  /Library/Managed Preferences/com.herojoneslabs.helios.console.credentials.plist.
//  Never log these values; scope the delivering profile tightly.
//

import Foundation

/// Managed secrets for Helios Console, delivered by the
/// `com.herojoneslabs.helios.console.credentials` configuration profile.
///
/// Flat, deliberately minimal payload: just the three secrets plus the
/// informational `configurationVersion`. Non-secret companions (server URLs,
/// client IDs, key IDs) live in `com.herojoneslabs.helios.console.core`.
struct CredentialsConfiguration: Codable {

    /// The managed-preference domain this model is decoded from.
    /// Sync points: schemas/Helios_Credentials_SCHEMA.json `$id` and
    /// docs/ConfigProfileMigration.md.
    static let domain = "com.herojoneslabs.helios.console.credentials"

    /// Informational schema version (loader logs it, nothing else reads it).
    var configurationVersion: String?

    /// OAuth `client_secret` for the master Jamf Pro API client (pairs with
    /// `jamfPro.masterClientID` from the core domain). Required for the app
    /// to be considered configured — validity is enforced at the aggregation
    /// layer (`MDMConfigurationManager.isConfigured`), never by decode failure.
    var jamfProClientSecret: String?

    /// PEM-encoded ES256 private key for Apple Business Manager JWT signing
    /// (pairs with `appleBusinessManager.clientID`/`keyID` from the core
    /// domain). Optional — absent when the ABM integration is unused.
    var abmPrivateKey: String?

    /// Jamf Protect API password/client secret. Optional two-tier chain:
    /// when delivered here the in-app password field locks and this value is
    /// used; when absent the app falls back to in-app entry backed by the
    /// Keychain item `com.herojoneslabs.helios.console.protect.password`.
    var jamfProtectPassword: String?

    // MARK: - Effective accessors (defaults live here, never in decode)

    /// Schema version with the documented default applied.
    var effectiveConfigurationVersion: String {
        let version = configurationVersion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return version.isEmpty ? "2.0" : version
    }

    /// Whether a non-empty Jamf Pro client secret was delivered. Feeds the
    /// aggregation layer's `isConfigured` check (core serverURL + clientID
    /// non-empty AND this secret non-empty).
    var hasJamfProClientSecret: Bool {
        !(jamfProClientSecret?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    /// Whether a non-empty ABM private key was delivered.
    var hasABMPrivateKey: Bool {
        !(abmPrivateKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    /// Whether the Jamf Protect password is profile-managed. `true` locks the
    /// in-app password field; `false` keeps today's in-app entry + Keychain
    /// (`com.herojoneslabs.helios.console.protect.password`) chain.
    var isProtectPasswordManaged: Bool {
        !(jamfProtectPassword?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}
