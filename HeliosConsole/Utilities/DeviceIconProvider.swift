//
//  DeviceIconProvider.swift
//  HeliosConsole
//
//  Provides device icons from macOS CoreTypes bundle based on hardware model
//
//  ⚠️ APPKIT REQUIRED ⚠️
//  This file requires AppKit because SwiftUI's Image cannot load images from
//  arbitrary file system paths. NSImage(contentsOfFile:) is the only way to
//  load .icns files from /System/Library/CoreServices/CoreTypes.bundle.
//  This is macOS-specific functionality with no pure SwiftUI equivalent.
//

import SwiftUI
import AppKit

// MARK: - Device Icon Provider

enum DeviceIconProvider {
    
    /// Base path for CoreTypes bundle resources
    private static let coreTypesPath = "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources"
    
    // MARK: - Static Icon Names
    
    private enum IconName {
        static let iMac = "com.apple.imac-2021-silver"
        static let macBookAir = "com.apple.macbookair-13-2022-silver"
        static let macBookPro = "com.apple.macbookpro-16-2021-silver"
        static let macMini = "com.apple.macmini-2020"
        static let macPro = "com.apple.macpro-2019"
        static let macStudio = "com.apple.macstudio"
        static let iPhone = "com.apple.iphone-x-1"
    }
    
    // MARK: - Device Type Detection
    
    private enum DeviceType {
        case iMac, macBookAir, macBookPro, macMini, macPro, macStudio
        case iPhone, iPad, visionPro, unknown
    }
    
    /// Returns an NSImage for the given model identifier or model name
    static func icon(for modelIdentifier: String?, modelName: String?, platform: PlatformType? = nil) -> NSImage? {
        let deviceType = determineDeviceType(modelIdentifier: modelIdentifier, modelName: modelName, platform: platform)
        
        // iPad and VisionPro use SF Symbols - return nil to signal fallback
        if deviceType == .iPad || deviceType == .visionPro {
            return nil
        }
        
        guard let iconName = iconFileName(for: deviceType) else {
            return nil
        }
        
        return loadIcon(named: iconName)
    }
    
    /// Returns SwiftUI Image for the given model (returns nil if SF Symbol should be used)
    static func iconImage(for modelIdentifier: String?, modelName: String?, platform: PlatformType? = nil) -> Image? {
        guard let nsImage = icon(for: modelIdentifier, modelName: modelName, platform: platform) else {
            return nil
        }
        return Image(nsImage: nsImage)
    }
    
    private static func determineDeviceType(modelIdentifier: String?, modelName: String?, platform: PlatformType?) -> DeviceType {
        // Check platform first for mobile devices
        if let platform = platform {
            switch platform {
            case .iOS: return .iPhone
            case .iPadOS: return .iPad
            case .visionOS: return .visionPro
            case .macOS, .all: break
            }
        }
        
        // Check model name
        if let name = modelName?.lowercased() {
            if name.contains("iphone") { return .iPhone }
            if name.contains("ipad") { return .iPad }
            if name.contains("vision") { return .visionPro }
            if name.contains("imac") { return .iMac }
            if name.contains("macbook air") || name.contains("mba") { return .macBookAir }
            if name.contains("macbook pro") || name.contains("mbp") { return .macBookPro }
            if name.contains("macbook") { return .macBookAir }
            if name.contains("mac mini") { return .macMini }
            if name.contains("mac pro") { return .macPro }
            if name.contains("mac studio") { return .macStudio }
        }
        
        // Check model identifier
        if let identifier = modelIdentifier?.lowercased() {
            if identifier.contains("iphone") { return .iPhone }
            if identifier.contains("ipad") { return .iPad }
            
            // Mac Studio
            if identifier.hasPrefix("mac13,") || identifier == "mac14,13" || identifier == "mac14,14" {
                return .macStudio
            }
            // Mac Pro
            if identifier == "mac14,8" { return .macPro }
            // Mac mini
            if identifier.contains("macmini") || identifier == "mac14,3" || identifier == "mac14,12" {
                return .macMini
            }
            // iMac
            if identifier.contains("imac") || identifier == "mac15,4" || identifier == "mac15,5" {
                return .iMac
            }
            // MacBook Pro
            if identifier.contains("macbookpro") ||
               ["mac14,5", "mac14,6", "mac14,9", "mac14,10", "mac15,3", "mac15,6",
                "mac15,7", "mac15,8", "mac15,9", "mac15,10", "mac15,11"].contains(identifier) {
                return .macBookPro
            }
            // MacBook Air
            if identifier.contains("macbookair") ||
               ["mac14,2", "mac14,15", "mac15,12", "mac15,13"].contains(identifier) {
                return .macBookAir
            }
            if identifier.contains("macbook") { return .macBookAir }
        }
        
        return .unknown
    }
    
    private static func iconFileName(for deviceType: DeviceType) -> String? {
        switch deviceType {
        case .iMac: return IconName.iMac
        case .macBookAir: return IconName.macBookAir
        case .macBookPro: return IconName.macBookPro
        case .macMini: return IconName.macMini
        case .macPro: return IconName.macPro
        case .macStudio: return IconName.macStudio
        case .iPhone: return IconName.iPhone
        case .iPad, .visionPro, .unknown: return nil
        }
    }
    
    // MARK: - Icon Loading
    
    /// Loads an icon from the CoreTypes bundle
    /// NOTE: This requires NSImage - SwiftUI Image cannot load from file paths
    private static func loadIcon(named name: String) -> NSImage? {
        let icnsPath = "\(coreTypesPath)/\(name).icns"
        return NSImage(contentsOfFile: icnsPath)
    }
    
    // MARK: - SF Symbol Fallbacks
    
    static func sfSymbolName(for modelIdentifier: String?, modelName: String?, platform: PlatformType? = nil) -> String {
        let deviceType = determineDeviceType(modelIdentifier: modelIdentifier, modelName: modelName, platform: platform)
        
        switch deviceType {
        case .iPad: return "ipad.gen2"
        case .visionPro: return "visionpro"
        case .iMac: return "desktopcomputer"
        case .macBookAir, .macBookPro: return "laptopcomputer"
        case .macMini: return "macmini"
        case .macStudio: return "macstudio"
        case .macPro: return "macpro.gen3"
        case .iPhone: return "iphone"
        case .unknown: return "desktopcomputer"
        }
    }
    
    static func gradientColors(for modelIdentifier: String?, modelName: String?, platform: PlatformType? = nil) -> [Color] {
        let deviceType = determineDeviceType(modelIdentifier: modelIdentifier, modelName: modelName, platform: platform)
        
        switch deviceType {
        case .macBookAir, .macBookPro, .iMac, .macMini, .macStudio, .macPro:
            return [.blue, .cyan]
        case .iPhone:
            return [.green, .mint]
        case .iPad:
            return [.pink, .purple]
        case .visionPro:
            return [.yellow, .orange]
        case .unknown:
            return [.gray, .gray.opacity(0.7)]
        }
    }
}

// MARK: - SwiftUI View Extension

struct DeviceIconView: View {
    let modelIdentifier: String?
    let modelName: String?
    let platform: PlatformType?
    let size: CGFloat
    
    @Environment(\.colorScheme) private var colorScheme
    
    init(modelIdentifier: String? = nil, modelName: String? = nil, platform: PlatformType? = nil, size: CGFloat = 64) {
        self.modelIdentifier = modelIdentifier
        self.modelName = modelName
        self.platform = platform
        self.size = size
    }
    
    var body: some View {
        if let nsImage = DeviceIconProvider.icon(for: modelIdentifier, modelName: modelName, platform: platform) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            sfSymbolFallback
        }
    }
    
    @ViewBuilder
    private var sfSymbolFallback: some View {
        let symbolName = DeviceIconProvider.sfSymbolName(for: modelIdentifier, modelName: modelName, platform: platform)
        let gradientColors = DeviceIconProvider.gradientColors(for: modelIdentifier, modelName: modelName, platform: platform)
        
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2)
                .fill(
                    LinearGradient(
                        colors: gradientColors.map { $0.opacity(colorScheme == .dark ? 0.2 : 0.15) },
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
            
            Image(systemName: symbolName)
                .font(.system(size: size * 0.45, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Device Icons") {
    VStack(spacing: 30) {
        Text("Mac Devices (CoreTypes Icons)")
            .font(.headline)
        
        HStack(spacing: 30) {
            VStack {
                DeviceIconView(modelName: "iMac", size: 64)
                Text("iMac").font(.caption)
            }
            VStack {
                DeviceIconView(modelName: "MacBook Air", size: 64)
                Text("MacBook Air").font(.caption)
            }
            VStack {
                DeviceIconView(modelName: "MacBook Pro", size: 64)
                Text("MacBook Pro").font(.caption)
            }
        }
        
        Divider()
        
        Text("Mobile Devices (SF Symbols)")
            .font(.headline)
        
        HStack(spacing: 30) {
            VStack {
                DeviceIconView(platform: .iOS, size: 64)
                Text("iPhone").font(.caption)
            }
            VStack {
                DeviceIconView(platform: .iPadOS, size: 64)
                Text("iPad").font(.caption)
            }
            VStack {
                DeviceIconView(platform: .visionOS, size: 64)
                Text("Vision Pro").font(.caption)
            }
        }
    }
    .padding(40)
    .background(Color.black)
    .preferredColorScheme(.dark)
}
#endif
