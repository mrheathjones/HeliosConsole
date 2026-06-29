//
//  ConfigurationManager.swift
//  HeliosConsole
//
//  Unified configuration manager supporting both MDM-managed and standalone deployment
//  
//  Configuration Sources (in priority order):
//  1. MDM Configuration Profile (com.helios.console)
//  2. Local configuration file (~/.helios/config.json)
//  3. UserDefaults (for standalone/development)
//  4. Default values
//

import Foundation
import Combine
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.helios.console", category: "ConfigurationManager")

// MARK: - Configuration Source

enum ConfigurationSource: String, CustomStringConvertible {
    case mdm = "MDM Profile"
    case localFile = "Local File"
    case userDefaults = "User Defaults"
    case defaults = "Defaults"
    
    var description: String { rawValue }
}

// MARK: - Configuration Manager

@MainActor
final class ConfigurationManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = ConfigurationManager()
    
    // MARK: - Published Properties
    
    @Published private(set) var configuration: AppConfiguration
    @Published private(set) var announcementConfiguration: AnnouncementConfiguration
    @Published private(set) var configurationSource: ConfigurationSource = .defaults
    @Published private(set) var announcementSource: ConfigurationSource = .defaults
    @Published private(set) var lastLoadTime: Date?
    @Published private(set) var loadError: String?
    
    // MARK: - Constants
    
    private let mainPreferenceDomain = "com.helios.console"
    private let announcementPreferenceDomain = "com.helios.console.announcements"
    private let localConfigPath: String
    private let localAnnouncementsPath: String
    
    // MARK: - Initialization
    
    private init() {
        // Set up paths
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        self.localConfigPath = "\(homeDir)/.helios/config.json"
        self.localAnnouncementsPath = "\(homeDir)/.helios/announcements.json"
        
        // Initialize with defaults
        self.configuration = AppConfiguration.default
        self.announcementConfiguration = AnnouncementConfiguration()
        
        // Load configuration
        loadConfiguration()
        loadAnnouncementConfiguration()
        
        // Set up observers for MDM profile changes
        setupConfigurationObservers()
    }
    
    // MARK: - Public Methods
    
    /// Reload all configuration from sources
    func reloadConfiguration() {
        loadConfiguration()
        loadAnnouncementConfiguration()
    }
    
    /// Check if the app is properly configured for operation
    var isConfigured: Bool {
        configuration.isValid
    }
    
    /// Check if running in MDM-managed mode
    var isMDMManaged: Bool {
        configurationSource == .mdm
    }
    
    // MARK: - Convenience Accessors
    
    var jamfURL: String { configuration.jamfPro.serverURL }
    var masterClientID: String { configuration.jamfPro.masterClientID }
    var masterClientSecret: String { configuration.jamfPro.masterClientSecret }
    var requiredRoleName: String { configuration.jamfPro.effectiveRoleName }
    var localAdminUsername: String { configuration.localAdministration?.username ?? "macadmin" }
    
    var computersEnabled: Bool { configuration.computers?.enabled ?? true }
    var mobileDevicesEnabled: Bool { configuration.mobileDevices?.enabled ?? true }
    
    var appTitle: String { configuration.userInterface?.appTitle ?? "Helios" }
    var appSubtitle: String { configuration.userInterface?.appSubtitle ?? "Console" }
    var supportURL: String? { configuration.userInterface?.supportURL }
    
    var isABMConfigured: Bool { configuration.isABMConfigured }
    
    // MARK: - Device Action Checks
    
    func isComputerActionEnabled(_ action: String) -> Bool {
        let actions = configuration.deviceActions?.effectiveComputerActions ?? ComputerActionsConfiguration()
        switch action {
        case "sendBlankPush": return actions.sendBlankPush
        case "restart": return actions.restart
        case "shutdown": return actions.shutdown
        case "lock": return actions.lock
        case "wipe": return actions.wipe
        case "enableRemoteDesktop": return actions.enableRemoteDesktop
        case "disableRemoteDesktop": return actions.disableRemoteDesktop
        case "enableBluetooth": return actions.enableBluetooth
        case "disableBluetooth": return actions.disableBluetooth
        case "viewRecoveryLockPassword": return actions.viewRecoveryLockPassword
        case "viewFileVaultKey": return actions.viewFileVaultKey
        case "viewLocalAdminPassword": return actions.viewLocalAdminPassword
        case "unlockUserAccount": return actions.unlockUserAccount
        case "renewMDMProfile": return actions.renewMDMProfile
        case "sendCustomCommand": return actions.sendCustomCommand
        case "updateInventory": return actions.updateInventory
        case "installPackage": return actions.installPackage
        case "runPolicy": return actions.runPolicy
        default: return false
        }
    }
    
    func isMobileActionEnabled(_ action: String) -> Bool {
        let actions = configuration.deviceActions?.effectiveMobileActions ?? MobileDeviceActionsConfiguration()
        switch action {
        case "sendBlankPush": return actions.sendBlankPush
        case "restart": return actions.restart
        case "shutdown": return actions.shutdown
        case "lock": return actions.lock
        case "wipe": return actions.wipe
        case "clearPasscode": return actions.clearPasscode
        case "enableLostMode": return actions.enableLostMode
        case "disableLostMode": return actions.disableLostMode
        case "playLostModeSound": return actions.playLostModeSound
        case "updateInventory": return actions.updateInventory
        case "renewMDMProfile": return actions.renewMDMProfile
        case "enableActivationLock": return actions.enableActivationLock
        case "clearActivationLock": return actions.clearActivationLock
        default: return false
        }
    }
    
    // MARK: - Health Metric Checks
    
    func isScorecardMetricEnabled(_ metricId: String) -> Bool {
        let metrics = configuration.healthScorecard?.effectiveMetrics ?? []
        return metrics.first(where: { $0.id == metricId })?.enabled ?? false
    }
    
    func enabledScorecardMetrics(for platform: String) -> [HealthMetricConfiguration] {
        let metrics = configuration.healthScorecard?.enabledMetrics ?? []
        return metrics.filter { $0.appliesTo(platform: platform) }
    }
    
    // MARK: - Main Configuration Loading
    
    private func loadConfiguration() {
        logger.info("Loading app configuration...")
        loadError = nil
        
        // Try MDM profile first
        if let mdmConfig = loadFromMDMProfile() {
            configuration = mdmConfig
            configurationSource = .mdm
            logger.info("Loaded configuration from MDM profile")
            lastLoadTime = Date()
            return
        }
        
        // Try local file
        if let fileConfig = loadFromLocalFile() {
            configuration = fileConfig
            configurationSource = .localFile
            logger.info("Loaded configuration from local file: \(self.localConfigPath)")
            lastLoadTime = Date()
            return
        }
        
        // Try UserDefaults (for standalone/development)
        if let defaultsConfig = loadFromUserDefaults() {
            configuration = defaultsConfig
            configurationSource = .userDefaults
            logger.info("Loaded configuration from UserDefaults")
            lastLoadTime = Date()
            return
        }
        
        // Use defaults
        configuration = AppConfiguration.default
        configurationSource = .defaults
        logger.warning("No configuration found, using defaults")
        lastLoadTime = Date()
    }
    
    // MARK: - MDM Profile Loading
    
    private func loadFromMDMProfile() -> AppConfiguration? {
        let defaults = UserDefaults(suiteName: mainPreferenceDomain) ?? UserDefaults.standard
        
        // Check if MDM configuration exists
        guard let jamfProDict = defaults.dictionary(forKey: "jamfPro") else {
            return nil
        }
        
        // Build configuration from managed preferences
        var config = AppConfiguration.default
        
        // Jamf Pro settings
        if let serverURL = jamfProDict["serverURL"] as? String,
           let clientID = jamfProDict["masterClientID"] as? String,
           let clientSecret = jamfProDict["masterClientSecret"] as? String {
            config.jamfPro = JamfProConfiguration(
                serverURL: serverURL,
                masterClientID: clientID,
                masterClientSecret: clientSecret,
                requiredRoleName: jamfProDict["requiredRoleName"] as? String,
                connectionTimeout: jamfProDict["connectionTimeout"] as? Int,
                requestTimeout: jamfProDict["requestTimeout"] as? Int
            )
        } else {
            return nil
        }
        
        // ABM settings
        if let abmDict = defaults.dictionary(forKey: "appleBusinessManager") {
            config.appleBusinessManager = ABMConfiguration(
                enabled: abmDict["enabled"] as? Bool ?? false,
                clientID: abmDict["clientID"] as? String,
                keyID: abmDict["keyID"] as? String,
                privateKey: abmDict["privateKey"] as? String
            )
        }
        
        // Local admin settings
        if let localDict = defaults.dictionary(forKey: "localAdministration") {
            config.localAdministration = LocalAdminConfiguration(
                enabled: localDict["enabled"] as? Bool ?? true,
                username: localDict["username"] as? String ?? "macadmin"
            )
        }
        
        // Computer settings
        if let compDict = defaults.dictionary(forKey: "computers") {
            config.computers = ComputerConfiguration(
                enabled: compDict["enabled"] as? Bool ?? true,
                fetchInventory: compDict["fetchInventory"] as? Bool ?? true,
                showDashboardCard: compDict["showDashboardCard"] as? Bool ?? true,
                enableAPIActions: compDict["enableAPIActions"] as? Bool ?? true,
                enableReports: compDict["enableReports"] as? Bool ?? true,
                inventoryRefreshInterval: compDict["inventoryRefreshInterval"] as? Int ?? 15,
                inventorySections: compDict["inventorySections"] as? [String]
            )
        }
        
        // Mobile device settings
        if let mobileDict = defaults.dictionary(forKey: "mobileDevices") {
            var dashboardCards: MobileDeviceConfiguration.MobileDashboardCards?
            if let cardsDict = mobileDict["showDashboardCards"] as? [String: Bool] {
                dashboardCards = MobileDeviceConfiguration.MobileDashboardCards(
                    iOS: cardsDict["iOS"] ?? true,
                    iPadOS: cardsDict["iPadOS"] ?? true,
                    visionOS: cardsDict["visionOS"] ?? true
                )
            }
            
            config.mobileDevices = MobileDeviceConfiguration(
                enabled: mobileDict["enabled"] as? Bool ?? true,
                fetchInventory: mobileDict["fetchInventory"] as? Bool ?? true,
                showDashboardCards: dashboardCards,
                enableAPIActions: mobileDict["enableAPIActions"] as? Bool ?? true,
                enableReports: mobileDict["enableReports"] as? Bool ?? true,
                inventoryRefreshInterval: mobileDict["inventoryRefreshInterval"] as? Int ?? 15,
                inventorySections: mobileDict["inventorySections"] as? [String]
            )
        }
        
        // Device actions
        if let actionsDict = defaults.dictionary(forKey: "deviceActions") {
            config.deviceActions = parseDeviceActions(actionsDict)
        }
        
        // UI settings
        if let uiDict = defaults.dictionary(forKey: "userInterface") {
            config.userInterface = UIConfiguration(
                appTitle: uiDict["appTitle"] as? String ?? "Helios",
                appSubtitle: uiDict["appSubtitle"] as? String ?? "Console",
                supportURL: uiDict["supportURL"] as? String,
                companyName: uiDict["companyName"] as? String,
                logoURL: uiDict["logoURL"] as? String,
                accentColor: uiDict["accentColor"] as? String,
                defaultColorScheme: uiDict["defaultColorScheme"] as? String ?? "system",
                showEnrollments: uiDict["showEnrollments"] as? Bool ?? true,
                showAnnouncements: uiDict["showAnnouncements"] as? Bool ?? true,
                showSettings: uiDict["showSettings"] as? Bool ?? true
            )
        }
        
        // Authentication settings
        if let authDict = defaults.dictionary(forKey: "authentication") {
            config.authentication = AuthenticationConfiguration(
                requireBiometric: authDict["requireBiometric"] as? Bool ?? false,
                allowBiometricSetup: authDict["allowBiometricSetup"] as? Bool ?? true,
                sessionTimeout: authDict["sessionTimeout"] as? Int ?? 0,
                allowRememberMe: authDict["allowRememberMe"] as? Bool ?? true
            )
        }
        
        return config
    }
    
    private func parseDeviceActions(_ dict: [String: Any]) -> DeviceActionsConfiguration {
        var actions = DeviceActionsConfiguration()
        
        if let compDict = dict["computer"] as? [String: Bool] {
            actions.computer = ComputerActionsConfiguration(
                sendBlankPush: compDict["sendBlankPush"] ?? true,
                restart: compDict["restart"] ?? true,
                shutdown: compDict["shutdown"] ?? true,
                lock: compDict["lock"] ?? true,
                wipe: compDict["wipe"] ?? false,
                enableRemoteDesktop: compDict["enableRemoteDesktop"] ?? true,
                disableRemoteDesktop: compDict["disableRemoteDesktop"] ?? true,
                enableBluetooth: compDict["enableBluetooth"] ?? true,
                disableBluetooth: compDict["disableBluetooth"] ?? true,
                viewRecoveryLockPassword: compDict["viewRecoveryLockPassword"] ?? true,
                viewFileVaultKey: compDict["viewFileVaultKey"] ?? true,
                viewLocalAdminPassword: compDict["viewLocalAdminPassword"] ?? true,
                unlockUserAccount: compDict["unlockUserAccount"] ?? true,
                renewMDMProfile: compDict["renewMDMProfile"] ?? true,
                sendCustomCommand: compDict["sendCustomCommand"] ?? false,
                updateInventory: compDict["updateInventory"] ?? true,
                installPackage: compDict["installPackage"] ?? false,
                runPolicy: compDict["runPolicy"] ?? false
            )
        }
        
        if let mobileDict = dict["mobileDevice"] as? [String: Bool] {
            actions.mobileDevice = MobileDeviceActionsConfiguration(
                sendBlankPush: mobileDict["sendBlankPush"] ?? true,
                restart: mobileDict["restart"] ?? true,
                shutdown: mobileDict["shutdown"] ?? true,
                lock: mobileDict["lock"] ?? true,
                wipe: mobileDict["wipe"] ?? false,
                clearPasscode: mobileDict["clearPasscode"] ?? true,
                enableLostMode: mobileDict["enableLostMode"] ?? true,
                disableLostMode: mobileDict["disableLostMode"] ?? true,
                playLostModeSound: mobileDict["playLostModeSound"] ?? true,
                updateInventory: mobileDict["updateInventory"] ?? true,
                renewMDMProfile: mobileDict["renewMDMProfile"] ?? true,
                enableActivationLock: mobileDict["enableActivationLock"] ?? false,
                clearActivationLock: mobileDict["clearActivationLock"] ?? false
            )
        }
        
        return actions
    }
    
    // MARK: - Local File Loading
    
    private func loadFromLocalFile() -> AppConfiguration? {
        let path = (localConfigPath as NSString).expandingTildeInPath
        
        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path) else {
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(AppConfiguration.self, from: data)
        } catch {
            logger.error("Failed to parse local config file: \(error.localizedDescription)")
            loadError = "Failed to parse local configuration: \(error.localizedDescription)"
            return nil
        }
    }
    
    // MARK: - UserDefaults Loading (Standalone Mode)
    
    private func loadFromUserDefaults() -> AppConfiguration? {
        let defaults = UserDefaults.standard
        
        // Check for basic required keys
        guard let jamfURL = defaults.string(forKey: "JamfURL"),
              let clientID = defaults.string(forKey: "MasterClientID"),
              let clientSecret = defaults.string(forKey: "MasterClientSecret"),
              !jamfURL.isEmpty, !clientID.isEmpty, !clientSecret.isEmpty else {
            return nil
        }
        
        var config = AppConfiguration.default
        
        // Jamf Pro
        config.jamfPro = JamfProConfiguration(
            serverURL: jamfURL,
            masterClientID: clientID,
            masterClientSecret: clientSecret,
            requiredRoleName: defaults.string(forKey: "RequiredRoleName")
        )
        
        // ABM
        if let abmClientId = defaults.string(forKey: "ABMClientId"),
           let abmKeyId = defaults.string(forKey: "ABMKeyId"),
           let abmPrivateKey = defaults.string(forKey: "ABMPrivateKey"),
           !abmClientId.isEmpty {
            config.appleBusinessManager = ABMConfiguration(
                enabled: true,
                clientID: abmClientId,
                keyID: abmKeyId,
                privateKey: abmPrivateKey
            )
        }
        
        // Local admin
        if let username = defaults.string(forKey: "LocalAdminUsername") {
            config.localAdministration = LocalAdminConfiguration(
                enabled: true,
                username: username
            )
        }
        
        // UI
        config.userInterface = UIConfiguration(
            appTitle: defaults.string(forKey: "AppTitle") ?? "Helios",
            appSubtitle: defaults.string(forKey: "AppSubtitle") ?? "Console",
            supportURL: defaults.string(forKey: "SupportURL")
        )
        
        return config
    }
    
    // MARK: - Announcement Configuration Loading
    
    private func loadAnnouncementConfiguration() {
        logger.info("Loading announcement configuration...")
        
        // Try MDM profile first
        if let mdmConfig = loadAnnouncementsFromMDMProfile() {
            announcementConfiguration = mdmConfig
            announcementSource = .mdm
            logger.info("Loaded announcements from MDM profile")
            return
        }
        
        // Try local file
        if let fileConfig = loadAnnouncementsFromLocalFile() {
            announcementConfiguration = fileConfig
            announcementSource = .localFile
            logger.info("Loaded announcements from local file")
            return
        }
        
        // Use defaults
        announcementConfiguration = AnnouncementConfiguration()
        announcementSource = .defaults
        logger.info("Using default announcement configuration")
    }
    
    private func loadAnnouncementsFromMDMProfile() -> AnnouncementConfiguration? {
        let defaults = UserDefaults(suiteName: announcementPreferenceDomain) ?? UserDefaults.standard
        
        guard defaults.object(forKey: "announcementsEnabled") != nil else {
            return nil
        }
        
        var config = AnnouncementConfiguration()
        config.announcementsEnabled = defaults.bool(forKey: "announcementsEnabled")
        config.refreshInterval = defaults.integer(forKey: "refreshInterval")
        config.allowLocalFile = defaults.bool(forKey: "allowLocalFile")
        config.allowUserDismiss = defaults.bool(forKey: "allowUserDismiss")
        config.showUnreadBadge = defaults.bool(forKey: "showUnreadBadge")
        
        // Parse announcements array
        if let announcementsArray = defaults.array(forKey: "announcements") as? [[String: Any]] {
            config.announcements = announcementsArray.compactMap { parseAnnouncementItem($0) }
        }
        
        return config
    }
    
    private func parseAnnouncementItem(_ dict: [String: Any]) -> AnnouncementItem? {
        guard let id = dict["id"] as? String,
              let title = dict["title"] as? String,
              let message = dict["message"] as? String else {
            return nil
        }
        
        var item = AnnouncementItem(id: id, title: title, message: message)
        item.type = dict["type"] as? String ?? "info"
        item.priority = dict["priority"] as? String ?? "normal"
        item.createdAt = dict["createdAt"] as? String
        item.expiresAt = dict["expiresAt"] as? String
        item.startsAt = dict["startsAt"] as? String
        item.dismissible = dict["dismissible"] as? Bool ?? true
        item.requiredReading = dict["requiredReading"] as? Bool ?? false
        item.actionURL = dict["actionURL"] as? String
        item.actionLabel = dict["actionLabel"] as? String
        
        return item
    }
    
    private func loadAnnouncementsFromLocalFile() -> AnnouncementConfiguration? {
        let path = (localAnnouncementsPath as NSString).expandingTildeInPath
        
        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path) else {
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(AnnouncementConfiguration.self, from: data)
        } catch {
            logger.error("Failed to parse local announcements file: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Configuration Change Observers
    
    private func setupConfigurationObservers() {
        // Watch for UserDefaults changes
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Debounce and reload if needed
            Task { @MainActor in
                self?.reloadConfiguration()
            }
        }
    }
    
    // MARK: - Save Local Configuration
    
    /// Save current configuration to local file (for standalone mode)
    func saveToLocalFile() throws {
        let path = (localConfigPath as NSString).expandingTildeInPath
        let directory = (path as NSString).deletingLastPathComponent
        
        // Create directory if needed
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        
        try data.write(to: URL(fileURLWithPath: path))
        logger.info("Saved configuration to \(path)")
    }
    
    /// Update a specific setting in UserDefaults (for standalone mode)
    func updateSetting(_ key: String, value: Any?) {
        guard configurationSource == .userDefaults || configurationSource == .defaults else {
            logger.warning("Cannot update settings - configuration is MDM managed")
            return
        }
        
        if let value = value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        
        reloadConfiguration()
    }
}

// MARK: - SwiftUI Environment

struct ConfigurationManagerKey: EnvironmentKey {
    static let defaultValue = ConfigurationManager.shared
}

extension EnvironmentValues {
    var configurationManager: ConfigurationManager {
        get { self[ConfigurationManagerKey.self] }
        set { self[ConfigurationManagerKey.self] = newValue }
    }
}
