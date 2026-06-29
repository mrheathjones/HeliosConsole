//
//  AppConfiguration.swift
//  HeliosConsole
//
//  Comprehensive configuration models for MDM-managed and standalone deployment
//  Supports configuration via MDM profile or local settings
//

import Foundation
import SwiftUI
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.helios.console", category: "Configuration")

// MARK: - Main App Configuration

struct AppConfiguration: Codable {
    var configurationVersion: String = "1.0"
    var jamfPro: JamfProConfiguration
    var appleBusinessManager: ABMConfiguration?
    var localAdministration: LocalAdminConfiguration?
    var computers: ComputerConfiguration?
    var mobileDevices: MobileDeviceConfiguration?
    var healthScorecard: HealthScorecardConfiguration?
    var deviceHealth: DeviceHealthConfiguration?
    var deviceActions: DeviceActionsConfiguration?
    var reports: ReportsConfiguration?
    var userInterface: UIConfiguration?
    var authentication: AuthenticationConfiguration?
    
    // MARK: - Defaults
    
    static var `default`: AppConfiguration {
        AppConfiguration(
            jamfPro: JamfProConfiguration(
                serverURL: "",
                masterClientID: "",
                masterClientSecret: ""
            )
        )
    }
    
    /// Whether the configuration is valid for operation
    var isValid: Bool {
        !jamfPro.serverURL.isEmpty &&
        !jamfPro.masterClientID.isEmpty &&
        !jamfPro.masterClientSecret.isEmpty
    }
    
    /// Whether ABM is properly configured
    var isABMConfigured: Bool {
        guard let abm = appleBusinessManager, abm.enabled else { return false }
        return !(abm.clientID?.isEmpty ?? true) &&
               !(abm.keyID?.isEmpty ?? true) &&
               !(abm.privateKey?.isEmpty ?? true)
    }
}

// MARK: - Jamf Pro Configuration

struct JamfProConfiguration: Codable {
    var serverURL: String
    var masterClientID: String
    var masterClientSecret: String
    var requiredRoleName: String?
    var connectionTimeout: Int?
    var requestTimeout: Int?
    
    var effectiveRoleName: String {
        requiredRoleName ?? "SVC_WATCHER_USER"
    }
    
    var effectiveConnectionTimeout: TimeInterval {
        TimeInterval(connectionTimeout ?? 30)
    }
    
    var effectiveRequestTimeout: TimeInterval {
        TimeInterval(requestTimeout ?? 60)
    }
}

// MARK: - Apple Business Manager Configuration

struct ABMConfiguration: Codable {
    var enabled: Bool = false
    var clientID: String?
    var keyID: String?
    var privateKey: String?
}

// MARK: - Local Administration Configuration

struct LocalAdminConfiguration: Codable {
    var enabled: Bool = true
    var username: String = "macadmin"
}

// MARK: - Computer Configuration

struct ComputerConfiguration: Codable {
    var enabled: Bool = true
    var fetchInventory: Bool = true
    var showDashboardCard: Bool = true
    var enableAPIActions: Bool = true
    var enableReports: Bool = true
    var inventoryRefreshInterval: Int = 15
    var inventorySections: [String]?
    
    static var defaultSections: [String] {
        ["GENERAL", "HARDWARE", "OPERATING_SYSTEM", "USER_AND_LOCATION", "STORAGE",
         "SECURITY", "DISK_ENCRYPTION", "CONFIGURATION_PROFILES", "GROUP_MEMBERSHIPS", "SOFTWARE_UPDATES"]
    }
    
    var effectiveSections: [String] {
        inventorySections ?? Self.defaultSections
    }
}

// MARK: - Mobile Device Configuration

struct MobileDeviceConfiguration: Codable {
    var enabled: Bool = true
    var fetchInventory: Bool = true
    var showDashboardCards: MobileDashboardCards?
    var enableAPIActions: Bool = true
    var enableReports: Bool = true
    var inventoryRefreshInterval: Int = 15
    var inventorySections: [String]?
    
    struct MobileDashboardCards: Codable {
        var iOS: Bool = true
        var iPadOS: Bool = true
        var visionOS: Bool = true
    }
    
    static var defaultSections: [String] {
        ["GENERAL", "HARDWARE", "USER_AND_LOCATION", "SECURITY", "CONFIGURATION_PROFILES", "GROUP_MEMBERSHIPS"]
    }
    
    var effectiveSections: [String] {
        inventorySections ?? Self.defaultSections
    }
    
    var effectiveDashboardCards: MobileDashboardCards {
        showDashboardCards ?? MobileDashboardCards()
    }
}

// MARK: - Health Scorecard Configuration

struct HealthScorecardConfiguration: Codable {
    var enabled: Bool = true
    var metrics: [HealthMetricConfiguration]?
    
    static var defaultMetrics: [HealthMetricConfiguration] {
        [
            HealthMetricConfiguration(id: "checkedIn", enabled: true, checkedInDays: 7, platforms: ["macOS", "iOS", "iPadOS", "visionOS"]),
            HealthMetricConfiguration(id: "managed", enabled: true, platforms: ["macOS", "iOS", "iPadOS", "visionOS"]),
            HealthMetricConfiguration(id: "supervised", enabled: true, platforms: ["macOS", "iOS", "iPadOS", "visionOS"]),
            HealthMetricConfiguration(id: "fileVaultEnabled", enabled: true, platforms: ["macOS"]),
            HealthMetricConfiguration(id: "firewallEnabled", enabled: true, platforms: ["macOS"]),
            HealthMetricConfiguration(id: "gatekeeperEnabled", enabled: true, platforms: ["macOS"]),
            HealthMetricConfiguration(id: "sipEnabled", enabled: true, platforms: ["macOS"]),
            HealthMetricConfiguration(id: "softwareUpdateCompliance", enabled: true, platforms: ["macOS", "iOS", "iPadOS", "visionOS"])
        ]
    }
    
    var effectiveMetrics: [HealthMetricConfiguration] {
        metrics ?? Self.defaultMetrics
    }
    
    var enabledMetrics: [HealthMetricConfiguration] {
        effectiveMetrics.filter { $0.enabled }
    }
}

struct HealthMetricConfiguration: Codable, Identifiable {
    var id: String
    var enabled: Bool = true
    var displayName: String?
    var thresholds: MetricThresholds?
    var checkedInDays: Int?
    var platforms: [String]?
    
    struct MetricThresholds: Codable {
        var critical: Int = 50
        var warning: Int = 80
    }
    
    var effectiveThresholds: MetricThresholds {
        thresholds ?? MetricThresholds()
    }
    
    var effectivePlatforms: [String] {
        platforms ?? ["macOS"]
    }
    
    func appliesTo(platform: String) -> Bool {
        effectivePlatforms.contains(platform)
    }
}

// MARK: - Device Health Configuration

struct DeviceHealthConfiguration: Codable {
    var metrics: [DeviceHealthMetricConfiguration]?
    
    static var defaultMetrics: [DeviceHealthMetricConfiguration] {
        [
            DeviceHealthMetricConfiguration(id: "managementStatus", category: "management", platforms: ["macOS", "iOS", "iPadOS", "visionOS"]),
            DeviceHealthMetricConfiguration(id: "supervisionStatus", category: "management", platforms: ["macOS", "iOS", "iPadOS", "visionOS"]),
            DeviceHealthMetricConfiguration(id: "fileVault", category: "security", platforms: ["macOS"]),
            DeviceHealthMetricConfiguration(id: "firewall", category: "security", platforms: ["macOS"]),
            DeviceHealthMetricConfiguration(id: "gatekeeper", category: "security", platforms: ["macOS"]),
            DeviceHealthMetricConfiguration(id: "sip", category: "security", platforms: ["macOS"]),
            DeviceHealthMetricConfiguration(id: "activationLock", category: "security", platforms: ["macOS", "iOS", "iPadOS", "visionOS"]),
            DeviceHealthMetricConfiguration(id: "softwareUpdate", category: "compliance", platforms: ["macOS", "iOS", "iPadOS", "visionOS"]),
            DeviceHealthMetricConfiguration(id: "lastCheckIn", category: "status", platforms: ["macOS", "iOS", "iPadOS", "visionOS"]),
            DeviceHealthMetricConfiguration(id: "appleCare", category: "status", platforms: ["macOS", "iOS", "iPadOS", "visionOS"])
        ]
    }
    
    var effectiveMetrics: [DeviceHealthMetricConfiguration] {
        metrics ?? Self.defaultMetrics
    }
}

struct DeviceHealthMetricConfiguration: Codable, Identifiable {
    var id: String
    var enabled: Bool = true
    var displayName: String?
    var category: String?
    var platforms: [String]?
    
    var effectivePlatforms: [String] {
        platforms ?? ["macOS"]
    }
    
    func appliesTo(platform: String) -> Bool {
        effectivePlatforms.contains(platform)
    }
}

// MARK: - Device Actions Configuration

struct DeviceActionsConfiguration: Codable {
    var computer: ComputerActionsConfiguration?
    var mobileDevice: MobileDeviceActionsConfiguration?
    
    var effectiveComputerActions: ComputerActionsConfiguration {
        computer ?? ComputerActionsConfiguration()
    }
    
    var effectiveMobileActions: MobileDeviceActionsConfiguration {
        mobileDevice ?? MobileDeviceActionsConfiguration()
    }
}

struct ComputerActionsConfiguration: Codable {
    var sendBlankPush: Bool = true
    var restart: Bool = true
    var shutdown: Bool = true
    var lock: Bool = true
    var wipe: Bool = false
    var enableRemoteDesktop: Bool = true
    var disableRemoteDesktop: Bool = true
    var enableBluetooth: Bool = true
    var disableBluetooth: Bool = true
    var viewRecoveryLockPassword: Bool = true
    var viewFileVaultKey: Bool = true
    var viewLocalAdminPassword: Bool = true
    var unlockUserAccount: Bool = true
    var renewMDMProfile: Bool = true
    var sendCustomCommand: Bool = false
    var updateInventory: Bool = true
    var installPackage: Bool = false
    var runPolicy: Bool = false
}

struct MobileDeviceActionsConfiguration: Codable {
    var sendBlankPush: Bool = true
    var restart: Bool = true
    var shutdown: Bool = true
    var lock: Bool = true
    var wipe: Bool = false
    var clearPasscode: Bool = true
    var enableLostMode: Bool = true
    var disableLostMode: Bool = true
    var playLostModeSound: Bool = true
    var updateInventory: Bool = true
    var renewMDMProfile: Bool = true
    var enableActivationLock: Bool = false
    var clearActivationLock: Bool = false
}

// MARK: - Reports Configuration

struct ReportsConfiguration: Codable {
    var enabled: Bool = true
    var availableReports: [ReportConfiguration]?
    
    static var defaultReports: [ReportConfiguration] {
        [
            ReportConfiguration(id: "deviceInventory", category: "inventory", platforms: ["macOS", "iOS", "iPadOS", "visionOS"]),
            ReportConfiguration(id: "securityCompliance", category: "security", platforms: ["macOS"]),
            ReportConfiguration(id: "softwareUpdates", category: "compliance", platforms: ["macOS", "iOS", "iPadOS", "visionOS"]),
            ReportConfiguration(id: "applicationInventory", category: "inventory", platforms: ["macOS", "iOS", "iPadOS"]),
            ReportConfiguration(id: "appleCareStatus", category: "management", platforms: ["macOS", "iOS", "iPadOS", "visionOS"]),
            ReportConfiguration(id: "certificateExpiration", category: "security", platforms: ["macOS", "iOS", "iPadOS"]),
            ReportConfiguration(id: "fileVaultStatus", category: "security", platforms: ["macOS"]),
            ReportConfiguration(id: "configurationProfiles", category: "management", platforms: ["macOS", "iOS", "iPadOS", "visionOS"])
        ]
    }
    
    var effectiveReports: [ReportConfiguration] {
        availableReports ?? Self.defaultReports
    }
    
    var enabledReports: [ReportConfiguration] {
        effectiveReports.filter { $0.enabled }
    }
}

struct ReportConfiguration: Codable, Identifiable {
    var id: String
    var enabled: Bool = true
    var displayName: String?
    var category: String?
    var platforms: [String]?
    var exportFormats: [String]?
    
    var effectivePlatforms: [String] {
        platforms ?? ["macOS", "iOS", "iPadOS", "visionOS"]
    }
    
    var effectiveExportFormats: [String] {
        exportFormats ?? ["csv", "json"]
    }
}

// MARK: - UI Configuration

struct UIConfiguration: Codable {
    var appTitle: String = "Helios"
    var appSubtitle: String = "Console"
    var supportURL: String?
    var companyName: String?
    var logoURL: String?
    var accentColor: String?
    var defaultColorScheme: String = "system"
    var showEnrollments: Bool = true
    var showAnnouncements: Bool = true
    var showSettings: Bool = true
    
    var swiftUIColorScheme: ColorScheme? {
        switch defaultColorScheme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
    
    var accentSwiftUIColor: Color? {
        guard let hex = accentColor else { return nil }
        return Color(hex: hex)
    }
}

// MARK: - Authentication Configuration

struct AuthenticationConfiguration: Codable {
    var requireBiometric: Bool = false
    var allowBiometricSetup: Bool = true
    var sessionTimeout: Int = 0
    var allowRememberMe: Bool = true
    
    var hasSessionTimeout: Bool {
        sessionTimeout > 0
    }
    
    var sessionTimeoutInterval: TimeInterval {
        TimeInterval(sessionTimeout * 60)
    }
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        guard hexSanitized.count == 6 else { return nil }
        
        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        
        self.init(
            red: Double((rgb & 0xFF0000) >> 16) / 255.0,
            green: Double((rgb & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgb & 0x0000FF) / 255.0
        )
    }
}
