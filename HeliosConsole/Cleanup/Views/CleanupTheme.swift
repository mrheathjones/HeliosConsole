//
//  CleanupTheme.swift
//  HeliosConsole
//
//  Visual language for the Cleanup feature, matched to Helios's native look:
//  translucent-white cards over the app's AnimatedBackgroundView, a circular
//  back button, a stale badge, a tri-state checkbox, and shared date formatters.
//

import SwiftUI

/// Card styling matched to Helios's native cards (DashboardContentView /
/// DeviceListRow): a subtle translucent-white fill over the app's animated
/// background, a faint hairline border, and a soft shadow.
struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}

extension View {
    func glassCard() -> some View { modifier(GlassCard()) }
}

/// Helios-style circular back button (matches DeviceView / MobileDeviceView).
struct CleanupBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 30, height: 30)
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
        .help("Back to Cleanup")
    }
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

    /// Stable, locale-independent timestamp for report cells.
    static let report: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    static func reportDate(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return report.string(from: date)
    }

    /// Date stamp for export filenames, e.g. 2026-06-11.
    static let fileStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func fileDate(_ date: Date) -> String {
        fileStamp.string(from: date)
    }
}
