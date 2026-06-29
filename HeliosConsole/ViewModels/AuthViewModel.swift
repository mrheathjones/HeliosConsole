//
//  AuthViewModel.swift
//  Helios
//
//  Authentication view model for managing user sessions
//

import SwiftUI
import Combine
import LocalAuthentication

class AuthViewModel: ObservableObject {
    @Published var isLoggedIn = false
    @Published var currentUser: User?
    @Published var hasSeenWelcome: Bool {
        didSet {
            UserDefaults.standard.set(hasSeenWelcome, forKey: "hasSeenWelcome")
        }
    }
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showBiometricPrompt = false
    
    private let keychain = KeychainManager.shared
    let biometricManager = BiometricAuthManager()
    
    init() {
        self.hasSeenWelcome = UserDefaults.standard.bool(forKey: "hasSeenWelcome")
        restoreSession()
    }
    
    private func restoreSession() {
        guard let authToken = keychain.loadAuthToken(),
              !authToken.isEmpty else {
            return
        }
        
        let email = keychain.loadUserEmail() ?? ""
        let name = keychain.loadUserName() ?? ""
        let refreshToken = keychain.loadRefreshToken()
        
        guard !email.isEmpty else {
            clearSession()
            return
        }
        
        if biometricManager.isBiometricEnabled && biometricManager.biometricType != .none {
            showBiometricPrompt = true
            self.currentUser = User(
                email: email,
                name: name,
                authToken: authToken,
                refreshToken: refreshToken
            )
        } else {
            self.currentUser = User(
                email: email,
                name: name,
                authToken: authToken,
                refreshToken: refreshToken
            )
            self.isLoggedIn = true
        }
    }
    
    func authenticateWithBiometrics(completion: ((Bool) -> Void)? = nil) {
        biometricManager.authenticate(reason: "Unlock Helios Console") { [weak self] success, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if success {
                    self.isLoggedIn = true
                    self.showBiometricPrompt = false
                    completion?(true)
                } else {
                    if let error = error {
                        self.errorMessage = self.biometricManager.getErrorDescription(error)
                    }
                    
                    if let laError = error as? LAError, laError.code == .userCancel {
                        self.clearSession()
                        self.currentUser = nil
                        self.showBiometricPrompt = false
                    }
                    
                    completion?(false)
                }
            }
        }
    }
    
    func login(email: String, password: String, completion: ((Bool) -> Void)? = nil) {
        isLoading = true
        errorMessage = nil
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            
            let mockAuthToken = self.generateMockToken()
            let mockRefreshToken = self.generateMockToken()
            
            let user = User(
                email: email,
                name: "Admin User",
                authToken: mockAuthToken,
                refreshToken: mockRefreshToken
            )
            
            let success = self.saveUserToKeychain(user)
            
            if success {
                self.currentUser = user
                self.hasSeenWelcome = true
                self.isLoggedIn = true
                self.isLoading = false
                
                completion?(true)
            } else {
                self.errorMessage = "Failed to save credentials securely"
                self.isLoading = false
                completion?(false)
            }
        }
    }
    
    func loginWithEmail(_ email: String, completion: ((Bool) -> Void)? = nil) {
        isLoading = true
        errorMessage = nil
        
        Task { @MainActor in
            do {
                // Authenticate with Jamf Pro API using the master credentials
                NSLog("🔐 Authenticating with Jamf Pro for: %@", email)
                
                let jamfCredentials = try await JamfAPIService.shared.authenticateWithEmail(email)
                
                NSLog("✅ Jamf credentials received")
                NSLog("   Client ID: %@...", String(jamfCredentials.clientID.prefix(12)))
                
                // Save Jamf credentials to Keychain for API calls
                let credentialsSaved = keychain.saveJamfCredentials(jamfCredentials)
                
                if !credentialsSaved {
                    NSLog("⚠️ Failed to save Jamf credentials to Keychain")
                }
                
                // Extract name from email or use default
                let name = email.components(separatedBy: "@").first?.capitalized ?? "User"
                
                // Create user object
                let user = User(
                    email: email,
                    name: name,
                    authToken: jamfCredentials.clientID,
                    refreshToken: nil
                )
                
                // Save user info to keychain
                let userSaved = saveUserToKeychain(user)
                
                if userSaved && credentialsSaved {
                    self.currentUser = user
                    self.hasSeenWelcome = true
                    self.isLoggedIn = true
                    self.isLoading = false
                    NSLog("✅ Login successful")
                    completion?(true)
                } else {
                    self.errorMessage = "Failed to save credentials securely"
                    self.isLoading = false
                    completion?(false)
                }
                
            } catch let error as JamfAPIError {
                NSLog("❌ Jamf API error: %@", error.localizedDescription)
                self.errorMessage = error.localizedDescription
                self.isLoading = false
                completion?(false)
                
            } catch {
                NSLog("❌ Login error: %@", error.localizedDescription)
                self.errorMessage = "Authentication failed: \(error.localizedDescription)"
                self.isLoading = false
                completion?(false)
            }
        }
    }
    
    func loginWithToken(email: String, name: String, authToken: String, refreshToken: String? = nil) {
        let user = User(
            email: email,
            name: name,
            authToken: authToken,
            refreshToken: refreshToken
        )
        
        let success = saveUserToKeychain(user)
        
        if success {
            self.currentUser = user
            self.hasSeenWelcome = true
            self.isLoggedIn = true
        } else {
            self.errorMessage = "Failed to save credentials securely"
        }
    }
    
    func logout() {
        currentUser = nil
        errorMessage = nil
        clearSession()
        isLoggedIn = false
        showBiometricPrompt = false
    }
    
    func enableBiometricAuth() {
        biometricManager.setBiometricEnabled(true)
    }
    
    func disableBiometricAuth() {
        biometricManager.setBiometricEnabled(false)
    }
    
    private func saveUserToKeychain(_ user: User) -> Bool {
        var allSuccess = true
        
        allSuccess = keychain.saveAuthToken(user.authToken) && allSuccess
        allSuccess = keychain.saveUserEmail(user.email) && allSuccess
        allSuccess = keychain.saveUserName(user.name) && allSuccess
        
        if let refreshToken = user.refreshToken {
            allSuccess = keychain.saveRefreshToken(refreshToken) && allSuccess
        }
        
        return allSuccess
    }
    
    func clearSession() {
        keychain.clearAllAuthData()
    }
    
    func markWelcomeAsSeen() {
        hasSeenWelcome = true
    }
    
    func resetApp() {
        hasSeenWelcome = false
        currentUser = nil
        isLoggedIn = false
        errorMessage = nil
        showBiometricPrompt = false
        clearSession()
        biometricManager.setBiometricEnabled(false)
        UserDefaults.standard.removeObject(forKey: "hasSeenWelcome")
    }
    
    private func generateMockToken() -> String {
        return UUID().uuidString + "." + UUID().uuidString
    }
}
