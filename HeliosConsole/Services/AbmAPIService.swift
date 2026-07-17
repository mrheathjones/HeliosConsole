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
        
        var request = URLRequest(url: url)
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
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
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
    private static let maxPages = 200

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
        var refreshedToken = false

        while true {
            let token = try await getAccessToken()

            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = timeout
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let body {
                request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }

            let (data, response) = try await URLSession.shared.data(for: request)
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
        for server in servers {
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

    /// The per-device CSV log Apple publishes for completed activities —
    /// the only error detail available when subStatus is COMPLETED_WITH_ERROR.
    /// The URL is presigned; sending Authorization would break it.
    func fetchActivityLog(downloadUrl: String) async throws -> String {
        guard let url = URL(string: downloadUrl), url.scheme?.lowercased() == "https" else {
            throw ABMError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = NetworkTuning.requestTimeout

        let (data, response) = try await URLSession.shared.data(for: request)
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

/// Session-scoped, in-memory cache of the org's ABM inventory: the device
/// sweep, the MDM server list, and the deviceId → mdmServerId assignment
/// map. Deliberately does NOT persist to disk: cached data is only valid
/// within the session that fetched it, so a disk copy could never be
/// legitimately reloaded — it would always belong to a previous launch.
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

    // MARK: - Public Methods

    var hasCachedData: Bool {
        isCacheValid && !devices.isEmpty
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
        NSLog("🗑️ ABMDeviceCache: Cache cleared")
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
