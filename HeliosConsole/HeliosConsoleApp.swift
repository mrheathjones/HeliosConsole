//
//  HeliosConsoleApp.swift
//  HeliosConsole
//
//  Main application entry point
//

import SwiftUI
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.herojoneslabs.helios.console", category: "App")

@main
struct HeliosConsoleApp: App {
    @StateObject private var deepLinkRouter = DeepLinkRouter()
    
    init() {
        // Log final configuration state (loaded from the five managed
        // preference domains — dev config via `defaults write
        // com.herojoneslabs.helios.console.core …` etc.; see docs/ConfigProfileMigration.md)
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
                .onReceive(DistributedNotificationCenter.default().publisher(for: Notification.Name("com.herojoneslabs.helios.console.deeplink"))) { _ in
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    deepLinkRouter.checkForPendingDeepLink()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
