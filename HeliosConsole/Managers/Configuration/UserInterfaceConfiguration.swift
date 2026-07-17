//
//  UserInterfaceConfiguration.swift
//  HeliosConsole
//
//  Helios Console — Branding & UX managed-preference domain model.
//  Deploy via Jamf Pro > Configuration Profiles > Application & Custom Settings
//  (schema: schemas/Helios_UI_SCHEMA.json), scoped to ALL managed Macs.
//
//  Preference Domain MUST match everywhere it is read or documented:
//      com.herojoneslabs.helios.console.ui
//  (Matches this file's `UserInterfaceConfiguration.domain`, the schema $id in
//   schemas/Helios_UI_SCHEMA.json, and docs/ConfigProfileMigration.md.)
//
//  Decoding contract: ManagedDomainLoader reads each top-level key out of
//  UserDefaults(suiteName: UserInterfaceConfiguration.domain) into a
//  [String: Any], then decodes it with PropertyListDecoder. Every stored
//  property is therefore Optional — a missing or partially delivered profile
//  must NEVER fail the whole domain decode. Defaults live exclusively in the
//  computed `effective*` accessors below.
//

import Foundation

/// Codable model for the `com.herojoneslabs.helios.console.ui` managed-preference domain:
/// branding (`userInterface`), the optional sidebar override (`sidebarItems`,
/// camelCase — renamed from the legacy top-level `SidebarItems`), and sign-in
/// behavior (`authentication`).
///
/// NOTE (recorded decision): `sidebarItems` and `authentication` are parsed
/// and exposed but not yet enforced in views — SidebarView builds its own
/// list today. See docs/ConfigProfileMigration.md for enforcement status.
struct UserInterfaceConfiguration: Codable {

    /// Managed-preference domain this model is decoded from.
    /// Sync points: schemas/Helios_UI_SCHEMA.json ($id) and
    /// docs/ConfigProfileMigration.md.
    static let domain = "com.herojoneslabs.helios.console.ui"

    /// Informational version stamp ("2.0" for the domain split). The loader
    /// logs it; nothing else reads it.
    var configurationVersion: String?

    /// Branding and top-level UI visibility switches.
    var userInterface: UserInterfaceSettings?

    /// Optional custom sidebar item list (empty/absent → app built-in sidebar).
    var sidebarItems: [SidebarItemSetting]?

    /// Sign-in behavior preferences.
    var authentication: AuthenticationSettings?

    // MARK: - Effective values (defaults applied here, never in storage)

    var effectiveConfigurationVersion: String {
        nonEmptyTrimmed(configurationVersion) ?? "2.0"
    }

    /// Sidebar override sorted by `order` (ascending). Empty when the profile
    /// does not deliver one — callers fall back to the built-in sidebar.
    var effectiveSidebarItems: [SidebarItemSetting] {
        (sidebarItems ?? []).sorted { $0.effectiveOrder < $1.effectiveOrder }
    }
}

// MARK: - userInterface section

/// The `userInterface` dictionary: branding strings, accent color, appearance,
/// and visibility switches for top-level app areas.
struct UserInterfaceSettings: Codable {
    var appTitle: String?
    var appSubtitle: String?
    var supportURL: String?
    var companyName: String?
    var logoURL: String?
    var accentColor: String?
    var defaultColorScheme: String?
    var showEnrollments: Bool?
    var showAnnouncements: Bool?
    var showSettings: Bool?

    /// Preferred appearance. Raw values match the schema enum exactly.
    enum ColorSchemePreference: String {
        case system
        case light
        case dark
    }

    var effectiveAppTitle: String {
        nonEmptyTrimmed(appTitle) ?? "Helios"
    }

    var effectiveAppSubtitle: String {
        nonEmptyTrimmed(appSubtitle) ?? "Console"
    }

    /// Support link for the login screen. `nil` (absent or empty) hides it.
    var effectiveSupportURL: String? {
        nonEmptyTrimmed(supportURL)
    }

    /// Organization name for branding surfaces. `nil` when not configured.
    var effectiveCompanyName: String? {
        nonEmptyTrimmed(companyName)
    }

    /// Custom logo URL. `nil` (absent or empty) → built-in branding.
    var effectiveLogoURL: String? {
        nonEmptyTrimmed(logoURL)
    }

    /// Accent color as a "#RRGGBB" hex string.
    var effectiveAccentColor: String {
        nonEmptyTrimmed(accentColor) ?? "#007AFF"
    }

    /// Fail-safe appearance resolution: missing, blank, or unrecognized
    /// values fall back to following the macOS system appearance.
    var effectiveColorScheme: ColorSchemePreference {
        guard let raw = nonEmptyTrimmed(defaultColorScheme),
              let parsed = ColorSchemePreference(rawValue: raw) else {
            return .system
        }
        return parsed
    }

    var effectiveShowEnrollments: Bool { showEnrollments ?? true }
    var effectiveShowAnnouncements: Bool { showAnnouncements ?? true }
    var effectiveShowSettings: Bool { showSettings ?? true }
}

// MARK: - sidebarItems section

/// One entry of the optional `sidebarItems` override array
/// ({id, icon, title, isEnabled, order}).
struct SidebarItemSetting: Codable {
    var id: String?
    var icon: String?
    var title: String?
    var isEnabled: Bool?
    var order: Int?

    var effectiveID: String { nonEmptyTrimmed(id) ?? "" }

    /// SF Symbol name; a generic placeholder when not delivered.
    var effectiveIcon: String { nonEmptyTrimmed(icon) ?? "circle" }

    var effectiveTitle: String { nonEmptyTrimmed(title) ?? "" }

    var effectiveIsEnabled: Bool { isEnabled ?? true }

    /// Sort order (ascending). Items without one sink to the end.
    var effectiveOrder: Int { order ?? Int.max }

    /// Usable = shown: enabled with a non-empty id and title.
    var isUsable: Bool {
        effectiveIsEnabled && !effectiveID.isEmpty && !effectiveTitle.isEmpty
    }
}

// MARK: - authentication section

/// The `authentication` dictionary: sign-in behavior preferences.
struct AuthenticationSettings: Codable {
    var requireBiometric: Bool?
    var allowBiometricSetup: Bool?
    var sessionTimeout: Int?
    var allowRememberMe: Bool?

    var effectiveRequireBiometric: Bool { requireBiometric ?? false }

    var effectiveAllowBiometricSetup: Bool { allowBiometricSetup ?? true }

    /// Idle session timeout in minutes; 0 = no timeout. Negative values from
    /// a malformed profile are clamped to 0 (disabled) rather than trusted.
    var effectiveSessionTimeoutMinutes: Int { max(0, sessionTimeout ?? 0) }

    var effectiveAllowRememberMe: Bool { allowRememberMe ?? true }
}

// MARK: - Helpers

/// Treats absent, empty, and whitespace-only strings identically (the schema
/// pre-fills "" for optional branding keys, and Jamf can deliver blank
/// fields) so `effective*` accessors fall back consistently.
private func nonEmptyTrimmed(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
