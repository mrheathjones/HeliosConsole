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

    /// The delivered sidebar override, AS DELIVERED. Empty when the profile
    /// does not deliver one — callers fall back to the built-in sidebar.
    ///
    /// NOT SORTED, and there is nothing to sort by: this list is a set of
    /// per-id overrides (presence, label, icon), not an arrangement. Row order
    /// is the access domain's job — it is the position of an id in the
    /// signed-in user's role `modules` array — so ordering here would only be
    /// a second, conflicting answer to a question this domain no longer asks.
    var effectiveSidebarItems: [SidebarItemSetting] {
        sidebarItems ?? []
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
/// ({id, icon, title, isEnabled}).
///
/// This entry answers WHETHER a row exists on this Mac and WHAT it looks like.
/// It deliberately cannot answer WHERE it sits: the removed `order` key moved
/// to the access domain, where a role's `modules` array position IS its
/// sidebar order — so enabling a module and placing it are one edit, in one
/// place, and can be set per role.
struct SidebarItemSetting: Codable {
    var id: String?
    var icon: String?
    var title: String?
    var isEnabled: Bool?

    /// True when the profile still delivers the REMOVED `order` key. Codable
    /// ignores unknown keys, so such a profile decodes cleanly and `order`
    /// simply does nothing — invisible unless we look for it, which is what
    /// this flag is for (MDMConfiguration logs the notice once).
    /// Not part of the wire format: absent from CodingKeys, so it is neither
    /// decoded nor encoded.
    var deliveredLegacyOrder: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, icon, title, isEnabled
    }

    /// The `order` key as it used to be declared — probed for, never read.
    private enum LegacyCodingKeys: String, CodingKey {
        case order
    }

    init(
        id: String? = nil,
        icon: String? = nil,
        title: String? = nil,
        isEnabled: Bool? = nil
    ) {
        self.id = id
        self.icon = icon
        self.title = title
        self.isEnabled = isEnabled
    }

    /// Mirrors what synthesis would do for the four live keys, plus the
    /// legacy-`order` probe. Note it must NOT reject an entry carrying
    /// `order`: already-deployed profiles have one, and failing the decode
    /// would drop the item's label/icon over a key we chose to retire.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled)
        deliveredLegacyOrder = (try? decoder.container(keyedBy: LegacyCodingKeys.self))?
            .contains(.order) ?? false
    }

    var effectiveID: String { nonEmptyTrimmed(id) ?? "" }

    /// SF Symbol name; EMPTY when not delivered so SidebarView substitutes the
    /// destination's built-in icon. A placeholder here would be non-empty and
    /// would defeat that fallback, rendering a blank glyph instead.
    var effectiveIcon: String { nonEmptyTrimmed(icon) ?? "" }

    /// Empty when not delivered — SidebarView substitutes the destination's
    /// built-in label.
    var effectiveTitle: String { nonEmptyTrimmed(title) ?? "" }

    var effectiveIsEnabled: Bool { isEnabled ?? true }

    /// Usable = enabled with a non-empty id. `title` and `icon` are OPTIONAL in
    /// the schema and SidebarView falls back to the destination's built-in
    /// label/icon, so requiring them here would discard items the app renders
    /// fine — and discarding every item silently reverts the whole sidebar to
    /// the built-in list, ignoring the admin's label/icon overrides.
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
