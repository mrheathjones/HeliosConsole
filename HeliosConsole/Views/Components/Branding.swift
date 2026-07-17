//
//  Branding.swift
//  HeliosConsole
//
//  Single source of truth for admin-brandable UI values, resolved from the
//  ui managed-preference domain (schemas/Helios_UI_SCHEMA.json). Every
//  surface that renders the product name, wordmark, accent, logo, or
//  branded URLs must read from here — never a string literal — so an org
//  can rebrand the console entirely from the config profile.
//

import SwiftUI

enum Branding {

    private static var config: MDMConfiguration {
        MDMConfigurationManager.shared.configuration
    }

    private static var ui: UserInterfaceSettings? {
        config.userInterfaceExtras
    }

    // MARK: - Names

    /// ui userInterface.appTitle (default "Helios").
    static var title: String { config.appTitle }

    /// ui userInterface.appSubtitle (default "Console").
    static var subtitle: String { config.appSubtitle }

    /// Combined product name ("Helios Console").
    static var productName: String {
        subtitle.isEmpty ? title : "\(title) \(subtitle)"
    }

    /// ui userInterface.companyName, falling back to the product name.
    static var companyName: String {
        ui?.effectiveCompanyName ?? productName
    }

    /// Welcome-screen tagline (ui userInterface.tagline).
    static var tagline: String {
        ui?.effectiveTagline ?? "Device Management Made Simple"
    }

    /// About-card footer (ui userInterface.footerText); composed from the
    /// product name and current year when not configured.
    static var footerText: String {
        if let configured = ui?.effectiveFooterText { return configured }
        let year = Calendar.current.component(.year, from: Date())
        return "© \(year) \(productName). All rights reserved."
    }

    // MARK: - URLs

    /// Support link (ui userInterface.supportURL). nil = hide the affordance.
    static var supportURL: URL? {
        config.supportURL.flatMap { URL(string: $0) }
    }

    /// Documentation link (ui userInterface.documentationURL). nil = hidden.
    static var documentationURL: URL? {
        ui?.effectiveDocumentationURL.flatMap { URL(string: $0) }
    }

    /// Report-an-Issue link (ui userInterface.feedbackURL). nil = hidden.
    static var feedbackURL: URL? {
        ui?.effectiveFeedbackURL.flatMap { URL(string: $0) }
    }

    /// Custom organization logo (ui userInterface.logoURL). nil = built-in mark.
    static var logoURL: URL? {
        ui?.effectiveLogoURL.flatMap { URL(string: $0) }
    }

    // MARK: - Accent

    /// The accent the admin explicitly delivered, or nil when the profile
    /// leaves branding to the app.
    static var configuredAccent: Color? {
        guard let hex = ui?.accentColor else { return nil }
        return color(fromHex: hex)
    }

    /// Brand accent color (ui userInterface.accentColor, default #007AFF).
    static var accentColor: Color {
        configuredAccent ?? color(fromHex: "#007AFF") ?? .blue
    }

    /// The signature two-stop brand gradient. Keeps the built-in blue→cyan
    /// look unless the profile delivers a custom accent, in which case the
    /// gradient derives from it.
    static var accentGradient: [Color] {
        if let accent = configuredAccent {
            return [accent, accent.opacity(0.65)]
        }
        return [.blue, .cyan]
    }

    /// Parses "#RRGGBB" / "RRGGBB" (also 8-digit #AARRGGBB, alpha ignored).
    static func color(fromHex hex: String) -> Color? {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        if cleaned.count == 8 { cleaned = String(cleaned.suffix(6)) }
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }
}

// MARK: - Brand Mark

/// The in-window brand mark: the org's custom logo (ui userInterface.logoURL)
/// when delivered, otherwise the built-in gradient sun tile.
struct BrandMark: View {
    var size: CGFloat = 40

    var body: some View {
        if let url = Branding.logoURL {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                builtInMark
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.25))
        } else {
            builtInMark
        }
    }

    private var builtInMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25)
                .fill(
                    LinearGradient(
                        colors: Branding.accentGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "sun.max.fill")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}
