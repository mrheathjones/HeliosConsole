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
    
    private enum Keys {
        static let authToken = "com.helios.authToken"
        static let userEmail = "com.helios.userEmail"
        static let userName = "com.helios.userName"
        static let refreshToken = "com.helios.refreshToken"
        static let jamfCredentials = "com.helios.jamfCredentials"
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
    
    func saveUserEmail(_ email: String) -> Bool {
        return saveString(email, forKey: Keys.userEmail)
    }
    
    func loadUserEmail() -> String? {
        return loadString(forKey: Keys.userEmail)
    }
    
    func deleteUserEmail() -> Bool {
        return delete(key: Keys.userEmail)
    }
    
    func saveUserName(_ name: String) -> Bool {
        return saveString(name, forKey: Keys.userName)
    }
    
    func loadUserName() -> String? {
        return loadString(forKey: Keys.userName)
    }
    
    func deleteUserName() -> Bool {
        return delete(key: Keys.userName)
    }
    
    func clearAllAuthData() {
        _ = deleteAuthToken()
        _ = deleteRefreshToken()
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
