//
//  DeepLinkRouter.swift
//  HeliosConsole
//
//  Routes deep links from the menu bar companion app into navigation actions.
//  
//  Transport: The menu bar app writes a pending request to the main app's
//  UserDefaults (com.herojoneslabs.helios.console). The main app checks for pending requests
//  when it becomes active and routes them into the navigation hierarchy.
//
//  UserDefaults keys:
//    DeepLink_DeviceType  — "computer" or "mobiledevice"
//    DeepLink_DeviceID    — the Jamf Pro device ID
//

import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.herojoneslabs.helios.console", category: "DeepLink")

// MARK: - Deep Link Request

/// Represents a pending deep link navigation request.
struct DeepLinkRequest: Equatable {
    let deviceType: DeviceType
    let deviceID: String
    
    enum DeviceType: String {
        case computer
        case mobiledevice
    }
}

// MARK: - Deep Link Router

@MainActor
class DeepLinkRouter: ObservableObject {
    /// The current pending navigation request. Views observe this and clear it after handling.
    @Published var pendingRequest: DeepLinkRequest?
    
    private static let suiteName = "com.herojoneslabs.helios.console"
    private static let deviceTypeKey = "DeepLink_DeviceType"
    private static let deviceIDKey = "DeepLink_DeviceID"
    
    /// Called by the main app on activation to check for pending deep link requests
    /// written by the menu bar companion app.
    func checkForPendingDeepLink() {
        // Check both standard defaults and the named suite — the menu bar app
        // writes to suiteName but it may land in standard depending on sandbox state
        let candidates: [(String, UserDefaults)] = {
            var list: [(String, UserDefaults)] = []
            list.append(("standard", UserDefaults.standard))
            if let suite = UserDefaults(suiteName: Self.suiteName) {
                list.append(("suite:\(Self.suiteName)", suite))
            }
            return list
        }()
        
        for (label, defaults) in candidates {
            guard let typeRaw = defaults.string(forKey: Self.deviceTypeKey),
                  let deviceID = defaults.string(forKey: Self.deviceIDKey),
                  !deviceID.isEmpty,
                  let deviceType = DeepLinkRequest.DeviceType(rawValue: typeRaw)
            else { continue }
            
            NSLog("🔗 DeepLink: Found %@ id:%@ (via %@)", typeRaw, deviceID, label)
            
            // Clear from all domains
            for (_, d) in candidates {
                d.removeObject(forKey: Self.deviceTypeKey)
                d.removeObject(forKey: Self.deviceIDKey)
                d.synchronize()
            }
            
            pendingRequest = DeepLinkRequest(deviceType: deviceType, deviceID: deviceID)
            return
        }
    }
    
    /// Also handle URL-based deep links (belt and suspenders).
    func handleURL(_ url: URL) {
        guard url.scheme == "heliosconsole",
              url.host == "device",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let typeValue = components.queryItems?.first(where: { $0.name == "type" })?.value,
              let deviceType = DeepLinkRequest.DeviceType(rawValue: typeValue),
              let id = components.queryItems?.first(where: { $0.name == "id" })?.value,
              !id.isEmpty
        else { return }
        
        NSLog("🔗 DeepLink: URL %@ id:%@", typeValue, id)
        pendingRequest = DeepLinkRequest(deviceType: deviceType, deviceID: id)
    }
    
    /// Write a deep link request to shared UserDefaults.
    /// Called by the menu bar companion app before activating the main app.
    static func writeDeepLinkToDefaults(deviceType: String, deviceID: String) {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            NSLog("🔗 DeepLinkRouter: Failed to open suite %@", suiteName)
            return
        }
        
        defaults.set(deviceType, forKey: deviceTypeKey)
        defaults.set(deviceID, forKey: deviceIDKey)
        defaults.synchronize()
        
        NSLog("🔗 DeepLinkRouter: Wrote deep link to defaults — type: %@, id: %@", deviceType, deviceID)
    }
    
    /// Clear the pending request after a view has consumed it.
    func clearRequest() {
        pendingRequest = nil
    }
}
