//
//  HeliosConsoleApp.swift
//  HeliosConsole
//
//  Main application entry point
//

import SwiftUI
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.helios.console", category: "App")

@main
struct HeliosConsoleApp: App {
    @StateObject private var deepLinkRouter = DeepLinkRouter()
    
    init() {
        // Setup development configuration
        Self.setupDevelopmentConfiguration()
        
        // Force reload configuration after defaults are set
        MDMConfigurationManager.shared.reloadConfiguration()
        
        // Log final configuration state
        let config = MDMConfigurationManager.shared.configuration
        logger.info("App initialized with Jamf URL: \(config.jamfURL)")
        
        // Check ABM configuration
        if config.isABMConfigured {
            logger.info("ABM is configured - AppleCare lookups enabled")
        } else {
            logger.info("ABM is not configured - AppleCare lookups disabled")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            WelcomeLoginView()
                .frame(minWidth: 1200, minHeight: 800)
                .preferredColorScheme(AppSettings.shared.currentColorScheme)
                .environmentObject(AppSettings.shared)
                .environmentObject(deepLinkRouter)
                .onOpenURL { url in
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    deepLinkRouter.handleURL(url)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    deepLinkRouter.checkForPendingDeepLink()
                }
                .onReceive(DistributedNotificationCenter.default().publisher(for: Notification.Name("com.helios.console.deeplink"))) { _ in
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    deepLinkRouter.checkForPendingDeepLink()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
    
    // MARK: - Development Configuration
    
    /// Sets up development configuration for testing with real Jamf Pro data.
    private static func setupDevelopmentConfiguration() {
        let defaults = UserDefaults.standard
        
        // =====================================================================
        // ⚠️ REPLACE THESE WITH YOUR ACTUAL JAMF PRO CREDENTIALS ⚠️
        // =====================================================================
        
        // Your Jamf Pro instance URL (no trailing slash)
        let jamfURL = "https://yourinstance.jamfcloud.com"
    
        // API Client credentials from Jamf Pro
        // Settings → API Roles and Clients → API Clients
        let masterClientID = "your-client-id"
        let masterClientSecret = "your-client-secret"
    
        // The API Role name that will be assigned to user-specific credentials
        let requiredRoleName = "SVC_WATCHER_USER"
        
        // Local admin username for LAPS
        let localAdminUsername = "macadmin"
        
        // =====================================================================
        // APPLE BUSINESS MANAGER API CREDENTIALS (Optional)
        // =====================================================================
        let abmClientId = ""
        let abmKeyId = ""
        let abmPrivateKey = ""
        
        // =====================================================================
        // END CREDENTIALS
        // =====================================================================
        
        // Set all configuration values
        defaults.set(jamfURL, forKey: "JamfURL")
        defaults.set(masterClientID, forKey: "MasterClientID")
        defaults.set(masterClientSecret, forKey: "MasterClientSecret")
        defaults.set("Helios", forKey: "AppTitle")
        defaults.set("Console", forKey: "AppSubtitle")
        defaults.set(requiredRoleName, forKey: "RequiredRoleName")
        defaults.set(localAdminUsername, forKey: "LocalAdminUsername")
        defaults.set("https://support.yourcompany.com", forKey: "SupportURL")
        
        // ABM credentials (only set if configured)
        if !abmClientId.isEmpty {
            defaults.set(abmClientId, forKey: "ABMClientId")
        }
        if !abmKeyId.isEmpty {
            defaults.set(abmKeyId, forKey: "ABMKeyId")
        }
        if !abmPrivateKey.isEmpty {
            defaults.set(abmPrivateKey, forKey: "ABMPrivateKey")
        }
        
        defaults.synchronize()
        
        logger.info("Configuration loaded - Jamf URL: \(jamfURL)")
    }
}
