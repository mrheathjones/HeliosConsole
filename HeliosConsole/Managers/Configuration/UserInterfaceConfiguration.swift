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

    /// Optional per-id sidebar label/icon override list. COSMETIC ONLY — it
    /// no longer controls presence (an absent id → app default). Empty/absent
    /// → every row uses its built-in label and icon.
    var sidebarItems: [SidebarItemSetting]?

    /// Optional per-id Devices-tab label rename list ({id, displayName}).
    /// Cosmetic override only: an absent id → the tab's built-in title.
    var deviceTabs: [DeviceTabLabelSetting]?

    /// Optional per-id device-action label/icon override list
    /// ({id, displayName, icon}). Cosmetic override only: an absent id → the
    /// action's built-in label and icon.
    var deviceActionLabels: [DeviceActionLabelSetting]?

    /// Sign-in behavior preferences.
    var authentication: AuthenticationSettings?

    enum CodingKeys: String, CodingKey {
        case configurationVersion, userInterface, sidebarItems, deviceTabs, deviceActionLabels, authentication
    }

    init(
        configurationVersion: String? = nil,
        userInterface: UserInterfaceSettings? = nil,
        sidebarItems: [SidebarItemSetting]? = nil,
        deviceTabs: [DeviceTabLabelSetting]? = nil,
        deviceActionLabels: [DeviceActionLabelSetting]? = nil,
        authentication: AuthenticationSettings? = nil
    ) {
        self.configurationVersion = configurationVersion
        self.userInterface = userInterface
        self.sidebarItems = sidebarItems
        self.deviceTabs = deviceTabs
        self.deviceActionLabels = deviceActionLabels
        self.authentication = authentication
    }

    /// Per-key resilient decode: this whole domain is cosmetic, so ONE
    /// malformed key (e.g. deviceTabs delivered as a dict) must degrade to
    /// nil — the app default — never throw and take all the other branding
    /// with it (ManagedDomainLoader discards the entire domain on a throw).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        configurationVersion = try? container.decodeIfPresent(String.self, forKey: .configurationVersion)
        userInterface = try? container.decodeIfPresent(UserInterfaceSettings.self, forKey: .userInterface)
        sidebarItems = try? container.decodeIfPresent([SidebarItemSetting].self, forKey: .sidebarItems)
        deviceTabs = try? container.decodeIfPresent([DeviceTabLabelSetting].self, forKey: .deviceTabs)
        deviceActionLabels = try? container.decodeIfPresent([DeviceActionLabelSetting].self, forKey: .deviceActionLabels)
        authentication = try? container.decodeIfPresent(AuthenticationSettings.self, forKey: .authentication)
    }

    // MARK: - Effective values (defaults applied here, never in storage)

    var effectiveConfigurationVersion: String {
        nonEmptyTrimmed(configurationVersion) ?? "2.0"
    }

    /// The delivered sidebar override, AS DELIVERED. Empty when the profile
    /// does not deliver one — callers fall back to the built-in sidebar.
    ///
    /// NOT SORTED, and there is nothing to sort by: this list is a set of
    /// per-id overrides (label, icon), not an arrangement. Row order
    /// is the access domain's job — it is the position of an id in the
    /// signed-in user's role `modules` array — so ordering here would only be
    /// a second, conflicting answer to a question this domain no longer asks.
    var effectiveSidebarItems: [SidebarItemSetting] {
        sidebarItems ?? []
    }

    // MARK: - Cosmetic override accessors (keyed by id)

    /// Sidebar label/icon overrides keyed by row id. A field is `nil` when the
    /// profile left it blank — the caller then falls back to the built-in.
    var sidebarOverrides: [String: (displayName: String?, icon: String?)] {
        var map: [String: (displayName: String?, icon: String?)] = [:]
        for item in effectiveSidebarItems where !item.effectiveID.isEmpty {
            map[item.effectiveID] = (
                displayName: item.effectiveDisplayName.isEmpty ? nil : item.effectiveDisplayName,
                icon: item.effectiveIcon.isEmpty ? nil : item.effectiveIcon
            )
        }
        return map
    }

    /// The Devices-tab rename for `id`, or `nil` when none was delivered (use
    /// the tab's built-in title). Last non-empty entry for a duplicate id wins.
    func deviceTabOverride(id: String) -> String? {
        var result: String?
        for item in (deviceTabs ?? []) where item.effectiveID == id {
            if !item.effectiveDisplayName.isEmpty { result = item.effectiveDisplayName }
        }
        return result
    }

    /// The label/icon override for device-action `id`, or `nil` when none was
    /// delivered. Either field may still be `nil` (blank → app default). Last
    /// entry carrying a non-empty field for a duplicate id wins per field.
    func deviceActionLabelOverride(id: String) -> (displayName: String?, icon: String?)? {
        var displayName: String?
        var icon: String?
        var matched = false
        for item in (deviceActionLabels ?? []) where item.effectiveID == id {
            matched = true
            if !item.effectiveDisplayName.isEmpty { displayName = item.effectiveDisplayName }
            if !item.effectiveIcon.isEmpty { icon = item.effectiveIcon }
        }
        return matched ? (displayName: displayName, icon: icon) : nil
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
/// ({id, displayName, icon}).
///
/// COSMETIC ONLY: it answers WHAT a row looks like (its label and icon),
/// never WHETHER it exists or WHERE it sits. Presence comes from the signed-in
/// user's role `modules` (access domain); a role's `modules` array position IS
/// its sidebar order — so granting a module and placing it are one edit, in
/// one place, per role. The removed `isEnabled` and `order` keys both moved
/// out this way.
struct SidebarItemSetting: Codable {
    var id: String?
    var displayName: String?
    var icon: String?

    /// True when the profile still delivers the RETIRED `order` key. Codable
    /// ignores unknown keys, so such a profile decodes cleanly and `order`
    /// simply does nothing — invisible unless we look for it, which is what
    /// this flag is for (MDMConfiguration logs the notice once).
    /// Not part of the wire format: absent from CodingKeys, so it is neither
    /// decoded nor encoded.
    var deliveredLegacyOrder: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, displayName, icon
    }

    /// Retired/renamed keys that already-deployed profiles still deliver,
    /// probed for backward compatibility: `title` was renamed to `displayName`
    /// and is accepted as an alias; `order` is retired and only detected so
    /// the composition layer can log the once-per-launch notice.
    private enum LegacyCodingKeys: String, CodingKey {
        case title, order
    }

    init(
        id: String? = nil,
        displayName: String? = nil,
        icon: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.icon = icon
    }

    /// Resilient per-key decode. Accepts either the new `displayName` key or
    /// the legacy `title` alias so old profiles keep their labels, and must
    /// NOT reject an entry carrying `order`: already-deployed profiles have
    /// one, and failing the decode would drop the item's label/icon over a key
    /// we chose to retire.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try? decoder.container(keyedBy: LegacyCodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        if let name = try container.decodeIfPresent(String.self, forKey: .displayName) {
            displayName = name
        } else if let legacy, let title = try? legacy.decodeIfPresent(String.self, forKey: .title) {
            displayName = title
        } else {
            displayName = nil
        }
        deliveredLegacyOrder = legacy?.contains(.order) ?? false
    }

    var effectiveID: String { nonEmptyTrimmed(id) ?? "" }

    /// SF Symbol name; EMPTY when not delivered so SidebarView substitutes the
    /// destination's built-in icon. A placeholder here would be non-empty and
    /// would defeat that fallback, rendering a blank glyph instead.
    var effectiveIcon: String { nonEmptyTrimmed(icon) ?? "" }

    /// Empty when not delivered — SidebarView substitutes the destination's
    /// built-in label.
    var effectiveDisplayName: String { nonEmptyTrimmed(displayName) ?? "" }

    /// Usable = a non-empty id. `displayName` and `icon` are OPTIONAL and
    /// SidebarView falls back to the destination's built-in label/icon, so
    /// requiring them here would discard items the app renders fine.
    var isUsable: Bool { !effectiveID.isEmpty }
}

// MARK: - deviceTabs section

/// One entry of the optional `deviceTabs` rename list ({id, displayName}).
/// A rename ONLY — Devices tabs carry no icon override. Presence of a tab is
/// gated by the access domain's `deviceTabs`; this list only relabels a tab
/// the role already grants.
struct DeviceTabLabelSetting: Codable {
    var id: String?
    var displayName: String?

    enum CodingKeys: String, CodingKey {
        case id, displayName
    }

    init(id: String? = nil, displayName: String? = nil) {
        self.id = id
        self.displayName = displayName
    }

    /// Resilient per-key decode: a malformed field degrades to nil rather than
    /// failing the array (and, via the loader's catch, the whole ui domain).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decodeIfPresent(String.self, forKey: .id)
        displayName = try? container.decodeIfPresent(String.self, forKey: .displayName)
    }

    var effectiveID: String { nonEmptyTrimmed(id) ?? "" }
    var effectiveDisplayName: String { nonEmptyTrimmed(displayName) ?? "" }
}

// MARK: - deviceActionLabels section

/// One entry of the optional `deviceActionLabels` override list
/// ({id, displayName, icon}). Cosmetic override for a device action's menu
/// label and SF-Symbol icon; the action's availability is gated ROLE-ONLY by
/// the access domain, never here.
struct DeviceActionLabelSetting: Codable {
    var id: String?
    var displayName: String?
    var icon: String?

    enum CodingKeys: String, CodingKey {
        case id, displayName, icon
    }

    init(id: String? = nil, displayName: String? = nil, icon: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.icon = icon
    }

    /// Resilient per-key decode: a malformed field degrades to nil rather than
    /// failing the array (and, via the loader's catch, the whole ui domain).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decodeIfPresent(String.self, forKey: .id)
        displayName = try? container.decodeIfPresent(String.self, forKey: .displayName)
        icon = try? container.decodeIfPresent(String.self, forKey: .icon)
    }

    var effectiveID: String { nonEmptyTrimmed(id) ?? "" }
    var effectiveDisplayName: String { nonEmptyTrimmed(displayName) ?? "" }
    var effectiveIcon: String { nonEmptyTrimmed(icon) ?? "" }
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
