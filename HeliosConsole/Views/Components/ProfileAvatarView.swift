//
//  ProfileAvatarView.swift
//  HeliosConsole
//
//  The operator's avatar, resolved once and rendered everywhere it appears
//  (Settings → Profile, the sidebar Preferences row). The style is a local,
//  cosmetic user preference held in AppSettings — it never gates anything and
//  is never uploaded. Resolution precedence follows the chosen AvatarStyle:
//    .photo    → the locally chosen photo (falls back to the directory photo)
//    .auto     → the Entra directory photo, else the initials avatar
//    .initials → initials on the chosen palette color
//    .symbol   → an SF Symbol on the chosen palette color
//

import AppKit
import SwiftUI

// MARK: - Palette

/// The generated-avatar palette: gradient background options plus the symbol
/// set offered in the picker. Indices are what AppSettings persists, so the
/// ORDER here is stable — append new entries, don't reorder existing ones.
enum AvatarPalette {
    static let gradients: [[Color]] = [
        [Color(red: 0.31, green: 0.51, blue: 0.96), Color(red: 0.58, green: 0.33, blue: 0.92)], // blue → purple
        [Color(red: 0.96, green: 0.42, blue: 0.55), Color(red: 0.90, green: 0.22, blue: 0.27)], // pink → red
        [Color(red: 0.98, green: 0.62, blue: 0.24), Color(red: 0.96, green: 0.42, blue: 0.16)], // amber → orange
        [Color(red: 0.20, green: 0.78, blue: 0.55), Color(red: 0.10, green: 0.60, blue: 0.47)], // green → teal
        [Color(red: 0.22, green: 0.74, blue: 0.86), Color(red: 0.16, green: 0.52, blue: 0.78)], // cyan → blue
        [Color(red: 0.40, green: 0.31, blue: 0.85), Color(red: 0.27, green: 0.22, blue: 0.62)], // indigo
        [Color(red: 0.85, green: 0.35, blue: 0.78), Color(red: 0.58, green: 0.24, blue: 0.70)], // magenta → purple
        [Color(red: 0.45, green: 0.50, blue: 0.58), Color(red: 0.30, green: 0.34, blue: 0.42)], // slate
    ]

    static let symbols: [String] = [
        "person.fill", "face.smiling.fill", "star.fill", "bolt.fill",
        "leaf.fill", "flame.fill", "heart.fill", "moon.stars.fill",
        "sparkles", "pawprint.fill", "desktopcomputer", "shield.lefthalf.filled",
    ]

    /// Clamp-by-wrap so a stored index can never crash if the palette shrinks.
    static func gradient(_ index: Int) -> LinearGradient {
        let count = gradients.count
        let colors = gradients[((index % count) + count) % count]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Badge (render-only, explicit inputs)

/// Renders one avatar from explicit inputs — used both by the live
/// `ProfileAvatarView` and by the picker cells (which preview styles other
/// than the active one). A non-nil `image` always wins; otherwise a `symbol`
/// renders, else the `initials` text, both over the palette gradient.
struct AvatarBadge: View {
    let size: CGFloat
    let image: NSImage?
    let symbol: String?
    let initials: String
    let colorIndex: Int

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(AvatarPalette.gradient(colorIndex))
                    .frame(width: size, height: size)

                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.44, weight: .semibold))
                        .foregroundColor(.white)
                } else {
                    Text(initials)
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Live avatar (reads the current selection)

/// The operator's avatar as currently configured. Observes AppSettings (the
/// chosen style/color/symbol/photo) and UserSession (the directory photo and
/// the name/email the initials derive from), so every place it appears updates
/// the instant the selection changes.
struct ProfileAvatarView: View {
    var size: CGFloat

    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var session = UserSession.shared

    var body: some View {
        AvatarBadge(
            size: size,
            image: liveImage,
            symbol: liveSymbol,
            initials: Self.initials(displayName: session.displayName, email: session.email),
            colorIndex: settings.avatarColorIndex
        )
    }

    private var liveImage: NSImage? {
        switch settings.avatarStyle {
        case .photo:              return settings.customProfilePicture ?? session.profilePhoto
        case .auto:               return session.profilePhoto
        case .initials, .symbol:  return nil
        }
    }

    private var liveSymbol: String? {
        settings.avatarStyle == .symbol ? settings.avatarSymbol : nil
    }

    /// Up to two initials from the display name; first letter of the email as a
    /// fallback; `?` when neither is available.
    static func initials(displayName: String, email: String) -> String {
        let parts = displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        if !parts.isEmpty {
            return String(parts).uppercased()
        }
        if let first = email.first {
            return String(first).uppercased()
        }
        return "?"
    }
}
