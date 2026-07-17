//
//  AppSettings.swift
//  Helios
//
//  Manages app-wide settings and preferences with persistence
//

import SwiftUI
import Combine
import LocalAuthentication

// MARK: - Appearance Mode

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    
    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - App Settings Manager

class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    private let defaults = UserDefaults.standard
    
    // MARK: - Keys
    private enum Keys {
        static let appearanceMode = "helios.appearanceMode"
        static let biometricsEnabled = "helios.biometricsEnabled"
        static let showDeviceIcons = "helios.showDeviceIcons"
        static let defaultItemsPerPage = "helios.defaultItemsPerPage"
        static let autoRefreshInterval = "helios.autoRefreshInterval"
    }
    
    // MARK: - Published Properties
    
    @Published var appearanceMode: AppearanceMode {
        didSet {
            defaults.set(appearanceMode.rawValue, forKey: Keys.appearanceMode)
            Task { @MainActor in
                updateAppearance()
            }
            // Force objectWillChange to notify all observers
            objectWillChange.send()
        }
    }
    
    @Published var biometricsEnabled: Bool {
        didSet {
            defaults.set(biometricsEnabled, forKey: Keys.biometricsEnabled)
        }
    }
    
    @Published var showDeviceIcons: Bool {
        didSet {
            defaults.set(showDeviceIcons, forKey: Keys.showDeviceIcons)
        }
    }
    
    @Published var defaultItemsPerPage: Int {
        didSet {
            defaults.set(defaultItemsPerPage, forKey: Keys.defaultItemsPerPage)
        }
    }
    
    @Published var autoRefreshInterval: Int {
        didSet {
            defaults.set(autoRefreshInterval, forKey: Keys.autoRefreshInterval)
        }
    }
    
    // MARK: - Computed Properties
    
    var currentColorScheme: ColorScheme? {
        appearanceMode.colorScheme
    }
    
    var isDarkMode: Bool {
        switch appearanceMode {
        case .dark:
            return true
        case .light:
            return false
        case .system:
            return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }
    
    var biometricsAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    var biometricType: LABiometryType {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        return context.biometryType
    }
    
    var biometricTypeName: String {
        switch biometricType {
        case .touchID:
            return "Touch ID"
        case .faceID:
            return "Face ID"
        case .opticID:
            return "Optic ID"
        default:
            return "Biometrics"
        }
    }
    
    var biometricIcon: String {
        switch biometricType {
        case .touchID:
            return "touchid"
        case .faceID:
            return "faceid"
        case .opticID:
            return "opticid"
        default:
            return "person.badge.key"
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        // Load appearance mode. A user's own saved choice always wins; on
        // first launch (no saved value) the ui domain's defaultColorScheme
        // seeds it (schema default "system"). The old behavior forced dark.
        if let savedMode = defaults.string(forKey: Keys.appearanceMode),
           let mode = AppearanceMode(rawValue: savedMode) {
            self.appearanceMode = mode
        } else {
            switch MDMConfigurationManager.shared.configuration
                .userInterfaceExtras?.effectiveColorScheme ?? .system {
            case .light: self.appearanceMode = .light
            case .dark: self.appearanceMode = .dark
            case .system: self.appearanceMode = .system
            }
        }
        
        // Load biometrics setting
        self.biometricsEnabled = defaults.bool(forKey: Keys.biometricsEnabled)
        
        // Load other settings with defaults
        self.showDeviceIcons = defaults.object(forKey: Keys.showDeviceIcons) as? Bool ?? true
        self.defaultItemsPerPage = defaults.object(forKey: Keys.defaultItemsPerPage) as? Int ?? 25
        self.autoRefreshInterval = defaults.object(forKey: Keys.autoRefreshInterval) as? Int ?? 0
        
        // Apply initial appearance
        Task { @MainActor in
            self.updateAppearance()
        }
    }
    
    // MARK: - Methods
    
    @MainActor
    func updateAppearance() {
        // Update NSApp appearance immediately
        switch appearanceMode {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        
        // Force all windows to update
        for window in NSApp.windows {
            switch appearanceMode {
            case .system:
                window.appearance = nil
            case .light:
                window.appearance = NSAppearance(named: .aqua)
            case .dark:
                window.appearance = NSAppearance(named: .darkAqua)
            }
        }
    }
    
    func authenticateWithBiometrics(reason: String, completion: @escaping (Bool, Error?) -> Void) {
        guard biometricsEnabled && biometricsAvailable else {
            completion(false, nil)
            return
        }
        
        let context = LAContext()
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
            DispatchQueue.main.async {
                completion(success, error)
            }
        }
    }
    
    func resetToDefaults() {
        appearanceMode = .dark
        biometricsEnabled = false
        showDeviceIcons = true
        defaultItemsPerPage = 25
        autoRefreshInterval = 0
    }
}
