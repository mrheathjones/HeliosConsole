//
//  ABMAPIService.swift
//  Helios
//
//  Apple Business Manager API Service
//  Handles authentication and AppleCare coverage lookups
//

import Foundation
import CryptoKit
import Combine

// MARK: - AppleCare Coverage Models

struct AppleCareCoverage: Codable, Identifiable {
    let id: String
    let status: String           // "ACTIVE" or "INACTIVE"
    let description: String      // "AppleCare+", "Limited Warranty", etc.
    let startDateTime: String?
    let endDateTime: String?
    let isRenewable: Bool?
    let isCanceled: Bool?
    let agreementNumber: String?
    let paymentType: String?
    
    var isActive: Bool {
        return status.uppercased() == "ACTIVE"
    }
    
    var startDate: Date? {
        guard let dateString = startDateTime else { return nil }
        return ISO8601DateFormatter().date(from: dateString)
    }
    
    var endDate: Date? {
        guard let dateString = endDateTime else { return nil }
        return ISO8601DateFormatter().date(from: dateString)
    }
    
    var daysRemaining: Int? {
        guard let end = endDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: end).day
        return days
    }
    
    var isExpiringSoon: Bool {
        guard let days = daysRemaining else { return false }
        return days > 0 && days <= 90
    }
    
    var isExpired: Bool {
        guard let days = daysRemaining else { return false }
        return days < 0
    }
}

struct AppleCareCoverageResponse: Codable {
    let data: [AppleCareCoverageData]
    
    struct AppleCareCoverageData: Codable {
        let type: String
        let id: String
        let attributes: AppleCareCoverageAttributes
    }
    
    struct AppleCareCoverageAttributes: Codable {
        let status: String
        let description: String
        let startDateTime: String?
        let endDateTime: String?
        let isRenewable: Bool?
        let isCanceled: Bool?
        let agreementNumber: String?
        let paymentType: String?
        let contractCancelDateTime: String?
    }
    
    func toCoverages() -> [AppleCareCoverage] {
        return data.map { item in
            AppleCareCoverage(
                id: item.id,
                status: item.attributes.status,
                description: item.attributes.description,
                startDateTime: item.attributes.startDateTime,
                endDateTime: item.attributes.endDateTime,
                isRenewable: item.attributes.isRenewable,
                isCanceled: item.attributes.isCanceled,
                agreementNumber: item.attributes.agreementNumber,
                paymentType: item.attributes.paymentType
            )
        }
    }
}

// MARK: - ABM Device Model

struct ABMDevice: Codable, Identifiable {
    let id: String
    let serialNumber: String
    let model: String?
    let deviceFamily: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case attributes
    }
    
    enum AttributeKeys: String, CodingKey {
        case serialNumber
        case model
        case deviceFamily
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        
        let attributes = try container.nestedContainer(keyedBy: AttributeKeys.self, forKey: .attributes)
        serialNumber = try attributes.decode(String.self, forKey: .serialNumber)
        model = try attributes.decodeIfPresent(String.self, forKey: .model)
        deviceFamily = try attributes.decodeIfPresent(String.self, forKey: .deviceFamily)
    }
    
    init(id: String, serialNumber: String, model: String?, deviceFamily: String?) {
        self.id = id
        self.serialNumber = serialNumber
        self.model = model
        self.deviceFamily = deviceFamily
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
    }
}

struct ABMDeviceListResponse: Codable {
    let data: [ABMDeviceData]
    let links: ABMLinks?
    
    struct ABMDeviceData: Codable {
        let type: String
        let id: String
        let attributes: ABMDeviceAttributes
    }
    
    struct ABMDeviceAttributes: Codable {
        let serialNumber: String
        let model: String?
        let deviceFamily: String?
    }
    
    struct ABMLinks: Codable {
        let next: String?
        let `self`: String?
    }
    
    func toDevices() -> [ABMDevice] {
        return data.map { item in
            ABMDevice(
                id: item.id,
                serialNumber: item.attributes.serialNumber,
                model: item.attributes.model,
                deviceFamily: item.attributes.deviceFamily
            )
        }
    }
}

// MARK: - ABM API Service

class ABMAPIService: ObservableObject {
    static let shared = ABMAPIService()
    
    private let baseURL = "https://api-business.apple.com/v1"
    private let tokenURL = "https://account.apple.com/auth/oauth2/token"
    
    @Published var isConfigured: Bool = false
    @Published var isAuthenticated: Bool = false
    @Published var lastError: String?
    
    // Cache
    private var accessToken: String?
    private var tokenExpiry: Date?
    private var coverageCache: [String: [AppleCareCoverage]] = [:]  // serialNumber -> coverages
    
    private init() {
        checkConfiguration()
    }
    
    private func log(_ message: String) {
        NSLog("ABM: \(message)")
    }
    
    // MARK: - Configuration Check
    
    func checkConfiguration() {
        let config = MDMConfigurationManager.shared.configuration
        isConfigured = config.isABMConfigured
        
        if isConfigured {
            NSLog("✅ ABM API is configured")
        } else {
            NSLog("⚠️ ABM API is not configured - AppleCare lookups disabled")
        }
    }
    
    // MARK: - JWT Generation
    
    private func generateJWT() throws -> String {
        let config = MDMConfigurationManager.shared.configuration
        
        guard let clientId = config.abmClientId,
              let keyId = config.abmKeyId,
              let privateKeyPEM = config.abmPrivateKey else {
            throw ABMError.notConfigured
        }
        
        // JWT Header
        let header: [String: Any] = [
            "alg": "ES256",
            "kid": keyId,
            "typ": "JWT"
        ]
        
        // JWT Payload
        let now = Date()
        let expiry = now.addingTimeInterval(3600 * 24 * 180)  // 180 days max
        
        let payload: [String: Any] = [
            "iss": clientId,
            "sub": clientId,
            "aud": "https://account.apple.com/auth/oauth2/v2/token",
            "iat": Int(now.timeIntervalSince1970),
            "exp": Int(expiry.timeIntervalSince1970),
            "jti": UUID().uuidString
        ]
        
        // Encode header and payload
        let headerData = try JSONSerialization.data(withJSONObject: header)
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        
        let headerBase64 = headerData.base64URLEncodedString()
        let payloadBase64 = payloadData.base64URLEncodedString()
        
        let signingInput = "\(headerBase64).\(payloadBase64)"
        
        // Sign with private key
        let signature = try signWithES256(data: signingInput.data(using: .utf8)!, privateKeyPEM: privateKeyPEM)
        let signatureBase64 = signature.base64URLEncodedString()
        
        return "\(signingInput).\(signatureBase64)"
    }
    
    private func signWithES256(data: Data, privateKeyPEM: String) throws -> Data {
        // Extract the base64 key data from PEM format
        let keyString = privateKeyPEM
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----BEGIN EC PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END EC PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        guard let keyData = Data(base64Encoded: keyString) else {
            NSLog("❌ ABM: Failed to decode base64 private key")
            throw ABMError.invalidPrivateKey
        }
        
        NSLog("📋 ABM: Private key data length: \(keyData.count) bytes")
        
        // Try different key formats
        var privateKey: P256.Signing.PrivateKey?
        
        // Try 1: PEM (SEC1 EC format) - this is what "BEGIN EC PRIVATE KEY" uses
        do {
            privateKey = try P256.Signing.PrivateKey(pemRepresentation: privateKeyPEM)
            NSLog("✅ ABM: Parsed key as PEM")
        } catch {
            NSLog("⚠️ ABM: PEM parsing failed: \(error.localizedDescription)")
        }
        
        // Try 2: PKCS#8 DER format
        if privateKey == nil {
            do {
                privateKey = try P256.Signing.PrivateKey(derRepresentation: keyData)
                NSLog("✅ ABM: Parsed key as PKCS#8 DER")
            } catch {
                NSLog("⚠️ ABM: PKCS#8 DER parsing failed: \(error.localizedDescription)")
            }
        }
        
        // Try 3: SEC1 DER format (EC PRIVATE KEY without PEM wrapper)
        if privateKey == nil {
            do {
                // For SEC1 format, the structure contains the raw key
                // Try to extract and use raw representation
                // SEC1 EC private key for P-256 is typically 121 bytes
                // The 32-byte private key scalar starts at offset 7
                if keyData.count >= 39 {  // Minimum size for SEC1 P-256
                    let rawKey = keyData.subdata(in: 7..<39)
                    privateKey = try P256.Signing.PrivateKey(rawRepresentation: rawKey)
                    NSLog("✅ ABM: Parsed key as SEC1 (offset 7)")
                }
            } catch {
                NSLog("⚠️ ABM: SEC1 parsing failed: \(error.localizedDescription)")
            }
        }
        
        // Try 4: x963 representation
        if privateKey == nil {
            do {
                privateKey = try P256.Signing.PrivateKey(x963Representation: keyData)
                NSLog("✅ ABM: Parsed key as x963")
            } catch {
                NSLog("⚠️ ABM: x963 parsing failed: \(error.localizedDescription)")
            }
        }
        
        // Try 5: Raw representation (last 32 bytes)
        if privateKey == nil && keyData.count >= 32 {
            do {
                let rawKey = keyData.suffix(32)
                privateKey = try P256.Signing.PrivateKey(rawRepresentation: rawKey)
                NSLog("✅ ABM: Parsed key as raw (last 32 bytes)")
            } catch {
                NSLog("⚠️ ABM: Raw parsing failed: \(error.localizedDescription)")
            }
        }
        
        guard let key = privateKey else {
            NSLog("❌ ABM: Could not parse private key in any known format")
            throw ABMError.invalidPrivateKey
        }
        
        // Sign the data
        let signature = try key.signature(for: data)
        return signature.rawRepresentation
    }
    
    // MARK: - Token Exchange
    
    private func getAccessToken() async throws -> String {
        // Return cached token if valid
        if let token = accessToken, let expiry = tokenExpiry, expiry > Date() {
            return token
        }
        
        let config = MDMConfigurationManager.shared.configuration
        guard let clientId = config.abmClientId else {
            throw ABMError.notConfigured
        }
        
        let jwt = try generateJWT()
        
        guard let url = URL(string: tokenURL) else {
            throw ABMError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "grant_type": "client_credentials",
            "client_id": clientId,
            "client_assertion_type": "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
            "client_assertion": jwt,
            "scope": "business.api"
        ]
        
        let bodyString = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        NSLog("📤 ABM: Requesting access token...")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ABMError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            NSLog("❌ ABM: Token request failed (\(httpResponse.statusCode)): \(errorBody)")
            throw ABMError.authenticationFailed(errorBody)
        }
        
        struct TokenResponse: Codable {
            let access_token: String
            let token_type: String
            let expires_in: Int
        }
        
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        
        accessToken = tokenResponse.access_token
        tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in - 60))  // Refresh 1 min early
        isAuthenticated = true
        
        NSLog("✅ ABM: Access token obtained (expires in \(tokenResponse.expires_in)s)")
        
        return tokenResponse.access_token
    }
    
    // MARK: - AppleCare Coverage Lookup (Direct Serial Number)
    
    /// Gets AppleCare coverage directly using the serial number.
    /// The ABM API accepts serial numbers directly - no device lookup needed!
    func getAppleCareCoverage(forSerialNumber serialNumber: String) async throws -> [AppleCareCoverage] {
        // Check cache first
        if let cached = coverageCache[serialNumber] {
            log("Returning cached coverage for \(serialNumber)")
            return cached
        }
        
        guard isConfigured else {
            throw ABMError.notConfigured
        }
        
        log("Fetching AppleCare coverage for serial: \(serialNumber)")
        
        let token = try await getAccessToken()
        
        // Call AppleCare endpoint directly with serial number (no device lookup needed!)
        guard let url = URL(string: "\(baseURL)/orgDevices/\(serialNumber)/appleCareCoverage") else {
            throw ABMError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = NetworkTuning.connectionTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ABMError.invalidResponse
        }
        
        if httpResponse.statusCode == 404 {
            log("Device \(serialNumber) not found in ABM")
            throw ABMError.deviceNotFound(serialNumber)
        }
        
        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            log("AppleCare request failed (\(httpResponse.statusCode)): \(errorBody)")
            throw ABMError.requestFailed(httpResponse.statusCode, errorBody)
        }
        
        let coverageResponse = try JSONDecoder().decode(AppleCareCoverageResponse.self, from: data)
        let coverages = coverageResponse.toCoverages()
        
        // Cache the result
        coverageCache[serialNumber] = coverages
        
        log("Found \(coverages.count) coverage records for \(serialNumber)")
        return coverages
    }
    
    // MARK: - Batch Loading
    
    func preloadCoverageForDevices(serialNumbers: [String]) async {
        guard isConfigured else {
            NSLog("⚠️ ABM: Skipping coverage preload - not configured")
            return
        }
        
        NSLog("📤 ABM: Preloading coverage for \(serialNumbers.count) devices...")
        
        var successCount = 0
        var errorCount = 0
        
        for serialNumber in serialNumbers {
            do {
                _ = try await getAppleCareCoverage(forSerialNumber: serialNumber)
                successCount += 1
            } catch {
                errorCount += 1
                // Don't log individual errors during batch load
            }
            
            // Small delay to avoid rate limiting
            try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
        }
        
        NSLog("✅ ABM: Preload complete - \(successCount) succeeded, \(errorCount) failed")
    }
    
    // MARK: - Cache Management
    
    func clearCache() {
        coverageCache.removeAll()
        log("Coverage cache cleared")
    }
    
    func getCachedCoverage(forSerialNumber serialNumber: String) -> [AppleCareCoverage]? {
        return coverageCache[serialNumber]
    }
}

// MARK: - ABM Errors

enum ABMError: LocalizedError {
    case notConfigured
    case invalidPrivateKey
    case signatureFailed(String)
    case invalidURL
    case invalidResponse
    case authenticationFailed(String)
    case requestFailed(Int, String)
    case deviceNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Apple Business Manager API is not configured"
        case .invalidPrivateKey:
            return "Invalid ABM private key format"
        case .signatureFailed(let reason):
            return "Failed to sign JWT: \(reason)"
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from ABM API"
        case .authenticationFailed(let reason):
            return "ABM authentication failed: \(reason)"
        case .requestFailed(let code, let message):
            return "ABM request failed (\(code)): \(message)"
        case .deviceNotFound(let serial):
            return "Device not found in ABM: \(serial)"
        }
    }
}

// MARK: - Data Extensions

extension Data {
    func base64URLEncodedString() -> String {
        return self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
