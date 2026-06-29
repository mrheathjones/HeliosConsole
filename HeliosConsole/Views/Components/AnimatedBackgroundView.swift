//
//  AnimatedBackgroundView.swift
//  Helios
//
//  Animated gradient background that adapts to light/dark mode
//

import SwiftUI

// MARK: - Animated Background

struct AnimatedBackgroundView: View {
    @Binding var animate: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool {
        colorScheme == .dark
    }
    
    var body: some View {
        ZStack {
            // Base background color
            backgroundColor
                .ignoresSafeArea()
            
            // Primary gradient orb
            Circle()
                .fill(
                    LinearGradient(
                        colors: primaryGradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 600, height: 600)
                .blur(radius: isDark ? 100 : 150)
                .offset(x: animate ? -100 : 100, y: animate ? -100 : 100)
                .animation(.easeInOut(duration: 8).repeatForever(autoreverses: true), value: animate)
            
            // Secondary gradient orb
            Circle()
                .fill(
                    LinearGradient(
                        colors: secondaryGradientColors,
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    )
                )
                .frame(width: 500, height: 500)
                .blur(radius: isDark ? 90 : 130)
                .offset(x: animate ? 100 : -100, y: animate ? 100 : -100)
                .animation(.easeInOut(duration: 7).repeatForever(autoreverses: true), value: animate)
            
            // Tertiary accent orb (adds depth)
            Circle()
                .fill(
                    LinearGradient(
                        colors: tertiaryGradientColors,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 400, height: 400)
                .blur(radius: isDark ? 80 : 120)
                .offset(x: animate ? -50 : 50, y: animate ? 150 : -50)
                .animation(.easeInOut(duration: 9).repeatForever(autoreverses: true), value: animate)
            
            // Overlay for depth
            Rectangle()
                .fill(overlayColor)
                .ignoresSafeArea()
                .blendMode(isDark ? .overlay : .multiply)
        }
        .animation(.easeInOut(duration: 0.3), value: colorScheme)
    }
    
    // MARK: - Adaptive Colors
    
    private var backgroundColor: Color {
        isDark ? Color(red: 0.05, green: 0.05, blue: 0.07) : Color(red: 0.92, green: 0.93, blue: 0.95)
    }
    
    private var primaryGradientColors: [Color] {
        isDark
            ? [Color.blue.opacity(0.3), Color.purple.opacity(0.2)]
            : [Color.blue.opacity(0.08), Color.purple.opacity(0.05)]
    }
    
    private var secondaryGradientColors: [Color] {
        isDark
            ? [Color.cyan.opacity(0.2), Color.blue.opacity(0.3)]
            : [Color.cyan.opacity(0.06), Color.blue.opacity(0.08)]
    }
    
    private var tertiaryGradientColors: [Color] {
        isDark
            ? [Color.indigo.opacity(0.15), Color.purple.opacity(0.1)]
            : [Color.indigo.opacity(0.04), Color.purple.opacity(0.03)]
    }
    
    private var overlayColor: Color {
        isDark ? Color.black.opacity(0.3) : Color.white.opacity(0.1)
    }
}

// MARK: - Simple Background (Non-animated)

struct SimpleBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool {
        colorScheme == .dark
    }
    
    var body: some View {
        ZStack {
            // Base background color
            (isDark ? Color(red: 0.05, green: 0.05, blue: 0.07) : Color(red: 0.92, green: 0.93, blue: 0.95))
                .ignoresSafeArea()
            
            // Static gradient orb - top left
            Circle()
                .fill(
                    LinearGradient(
                        colors: isDark
                            ? [Color.blue.opacity(0.25), Color.purple.opacity(0.15)]
                            : [Color.blue.opacity(0.06), Color.purple.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 500, height: 500)
                .blur(radius: isDark ? 100 : 140)
                .offset(x: -150, y: -100)
            
            // Static gradient orb - bottom right
            Circle()
                .fill(
                    LinearGradient(
                        colors: isDark
                            ? [Color.cyan.opacity(0.2), Color.blue.opacity(0.25)]
                            : [Color.cyan.opacity(0.05), Color.blue.opacity(0.06)],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    )
                )
                .frame(width: 450, height: 450)
                .blur(radius: isDark ? 90 : 120)
                .offset(x: 150, y: 100)
            
            // Overlay
            Rectangle()
                .fill(isDark ? Color.black.opacity(0.2) : Color.white.opacity(0.05))
                .ignoresSafeArea()
                .blendMode(isDark ? .overlay : .multiply)
        }
        .animation(.easeInOut(duration: 0.3), value: colorScheme)
    }
}

// MARK: - Preview

#Preview("Animated Background - Dark") {
    AnimatedBackgroundView(animate: .constant(true))
        .preferredColorScheme(.dark)
}

#Preview("Animated Background - Light") {
    AnimatedBackgroundView(animate: .constant(true))
        .preferredColorScheme(.light)
}

#Preview("Simple Background - Dark") {
    SimpleBackgroundView()
        .preferredColorScheme(.dark)
}

#Preview("Simple Background - Light") {
    SimpleBackgroundView()
        .preferredColorScheme(.light)
}
