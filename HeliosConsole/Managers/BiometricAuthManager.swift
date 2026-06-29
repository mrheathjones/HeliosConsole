//
//  BiometricAuthManager.swift
//  test
//
//  Created by heath on 1/19/26.
//


import SwiftUI
import LocalAuthentication
import Combine

class BiometricAuthManager: ObservableObject {
    @Published var isBiometricEnabled = false
    @Published var biometricType: BiometricType = .none
    
    enum BiometricType {
        case none
        case touchID
        case faceID
        case opticID
        
        var displayName: String {
            switch self {
            case .none: return "None"
            case .touchID: return "Touch ID"
            case .faceID: return "Face ID"
            case .opticID: return "Optic ID"
            }
        }
        
        var icon: String {
            switch self {
            case .none: return "lock.fill"
            case .touchID: return "touchid"
            case .faceID: return "faceid"
            case .opticID: return "opticid"
            }
        }
    }
    
    private let context = LAContext()
    private let biometricEnabledKey = "biometricAuthEnabled"
    
    init() {
        checkBiometricAvailability()
        loadBiometricPreference()
    }
    
    func checkBiometricAvailability() {
        var error: NSError?
        
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            biometricType = .none
            return
        }
        
        switch context.biometryType {
        case .none:
            biometricType = .none
        case .touchID:
            biometricType = .touchID
        case .faceID:
            biometricType = .faceID
        case .opticID:
            biometricType = .opticID
        @unknown default:
            biometricType = .none
        }
    }
    
    func authenticate(reason: String = "Authenticate to access your account", completion: @escaping (Bool, Error?) -> Void) {
        let context = LAContext()
        var error: NSError?
        
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            completion(false, error)
            return
        }
        
        context.localizedFallbackTitle = "Use Password"
        context.localizedCancelTitle = "Cancel"
        
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, authError in
            DispatchQueue.main.async {
                completion(success, authError)
            }
        }
    }
    
    func setBiometricEnabled(_ enabled: Bool) {
        isBiometricEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: biometricEnabledKey)
    }
    
    func loadBiometricPreference() {
        isBiometricEnabled = UserDefaults.standard.bool(forKey: biometricEnabledKey)
    }
    
    func getErrorDescription(_ error: Error) -> String {
        guard let laError = error as? LAError else {
            return error.localizedDescription
        }
        
        switch laError.code {
        case .authenticationFailed:
            return "Authentication failed. Please try again."
        case .userCancel:
            return "Authentication was cancelled."
        case .userFallback:
            return "User chose to enter password."
        case .systemCancel:
            return "Authentication was cancelled by the system."
        case .passcodeNotSet:
            return "Passcode is not set on the device."
        case .biometryNotAvailable:
            return "Biometric authentication is not available."
        case .biometryNotEnrolled:
            return "No biometric data is enrolled."
        case .biometryLockout:
            return "Biometric authentication is locked. Please try again later."
        default:
            return "Authentication error: \(laError.localizedDescription)"
        }
    }
}
