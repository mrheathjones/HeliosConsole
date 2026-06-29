//
//  PlatformType.swift
//  HeliosConsole
//
//  Represents Apple device platforms managed by Helios.
//  Extracted into its own file so it can be shared across targets
//  (main app + menu bar) without dragging in DashboardContentView dependencies.
//

import SwiftUI

// MARK: - Platform Type

enum PlatformType: String, CaseIterable, Identifiable, Hashable {
    case macOS = "macOS"
    case iOS = "iOS"
    case iPadOS = "iPadOS"
    case visionOS = "visionOS"
    case all = "All Devices"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .macOS: return "desktopcomputer"
        case .iOS: return "iphone"
        case .iPadOS: return "ipad"
        case .visionOS: return "visionpro"
        case .all: return "rectangle.stack"
        }
    }

    var color: Color {
        switch self {
        case .macOS: return .blue
        case .iOS: return .green
        case .iPadOS: return .pink
        case .visionOS: return .yellow
        case .all: return .cyan
        }
    }

    var gradientColors: [Color] {
        switch self {
        case .macOS: return [.blue, .cyan]
        case .iOS: return [.green, .mint]
        case .iPadOS: return [.pink, .purple]
        case .visionOS: return [.yellow, .orange]
        case .all: return [.blue, .purple]
        }
    }

    static var displayCases: [PlatformType] {
        [.macOS, .iOS, .iPadOS, .visionOS]
    }

    static var filterCases: [PlatformType] {
        [.all, .macOS, .iOS, .iPadOS, .visionOS]
    }
}
