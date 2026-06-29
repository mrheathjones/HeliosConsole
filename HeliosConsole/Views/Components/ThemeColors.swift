//
//  AdaptiveCardStyle.swift
//  test
//
//  Created by heath on 1/21/26.
//


//
//  ThemeColors.swift
//  Helios
//
//  Adaptive color definitions for light and dark mode
//

import SwiftUI

// MARK: - Theme Colors

extension Color {
    
    // MARK: - Background Colors
    
    /// Primary background color
    static var themeBackground: Color {
        Color("ThemeBackground", bundle: nil)
    }
    
    /// Secondary/card background color
    static var themeCardBackground: Color {
        Color("ThemeCardBackground", bundle: nil)
    }
    
    // MARK: - Adaptive Colors
    
    /// Adaptive text color - primary
    static func adaptiveText(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white : .primary
    }
    
    /// Adaptive text color - secondary
    static func adaptiveSecondaryText(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .gray : .secondary
    }
    
    /// Adaptive card background
    static func adaptiveCardBackground(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.03) : Color.white.opacity(0.8)
    }
    
    /// Adaptive card border
    static func adaptiveCardBorder(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.08)
    }
    
    /// Adaptive divider
    static func adaptiveDivider(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)
    }
    
    /// Adaptive subtle background (for hover states, etc.)
    static func adaptiveSubtleBackground(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05)
    }
    
    /// Adaptive hover background
    static func adaptiveHoverBackground(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }
}

// MARK: - Theme View Modifiers

struct AdaptiveCardStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = 12
    var hasShadow: Bool = true
    
    func body(content: Content) -> some View {
        content
            .background(Color.adaptiveCardBackground(colorScheme))
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.adaptiveCardBorder(colorScheme), lineWidth: 1)
            )
            .shadow(
                color: hasShadow && colorScheme == .light ? .black.opacity(0.05) : .clear,
                radius: 10,
                x: 0,
                y: 4
            )
    }
}

extension View {
    func adaptiveCard(cornerRadius: CGFloat = 12, hasShadow: Bool = true) -> some View {
        modifier(AdaptiveCardStyle(cornerRadius: cornerRadius, hasShadow: hasShadow))
    }
}

// MARK: - Sidebar Adaptive Colors

extension Color {
    /// Sidebar background
    static func sidebarBackground(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.black.opacity(0.3) : Color.white.opacity(0.6)
    }
    
    /// Sidebar item background when selected
    static func sidebarSelectedBackground(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.blue.opacity(0.1)
    }
    
    /// Sidebar item text when selected
    static func sidebarSelectedText(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white : .blue
    }
    
    /// Sidebar item text when not selected
    static func sidebarText(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .gray : .secondary
    }
}

// MARK: - Status Badge Colors

extension Color {
    static func statusBadgeBackground(_ baseColor: Color, _ colorScheme: ColorScheme) -> Color {
        baseColor.opacity(colorScheme == .dark ? 0.2 : 0.15)
    }
}