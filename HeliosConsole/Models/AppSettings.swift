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

    /// The operator's locally chosen avatar, persisted as a small JPEG in
    /// Application Support. Purely cosmetic and local to this Mac — in the
    /// UI it takes precedence over the Entra directory photo, and it is
    /// never uploaded anywhere. Nil = fall back to the directory photo or
    /// the initials avatar.
    @Published var customProfilePicture: NSImage? {
        didSet {
            persistCustomProfilePicture()
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
        self.customProfilePicture = Self.loadCustomProfilePicture()
        
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
        // Reseed appearance from the ui domain's defaultColorScheme (same
        // rule as first launch) rather than forcing dark.
        switch MDMConfigurationManager.shared.configuration
            .userInterfaceExtras?.effectiveColorScheme ?? .system {
        case .light: appearanceMode = .light
        case .dark: appearanceMode = .dark
        case .system: appearanceMode = .system
        }
        biometricsEnabled = false
        showDeviceIcons = true
        defaultItemsPerPage = 25
        autoRefreshInterval = 0
        customProfilePicture = nil
    }

    // MARK: - Custom profile picture persistence

    private static var customProfilePictureURL: URL? {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }
        return base
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "HeliosConsole", isDirectory: true)
            .appendingPathComponent("ProfilePicture.jpg")
    }

    private static func loadCustomProfilePicture() -> NSImage? {
        guard let url = customProfilePictureURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return NSImage(data: data)
    }

    private func persistCustomProfilePicture() {
        guard let url = Self.customProfilePictureURL else { return }
        guard let image = customProfilePicture else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let data = Self.jpegData(for: image, maxPixels: 512) else {
            NSLog("⚠️ Could not encode the chosen profile picture — not saved")
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("⚠️ Could not save the profile picture: %@", error.localizedDescription)
        }
    }

    /// Downscale to at most `maxPixels` on the long edge and JPEG-encode —
    /// the avatar renders at ~80 pt, so storing a full camera image is waste.
    private static func jpegData(for image: NSImage, maxPixels: CGFloat) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let scale = min(1, maxPixels / max(width, height, 1))
        let pixelsWide = max(1, Int(width * scale))
        let pixelsHigh = max(1, Int(height * scale))

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = NSSize(width: pixelsWide, height: pixelsHigh)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
}
