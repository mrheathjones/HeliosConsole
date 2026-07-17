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
    /// Marketing tagline under the wordmark on the welcome screen.
    var tagline: String?
    /// Footer/copyright line for the Settings About card.
    var footerText: String?
    /// Destination for the About card's Documentation link (empty = hidden).
    var documentationURL: String?
    /// Destination for the About card's Report-an-Issue link (empty = hidden).
    var feedbackURL: String?

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

    /// Welcome-screen tagline. `nil` → built-in copy.
    var effectiveTagline: String? { nonEmptyTrimmed(tagline) }

    /// About-card footer line. `nil` → composed from the product name.
    var effectiveFooterText: String? { nonEmptyTrimmed(footerText) }

    /// Documentation link. `nil` (absent or empty) hides the row.
    var effectiveDocumentationURL: String? { nonEmptyTrimmed(documentationURL) }

    /// Report-an-Issue link. `nil` (absent or empty) hides the row.
    var effectiveFeedbackURL: String? { nonEmptyTrimmed(feedbackURL) }
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

    /// SF Symbol name; EMPTY when not delivered so SidebarView substitutes the
    /// destination's built-in icon. A placeholder here would be non-empty and
    /// would defeat that fallback, rendering a blank glyph instead.
    var effectiveIcon: String { nonEmptyTrimmed(icon) ?? "" }

    /// Empty when not delivered — SidebarView substitutes the destination's
    /// built-in label.
    var effectiveTitle: String { nonEmptyTrimmed(title) ?? "" }

    var effectiveIsEnabled: Bool { isEnabled ?? true }

    /// Sort order (ascending). Items without one sink to the end.
    var effectiveOrder: Int { order ?? Int.max }

    /// Usable = enabled with a non-empty id. `title` and `icon` are OPTIONAL in
    /// the schema and SidebarView falls back to the destination's built-in
    /// label/icon, so requiring them here would discard items the app renders
    /// fine — and discarding every item silently reverts the whole sidebar to
    /// the built-in default order, ignoring the admin's `order` values.
    var isUsable: Bool {
        effectiveIsEnabled && !effectiveID.isEmpty
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
