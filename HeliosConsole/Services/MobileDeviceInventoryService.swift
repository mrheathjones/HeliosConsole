//
//  MobileDeviceInventoryService.swift
//  Helios
//
//  Service for fetching mobile device inventory (iOS, iPadOS, visionOS) from Jamf Pro API v2
//  Uses /api/v2/mobile-devices/detail endpoint with GENERAL section for complete inventory data
//
//  Shared models used from MobileDeviceModels.swift:
//  - MobileDeviceSecurity, MobileDeviceLostModeLocation
//  - MobileDeviceNetwork
//  - MobileDevicePurchasing
//  - MobileDeviceApplication
//  - MobileDeviceCertificate
//  - MobileDeviceProvisioningProfile
//  - MobileDeviceEbook
//  - MobileDeviceServiceSubscription
//  - MobileDeviceExtensionAttribute
//  - MobileDeviceGroup
//

import Foundation
import Combine

// MARK: - Mobile Device Inventory Error

enum MobileDeviceInventoryError: LocalizedError {
    case invalidURL
    case noCredentials
    case networkError(Error)
    case decodingError(Error)
    case httpError(statusCode: Int, message: String)
    case notAuthenticated
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL configuration"
        case .noCredentials:
            return "No API credentials available. Please log in again."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        case .httpError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        case .notAuthenticated:
            return "Authentication required. Please log in."
        }
    }
}

// MARK: - Mobile Device Inventory Service

@MainActor
final class MobileDeviceInventoryService: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var devices: [MobileDeviceInventoryItem] = []
    @Published var totalCount: Int = 0
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    // Counts by platform
    @Published var iOSCount: Int = 0
    @Published var iPadOSCount: Int = 0
    @Published var visionOSCount: Int = 0
    
    // MARK: - Private Properties
    
    // Master API credentials are used from MDMConfigurationManager
    private let cache = MobileDeviceInventoryCache.shared
    private var cachedBearerToken: String?
    private var tokenExpiration: Date?
    
    private var configuration: MDMConfiguration {
        MDMConfigurationManager.shared.configuration
    }
    
    private var jamfURL: String {
        configuration.jamfURL
    }
    
    // MARK: - Public Methods
    
    /// Fetch all mobile devices - uses cache if available, otherwise fetches from API
    /// - Parameters:
    ///   - forceRefresh: If true, ignores cache and fetches fresh data
    ///   - sortField: Field to sort by (e.g., "displayName")
    ///   - sortOrder: Sort order ("asc" or "desc")
    func fetchAllDevices(
        forceRefresh: Bool = false,
        sortField: String = "displayName",
        sortOrder: String = "asc"
    ) async {
        // Check cache first (unless force refresh)
        if !forceRefresh && cache.hasCachedData {
            NSLog("📦 MobileDeviceInventoryService: Using cached data (%d devices)", cache.devices.count)
            devices = cache.devices
            totalCount = cache.totalCount
            updatePlatformCounts()
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let token = try await getBearerToken()
            var allDevices: [MobileDeviceInventoryItem] = []
            var page = 0
            let pageSize = 100
            var hasMore = true
            
            while hasMore {
                let response = try await performFetch(
                    page: page,
                    pageSize: pageSize,
                    sortField: sortField,
                    sortOrder: sortOrder,
                    bearerToken: token
                )
                
                allDevices.append(contentsOf: response.results)
                totalCount = response.totalCount
                
                NSLog("📥 MobileDeviceInventoryService: Fetched page %d (%d items, total: %d)",
                      page, response.results.count, response.totalCount)
                
                if allDevices.count >= response.totalCount {
                    hasMore = false
                } else {
                    page += 1
                }
                
                // Safety limit to prevent infinite loops
                if page > 100 {
                    NSLog("⚠️ MobileDeviceInventoryService: Reached safety limit of 100 pages")
                    hasMore = false
                }
            }
            
            devices = allDevices
            updatePlatformCounts()
            
            // Update cache
            cache.updateCache(devices: allDevices, totalCount: totalCount)
            
            NSLog("✅ MobileDeviceInventoryService: Fetched all %d mobile devices (iOS: %d, iPadOS: %d, visionOS: %d)",
                  devices.count, iOSCount, iPadOSCount, visionOSCount)
            
        } catch let error as MobileDeviceInventoryError {
            errorMessage = error.errorDescription
            NSLog("❌ MobileDeviceInventoryService: %@", errorMessage ?? "Unknown error")
        } catch {
            errorMessage = "An unexpected error occurred: \(error.localizedDescription)"
            NSLog("❌ MobileDeviceInventoryService: %@", errorMessage ?? "Unknown error")
        }
        
        isLoading = false
    }
    
    /// Get devices filtered by platform type
    func devices(for platform: PlatformType) -> [MobileDeviceInventoryItem] {
        switch platform {
        case .iOS:
            return devices.filter { $0.platformType == .iOS }
        case .iPadOS:
            return devices.filter { $0.platformType == .iPadOS }
        case .visionOS:
            return devices.filter { $0.platformType == .visionOS }
        default:
            return devices
        }
    }
    
    /// Clear the cache and force next fetch to get fresh data
    func refreshCache() {
        cache.invalidateCache()
    }
    
    // MARK: - Private Methods
    
    private func updatePlatformCounts() {
        iOSCount = devices.filter { $0.platformType == .iOS }.count
        iPadOSCount = devices.filter { $0.platformType == .iPadOS }.count
        visionOSCount = devices.filter { $0.platformType == .visionOS }.count
    }
    
    /// Get bearer token for inventory loads. Routed per the `inventory` scope
    /// (default master; per-user fail-closed when the profile asks).
    private func getBearerToken() async throws -> String {
        if MDMConfigurationManager.shared.configuration.credentialSource(for: .inventory) == .user {
            return try await JamfUserSession.shared.bearerToken()
        }

        // Check if we have a valid cached token
        if let token = cachedBearerToken,
           let expiration = tokenExpiration,
           expiration > Date().addingTimeInterval(60) {
            return token
        }

        // Get master API credentials from MDM configuration
        let config = MDMConfigurationManager.shared.configuration
        let masterClientID = config.masterClientID
        let masterClientSecret = config.masterClientSecret
        
        // Request new bearer token
        guard let url = URL(string: "\(jamfURL)/api/v1/oauth/token") else {
            throw MobileDeviceInventoryError.invalidURL
        }
        
        NSLog("🔐 MobileDeviceInventoryService: Getting bearer token using master API client")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = NetworkTuning.connectionTimeout
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
        
        let bodyString = "grant_type=client_credentials&client_id=\(masterClientID)&client_secret=\(masterClientSecret)"
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MobileDeviceInventoryError.networkError(URLError(.badServerResponse))
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw MobileDeviceInventoryError.httpError(statusCode: httpResponse.statusCode, message: message)
        }
        
        struct TokenResponse: Codable {
            let access_token: String
            let token_type: String?
            let scope: String?
            let expires_in: Int
        }
        
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        
        // Cache the token
        cachedBearerToken = tokenResponse.access_token
        tokenExpiration = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in))
        
        NSLog("✅ MobileDeviceInventoryService: Got bearer token using master API")
        return tokenResponse.access_token
    }
    
    /// Perform the API fetch request using the detail endpoint with multiple sections
    private func performFetch(
        page: Int,
        pageSize: Int,
        sortField: String,
        sortOrder: String,
        bearerToken: String
    ) async throws -> MobileDeviceInventoryResponse {
        // Build URL with query parameters
        // Using v2 API: /api/v2/mobile-devices/detail with multiple sections
        // This provides comprehensive inventory data including lastInventoryUpdateDate
        let sortParam = "\(sortField):\(sortOrder)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "\(sortField):\(sortOrder)"
        
        let endpoint = "/api/v2/mobile-devices/detail"

        // Sections come from features.mobileDevices.inventorySections,
        // validated against the values /api/v2/mobile-devices/detail
        // accepts. The mobile vocabulary differs from computers (PROFILES /
        // GROUPS, not CONFIGURATION_PROFILES / GROUP_MEMBERSHIPS); an
        // invalid section 400s the whole fetch. Falls back to the default.
        let sectionNames = (MDMConfigurationManager.shared.configuration
            .features?.effectiveMobileDevices ?? .empty).validatedInventorySections
        let sections = sectionNames
            .map { "section=\($0)" }
            .joined(separator: "&")
        
        let queryParams = "\(sections)&page=\(page)&page-size=\(pageSize)&sort=\(sortParam)"
        
        guard let url = URL(string: "\(jamfURL)\(endpoint)?\(queryParams)") else {
            throw MobileDeviceInventoryError.invalidURL
        }
        
        NSLog("📥 MobileDeviceInventoryService: Fetching from %@", url.absoluteString)
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = NetworkTuning.requestTimeout  // Longer timeout for detail endpoint
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MobileDeviceInventoryError.networkError(URLError(.badServerResponse))
        }
        
        NSLog("📥 MobileDeviceInventoryService: Response status %d", httpResponse.statusCode)
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            NSLog("❌ MobileDeviceInventoryService: HTTP error: %@", message)
            throw MobileDeviceInventoryError.httpError(statusCode: httpResponse.statusCode, message: message)
        }
        
        do {
            let inventoryResponse = try JSONDecoder().decode(MobileDeviceInventoryResponse.self, from: data)
            return inventoryResponse
        } catch let DecodingError.keyNotFound(key, context) {
            NSLog("❌ MobileDeviceInventoryService: Missing key '%@' at path: %@",
                  key.stringValue, context.codingPath.map { $0.stringValue }.joined(separator: "."))
            throw MobileDeviceInventoryError.decodingError(DecodingError.keyNotFound(key, context))
        } catch let DecodingError.typeMismatch(type, context) {
            NSLog("❌ MobileDeviceInventoryService: Type mismatch for %@ at path: %@",
                  String(describing: type), context.codingPath.map { $0.stringValue }.joined(separator: "."))
            throw MobileDeviceInventoryError.decodingError(DecodingError.typeMismatch(type, context))
        } catch let DecodingError.valueNotFound(type, context) {
            NSLog("❌ MobileDeviceInventoryService: Value not found for %@ at path: %@",
                  String(describing: type), context.codingPath.map { $0.stringValue }.joined(separator: "."))
            throw MobileDeviceInventoryError.decodingError(DecodingError.valueNotFound(type, context))
        } catch {
            NSLog("❌ MobileDeviceInventoryService: Decode error: %@", String(describing: error))
            // Log raw response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                NSLog("📥 MobileDeviceInventoryService: Raw response (first 1000 chars): %@",
                      String(responseString.prefix(1000)))
            }
            throw MobileDeviceInventoryError.decodingError(error)
        }
    }
}

// MARK: - API Response Models

/// Response from /api/v2/mobile-devices/detail
struct MobileDeviceInventoryResponse: Codable {
    let totalCount: Int
    let results: [MobileDeviceInventoryItem]
}

/// Mobile device item from inventory detail listing
/// Uses the /api/v2/mobile-devices/detail endpoint
struct MobileDeviceInventoryItem: Codable, Identifiable, Hashable {
    let mobileDeviceId: String
    let deviceType: String?  // "iOS", "tvOS", "visionOS"
    
    // Nested sections from API
    let general: MobileDeviceGeneral?
    let hardware: MobileDeviceHardware?
    let userAndLocation: MobileDeviceUserAndLocation?
    let security: MobileDeviceSecurity?
    let network: MobileDeviceNetwork?
    let purchasing: MobileDevicePurchasing?
    let applications: [MobileDeviceApplication]?
    let certificates: [MobileDeviceCertificate]?
    let profiles: [MobileDeviceProfile]?
    let groups: [MobileDeviceGroup]?
    let extensionAttributes: [MobileDeviceExtensionAttribute]?
    let ebooks: [MobileDeviceEbook]?
    let serviceSubscriptions: [MobileDeviceServiceSubscription]?
    let provisioningProfiles: [MobileDeviceProvisioningProfile]?
    let sharedUsers: [MobileDeviceSharedUser]?
    let userProfiles: [MobileDeviceUserProfile]?
    
    // Identifiable conformance
    var id: String { mobileDeviceId }
    
    // MARK: - Computed Properties
    
    /// Platform type based on deviceType and model
    var platformType: PlatformType {
        // Check deviceType first
        if let deviceType = deviceType?.lowercased() {
            switch deviceType {
            case "ios":
                // Check if it's an iPad based on model
                if let model = hardware?.model?.lowercased() {
                    if model.contains("ipad") {
                        return .iPadOS
                    }
                }
                if let modelId = hardware?.modelIdentifier?.lowercased() {
                    if modelId.contains("ipad") {
                        return .iPadOS
                    }
                }
                return .iOS
            case "ipados":
                return .iPadOS
            case "visionos":
                return .visionOS
            case "tvos":
                return .iOS // Group tvOS with iOS for now
            default:
                break
            }
        }
        
        // Fallback: check model identifier for Vision Pro
        if let modelId = hardware?.modelIdentifier?.lowercased() {
            if modelId.contains("realitydevice") {
                return .visionOS
            }
            if modelId.contains("ipad") {
                return .iPadOS
            }
        }
        
        return .iOS
    }
    
    /// Display name for the device
    var displayName: String? {
        general?.displayName
    }
    
    /// Device name (non-optional)
    var name: String? {
        general?.displayName
    }
    
    /// Friendly device name
    var deviceName: String {
        general?.displayName ?? "Unknown Device"
    }
    
    /// Serial number
    var serialNumber: String? {
        hardware?.serialNumber
    }
    
    /// Model name
    var model: String? {
        hardware?.model
    }
    
    /// Model identifier
    var modelIdentifier: String? {
        hardware?.modelIdentifier
    }
    
    /// Display model name
    var displayModel: String {
        hardware?.model ?? "Unknown Model"
    }
    
    /// OS Version
    var osVersion: String? {
        general?.osVersion
    }
    
    /// Assigned user from userAndLocation
    var username: String? {
        userAndLocation?.username
    }
    
    /// Assigned user display name
    var assignedUser: String? {
        if let realname = userAndLocation?.realName, !realname.isEmpty {
            return realname
        }
        return userAndLocation?.username
    }
    
    /// Check if device is managed
    var isManaged: Bool {
        general?.managed ?? false
    }
    
    /// Check if device is supervised
    var isSupervised: Bool {
        general?.supervised ?? false
    }
    
    /// Last inventory update date string
    var lastInventoryUpdateDate: String? {
        general?.lastInventoryUpdateDate
    }
    
    /// Parse lastInventoryUpdateDate to Date object
    var lastInventoryUpdate: Date? {
        guard let dateString = general?.lastInventoryUpdateDate else { return nil }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: dateString) {
            return date
        }
        
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString)
    }
    
    /// Parse lastEnrolledDate to Date object
    var lastEnrollment: Date? {
        guard let dateString = general?.lastEnrolledDate else { return nil }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: dateString) {
            return date
        }
        
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString)
    }
    
    /// WiFi MAC address
    var wifiMacAddress: String? {
        hardware?.wifiMacAddress
    }
    
    /// IP Address
    var ipAddress: String? {
        general?.ipAddress
    }
    
    /// Management ID
    var managementId: String? {
        general?.managementId
    }
}

// MARK: - General Section

struct MobileDeviceGeneral: Codable, Hashable {
    let udid: String?
    let displayName: String?
    let assetTag: String?
    let siteId: String?
    let lastInventoryUpdateDate: String?
    let osVersion: String?
    let osRapidSecurityResponse: String?
    let osBuild: String?
    let osSupplementalBuildVersion: String?
    let softwareUpdateDeviceId: String?
    let ipAddress: String?
    let managed: Bool?
    let supervised: Bool?
    let deviceOwnershipType: String?
    let enrollmentMethodPrestage: MobileDeviceEnrollmentPrestage?
    let enrollmentSessionTokenValid: Bool?
    let lastEnrolledDate: String?
    let mdmProfileExpirationDate: String?
    let timeZone: String?
    let declarativeDeviceManagementEnabled: Bool?
    let managementId: String?
    let extensionAttributes: [MobileDeviceExtensionAttribute]?
    let lastLoggedInUsernameSelfService: String?
    let lastLoggedInUsernameSelfServiceTimestamp: String?
    let sharedIpad: Bool?
    let diagnosticAndUsageReportingEnabled: Bool?
    let appAnalyticsEnabled: Bool?
    let residentUsers: Int?
    let quotaSize: Int?
    let temporarySessionOnly: Bool?
    let temporarySessionTimeout: Int?
    let userSessionTimeout: Int?
    let syncedToComputer: Int?
    let maximumSharediPadUsersStored: Int?
    let lastBackupDate: String?
    let deviceLocatorServiceEnabled: Bool?
    let doNotDisturbEnabled: Bool?
    let cloudBackupEnabled: Bool?
    let lastCloudBackupDate: String?
    let locationServicesForSelfServiceMobileEnabled: Bool?
    let itunesStoreAccountActive: Bool?
    let exchangeDeviceId: String?
    let tethered: Bool?
}

struct MobileDeviceEnrollmentPrestage: Codable, Hashable {
    let mobileDevicePrestageId: String?
    let profileName: String?
}

// MARK: - Hardware Section

struct MobileDeviceHardware: Codable, Hashable {
    let capacityMb: Int?
    let availableSpaceMb: Int?
    let usedSpacePercentage: Int?
    let batteryLevel: Int?
    let batteryHealth: String?
    let serialNumber: String?
    let wifiMacAddress: String?
    let bluetoothMacAddress: String?
    let modemFirmwareVersion: String?
    let model: String?
    let modelIdentifier: String?
    let modelNumber: String?
    let bluetoothLowEnergyCapable: Bool?
    let deviceId: String?
    let extensionAttributes: [MobileDeviceExtensionAttribute]?
}

// MARK: - User and Location Section

struct MobileDeviceUserAndLocation: Codable, Hashable {
    let username: String?
    let realName: String?
    let emailAddress: String?
    let position: String?
    let phoneNumber: String?
    let departmentId: String?
    let buildingId: String?
    let room: String?
    let building: String?
    let department: String?
    let extensionAttributes: [MobileDeviceExtensionAttribute]?
}

// MARK: - Security Section (defined in MobileDeviceModels.swift)

// MARK: - Network Section (defined in MobileDeviceModels.swift)

// MARK: - Purchasing Section (defined in MobileDeviceModels.swift)

// MARK: - Applications Section (defined in MobileDeviceModels.swift)

// MARK: - Certificates Section (defined in MobileDeviceModels.swift)

// MARK: - Profiles Section

struct MobileDeviceProfile: Codable, Hashable, Identifiable {
    let displayName: String?
    let version: String?
    let uuid: String?
    let identifier: String?
    let removable: Bool?
    let lastInstalled: String?
    
    var id: String {
        uuid ?? identifier ?? UUID().uuidString
    }
}

// MARK: - Shared Users Section

struct MobileDeviceSharedUser: Codable, Hashable, Identifiable {
    let managedAppleId: String?
    let currentUser: Bool?
    let dataQuota: Int?
    let dataUsed: Int?
    let dataSynced: Bool?
    let hasSecureToken: Bool?
    
    var id: String {
        managedAppleId ?? UUID().uuidString
    }
}

// MARK: - User Profiles Section

struct MobileDeviceUserProfile: Codable, Hashable, Identifiable {
    let displayName: String?
    let version: String?
    let uuid: String?
    let identifier: String?
    let removable: Bool?
    let lastInstalled: String?
    let organization: String?
    let signer: String?
    
    var id: String {
        uuid ?? identifier ?? UUID().uuidString
    }
}

// MARK: - Groups Section (defined in MobileDeviceModels.swift)

// MARK: - Extension Attributes Section (defined in MobileDeviceModels.swift)

// MARK: - Additional Sections (defined in MobileDeviceModels.swift)

