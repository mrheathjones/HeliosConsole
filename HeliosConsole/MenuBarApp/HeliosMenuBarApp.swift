//
//  HeliosMenuBarApp.swift
//  HeliosMenuBar
//
//  A lightweight macOS menu bar companion app for Helios Console.
//  Provides quick device search by name or serial number.
//  Click a result to open the device record in the main Helios Console app.
//
//  Shared files required in this target's Compile Sources:
//    Models:    Computer.swift, MobileDevice.swift, MDMConfiguration.swift,
//               AppSettings.swift, User.swift, DeviceListItem.swift,
//               PlatformType.swift
//    Managers:  KeychainManager.swift, MDMConfigurationManager.swift
//    Services:  JamfAPIService.swift, UnifiedSearchService.swift,
//               UnifiedSearchResult+ModelIdentifier.swift,
//               ComputerSearchModels.swift, ComputerSearchService.swift,
//               MobileDeviceModels.swift, MobileDeviceInventoryCache.swift,
//               MobileDeviceInventoryService.swift, ComputerInventoryCache.swift
//    Utilities: DeviceIconProvider.swift
//    Views:     ThemeColors.swift
//

import SwiftUI
import AppKit
import os.log

private let logger = Logger(subsystem: "com.helios.console.menubar", category: "MenuBarApp")

// MARK: - App Entry Point

@main
struct HeliosMenuBarApp: App {
    @NSApplicationDelegateAdaptor(MenuBarAppDelegate.self) var appDelegate

    init() {
        // Load configuration from shared UserDefaults / managed preferences
        MDMConfigurationManager.shared.reloadConfiguration()
        let config = MDMConfigurationManager.shared.configuration
        logger.info("HeliosMenuBar initialized — Jamf URL: \(config.jamfURL)")
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .frame(width: 420, height: 520)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - App Delegate

final class MenuBarAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Pure menu-bar app — no Dock icon
        NSApp.setActivationPolicy(.accessory)
        logger.info("HeliosMenuBar launched")
    }
}

// MARK: - Menu Bar Label (icon in the system menu bar)

private struct MenuBarLabel: View {
    var body: some View {
        Image(nsImage: menuBarIcon)
    }

    private var menuBarIcon: NSImage {
        if let icon = NSImage(named: "AppIcon") {
            let size = NSSize(width: 18, height: 18)
            let resized = NSImage(size: size)
            resized.lockFocus()
            icon.draw(
                in: NSRect(origin: .zero, size: size),
                from: NSRect(origin: .zero, size: icon.size),
                operation: .copy,
                fraction: 1.0
            )
            resized.unlockFocus()
            resized.isTemplate = false
            return resized
        }
        // Fallback SF Symbol
        return NSImage(
            systemSymbolName: "sun.max.fill",
            accessibilityDescription: "Helios"
        ) ?? NSImage()
    }
}

// MARK: - Menu Bar Content View

struct MenuBarContentView: View {
    @StateObject private var searchService = UnifiedDeviceSearchService()
    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            Divider().opacity(0.3)
            resultsList
            Divider().opacity(0.3)
            footer
        }
        .background(.ultraThickMaterial)
        .onAppear {
            isSearchFocused = true
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .yellow],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("Helios Console")
                    .font(.system(size: 13, weight: .semibold))
                Text("Quick Device Search")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            connectionBadge
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var connectionBadge: some View {
        let hasCredentials = KeychainManager.shared.loadJamfCredentials() != nil
        return HStack(spacing: 4) {
            Circle()
                .fill(hasCredentials ? .green : .orange)
                .frame(width: 6, height: 6)
            Text(hasCredentials ? "Connected" : "No Credentials")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(.quaternary.opacity(0.5))
        )
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))

            TextField("Search by name or serial number…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isSearchFocused)
                .onSubmit {
                    performSearch()
                }
                .onChange(of: searchText) { _, newValue in
                    // Debounced live search — 400ms after typing stops
                    searchTask?.cancel()
                    if newValue.trimmingCharacters(in: .whitespaces).count >= 2 {
                        searchTask = Task {
                            try? await Task.sleep(nanoseconds: 400_000_000)
                            guard !Task.isCancelled else { return }
                            performSearch()
                        }
                    } else if newValue.isEmpty {
                        searchService.searchResults = []
                        searchService.errorMessage = nil
                    }
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchService.searchResults = []
                    searchService.errorMessage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }

            if searchService.isSearching {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary.opacity(0.5))
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if searchService.searchResults.isEmpty && !searchService.isSearching {
                    emptyState
                } else {
                    ForEach(searchService.searchResults) { result in
                        MenuBarResultRow(result: result)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var emptyState: some View {
        if let error = searchService.errorMessage {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else if searchText.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("Search for a device")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Enter a device name or serial number")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 50)
        } else if searchText.count < 2 {
            Text("Type at least 2 characters…")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                openMainApp()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 10))
                    Text("Open Console")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }

            Spacer()

            Text("\(searchService.searchResults.count) result\(searchService.searchResults.count == 1 ? "" : "s")")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .opacity(searchService.searchResults.isEmpty ? 0 : 1)

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "power")
                        .font(.system(size: 10))
                    Text("Quit")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private func performSearch() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else { return }
        Task {
            await searchService.searchDevices(query: query)
        }
    }

    private func openMainApp() {
        activateOrLaunchMainApp()
    }
}

/// Activate the main Helios Console app if running, or launch it if not.
/// Never spawns a duplicate instance.
private func activateOrLaunchMainApp() {
    let bundleID = "com.helios.console"
    
    // Check if the main app is already running
    let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    
    if let app = runningApps.first {
        // Already running — just bring it to front
        NSLog("🔗 MenuBar: Main app already running (pid %d), activating", app.processIdentifier)
        app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    } else {
        // Not running — launch it
        NSLog("🔗 MenuBar: Main app not running, launching")
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: config)
        } else {
            NSLog("❌ MenuBar: Could not find HeliosConsole app")
        }
    }
}

// MARK: - Result Row

private struct MenuBarResultRow: View {
    let result: UnifiedSearchResult
    @State private var isHovered = false

    var body: some View {
        Button {
            openDeviceInConsole()
        } label: {
            HStack(spacing: 10) {
                deviceIcon
                deviceInfo
                Spacer(minLength: 4)
                chevron
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.accentColor.opacity(0.12) : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }

    // MARK: - Device Icon

    @ViewBuilder
    private var deviceIcon: some View {
        DeviceIconView(
            modelIdentifier: result.modelIdentifier,
            modelName: result.model,
            platform: result.platform,
            size: 36
        )
    }

    // MARK: - Device Info

    private var deviceInfo: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(result.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)

                platformBadge
            }

            HStack(spacing: 8) {
                Text(result.serialNumber)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)

                if result.model != "Mac" && result.model != "Unknown" {
                    Text("•")
                        .font(.system(size: 8))
                        .foregroundStyle(.quaternary)
                    Text(result.model)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let user = result.assignedUser {
                HStack(spacing: 3) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 8))
                    Text(user)
                        .font(.system(size: 10))
                }
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }
        }
    }

    private var platformBadge: some View {
        Text(result.platform.rawValue)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(
                Capsule().fill(result.platform.color)
            )
    }

    private var chevron: some View {
        Image(systemName: "arrow.up.forward.square")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
    }

    // MARK: - Action

    private func openDeviceInConsole() {
        let type: String
        let id: String

        switch result {
        case .computer(let computer):
            type = "computer"
            id = computer.id
        case .mobileDevice(let device):
            type = "mobiledevice"
            id = device.id
        }

        // Write deep link to shared UserDefaults so the main app picks it up on activation
        let suiteName = "com.helios.console"
        if let defaults = UserDefaults(suiteName: suiteName) {
            defaults.set(type, forKey: "DeepLink_DeviceType")
            defaults.set(id, forKey: "DeepLink_DeviceID")
            defaults.synchronize()
            NSLog("🔗 MenuBar: Wrote deep link — type: %@, id: %@", type, id)
        }
        
        // Post a cross-process notification so the main app picks it up immediately
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.helios.console.deeplink"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        NSLog("🔗 MenuBar: Posted distributed notification")
        
        // Activate or launch the main app
        activateOrLaunchMainApp()
    }
}
