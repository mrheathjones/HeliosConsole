//
//  KeychainManager.swift
//  Helios
//
//  Secure keychain storage for authentication and credentials
//

import Foundation
import Security

class KeychainManager {
    static let shared = KeychainManager()
    
    private init() {}
    
    /// Keychain account names, rebranded 2026-07 from the old `com.helios.*`
    /// prefix to the `com.herojoneslabs.helios.console.*` root (same pattern as
    /// the Protect item, `com.herojoneslabs.helios.console.protect.password`).
    /// Items stored under the old names are orphaned, not migrated — users
    /// re-authenticate once after updating (see docs/ConfigProfileMigration.md
    /// §9); the uninstall script removes both spellings.
    private enum Keys {
        static let authToken = "com.herojoneslabs.helios.console.authToken"
        static let userEmail = "com.herojoneslabs.helios.console.userEmail"
        static let userName = "com.herojoneslabs.helios.console.userName"
        static let refreshToken = "com.herojoneslabs.helios.console.refreshToken"
        static let entraRefreshToken = "com.herojoneslabs.helios.console.entraRefreshToken"
        static let jamfCredentials = "com.herojoneslabs.helios.console.jamfCredentials"
    }
    
    @discardableResult
    func save(key: String, data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            return true
        } else {
            print("Keychain save failed with status: \(status)")
            return false
        }
    }
    
    func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        return status == errSecSuccess ? result as? Data : nil
    }
    
    @discardableResult
    func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    func saveString(_ string: String, forKey key: String) -> Bool {
        guard let data = string.data(using: .utf8) else { return false }
        return save(key: key, data: data)
    }
    
    func loadString(forKey key: String) -> String? {
        guard let data = load(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    func saveAuthToken(_ token: String) -> Bool {
        return saveString(token, forKey: Keys.authToken)
    }
    
    func loadAuthToken() -> String? {
        return loadString(forKey: Keys.authToken)
    }
    
    func deleteAuthToken() -> Bool {
        return delete(key: Keys.authToken)
    }
    
    func saveRefreshToken(_ token: String) -> Bool {
        return saveString(token, forKey: Keys.refreshToken)
    }
    
    func loadRefreshToken() -> String? {
        return loadString(forKey: Keys.refreshToken)
    }
    
    func deleteRefreshToken() -> Bool {
        return delete(key: Keys.refreshToken)
    }
    
    func saveEntraRefreshToken(_ token: String) -> Bool {
        return saveString(token, forKey: Keys.entraRefreshToken)
    }

    func loadEntraRefreshToken() -> String? {
        return loadString(forKey: Keys.entraRefreshToken)
    }

    func deleteEntraRefreshToken() -> Bool {
        return delete(key: Keys.entraRefreshToken)
    }

    // MARK: - User identity (non-secret → UserDefaults, not Keychain)
    //
    // The signed-in user's email and display name are shown all over the UI
    // and carry no security value. Storing them in the Keychain only bought
    // an extra "HeliosConsole wants to use your confidential information"
    // ACL prompt per item on every fresh/re-signed build — for data that is
    // not confidential. They now live in UserDefaults. The accessors below
    // keep the same names/signatures (call sites are unchanged) and migrate
    // any value left in the Keychain by an older build on first read, then
    // delete the orphaned Keychain item so the prompt stops for good.

    private var defaults: UserDefaults { .standard }

    @discardableResult
    func saveUserEmail(_ email: String) -> Bool {
        defaults.set(email, forKey: Keys.userEmail)
        _ = delete(key: Keys.userEmail)   // clear any legacy Keychain copy
        return true
    }

    func loadUserEmail() -> String? {
        if let email = defaults.string(forKey: Keys.userEmail) { return email }
        // One-time migration from a Keychain value written by an older build.
        if let legacy = loadString(forKey: Keys.userEmail) {
            defaults.set(legacy, forKey: Keys.userEmail)
            _ = delete(key: Keys.userEmail)
            return legacy
        }
        return nil
    }

    @discardableResult
    func deleteUserEmail() -> Bool {
        defaults.removeObject(forKey: Keys.userEmail)
        return delete(key: Keys.userEmail)
    }

    @discardableResult
    func saveUserName(_ name: String) -> Bool {
        defaults.set(name, forKey: Keys.userName)
        _ = delete(key: Keys.userName)
        return true
    }

    func loadUserName() -> String? {
        if let name = defaults.string(forKey: Keys.userName) { return name }
        if let legacy = loadString(forKey: Keys.userName) {
            defaults.set(legacy, forKey: Keys.userName)
            _ = delete(key: Keys.userName)
            return legacy
        }
        return nil
    }

    @discardableResult
    func deleteUserName() -> Bool {
        defaults.removeObject(forKey: Keys.userName)
        return delete(key: Keys.userName)
    }
    
    func clearAllAuthData() {
        _ = deleteAuthToken()
        _ = deleteRefreshToken()
        _ = deleteEntraRefreshToken()
        _ = deleteUserEmail()
        _ = deleteUserName()
    }
    
    // MARK: - Jamf Credentials
    func saveJamfCredentials(_ credentials: JamfCredentials) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        guard let data = try? encoder.encode(credentials) else {
            return false
        }
        
        return save(key: Keys.jamfCredentials, data: data)
    }
    
    func loadJamfCredentials() -> JamfCredentials? {
        guard let data = load(key: Keys.jamfCredentials) else {
            return nil
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try? decoder.decode(JamfCredentials.self, from: data)
    }
    
    func deleteJamfCredentials() -> Bool {
        return delete(key: Keys.jamfCredentials)
    }
}
