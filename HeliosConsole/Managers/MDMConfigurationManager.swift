//
//  MDMConfigurationManager.swift
//  HeliosConsole
//
//  Manages MDM configuration profile settings
//

import Foundation
import Combine

class MDMConfigurationManager: ObservableObject {
    static let shared = MDMConfigurationManager()
    
    @Published private(set) var configuration: MDMConfiguration
    @Published private(set) var configurationSource: String = "defaults"
    
    // MDM Configuration Profile keys - supports both nested and flat structures
    private enum MDMKeys {
        // Nested structure keys (new format from AppConfiguration schema)
        static let jamfPro = "jamfPro"
        static let serverURL = "serverURL"
        static let masterClientIDNested = "masterClientID"
        static let masterClientSecretNested = "masterClientSecret"
        static let requiredRoleNameNested = "requiredRoleName"
        
        // Flat keys (legacy format)
        static let jamfURL = "JamfURL"
        static let masterClientID = "MasterClientID"
        static let masterClientSecret = "MasterClientSecret"
        static let requiredRoleName = "RequiredRoleName"
        
        // UI keys
        static let userInterface = "userInterface"
        static let appTitle = "AppTitle"
        static let appSubtitle = "AppSubtitle"
        static let supportURL = "SupportURL"
        
        // Other keys
        static let localAdministration = "localAdministration"
        static let localAdminUsername = "LocalAdminUsername"
        static let sidebarItems = "SidebarItems"
        static let screenShareEnabled = "ScreenShareEnabled"
        
        // Apple Business Manager (nested)
        static let appleBusinessManager = "appleBusinessManager"
        static let abmClientId = "ABMClientId"
        static let abmKeyId = "ABMKeyId"
        static let abmPrivateKey = "ABMPrivateKey"

        // Role-based access
        static let role = "role"

        // Cleanup feature (nested)
        static let cleanup = "cleanup"

        // Jamf Protect (nested)
        static let jamfProtect = "jamfProtect"
    }
    
    private init() {
        var source = "defaults"
        self.configuration = Self.loadConfiguration(source: &source)
        self.configurationSource = source
    }
    
    // MARK: - Load Configuration
    private static let mainAppBundleID = "com.helios.console"
    
    private static func loadConfiguration(source: inout String) -> MDMConfiguration {
        // Try managed preferences first (from MDM profile with nested structure)
        if let config = loadFromManagedPreferences() {
            print("✅ Loaded configuration from MDM managed preferences")
            source = "mdm"
            return config
        }
        
        // Try UserDefaults.standard with flat keys (legacy/development)
        if let config = loadFromFlatDefaults() {
            print("✅ Loaded configuration from UserDefaults (flat keys)")
            source = "userDefaults"
            return config
        }
        
        // If this is a companion app (different bundle ID), try the main app's domain.
        // The main app writes config to its own UserDefaults.standard, which is keyed
        // by its bundle ID. We can read it via UserDefaults(suiteName:).
        // MDM managed preferences are also written per-bundle-ID, so we check
        // /Library/Managed Preferences/<mainAppBundleID>.plist as well.
        if Bundle.main.bundleIdentifier != mainAppBundleID {
            if let config = loadFromMainAppDefaults() {
                print("✅ Loaded configuration from main app defaults (\(mainAppBundleID))")
                source = "mainApp"
                return config
            }
        }
        
        // Fallback to default configuration
        print("⚠️ No valid configuration found, using defaults")
        source = "defaults"
        return .default
    }
    
    // MARK: - Load from Managed Preferences (MDM Profile with Nested Structure)
    private static func loadFromManagedPreferences() -> MDMConfiguration? {
        // MDM profiles write to /Library/Managed Preferences/
        // For sandboxed apps, these are accessible via UserDefaults.standard
        let defaults = UserDefaults.standard
        
        print("🔍 Checking for MDM configuration (nested 'jamfPro' structure)...")
        
        // Check for nested jamfPro structure
        guard let jamfProDict = defaults.dictionary(forKey: MDMKeys.jamfPro) else {
            print("   ❌ No 'jamfPro' dictionary found in UserDefaults")
            return nil
        }
        
        guard let serverURL = jamfProDict[MDMKeys.serverURL] as? String,
              !serverURL.isEmpty else {
            print("   ❌ No serverURL in jamfPro dictionary")
            return nil
        }
        
        guard let clientID = jamfProDict[MDMKeys.masterClientIDNested] as? String,
              !clientID.isEmpty else {
            print("   ❌ No masterClientID in jamfPro dictionary")
            return nil
        }
        
        guard let clientSecret = jamfProDict[MDMKeys.masterClientSecretNested] as? String,
              !clientSecret.isEmpty else {
            print("   ❌ No masterClientSecret in jamfPro dictionary")
            return nil
        }
        
        print("   ✅ Found serverURL: \(serverURL)")
        print("   ✅ Found clientID: \(String(clientID.prefix(12)))...")
        
        // Get optional jamfPro settings
        let requiredRoleName = jamfProDict[MDMKeys.requiredRoleNameNested] as? String ?? "SVC_WATCHER_USER"
        
        // Get UI settings from nested structure
        var appTitle = "Helios"
        var appSubtitle = "Console"
        var supportURL: String? = nil
        
        if let uiDict = defaults.dictionary(forKey: MDMKeys.userInterface) {
            appTitle = uiDict["appTitle"] as? String ?? appTitle
            appSubtitle = uiDict["appSubtitle"] as? String ?? appSubtitle
            let urlValue = uiDict["supportURL"] as? String
            supportURL = (urlValue?.isEmpty == true) ? nil : urlValue
        }
        
        // Get local admin settings
        var localAdminUsername = "macadmin"
        if let localDict = defaults.dictionary(forKey: MDMKeys.localAdministration) {
            localAdminUsername = localDict["username"] as? String ?? localAdminUsername
        }
        
        // Get ABM settings from nested structure
        var abmClientId: String? = nil
        var abmKeyId: String? = nil
        var abmPrivateKey: String? = nil
        
        if let abmDict = defaults.dictionary(forKey: MDMKeys.appleBusinessManager),
           let enabled = abmDict["enabled"] as? Bool, enabled {
            abmClientId = abmDict["clientID"] as? String
            abmKeyId = abmDict["keyID"] as? String
            abmPrivateKey = abmDict["privateKey"] as? String
            
            if abmClientId != nil {
                print("   ✅ Found ABM configuration")
            }
        }
        
        // Get screen share setting
        let screenShareEnabled = jamfProDict["screenShareEnabled"] as? Bool ?? defaults.bool(forKey: MDMKeys.screenShareEnabled)
        
        // Get sidebar items (if provided)
        let sidebarItems: [MDMConfiguration.SidebarItemConfig]
        if let sidebarData = defaults.array(forKey: MDMKeys.sidebarItems) as? [[String: Any]] {
            sidebarItems = parseSidebarItems(from: sidebarData)
        } else {
            sidebarItems = MDMConfiguration.default.sidebarItems
        }

        // Operator role (Admin / Support / User). Accept top-level or nested.
        let role = (defaults.string(forKey: MDMKeys.role))
            ?? (jamfProDict[MDMKeys.role] as? String)
            ?? "Admin"

        // Cleanup feature settings (nested)
        var cleanupStaleDays = 90
        var cleanupDefaultStaticGroupID: String? = nil
        var cleanupDefaultSiteID: String? = nil
        if let cleanupDict = defaults.dictionary(forKey: MDMKeys.cleanup) {
            if let days = cleanupDict["staleDays"] as? Int { cleanupStaleDays = days }
            else if let s = cleanupDict["staleDays"] as? String, let days = Int(s) { cleanupStaleDays = days }
            cleanupDefaultStaticGroupID = cleanupDict["defaultStaticGroupID"] as? String
            cleanupDefaultSiteID = cleanupDict["defaultSiteID"] as? String
        }

        // Jamf Protect settings (nested). The password is never delivered
        // here — it lives in the Keychain.
        var protectEnabled = false
        var protectURL: String? = nil
        var protectClientID: String? = nil
        if let protectDict = defaults.dictionary(forKey: MDMKeys.jamfProtect) {
            protectEnabled = protectDict["enabled"] as? Bool ?? false
            protectURL = protectDict["url"] as? String
            protectClientID = protectDict["clientID"] as? String
        }

        return MDMConfiguration(
            jamfURL: serverURL,
            masterClientID: clientID,
            masterClientSecret: clientSecret,
            appTitle: appTitle,
            appSubtitle: appSubtitle,
            sidebarItems: sidebarItems,
            requiredRoleName: requiredRoleName,
            supportURL: supportURL,
            localAdminUsername: localAdminUsername,
            screenShareEnabled: screenShareEnabled,
            abmClientId: abmClientId,
            abmKeyId: abmKeyId,
            abmPrivateKey: abmPrivateKey,
            role: role,
            cleanupStaleDays: cleanupStaleDays,
            cleanupDefaultStaticGroupID: cleanupDefaultStaticGroupID,
            cleanupDefaultSiteID: cleanupDefaultSiteID,
            protectEnabled: protectEnabled,
            protectURL: protectURL,
            protectClientID: protectClientID
        )
    }
    
    // MARK: - Load from Flat Defaults (Legacy/Development)
    private static func loadFromFlatDefaults() -> MDMConfiguration? {
        let defaults = UserDefaults.standard
        
        print("🔍 Checking for flat key configuration (JamfURL, MasterClientID, etc.)...")
        
        guard let jamfURL = defaults.string(forKey: MDMKeys.jamfURL),
              !jamfURL.isEmpty,
              !jamfURL.contains("yourinstance"),
              !jamfURL.contains("your-instance") else {
            print("   ❌ No valid JamfURL found (flat keys)")
            return nil
        }
        
        guard let clientID = defaults.string(forKey: MDMKeys.masterClientID),
              !clientID.isEmpty,
              !clientID.hasPrefix("your-") else {
            print("   ❌ No valid MasterClientID found (flat keys)")
            return nil
        }
        
        guard let clientSecret = defaults.string(forKey: MDMKeys.masterClientSecret),
              !clientSecret.isEmpty else {
            print("   ❌ No MasterClientSecret found (flat keys)")
            return nil
        }
        
        print("   ✅ Found JamfURL: \(jamfURL)")
        print("   ✅ Found ClientID: \(String(clientID.prefix(12)))...")
        
        let appTitle = defaults.string(forKey: MDMKeys.appTitle) ?? "Helios"
        let appSubtitle = defaults.string(forKey: MDMKeys.appSubtitle) ?? "Console"
        let requiredRoleName = defaults.string(forKey: MDMKeys.requiredRoleName) ?? "SVC_WATCHER_USER"
        let supportURL = defaults.string(forKey: MDMKeys.supportURL)
        let localAdminUsername = defaults.string(forKey: MDMKeys.localAdminUsername) ?? "macadmin"
        let screenShareEnabled = defaults.bool(forKey: MDMKeys.screenShareEnabled)
        
        let abmClientId = defaults.string(forKey: MDMKeys.abmClientId)
        let abmKeyId = defaults.string(forKey: MDMKeys.abmKeyId)
        let abmPrivateKey = defaults.string(forKey: MDMKeys.abmPrivateKey)
        
        let sidebarItems: [MDMConfiguration.SidebarItemConfig]
        if let sidebarData = defaults.array(forKey: MDMKeys.sidebarItems) as? [[String: Any]] {
            sidebarItems = parseSidebarItems(from: sidebarData)
        } else {
            sidebarItems = MDMConfiguration.default.sidebarItems
        }
        
        return MDMConfiguration(
            jamfURL: jamfURL,
            masterClientID: clientID,
            masterClientSecret: clientSecret,
            appTitle: appTitle,
            appSubtitle: appSubtitle,
            sidebarItems: sidebarItems,
            requiredRoleName: requiredRoleName,
            supportURL: supportURL,
            localAdminUsername: localAdminUsername,
            screenShareEnabled: screenShareEnabled,
            abmClientId: abmClientId,
            abmKeyId: abmKeyId,
            abmPrivateKey: abmPrivateKey
        )
    }
    
    // MARK: - Load from Main App Defaults (Companion Apps)
    // When running as a companion app (e.g. HeliosMenuBar), the main app's
    // UserDefaults are stored under its bundle ID. We can access them via
    // UserDefaults(suiteName: "com.helios.console"). MDM managed prefs live
    // at /Library/Managed Preferences/com.helios.console.plist and are also
    // accessible this way on non-sandboxed apps.
    private static func loadFromMainAppDefaults() -> MDMConfiguration? {
        guard let defaults = UserDefaults(suiteName: mainAppBundleID) else {
            print("   ❌ Could not open UserDefaults suite for \(mainAppBundleID)")
            return nil
        }
        
        print("🔍 Checking main app defaults (\(mainAppBundleID))...")
        
        // Try nested structure first
        if let jamfProDict = defaults.dictionary(forKey: MDMKeys.jamfPro),
           let serverURL = jamfProDict[MDMKeys.serverURL] as? String, !serverURL.isEmpty,
           let clientID = jamfProDict[MDMKeys.masterClientIDNested] as? String, !clientID.isEmpty,
           let clientSecret = jamfProDict[MDMKeys.masterClientSecretNested] as? String, !clientSecret.isEmpty {
            
            print("   ✅ Found nested config in main app defaults")
            let requiredRoleName = jamfProDict[MDMKeys.requiredRoleNameNested] as? String ?? "SVC_WATCHER_USER"
            
            var appTitle = "Helios"
            var appSubtitle = "Console"
            var supportURL: String? = nil
            if let uiDict = defaults.dictionary(forKey: MDMKeys.userInterface) {
                appTitle = uiDict["appTitle"] as? String ?? appTitle
                appSubtitle = uiDict["appSubtitle"] as? String ?? appSubtitle
                let urlValue = uiDict["supportURL"] as? String
                supportURL = (urlValue?.isEmpty == true) ? nil : urlValue
            }
            
            var localAdminUsername = "macadmin"
            if let localDict = defaults.dictionary(forKey: MDMKeys.localAdministration) {
                localAdminUsername = localDict["username"] as? String ?? localAdminUsername
            }
            
            var abmClientId: String? = nil
            var abmKeyId: String? = nil
            var abmPrivateKey: String? = nil
            if let abmDict = defaults.dictionary(forKey: MDMKeys.appleBusinessManager),
               let enabled = abmDict["enabled"] as? Bool, enabled {
                abmClientId = abmDict["clientID"] as? String
                abmKeyId = abmDict["keyID"] as? String
                abmPrivateKey = abmDict["privateKey"] as? String
            }
            
            let screenShareEnabled = jamfProDict["screenShareEnabled"] as? Bool ?? defaults.bool(forKey: MDMKeys.screenShareEnabled)
            let sidebarItems = MDMConfiguration.default.sidebarItems
            
            return MDMConfiguration(
                jamfURL: serverURL,
                masterClientID: clientID,
                masterClientSecret: clientSecret,
                appTitle: appTitle,
                appSubtitle: appSubtitle,
                sidebarItems: sidebarItems,
                requiredRoleName: requiredRoleName,
                supportURL: supportURL,
                localAdminUsername: localAdminUsername,
                screenShareEnabled: screenShareEnabled,
                abmClientId: abmClientId,
                abmKeyId: abmKeyId,
                abmPrivateKey: abmPrivateKey
            )
        }
        
        // Try flat keys
        if let jamfURL = defaults.string(forKey: MDMKeys.jamfURL),
           !jamfURL.isEmpty, !jamfURL.contains("yourinstance"), !jamfURL.contains("your-instance"),
           let clientID = defaults.string(forKey: MDMKeys.masterClientID),
           !clientID.isEmpty, !clientID.hasPrefix("your-"),
           let clientSecret = defaults.string(forKey: MDMKeys.masterClientSecret),
           !clientSecret.isEmpty {
            
            print("   ✅ Found flat key config in main app defaults: \(jamfURL)")
            
            let appTitle = defaults.string(forKey: MDMKeys.appTitle) ?? "Helios"
            let appSubtitle = defaults.string(forKey: MDMKeys.appSubtitle) ?? "Console"
            let requiredRoleName = defaults.string(forKey: MDMKeys.requiredRoleName) ?? "SVC_WATCHER_USER"
            let supportURL = defaults.string(forKey: MDMKeys.supportURL)
            let localAdminUsername = defaults.string(forKey: MDMKeys.localAdminUsername) ?? "macadmin"
            let abmClientId = defaults.string(forKey: MDMKeys.abmClientId)
            let abmKeyId = defaults.string(forKey: MDMKeys.abmKeyId)
            let abmPrivateKey = defaults.string(forKey: MDMKeys.abmPrivateKey)
            let screenShareEnabled = defaults.bool(forKey: MDMKeys.screenShareEnabled)
            let sidebarItems = MDMConfiguration.default.sidebarItems
            
            return MDMConfiguration(
                jamfURL: jamfURL,
                masterClientID: clientID,
                masterClientSecret: clientSecret,
                appTitle: appTitle,
                appSubtitle: appSubtitle,
                sidebarItems: sidebarItems,
                requiredRoleName: requiredRoleName,
                supportURL: supportURL,
                localAdminUsername: localAdminUsername,
                screenShareEnabled: screenShareEnabled,
                abmClientId: abmClientId,
                abmKeyId: abmKeyId,
                abmPrivateKey: abmPrivateKey
            )
        }
        
        print("   ❌ No valid config in main app defaults")
        return nil
    }
    
    // MARK: - Parse Sidebar Items
    private static func parseSidebarItems(from data: [[String: Any]]) -> [MDMConfiguration.SidebarItemConfig] {
        var items: [MDMConfiguration.SidebarItemConfig] = []
        
        for dict in data {
            guard let id = dict["id"] as? String,
                  let icon = dict["icon"] as? String,
                  let title = dict["title"] as? String,
                  let order = dict["order"] as? Int else {
                continue
            }
            
            let isEnabled = dict["isEnabled"] as? Bool ?? true
            
            items.append(MDMConfiguration.SidebarItemConfig(
                id: id,
                icon: icon,
                title: title,
                isEnabled: isEnabled,
                order: order
            ))
        }
        
        return items.sorted { $0.order < $1.order }
    }
    
    // MARK: - Reload Configuration
    func reloadConfiguration() {
        var source = "defaults"
        self.configuration = Self.loadConfiguration(source: &source)
        self.configurationSource = source
    }
    
    // MARK: - Helper Methods
    func getEnabledSidebarItems() -> [MDMConfiguration.SidebarItemConfig] {
        return configuration.sidebarItems
            .filter { $0.isEnabled }
            .sorted { $0.order < $1.order }
    }
    
    // MARK: - Debug
    func printDebugInfo() {
        print("=== MDMConfigurationManager Debug ===")
        print("Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")
        print("Configuration Source: \(configurationSource)")
        print("Jamf URL: \(configuration.jamfURL)")
        print("Client ID: \(String(configuration.masterClientID.prefix(12)))...")
        print("Has Secret: \(!configuration.masterClientSecret.isEmpty)")
        print("ABM Configured: \(configuration.isABMConfigured)")
        print("=====================================")
    }
}
