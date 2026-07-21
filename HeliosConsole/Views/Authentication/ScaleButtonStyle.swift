//
//  ScaleButtonStyle.swift
//  test
//
//  Created by heath on 1/19/26.
//

import SwiftUI

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }

    init() {}
}

// MARK: - RefreshButton

/// The single, canonical "Refresh" control used across every view.
///
/// A rounded-rect button with the `arrow.clockwise` glyph and a "Refresh"
/// label (never icon-only), swapping to a spinner while `isLoading` and
/// disabling itself so a reload can't be double-fired. Adapts to light/dark.
///
/// Usage:
/// ```swift
/// RefreshButton(isLoading: model.isLoading) { Task { await model.refresh() } }
/// ```
struct RefreshButton: View {
    @Environment(\.colorScheme) private var colorScheme

    /// Shows a spinner and disables the button while true.
    var isLoading: Bool = false
    /// Label text; defaults to "Refresh".
    var title: String = "Refresh"
    /// Invoked on tap. Wrap async reloads in a `Task { }`.
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(colorScheme == .dark ? .white : .primary)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(colorScheme == .dark ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(isLoading)
        .help(title)
    }
}

// MARK: - ExportButtonLabel

/// The canonical blue "Export" chrome shared by every export control.
///
/// This is a *label* (not a Button) so it can back either a plain `Button`
/// or a `Menu` (format picker). Pair a `Menu` with
/// `.menuStyle(.borderlessButton).menuIndicator(.hidden)` so the blue
/// background renders. Uses the `square.and.arrow.down` glyph everywhere.
struct ExportButtonLabel: View {
    /// Label text; defaults to "Export".
    var title: String = "Export"
    /// Shows a spinner in place of the glyph while true.
    var isBusy: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            } else {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 13, weight: .semibold))
            }
            Text(title)
                .font(.system(size: 14, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color.blue)
        .cornerRadius(10)
        .contentShape(Rectangle())
    }
}
