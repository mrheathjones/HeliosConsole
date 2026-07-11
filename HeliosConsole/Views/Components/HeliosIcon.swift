//
//  HeliosIcon.swift
//  HeliosConsole
//
//  Reusable Helios icon component that uses the app icon from the asset catalog
//  Falls back to programmatic rendering if asset is unavailable
//

import SwiftUI

// MARK: - Icon Size Presets

enum HeliosIconSize {
    case small      // 24pt - for inline/list usage
    case medium     // 36pt - for sidebar header
    case large      // 64pt - for settings/about
    case xlarge     // 96pt - for login/splash
    case xxlarge    // 128pt - for welcome screen
    case custom(CGFloat)
    
    var dimension: CGFloat {
        switch self {
        case .small: return 24
        case .medium: return 36
        case .large: return 64
        case .xlarge: return 96
        case .xxlarge: return 128
        case .custom(let size): return size
        }
    }
    
    var cornerRadius: CGFloat {
        dimension * 0.22
    }
}

// MARK: - Helios Icon View

struct HeliosIcon: View {
    let size: HeliosIconSize
    var animate: Bool = false
    
    @State private var rotation: Double = 0
    @State private var pulse: Bool = false
    
    var body: some View {
        Group {
            if let appIcon = loadAppIcon() {
                appIcon
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.dimension, height: size.dimension)
                    .clipShape(RoundedRectangle(cornerRadius: size.cornerRadius))
            } else {
                // Fallback to SF Symbol if app icon not available
                fallbackIcon
            }
        }
        .scaleEffect(pulse && animate ? 1.02 : 1.0)
        .rotationEffect(.degrees(animate ? rotation : 0))
        .onAppear {
            if animate {
                withAnimation(.linear(duration: 60).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
    }
    
    // MARK: - Load App Icon from Bundle
    
    private func loadAppIcon() -> Image? {
        // Try to load from asset catalog
        #if os(macOS)
        if let nsImage = NSImage(named: "AppIcon") {
            return Image(nsImage: nsImage)
        }
        
        // Try to load from NSApp
        if let appIcon = NSApp.applicationIconImage {
            return Image(nsImage: appIcon)
        }
        #else
        if let uiImage = UIImage(named: "AppIcon") {
            return Image(uiImage: uiImage)
        }
        #endif
        
        return nil
    }
    
    // MARK: - Fallback Icon
    
    private var fallbackIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.1, green: 0.1, blue: 0.18),
                            Color(red: 0.06, green: 0.2, blue: 0.38)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Image(systemName: "sun.max.fill")
                .font(.system(size: size.dimension * 0.5, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.95, green: 0.61, blue: 0.07),
                            Color(red: 0.91, green: 0.30, blue: 0.24),
                            Color(red: 0.61, green: 0.35, blue: 0.71)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .frame(width: size.dimension, height: size.dimension)
    }
}

// MARK: - Convenience Initializers

extension HeliosIcon {
    /// Simple icon for sidebar/navigation
    static func sidebar() -> HeliosIcon {
        HeliosIcon(size: .medium)
    }
    
    /// Large icon for login/welcome screens
    static func hero(animate: Bool = false) -> HeliosIcon {
        HeliosIcon(size: .xxlarge, animate: animate)
    }
    
    /// Icon for settings/about section
    static func about() -> HeliosIcon {
        HeliosIcon(size: .large)
    }
    
    /// Small inline icon
    static func inline() -> HeliosIcon {
        HeliosIcon(size: .small)
    }
}

// MARK: - Animated Helios Logo (for loading states)

struct AnimatedHeliosLogo: View {
    @State private var isAnimating = false
    
    var body: some View {
        HeliosIcon(size: .xlarge, animate: true)
            .opacity(isAnimating ? 1 : 0.8)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - Helios Logo with Text

struct HeliosLogoWithText: View {
    enum TextStyle {
        case horizontal
        case stacked
    }
    
    let iconSize: HeliosIconSize
    var textStyle: TextStyle = .horizontal
    var showSubtitle: Bool = true
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool {
        colorScheme == .dark
    }
    
    var body: some View {
        switch textStyle {
        case .horizontal:
            horizontalLayout
        case .stacked:
            stackedLayout
        }
    }
    
    private var horizontalLayout: some View {
        HStack(spacing: iconSize.dimension * 0.3) {
            HeliosIcon(size: iconSize)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(Branding.title)
                    .font(.system(size: titleFontSize, weight: .semibold))
                    .foregroundColor(isDark ? .white : .primary)

                if showSubtitle && !Branding.subtitle.isEmpty {
                    Text(Branding.subtitle)
                        .font(.system(size: subtitleFontSize, weight: .medium))
                        .foregroundColor(.gray)
                }
            }
        }
    }
    
    private var stackedLayout: some View {
        VStack(spacing: iconSize.dimension * 0.25) {
            HeliosIcon(size: iconSize)
            
            VStack(spacing: 4) {
                Text(Branding.title)
                    .font(.system(size: titleFontSize, weight: .bold))
                    .foregroundColor(isDark ? .white : .primary)

                if showSubtitle && !Branding.subtitle.isEmpty {
                    Text(Branding.subtitle)
                        .font(.system(size: subtitleFontSize, weight: .medium))
                        .foregroundColor(.gray)
                }
            }
        }
    }
    
    private var titleFontSize: CGFloat {
        switch iconSize {
        case .small: return 14
        case .medium: return 16
        case .large: return 22
        case .xlarge: return 28
        case .xxlarge: return 36
        case .custom(let size): return size * 0.28
        }
    }
    
    private var subtitleFontSize: CGFloat {
        switch iconSize {
        case .small: return 10
        case .medium: return 12
        case .large: return 14
        case .xlarge: return 18
        case .xxlarge: return 22
        case .custom(let size): return size * 0.17
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Helios Icon Sizes") {
    VStack(spacing: 30) {
        HStack(spacing: 20) {
            VStack {
                HeliosIcon(size: .small)
                Text("Small").font(.caption)
            }
            VStack {
                HeliosIcon(size: .medium)
                Text("Medium").font(.caption)
            }
            VStack {
                HeliosIcon(size: .large)
                Text("Large").font(.caption)
            }
            VStack {
                HeliosIcon(size: .xlarge)
                Text("XLarge").font(.caption)
            }
            VStack {
                HeliosIcon(size: .xxlarge)
                Text("XXLarge").font(.caption)
            }
        }
        
        Divider()
        
        HStack(spacing: 20) {
            HeliosLogoWithText(iconSize: .medium)
            HeliosLogoWithText(iconSize: .large, textStyle: .stacked)
        }
        
        Divider()
        
        AnimatedHeliosLogo()
    }
    .padding(40)
    .background(Color(white: 0.1))
    .preferredColorScheme(.dark)
}

#Preview("Helios Icon - Light Mode") {
    VStack(spacing: 20) {
        HeliosIcon(size: .xlarge)
        HeliosLogoWithText(iconSize: .large)
    }
    .padding(40)
    .background(Color(white: 0.95))
    .preferredColorScheme(.light)
}
#endif
