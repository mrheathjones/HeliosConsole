//
//  CleanupTheme.swift
//  HeliosConsole
//
//  Visual language for the Cleanup feature: a soft gradient backdrop,
//  glassy cards, a stale badge, a tri-state checkbox, and shared date
//  formatters. Ported from Clean Slate; MeshGradient (macOS 15+) replaced
//  with a LinearGradient so it builds on the macOS 14 deployment target.
//

import SwiftUI

struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: colorScheme == .dark ? Self.darkColors : Self.lightColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private static let lightColors: [Color] = [
        Color(red: 0.88, green: 0.94, blue: 0.99),
        Color(red: 0.80, green: 0.90, blue: 0.98),
        Color(red: 0.78, green: 0.90, blue: 0.94),
    ]

    private static let darkColors: [Color] = [
        Color(red: 0.05, green: 0.09, blue: 0.16),
        Color(red: 0.08, green: 0.14, blue: 0.24),
        Color(red: 0.05, green: 0.10, blue: 0.17),
    ]
}

struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.10), radius: 14, y: 6)
    }
}

extension View {
    func glassCard() -> some View { modifier(GlassCard()) }
}

/// Color-coded "days stale" badge.
struct StaleBadge: View {
    let days: Int?

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private var label: String {
        guard let days else { return "never" }
        return "\(days)d"
    }

    private var color: Color {
        guard let days else { return .gray }
        switch days {
        case ..<45: return .yellow
        case ..<90: return .orange
        default: return .red
        }
    }
}

/// Tri-state checkbox used by the cleanup device lists.
struct CleanupCheckBox: View {
    enum State { case off, on, mixed }

    let state: State
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(state == .off ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state == .on ? "Deselect" : "Select")
    }

    private var symbol: String {
        switch state {
        case .off: "square"
        case .on: "checkmark.square.fill"
        case .mixed: "minus.square.fill"
        }
    }
}

enum CleanupFormatters {
    static let lastContact: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    static func lastContactString(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return lastContact.string(from: date)
    }
}
