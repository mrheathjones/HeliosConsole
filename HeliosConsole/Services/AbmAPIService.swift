//
//  ABMAPIService.swift
//  Helios
//
//  Apple Business Manager API Service
//  Authentication (ES256 client-assertion OAuth), AppleCare coverage,
//  org-device inventory sweeps, MDM server list + device→server
//  assignment map, and assign/unassign device activities.
//
//  API notes that shape this file (Apple ABM/ASM API, api-business.apple.com):
//    • /v1/orgDevices has NO server-side filter — serial lookup is the
//      direct-id fast path (id == serialNumber is observed, not contracted)
//      with a full paged sweep as fallback.
//    • Device→server mapping comes from each server's relationships/devices
//      linkages (1000/page), never one call per device.
//    • orgDeviceActivities requires the mdmServer relationship for BOTH
//      ASSIGN_DEVICES and UNASSIGN_DEVICES.
//    • Rate limits are undocumented; every call retries 429 with backoff.
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

// MARK: - JSON:API Paging Plumbing

struct ABMPageLinks: Codable {
    let next: String?

    enum CodingKeys: String, CodingKey {
        case next
    }
}

struct ABMPagingMeta: Codable {
    struct Paging: Codable {
        let total: Int?
        let limit: Int?
    }
    let paging: Paging?
}

/// Generic JSON:API list envelope — `data` decodes per-resource.
struct ABMPagedResponse<Resource: Codable>: Codable {
    let data: [Resource]
    let links: ABMPageLinks?
    let meta: ABMPagingMeta?
}

/// Generic JSON:API single-resource envelope.
struct ABMSingleResponse<Resource: Codable>: Codable {
    let data: Resource
}

/// Bare JSON:API linkage — `{ "type": "orgDevices", "id": "…" }`.
struct ABMResourceLinkage: Codable {
    let type: String?
    let id: String
}

// MARK: - MDM Server Model

struct ABMMdmServer: Codable, Identifiable, Hashable {
    let id: String
    let serverName: String
    let serverType: String?
    let createdDateTime: String?
    let updatedDateTime: String?

    /// Wire shape: JSON:API resource with nested attributes.
    struct Item: Codable {
        let id: String
        let attributes: Attributes?

        struct Attributes: Codable {
            let serverName: String?
            let serverType: String?
            let createdDateTime: String?
            let updatedDateTime: String?
        }

        func toServer() -> ABMMdmServer {
            ABMMdmServer(
                id: id,
                serverName: attributes?.serverName ?? id,
                serverType: attributes?.serverType,
                createdDateTime: attributes?.createdDateTime,
                updatedDateTime: attributes?.updatedDateTime
            )
        }
    }
}

// MARK: - Device Type Filter

/// Product-family filter for the ABM Lookup list. `rawValue` is the token the
/// config profile carries (appleBusinessManager.defaultDeviceType) and the
/// matcher key. Membership is decided by ABMOrgDevice.productFamily so it
/// tracks whatever families ABM reports without a per-model table.
enum ABMDeviceType: String, CaseIterable, Identifiable, Codable {
    case all
    case mac
    case iphone
    case ipad
    case appletv
    case watch
    case vision

    var id: String { rawValue }

    /// Fail-safe parse for the config value — unrecognized/empty → .all.
    static func from(_ raw: String?) -> ABMDeviceType {
        let key = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return ABMDeviceType(rawValue: key) ?? .all
    }

    var title: String {
        switch self {
        case .all: return "All Types"
        case .mac: return "Mac"
        case .iphone: return "iPhone"
        case .ipad: return "iPad"
        case .appletv: return "Apple TV"
        case .watch: return "Apple Watch"
        case .vision: return "Apple Vision"
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .mac: return "laptopcomputer"
        case .iphone: return "iphone"
        case .ipad: return "ipad"
        case .appletv: return "appletv"
        case .watch: return "applewatch"
        case .vision: return "visionpro"
        }
    }

    /// The productFamily substrings that count as this type (lowercased).
    /// ABM reports e.g. "Mac", "iPhone", "iPad", "Apple TV", "Watch", "Vision".
    private var familyNeedles: [String] {
        switch self {
        case .all: return []
        case .mac: return ["mac"]
        case .iphone: return ["iphone"]
        case .ipad: return ["ipad"]
        case .appletv: return ["tv"]
        case .watch: return ["watch"]
        case .vision: return ["vision"]
        }
    }

    /// Whether a device's productFamily belongs to this type. `.all` matches
    /// everything; an unknown/nil family matches only `.all`.
    func matches(productFamily: String?) -> Bool {
        guard self != .all else { return true }
        let family = (productFamily ?? "").lowercased()
        return familyNeedles.contains { family.contains($0) }
    }
}

// MARK: - Org Device Model

struct ABMOrgDevice: Codable, Identifiable, Hashable {
    let id: String
    let serialNumber: String
    let deviceModel: String?
    let productFamily: String?
    let productType: String?
    let deviceCapacity: String?
    let color: String?
    let status: String?              // ASSIGNED | UNASSIGNED
    let addedToOrgDateTime: String?
    let updatedDateTime: String?
    let orderNumber: String?
    let orderDateTime: String?
    /// Populated only if the API inlines the assignedServer linkage
    /// (undocumented — do not rely on it; use the linkages endpoints).
    let assignedServerId: String?

    var isAssigned: Bool {
        status?.uppercased() == "ASSIGNED"
    }

    var addedToOrgDate: Date? { ABMDateParser.date(from: addedToOrgDateTime) }
    var updatedDate: Date? { ABMDateParser.date(from: updatedDateTime) }

    /// Wire shape: JSON:API resource with nested attributes/relationships.
    struct Item: Codable {
        let id: String
        let attributes: Attributes?
        let relationships: Relationships?

        struct Attributes: Codable {
            let serialNumber: String?
            let deviceModel: String?
            let productFamily: String?
            let productType: String?
            let deviceCapacity: String?
            let color: String?
            let status: String?
            let addedToOrgDateTime: String?
            let updatedDateTime: String?
            let orderNumber: String?
            let orderDateTime: String?
        }

        struct Relationships: Codable {
            let assignedServer: Relationship?

            struct Relationship: Codable {
                let data: ABMResourceLinkage?
            }
        }

        func toDevice() -> ABMOrgDevice {
            ABMOrgDevice(
                id: id,
                serialNumber: attributes?.serialNumber ?? id,
                deviceModel: attributes?.deviceModel,
                productFamily: attributes?.productFamily,
                productType: attributes?.productType,
                deviceCapacity: attributes?.deviceCapacity,
                color: attributes?.color,
                status: attributes?.status,
                addedToOrgDateTime: attributes?.addedToOrgDateTime,
                updatedDateTime: attributes?.updatedDateTime,
                orderNumber: attributes?.orderNumber,
                orderDateTime: attributes?.orderDateTime,
                assignedServerId: relationships?.assignedServer?.data?.id
            )
        }
    }
}

/// ABM timestamps arrive both with and without fractional seconds.
enum ABMDateParser {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()

    static func date(from string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return fractional.date(from: string) ?? plain.date(from: string)
    }
}

// MARK: - Device Activity Models (assign / unassign)

enum ABMActivityType: String, Codable {
    case assignDevices = "ASSIGN_DEVICES"
    case unassignDevices = "UNASSIGN_DEVICES"
}

struct ABMDeviceActivity: Codable, Identifiable {
    let id: String
    let rawStatus: String?
    let rawSubStatus: String?
    let createdDateTime: String?
    let completedDateTime: String?
    let downloadUrl: String?

    enum Status: String {
        case completed = "COMPLETED"
        case inProgress = "IN_PROGRESS"
        case stopped = "STOPPED"
        case failed = "FAILED"
        case unknown = "UNKNOWN"
    }

    enum SubStatus: String {
        case submitted = "SUBMITTED"
        case preProcessing = "PRE_PROCESSING"
        case pending = "PENDING"
        case processing = "PROCESSING"
        case postProcessing = "POST_PROCESSING"
        case stopping = "STOPPING"
        case completedWithSuccess = "COMPLETED_WITH_SUCCESS"
        case completedWithError = "COMPLETED_WITH_ERROR"
        case completedWithFailure = "COMPLETED_WITH_FAILURE"
        case completedPostProcessingFailed = "COMPLETED_POST_PROCESSING_FAILED"
        case unknown = "UNKNOWN"
    }

    var status: Status {
        guard let rawStatus else { return .unknown }
        return Status(rawValue: rawStatus.uppercased()) ?? .unknown
    }

    var subStatus: SubStatus {
        guard let rawSubStatus else { return .unknown }
        return SubStatus(rawValue: rawSubStatus.uppercased()) ?? .unknown
    }

    var isTerminal: Bool {
        switch status {
        case .completed, .failed, .stopped: return true
        case .inProgress, .unknown: return false
        }
    }

    var isFullSuccess: Bool {
        status == .completed && subStatus == .completedWithSuccess
    }

    /// Wire shape: JSON:API resource with nested attributes.
    struct Item: Codable {
        let id: String
        let attributes: Attributes?

        struct Attributes: Codable {
            let status: String?
            let subStatus: String?
            let createdDateTime: String?
            let completedDateTime: String?
            let downloadUrl: String?
        }

        func toActivity() -> ABMDeviceActivity {
            ABMDeviceActivity(
                id: id,
                rawStatus: attributes?.status,
                rawSubStatus: attributes?.subStatus,
                createdDateTime: attributes?.createdDateTime,
                completedDateTime: attributes?.completedDateTime,
                downloadUrl: attributes?.downloadUrl
            )
        }
    }
}

// MARK: - ABM API Service

class ABMAPIService: ObservableObject {
    static let shared = ABMAPIService()
    
    /// AxM API host — Apple Business Manager or Apple School Manager,
    /// selected by core appleBusinessManager.serviceType.
    private var baseURL: String {
        MDMConfigurationManager.shared.configuration.abmAPIBaseURL
    }
    private let tokenURL = "https://account.apple.com/auth/oauth2/token"

    /// Dedicated session for ALL ABM/AxM + auth traffic. Deliberately NOT
    /// URLSession.shared: its own connection pool, isolated from the rest of
    /// the app, so an ABM sweep's bursty large transfers don't poison (or get
    /// poisoned by) shared connections, plus a per-host connection cap and
    /// waits-for-connectivity. HTTP/3 is suppressed per-request (see
    /// makeRequest) rather than here — there is no session-level toggle.
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()

    /// Builds a request with HTTP/3 suppressed. Enterprise SSL-inspection
    /// proxies (Zscaler/Netskope/…) and flaky links mangle QUIC/HTTP3 far more
    /// than HTTP/2-over-TCP; opting out keeps ABM on h2 like the curl path that
    /// works. (Apple still requires these endpoints bypass TLS inspection
    /// entirely — this reduces, not eliminates, proxy-induced failures.)
    private func makeRequest(url: URL, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.assumesHTTP3Capable = false
        return request
    }

    @Published var isConfigured: Bool = false
    @Published var isAuthenticated: Bool = false
    @Published var lastError: String?
    
    // Cache — token state is only touched under tokenLock: the device
    // sweeps run many overlapping requests, so unsynchronized reads/writes
    // here are a real race, not a theoretical one.
    private let tokenLock = NSLock()
    private var accessToken: String?
    private var tokenExpiry: Date?
    private var tokenExchangeTask: Task<String, Error>?
    private var coverageCache: [String: [AppleCareCoverage]] = [:]  // serialNumber -> coverages
    
    private init() {
        checkConfiguration()
    }
    
    private func log(_ message: String) {
        // %@ keeps server-controlled bytes out of NSLog's format-string
        // position (bodies containing %n/%@ would otherwise read the va_list).
        NSLog("ABM: %@", message)
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
    
    /// Concurrent callers share one in-flight exchange instead of racing
    /// the cached state or firing duplicate token requests. The lock is
    /// never held across an await.
    private func getAccessToken() async throws -> String {
        let exchange: Task<String, Error>

        tokenLock.lock()
        if let token = accessToken, let expiry = tokenExpiry, expiry > Date() {
            tokenLock.unlock()
            return token
        }
        if let inFlight = tokenExchangeTask {
            exchange = inFlight
            tokenLock.unlock()
        } else {
            let task = Task { [self] in
                defer {
                    tokenLock.lock()
                    tokenExchangeTask = nil
                    tokenLock.unlock()
                }
                return try await performTokenExchange()
            }
            tokenExchangeTask = task
            exchange = task
            tokenLock.unlock()
        }

        return try await exchange.value
    }

    /// Drops the cached token so the next request re-authenticates.
    private func invalidateCachedToken() {
        tokenLock.lock()
        accessToken = nil
        tokenExpiry = nil
        tokenLock.unlock()
    }

    private func performTokenExchange() async throws -> String {
        let config = MDMConfigurationManager.shared.configuration
        guard let clientId = config.abmClientId else {
            throw ABMError.notConfigured
        }
        
        let jwt = try generateJWT()
        
        guard let url = URL(string: tokenURL) else {
            throw ABMError.invalidURL
        }
        
        var request = makeRequest(url: url, timeout: NetworkTuning.connectionTimeout)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type": "client_credentials",
            "client_id": clientId,
            "client_assertion_type": "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
            "client_assertion": jwt,
            "scope": MDMConfigurationManager.shared.configuration.abmOAuthScope
        ]
        
        let bodyString = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        NSLog("📤 ABM: Requesting access token...")

        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ABMError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            NSLog("❌ ABM: Token request failed (%d): %@", httpResponse.statusCode, errorBody)
            throw ABMError.authenticationFailed(errorBody)
        }
        
        struct TokenResponse: Codable {
            let access_token: String
            let token_type: String
            let expires_in: Int
        }
        
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

        tokenLock.lock()
        accessToken = tokenResponse.access_token
        tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in - 60))  // Refresh 1 min early
        tokenLock.unlock()

        Task { @MainActor in self.isAuthenticated = true }

        NSLog("✅ ABM: Access token obtained (expires in %d s)", tokenResponse.expires_in)

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

        guard let encoded = serialNumber.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw ABMError.invalidURL
        }

        // Routed through abmRequest so coverage lookups share the 429
        // backoff and 401 refresh — preloadCoverageForDevices' bursts are
        // the calls most likely to need them.
        guard let coverageResponse: AppleCareCoverageResponse = try await abmGetDecoded(
            "\(baseURL)/orgDevices/\(encoded)/appleCareCoverage"
        ) else {
            log("Device \(serialNumber) not found in ABM")
            throw ABMError.deviceNotFound(serialNumber)
        }
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
    
    // MARK: - Core Request (auth, 429 backoff, 401 refresh-once)

    /// Percent-encoded sparse-fieldset query fragment — brackets must be
    /// escaped explicitly; URLComponents' handling of them varies by OS.
    private func fieldsQuery(_ resource: String, _ fields: [String]) -> String {
        "fields%5B\(resource)%5D=\(fields.joined(separator: ","))"
    }

    private static let maxRateLimitRetries = 3
    private static let maxTransientRetries = 4
    private static let maxPages = 200

    /// Transport failures worth retrying: the request either never reached
    /// the server or was cut off before a complete response, so re-sending is
    /// safe for idempotent GETs. -1005 (networkConnectionLost) is the common
    /// one — a pooled keep-alive connection that an SSL-inspecting proxy (or
    /// Apple's edge, after a burst of large sweep requests) silently reset
    /// surfaces as "The network connection was lost." -1200 covers the TLS
    /// teardown a MITM proxy produces. A retry forces a fresh connection.
    /// Deliberately NOT retried on POST (assign/unassign): a lost connection
    /// can't prove Apple didn't already accept the activity, so a blind resend
    /// risks a double submission.
    private static let transientURLErrorCodes: Set<URLError.Code> = [
        .networkConnectionLost,     // -1005
        .timedOut,                  // -1001
        .cannotConnectToHost,       // -1004
        .cannotFindHost,            // -1003
        .dnsLookupFailed,           // -1006
        .secureConnectionFailed,    // -1200 (TLS teardown, e.g. inspection proxy)
    ]

    /// Every authenticated ABM API call funnels through here (the presigned
    /// activity-log download is the deliberate exception — it must not carry
    /// the bearer token). Retries 429 (honoring Retry-After, capped at 30 s)
    /// and retries a 401 once after dropping the cached token.
    private func abmRequest(
        urlString: String,
        method: String = "GET",
        body: Data? = nil,
        timeout: TimeInterval = NetworkTuning.connectionTimeout
    ) async throws -> (Data, HTTPURLResponse) {
        guard isConfigured else { throw ABMError.notConfigured }
        guard let url = URL(string: urlString) else { throw ABMError.invalidURL }

        var rateLimitRetries = 0
        var transientRetries = 0
        var refreshedToken = false

        while true {
            let token = try await getAccessToken()

            var request = makeRequest(url: url, timeout: timeout)
            request.httpMethod = method
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let body {
                request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch let urlError as URLError where
                method == "GET"
                && transientRetries < Self.maxTransientRetries
                && Self.transientURLErrorCodes.contains(urlError.code) {
                transientRetries += 1
                // Exponential base (1, 2, 4, 8 s, capped at 10) + up to 1 s of
                // jitter. When Apple's edge tarpits after a burst of large sweep
                // requests, recovery takes several seconds — the earlier sub-2 s
                // schedule burned every retry inside that window. This bridges it.
                let base = min(pow(2.0, Double(transientRetries - 1)), 10)
                let delay = base + Double.random(in: 0...1)
                log("Transient \(urlError.code) on \(url.path) — retry \(transientRetries)/\(Self.maxTransientRetries) in \(String(format: "%.1f", delay))s (\(urlError.localizedDescription))")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                continue
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ABMError.invalidResponse
            }

            if httpResponse.statusCode == 401, !refreshedToken {
                refreshedToken = true
                invalidateCachedToken()
                log("401 from \(url.path) — refreshing token and retrying once")
                continue
            }

            if httpResponse.statusCode == 429, rateLimitRetries < Self.maxRateLimitRetries {
                rateLimitRetries += 1
                // Only trust a finite, non-negative numeric Retry-After —
                // a negative/NaN value (proxies, middleboxes) would trap the
                // UInt64 conversion below. HTTP-date forms parse to nil and
                // fall back to exponential backoff.
                let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                    .flatMap { Double($0) }
                let base: Double
                if let retryAfter, retryAfter.isFinite, retryAfter >= 0 {
                    base = retryAfter
                } else {
                    base = pow(2.0, Double(rateLimitRetries - 1))
                }
                let delay = min(base, 30)
                log("429 from \(url.path) — retry \(rateLimitRetries)/\(Self.maxRateLimitRetries) in \(delay)s")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                continue
            }

            return (data, httpResponse)
        }
    }

    /// GET + decode, treating any non-200 as an error. 404 maps to nil so
    /// callers can distinguish "not found" from real failures.
    private func abmGetDecoded<T: Codable>(
        _ urlString: String,
        timeout: TimeInterval = NetworkTuning.connectionTimeout
    ) async throws -> T? {
        let (data, response) = try await abmRequest(urlString: urlString, timeout: timeout)

        if response.statusCode == 404 { return nil }
        guard response.statusCode == 200 else {
            let bodyText = String(data: data, encoding: .utf8) ?? "Unknown error"
            log("GET \(urlString) failed (\(response.statusCode)): \(bodyText)")
            throw ABMError.requestFailed(response.statusCode, bodyText)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Follows links.next until exhausted. Page cap guards against a
    /// links.next cycle ever looping forever.
    private func fetchAllPages<Item: Codable>(
        initialURL: String,
        as itemType: Item.Type
    ) async throws -> [Item] {
        var items: [Item] = []
        var nextURL: String? = initialURL
        var pageCount = 0

        while let urlString = nextURL {
            pageCount += 1
            if pageCount > Self.maxPages {
                log("⚠️ Aborting pagination after \(Self.maxPages) pages: \(initialURL)")
                throw ABMError.requestFailed(0, "Pagination exceeded \(Self.maxPages) pages")
            }

            guard let page: ABMPagedResponse<Item> = try await abmGetDecoded(
                urlString,
                timeout: NetworkTuning.requestTimeout
            ) else {
                throw ABMError.requestFailed(404, "Paged resource not found: \(urlString)")
            }

            items.append(contentsOf: page.data)
            nextURL = page.links?.next
        }
        return items
    }

    // MARK: - MDM Servers

    /// Sparse fieldset for org-device list sweeps — everything the ABM
    /// Lookup list renders, nothing more (pages carry up to 1000 devices).
    private static let orgDeviceListFields = [
        "serialNumber", "deviceModel", "productFamily", "productType",
        "deviceCapacity", "color", "status",
        "addedToOrgDateTime", "updatedDateTime",
        "orderNumber", "orderDateTime",
    ]

    func fetchMdmServers() async throws -> [ABMMdmServer] {
        let url = "\(baseURL)/mdmServers?limit=1000"
        let items = try await fetchAllPages(initialURL: url, as: ABMMdmServer.Item.self)
        let servers = items.map { $0.toServer() }
        log("Fetched \(servers.count) MDM server(s)")
        return servers
    }

    // MARK: - Org Devices

    /// Full paged sweep of the org's device inventory (1000/page).
    func fetchAllOrgDevices() async throws -> [ABMOrgDevice] {
        let url = "\(baseURL)/orgDevices?limit=1000&\(fieldsQuery("orgDevices", Self.orgDeviceListFields))"
        let items = try await fetchAllPages(initialURL: url, as: ABMOrgDevice.Item.self)
        let devices = items.map { $0.toDevice() }
        log("Fetched \(devices.count) org device(s)")
        return devices
    }

    /// Serial lookup. Fast path bets on the (undocumented but observed)
    /// orgDevice id == serialNumber equality; a miss falls back to the
    /// full paged sweep, so a tenant where the bet is wrong still works.
    func findOrgDevice(serialNumber: String) async throws -> ABMOrgDevice? {
        let serial = serialNumber
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !serial.isEmpty else { return nil }

        guard let encoded = serial.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw ABMError.invalidURL
        }

        if let single: ABMSingleResponse<ABMOrgDevice.Item> = try await abmGetDecoded(
            "\(baseURL)/orgDevices/\(encoded)"
        ) {
            log("Serial \(serial) resolved via direct lookup")
            return single.data.toDevice()
        }

        log("Serial \(serial) not found via direct lookup — falling back to full sweep")
        let all = try await fetchAllOrgDevices()
        return all.first { $0.serialNumber.uppercased() == serial }
    }

    /// The device's currently-assigned MDM server id (nil = unassigned).
    func fetchAssignedServerId(deviceId: String) async throws -> String? {
        guard let encoded = deviceId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw ABMError.invalidURL
        }

        struct LinkageResponse: Codable {
            let data: ABMResourceLinkage?
        }
        guard let response: LinkageResponse = try await abmGetDecoded(
            "\(baseURL)/orgDevices/\(encoded)/relationships/assignedServer"
        ) else {
            throw ABMError.deviceNotFound(deviceId)
        }
        return response.data?.id
    }

    /// Device ids assigned to one MDM server (paged linkages, ids only).
    func fetchDeviceIds(assignedToMdmServer serverId: String) async throws -> [String] {
        guard let encoded = serverId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw ABMError.invalidURL
        }
        let url = "\(baseURL)/mdmServers/\(encoded)/relationships/devices?limit=1000"
        let linkages = try await fetchAllPages(initialURL: url, as: ABMResourceLinkage.self)
        return linkages.map { $0.id }
    }

    /// deviceId → mdmServerId across the whole org. A handful of paged
    /// linkage calls instead of one relationships call per device.
    func buildAssignmentMap(servers: [ABMMdmServer]) async throws -> [String: String] {
        var map: [String: String] = [:]
        for (index, server) in servers.enumerated() {
            // Gentle pacing: each server's linkage sweep pulls large paged
            // responses back-to-back, and firing them with no gap is what
            // preceded Apple's edge dropping the reused connection mid-sweep.
            // A short breather between servers keeps the burst under that
            // threshold. Skipped before the first request.
            if index > 0 {
                try await Task.sleep(nanoseconds: 250_000_000)  // 250 ms
            }
            let deviceIds = try await fetchDeviceIds(assignedToMdmServer: server.id)
            for deviceId in deviceIds {
                if let existing = map[deviceId], existing != server.id {
                    log("⚠️ Device \(deviceId) appears in two server scopes: \(existing) and \(server.id)")
                }
                map[deviceId] = server.id
            }
        }
        log("Assignment map built: \(map.count) device(s) across \(servers.count) server(s)")
        return map
    }

    // MARK: - Device Activities (assign / unassign)

    /// Submits an assign/unassign activity. ABM requires the mdmServer
    /// relationship for BOTH types: the target server for ASSIGN_DEVICES,
    /// the device's current server for UNASSIGN_DEVICES.
    @discardableResult
    func submitDeviceActivity(
        _ type: ABMActivityType,
        deviceIds: [String],
        mdmServerId: String
    ) async throws -> ABMDeviceActivity {
        guard !deviceIds.isEmpty else {
            throw ABMError.requestFailed(0, "No device ids supplied for \(type.rawValue)")
        }

        struct ActivityRequest: Encodable {
            struct Body: Encodable {
                let type = "orgDeviceActivities"
                let attributes: Attributes
                let relationships: Relationships
            }
            struct Attributes: Encodable {
                let activityType: String
            }
            struct Relationships: Encodable {
                let mdmServer: SingleRelationship
                let devices: ManyRelationship
            }
            struct SingleRelationship: Encodable {
                let data: Linkage
            }
            struct ManyRelationship: Encodable {
                let data: [Linkage]
            }
            struct Linkage: Encodable {
                let type: String
                let id: String
            }
            let data: Body
        }

        let payload = ActivityRequest(data: .init(
            attributes: .init(activityType: type.rawValue),
            relationships: .init(
                mdmServer: .init(data: .init(type: "mdmServers", id: mdmServerId)),
                devices: .init(data: deviceIds.map { .init(type: "orgDevices", id: $0) })
            )
        ))

        let body = try JSONEncoder().encode(payload)
        log("Submitting \(type.rawValue) for \(deviceIds.count) device(s) → server \(mdmServerId)")

        let (data, response) = try await abmRequest(
            urlString: "\(baseURL)/orgDeviceActivities",
            method: "POST",
            body: body
        )

        guard response.statusCode == 201 || response.statusCode == 200 else {
            let bodyText = String(data: data, encoding: .utf8) ?? "Unknown error"
            log("\(type.rawValue) rejected (\(response.statusCode)): \(bodyText)")
            throw ABMError.requestFailed(response.statusCode, bodyText)
        }

        let created = try JSONDecoder().decode(
            ABMSingleResponse<ABMDeviceActivity.Item>.self, from: data
        ).data.toActivity()
        log("\(type.rawValue) accepted — activity \(created.id)")
        return created
    }

    func fetchActivity(id: String) async throws -> ABMDeviceActivity {
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw ABMError.invalidURL
        }
        guard let response: ABMSingleResponse<ABMDeviceActivity.Item> = try await abmGetDecoded(
            "\(baseURL)/orgDeviceActivities/\(encoded)"
        ) else {
            throw ABMError.requestFailed(404, "Activity \(id) not found")
        }
        return response.data.toActivity()
    }

    /// Polls until the activity reaches a terminal status or attempts run
    /// out; a timeout returns the last non-terminal state (caller decides).
    func pollActivity(
        id: String,
        maxAttempts: Int = 10,
        interval: TimeInterval = 3
    ) async throws -> ABMDeviceActivity {
        let safeInterval = max(interval, 0)  // negative would trap the UInt64 conversion
        var last = try await fetchActivity(id: id)
        var attempt = 1

        while !last.isTerminal, attempt < maxAttempts {
            try await Task.sleep(nanoseconds: UInt64(safeInterval * 1_000_000_000))
            last = try await fetchActivity(id: id)
            attempt += 1
        }

        log("Activity \(id) after \(attempt) poll(s): \(last.rawStatus ?? "?") / \(last.rawSubStatus ?? "?")")
        return last
    }

    // MARK: - Assignment Orchestration (shared by DeviceView + ABM Lookup)

    /// The interpreted end state of an assign/unassign attempt — everything
    /// a UI needs to render a result without re-deriving activity semantics.
    enum ABMAssignmentOutcome {
        /// Terminal COMPLETED with a clean subStatus.
        case succeeded
        /// Terminal COMPLETED but Apple reported per-device errors; the
        /// associated string is the activity CSV log (or a fetch-failure
        /// note) for display.
        case completedWithErrors(detail: String)
        /// Terminal FAILED / STOPPED.
        case failed(status: String)
        /// Polling ran out while the activity was still in progress — the
        /// request was ACCEPTED and may still complete on Apple's side.
        case stillRunning(activityId: String)
    }

    /// Submits an assign/unassign for one device and polls to a terminal
    /// state. Throws only on submission failure — an accepted-but-unhappy
    /// activity is reported through the outcome, not an error, because at
    /// that point the change may be partially applied on Apple's side.
    func performAssignment(
        _ type: ABMActivityType,
        deviceId: String,
        mdmServerId: String
    ) async throws -> ABMAssignmentOutcome {
        let activity = try await submitDeviceActivity(type, deviceIds: [deviceId], mdmServerId: mdmServerId)
        let final = try await pollActivity(id: activity.id)

        switch final.status {
        case .completed:
            // Allowlist, not blocklist: only COMPLETED_WITH_SUCCESS counts
            // as success. A missing or newly-introduced subStatus must not
            // let callers update local state as if the change verified.
            if final.subStatus == .completedWithSuccess {
                return .succeeded
            }
            var detail = "Apple reported completion sub-status \(final.rawSubStatus ?? "unknown")."
            if let urlString = final.downloadUrl,
               let csv = try? await fetchActivityLog(downloadUrl: urlString) {
                detail = csv
            }
            return .completedWithErrors(detail: detail)
        case .failed, .stopped:
            return .failed(status: final.rawStatus ?? "FAILED")
        case .inProgress, .unknown:
            return .stillRunning(activityId: final.id)
        }
    }

    /// The per-device CSV log Apple publishes for completed activities —
    /// the only error detail available when subStatus is COMPLETED_WITH_ERROR.
    /// The URL is presigned; sending Authorization would break it.
    func fetchActivityLog(downloadUrl: String) async throws -> String {
        guard let url = URL(string: downloadUrl), url.scheme?.lowercased() == "https" else {
            throw ABMError.invalidURL
        }

        let request = makeRequest(url: url, timeout: NetworkTuning.requestTimeout)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ABMError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw ABMError.requestFailed(httpResponse.statusCode, "Activity log download failed")
        }
        guard let csv = String(data: data, encoding: .utf8) else {
            throw ABMError.invalidResponse
        }
        return csv
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

// MARK: - ABM Device Cache

/// Cache of the org's ABM inventory: the device sweep, the MDM server list,
/// and the deviceId → mdmServerId assignment map.
///
/// Persists to disk (Application Support) so a large org — tens of thousands
/// of devices — doesn't re-sweep on every launch. The disk copy is loaded at
/// the login screen and shown as-is; a network sweep runs ONLY when there is
/// no usable cache, or when the user hits Refresh. Because that means the UI
/// can show data from a previous launch (possibly days old), two guards keep
/// a stale copy from ever being wrong rather than merely old:
///   • schemaVersion — a model change invalidates every older file.
///   • orgFingerprint — a snapshot written for one ABM org/credential set is
///     discarded if the current config points at a different one.
/// The ABM Lookup header always renders lastFetchDate (date + time) so the
/// operator can see how old the shown inventory is.
@MainActor
final class ABMDeviceCache: ObservableObject {

    static let shared = ABMDeviceCache()

    // MARK: - Published Properties

    @Published private(set) var devices: [ABMOrgDevice] = []
    @Published private(set) var mdmServers: [ABMMdmServer] = []
    @Published private(set) var assignmentMap: [String: String] = [:]  // deviceId → mdmServerId
    @Published private(set) var lastFetchDate: Date?
    @Published private(set) var isCacheValid: Bool = false

    private init() {}

    // MARK: - Disk Persistence

    /// Bump when the persisted shape changes (any Codable field of the models
    /// below, or Snapshot itself) so older files are discarded, not misread.
    private static let cacheSchemaVersion = 1

    private struct Snapshot: Codable {
        let schemaVersion: Int
        let orgFingerprint: String
        let fetchedAt: Date
        let devices: [ABMOrgDevice]
        let mdmServers: [ABMMdmServer]
        let assignmentMap: [String: String]
    }

    private var cacheFileURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let bundleId = Bundle.main.bundleIdentifier ?? "com.herojoneslabs.helios.console"
        return dir
            .appendingPathComponent(bundleId, isDirectory: true)
            .appendingPathComponent("abm-inventory-cache.json")
    }

    /// Identifies the ABM org+endpoint a snapshot belongs to, so a cache from
    /// a different tenant/credential set is never shown. Hashed so the client
    /// id isn't written to the cache file in the clear.
    private func currentOrgFingerprint() -> String {
        let config = MDMConfigurationManager.shared.configuration
        let material = "\(config.abmClientId ?? "none")|\(config.abmAPIBaseURL)"
        return SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Loads the persisted snapshot into memory if one exists AND passes both
    /// guards (schema + org fingerprint). A file that fails either guard is
    /// deleted, not shown. Returns true when the cache was populated from disk.
    @discardableResult
    func loadFromDisk() -> Bool {
        guard let url = cacheFileURL, let data = try? Data(contentsOf: url) else { return false }

        guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.schemaVersion == Self.cacheSchemaVersion else {
            NSLog("ABM: Discarding disk cache (unreadable or old schema)")
            try? FileManager.default.removeItem(at: url)
            return false
        }

        guard snapshot.orgFingerprint == currentOrgFingerprint() else {
            NSLog("ABM: Discarding disk cache — ABM org/credentials changed since it was written")
            try? FileManager.default.removeItem(at: url)
            return false
        }

        devices = snapshot.devices
        mdmServers = snapshot.mdmServers
        assignmentMap = snapshot.assignmentMap
        lastFetchDate = snapshot.fetchedAt
        isCacheValid = true
        NSLog("ABM: Loaded inventory from disk cache — %d device(s), %d server(s)",
              snapshot.devices.count, snapshot.mdmServers.count)
        return true
    }

    /// Writes the current in-memory state to disk. Encode+write run off the
    /// main actor (a 26k-device snapshot is several MB); the models are value
    /// types, so the copy captured here is safe. Called after a completed
    /// network load and after a local assignment change.
    private func persistToDisk() {
        guard let url = cacheFileURL else { return }
        let snapshot = Snapshot(
            schemaVersion: Self.cacheSchemaVersion,
            orgFingerprint: currentOrgFingerprint(),
            fetchedAt: lastFetchDate ?? Date(),
            devices: devices,
            mdmServers: mdmServers,
            assignmentMap: assignmentMap
        )
        Task.detached(priority: .utility) {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: [.atomic])
                NSLog("ABM: Persisted inventory cache (%d device(s), %d bytes)", snapshot.devices.count, data.count)
            } catch {
                NSLog("ABM: Failed to persist inventory cache: %@", error.localizedDescription)
            }
        }
    }

    // MARK: - Public Methods

    var hasCachedData: Bool {
        isCacheValid && !devices.isEmpty
    }

    /// De-dupes overlapping sweeps: the background preload and a fast tab-open
    /// can both call loadFromNetwork() before either commits — they coalesce
    /// onto this one in-flight task instead of hitting the API twice.
    private var inFlightLoad: Task<Void, Error>?

    /// Full network sweep → one atomic cache update: MDM server list → org
    /// device sweep → deviceId→serverId assignment map. Shared by the ABM
    /// Lookup view's on-demand load and the post-login background preload, so
    /// both take the identical path (and the same transient-retry protection
    /// in ABMAPIService.abmRequest). Concurrent callers share a single
    /// in-flight sweep.
    ///
    /// Graceful degradation: the device list is the primary content; the
    /// server list and the assignment map are enrichment. The device sweep
    /// failing throws (there's nothing to show), but if the org devices came
    /// back and only the server-list or assignment-map legs fail — the exact
    /// case seen in the field, where Apple's edge dropped a connection during
    /// the map build after every device page had already arrived — the
    /// inventory is cached WITHOUT assignment tags rather than thrown away.
    /// The tab renders devices; server/assignment columns just show as
    /// unassigned until the next successful refresh.
    func loadFromNetwork() async throws {
        if let existing = inFlightLoad {
            try await existing.value
            return
        }
        let task = Task { () throws -> Void in
            let service = ABMAPIService.shared

            // Primary content — a failure here has nothing to fall back to.
            let devices = try await service.fetchAllOrgDevices()

            // Commit the device list IMMEDIATELY (unassigned), so a large org's
            // inventory renders as soon as the page sweep finishes instead of
            // blocking on the assignment map too. At ~26k devices the map is
            // many more requests; making the list wait on it is the bulk of the
            // perceived load time. isCacheValid flips true here, so the tab
            // stops spinning now and the enrichment fills in a moment later.
            updateCache(devices: devices, mdmServers: [], assignmentMap: [:])

            // Enrichment — server names + per-device assignment. On failure the
            // devices-only commit above stands (graceful degradation).
            do {
                let servers = try await service.fetchMdmServers()
                let assignmentMap = try await service.buildAssignmentMap(servers: servers)
                updateCache(devices: devices, mdmServers: servers, assignmentMap: assignmentMap)
            } catch {
                NSLog("ABM: Loaded %d device(s) but server/assignment enrichment failed — showing inventory without assignment info: %@",
                      devices.count, error.localizedDescription)
            }

            // Persist the final state (enriched, or devices-only if enrichment
            // failed) so the next launch loads instantly from disk.
            persistToDisk()
        }
        inFlightLoad = task
        defer { inFlightLoad = nil }
        try await task.value
    }

    /// Warm-up run at the login screen so the ABM Lookup tab opens populated.
    /// Cache-first: a valid disk snapshot is loaded and shown as-is — NO
    /// network sweep — because a large org shouldn't re-fetch every launch.
    /// Only when there's no usable cache on disk do we sweep once. After that,
    /// fresh data comes solely from the Refresh button. No-op if ABM isn't
    /// configured or the in-memory cache is already valid; silent on failure
    /// (the tab falls back to its own on-demand load).
    func preloadIfNeeded() async {
        let config = MDMConfigurationManager.shared.configuration
        NSLog("ABM: preloadIfNeeded — configured=%@ cacheValid=%@ defaults(server=%@, deviceType=%@)",
              ABMAPIService.shared.isConfigured ? "true" : "false",
              isCacheValid ? "true" : "false",
              config.abmDefaultMdmServerName ?? "nil",
              config.abmDefaultDeviceType ?? "nil")

        guard ABMAPIService.shared.isConfigured else {
            NSLog("ABM: preload skipped — ABM not configured")
            return
        }
        guard !isCacheValid else { return }  // already loaded this session

        if loadFromDisk() {
            NSLog("ABM: preload served from disk cache — no network fetch (use Refresh for fresh data)")
            return
        }

        NSLog("ABM: preload — no disk cache, starting network sweep")
        do {
            try await loadFromNetwork()
        } catch {
            NSLog("ABM: Background inventory preload failed (tab will load on demand): %@", error.localizedDescription)
        }
    }

    func updateCache(
        devices: [ABMOrgDevice],
        mdmServers: [ABMMdmServer],
        assignmentMap: [String: String]
    ) {
        self.devices = devices
        self.mdmServers = mdmServers
        self.assignmentMap = assignmentMap
        self.lastFetchDate = Date()
        self.isCacheValid = true

        NSLog("✅ ABMDeviceCache: Updated cache — %d devices, %d servers, %d assignments",
              devices.count, mdmServers.count, assignmentMap.count)
    }

    func clearCache() {
        devices = []
        mdmServers = []
        assignmentMap = [:]
        lastFetchDate = nil
        isCacheValid = false
        if let url = cacheFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        NSLog("🗑️ ABMDeviceCache: Cache cleared (memory + disk)")
    }

    func invalidateCache() {
        isCacheValid = false
        NSLog("⚠️ ABMDeviceCache: Cache invalidated")
    }

    // MARK: - Lookup Helpers

    func device(forSerial serial: String) -> ABMOrgDevice? {
        let normalized = serial.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return devices.first { $0.serialNumber.uppercased() == normalized }
    }

    func assignedServer(forDeviceId deviceId: String) -> ABMMdmServer? {
        guard let serverId = assignmentMap[deviceId] else { return nil }
        return mdmServers.first { $0.id == serverId }
    }

    /// Applies a locally-known assignment change (after a successful
    /// assign/unassign) so the list reflects reality without a full org
    /// re-sweep. Pass nil serverId for an unassignment.
    func applyAssignment(deviceId: String, serverId: String?) {
        if let serverId {
            assignmentMap[deviceId] = serverId
        } else {
            assignmentMap.removeValue(forKey: deviceId)
        }
        if let index = devices.firstIndex(where: { $0.id == deviceId }) {
            let d = devices[index]
            devices[index] = ABMOrgDevice(
                id: d.id,
                serialNumber: d.serialNumber,
                deviceModel: d.deviceModel,
                productFamily: d.productFamily,
                productType: d.productType,
                deviceCapacity: d.deviceCapacity,
                color: d.color,
                status: serverId == nil ? "UNASSIGNED" : "ASSIGNED",
                addedToOrgDateTime: d.addedToOrgDateTime,
                updatedDateTime: d.updatedDateTime,
                orderNumber: d.orderNumber,
                orderDateTime: d.orderDateTime,
                assignedServerId: serverId
            )
        }
        // Keep the disk cache consistent with the local assignment change so a
        // relaunch doesn't show the device back on its old server.
        persistToDisk()
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
