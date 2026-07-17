//
//  ComputerInventoryService.swift
//  Helios
//
//  Service for fetching computer inventory list from Jamf Pro API v3
//

import Foundation
import Combine

// MARK: - Computer Inventory Error

enum ComputerInventoryError: LocalizedError {
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

// MARK: - Computer Inventory Service

@MainActor
final class ComputerInventoryService: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var computers: [ComputerInventoryItem] = []
    @Published var totalCount: Int = 0
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    // Master API credentials are used from MDMConfigurationManager
    private let cache = ComputerInventoryCache.shared
    private var cachedBearerToken: String?
    private var tokenExpiration: Date?
    
    private var configuration: MDMConfiguration {
        MDMConfigurationManager.shared.configuration
    }
    
    private var jamfURL: String {
        configuration.jamfURL
    }
    
    // MARK: - Public Methods
    
    /// Fetch all computers - uses cache if available, otherwise fetches from API
    /// - Parameters:
    ///   - forceRefresh: If true, ignores cache and fetches fresh data
    ///   - sortField: Field to sort by (e.g., "general.name")
    ///   - sortOrder: Sort order ("asc" or "desc")
    func fetchAllComputers(
        forceRefresh: Bool = false,
        sortField: String = "general.name",
        sortOrder: String = "asc"
    ) async {
        // Check cache first (unless force refresh)
        if !forceRefresh && cache.hasCachedData {
            NSLog("📦 ComputerInventoryService: Using cached data (%d computers)", cache.computers.count)
            computers = cache.computers
            totalCount = cache.totalCount
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let token = try await getBearerToken()
            var allComputers: [ComputerInventoryItem] = []
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
                
                allComputers.append(contentsOf: response.results)
                totalCount = response.totalCount
                
                NSLog("📥 ComputerInventoryService: Fetched page %d (%d items, total: %d)",
                      page, response.results.count, response.totalCount)
                
                if allComputers.count >= response.totalCount {
                    hasMore = false
                } else {
                    page += 1
                }
                
                // Safety limit to prevent infinite loops
                if page > 100 {
                    NSLog("⚠️ ComputerInventoryService: Reached safety limit of 100 pages")
                    hasMore = false
                }
            }
            
            computers = allComputers
            
            // Update cache
            cache.updateCache(computers: allComputers, totalCount: totalCount)
            
            NSLog("✅ ComputerInventoryService: Fetched all %d computers", computers.count)
            
        } catch let error as ComputerInventoryError {
            errorMessage = error.errorDescription
            NSLog("❌ ComputerInventoryService: %@", errorMessage ?? "Unknown error")
        } catch {
            errorMessage = "An unexpected error occurred: \(error.localizedDescription)"
            NSLog("❌ ComputerInventoryService: %@", errorMessage ?? "Unknown error")
        }
        
        isLoading = false
    }
    
    /// Fetch computers with pagination (single page)
    /// - Parameters:
    ///   - page: Page number (0-indexed)
    ///   - pageSize: Number of items per page
    ///   - sortField: Field to sort by (e.g., "general.name")
    ///   - sortOrder: Sort order ("asc" or "desc")
    func fetchComputers(
        page: Int = 0,
        pageSize: Int = 100,
        sortField: String = "general.name",
        sortOrder: String = "asc"
    ) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let token = try await getBearerToken()
            let response = try await performFetch(
                page: page,
                pageSize: pageSize,
                sortField: sortField,
                sortOrder: sortOrder,
                bearerToken: token
            )
            
            computers = response.results
            totalCount = response.totalCount
            
            NSLog("✅ ComputerInventoryService: Fetched %d computers (total: %d)", computers.count, totalCount)
            
        } catch let error as ComputerInventoryError {
            errorMessage = error.errorDescription
            NSLog("❌ ComputerInventoryService: %@", errorMessage ?? "Unknown error")
        } catch {
            errorMessage = "An unexpected error occurred: \(error.localizedDescription)"
            NSLog("❌ ComputerInventoryService: %@", errorMessage ?? "Unknown error")
        }
        
        isLoading = false
    }
    
    /// Clear the cache and force next fetch to get fresh data
    func refreshCache() {
        cache.invalidateCache()
    }
    
    // MARK: - Private Methods
    
    /// Get bearer token using master API credentials from MDM configuration
    private func getBearerToken() async throws -> String {
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
            throw ComputerInventoryError.invalidURL
        }
        
        NSLog("🔐 ComputerInventoryService: Getting bearer token using master API client")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = NetworkTuning.connectionTimeout
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
        
        let bodyString = "grant_type=client_credentials&client_id=\(masterClientID)&client_secret=\(masterClientSecret)"
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ComputerInventoryError.networkError(URLError(.badServerResponse))
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ComputerInventoryError.httpError(statusCode: httpResponse.statusCode, message: message)
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
        
        NSLog("✅ ComputerInventoryService: Got bearer token using master API")
        return tokenResponse.access_token
    }
    
    /// Perform the API fetch request
    private func performFetch(
        page: Int,
        pageSize: Int,
        sortField: String,
        sortOrder: String,
        bearerToken: String
    ) async throws -> ComputerInventoryResponse {
        // Build URL with query parameters
        // Try v1 API first: /api/v1/computers-inventory (more widely supported)
        let sortParam = "\(sortField):\(sortOrder)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "\(sortField):\(sortOrder)"
        
        let endpoint = "/api/v1/computers-inventory"
        // Sections come from features.computers.inventorySections, validated
        // against the values /api/v1/computers-inventory accepts (an invalid
        // one 400s the whole request). Falls back to the default list.
        let sectionNames = (MDMConfigurationManager.shared.configuration
            .features?.effectiveComputers ?? .empty).validatedInventorySections
        let sections = sectionNames
            .map { "section=\($0)" }
            .joined(separator: "&")
        let queryParams = "\(sections)&page=\(page)&page-size=\(pageSize)&sort=\(sortParam)"
        
        guard let url = URL(string: "\(jamfURL)\(endpoint)?\(queryParams)") else {
            throw ComputerInventoryError.invalidURL
        }
        
        NSLog("📥 ComputerInventoryService: Fetching from %@", url.absoluteString)
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = NetworkTuning.connectionTimeout
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ComputerInventoryError.networkError(URLError(.badServerResponse))
        }
        
        NSLog("📥 ComputerInventoryService: Response status %d", httpResponse.statusCode)
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            NSLog("❌ ComputerInventoryService: HTTP error: %@", message)
            throw ComputerInventoryError.httpError(statusCode: httpResponse.statusCode, message: message)
        }
        
        do {
            let inventoryResponse = try JSONDecoder().decode(ComputerInventoryResponse.self, from: data)
            return inventoryResponse
        } catch {
            NSLog("❌ ComputerInventoryService: Decode error: %@", String(describing: error))
            throw ComputerInventoryError.decodingError(error)
        }
    }
}

// MARK: - API Response Models

/// Response from /api/v3/computers-inventory
struct ComputerInventoryResponse: Codable {
    let totalCount: Int
    let results: [ComputerInventoryItem]
}

/// Lightweight computer item from inventory listing
struct ComputerInventoryItem: Codable, Identifiable, Hashable {
    let id: String
    let udid: String?
    let general: ComputerInventoryGeneral?
    
    // These are null when only requesting GENERAL section
    let diskEncryption: ComputerInventoryDiskEncryption?
    let hardware: ComputerInventoryHardware?
    let operatingSystem: ComputerInventoryOS?
    let userAndLocation: ComputerInventoryUserLocation?
    let security: ComputerInventorySecurity?
    let applications: [ComputerInventoryApplication]?
    let softwareUpdates: [ComputerInventorySoftwareUpdate]?
    let purchasing: ComputerInventoryPurchasing?
    let groupMemberships: [ComputerInventoryGroupMembership]?

    // Convenience properties
    var name: String {
        general?.name ?? "Unknown"
    }
    
    var isManaged: Bool {
        general?.remoteManagement?.managed ?? false
    }
    
    var isSupervised: Bool {
        general?.supervised ?? false
    }
    
    var lastContactTime: Date? {
        guard let dateString = general?.lastContactTime else { return nil }
        
        // Try with fractional seconds first
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: dateString) {
            return date
        }
        
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: dateString) {
            return date
        }
        
        // Try reportDate as fallback
        if let reportDateString = general?.reportDate {
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: reportDateString) {
                return date
            }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: reportDateString)
        }
        
        return nil
    }
    
    var siteName: String? {
        general?.site?.name
    }
    
    /// Check if a specific app is installed (by name, case-insensitive)
    func hasAppInstalled(_ appName: String) -> Bool {
        guard let apps = applications else { return false }
        let lowercaseAppName = appName.lowercased()
        return apps.contains { app in
            guard let name = app.name else { return false }
            return name.lowercased().contains(lowercaseAppName)
        }
    }
}

struct ComputerInventoryGeneral: Codable, Hashable {
    let name: String?
    let lastIpAddress: String?
    let lastReportedIp: String?
    let lastReportedIpV4: String?
    let lastReportedIpV6: String?
    let jamfBinaryVersion: String?
    let platform: String?
    let barcode1: String?
    let barcode2: String?
    let assetTag: String?
    let remoteManagement: ComputerInventoryRemoteManagement?
    let supervised: Bool?
    let mdmCapable: ComputerInventoryMDMCapable?
    let reportDate: String?
    let lastContactTime: String?
    let lastCloudBackupDate: String?
    let lastEnrolledDate: String?
    let mdmProfileExpiration: String?
    let initialEntryDate: String?
    let distributionPoint: String?
    let site: ComputerInventorySite?
    let itunesStoreAccountActive: Bool?
    let enrolledViaAutomatedDeviceEnrollment: Bool?
    let userApprovedMdm: Bool?
    let enrollmentMethod: ComputerInventoryEnrollmentMethod?
    let declarativeDeviceManagementEnabled: Bool?
    let managementId: String?
    let lastLoggedInUsernameSelfService: String?
    let lastLoggedInUsernameSelfServiceTimestamp: String?
    let lastLoggedInUsernameBinary: String?
    let lastLoggedInUsernameBinaryTimestamp: String?
    let extensionAttributes: [ComputerInventoryExtensionAttribute]?
}

struct ComputerInventoryRemoteManagement: Codable, Hashable {
    let managed: Bool?
    let managementUsername: String?
}

struct ComputerInventoryMDMCapable: Codable, Hashable {
    let capable: Bool?
    let capableUsers: [String]?
    let userManagementInfo: [ComputerInventoryUserManagementInfo]?
}

struct ComputerInventoryUserManagementInfo: Codable, Hashable {
    let capableUser: String?
    let managementId: String?
}

struct ComputerInventorySite: Codable, Hashable {
    let id: String?
    let name: String?
}

struct ComputerInventoryGroupMembership: Codable, Hashable {
    let groupId: String?
    let groupName: String?
    let smartGroup: Bool?
}

struct ComputerInventoryEnrollmentMethod: Codable, Hashable {
    let id: String?
    let objectName: String?
    let objectType: String?
}

struct ComputerInventoryExtensionAttribute: Codable, Hashable {
    let definitionId: String?
    let name: String?
    let description: String?
    let values: [String]?
    let dataType: String?
    let options: [String]?
    let inputType: String?
    let enabled: Bool?
    let multiValue: Bool?
}

// Optional sections (null when not requested)
struct ComputerInventoryDiskEncryption: Codable, Hashable {
    let bootPartitionEncryptionDetails: ComputerBootPartitionEncryption?
    let individualRecoveryKeyValidityStatus: String?
    let institutionalRecoveryKeyPresent: Bool?
    let diskEncryptionConfigurationName: String?
    let fileVault2Enabled: Bool?
    let fileVault2EnabledUserNames: [String]?
    let fileVault2EligibilityMessage: String?
    
    /// Check if boot partition is encrypted (ENCRYPTED state)
    var isBootPartitionEncrypted: Bool {
        guard let state = bootPartitionEncryptionDetails?.partitionFileVault2State?.uppercased() else {
            return fileVault2Enabled ?? false
        }
        return state == "ENCRYPTED"
    }
}

struct ComputerBootPartitionEncryption: Codable, Hashable {
    let partitionName: String?
    let partitionFileVault2State: String?
    let partitionFileVault2Percent: Int?
}

struct ComputerInventoryHardware: Codable, Hashable {
    let make: String?
    let model: String?
    let modelIdentifier: String?
    let serialNumber: String?
    let processorType: String?
    let totalRamMegabytes: Int?
    let appleSilicon: Bool?
}

struct ComputerInventoryOS: Codable, Hashable {
    let name: String?
    let version: String?
    let build: String?
}

struct ComputerInventoryUserLocation: Codable, Hashable {
    let username: String?
    let realname: String?
    let email: String?
    let position: String?
    let department: String?
}

struct ComputerInventorySecurity: Codable, Hashable {
    let sipStatus: String?
    let gatekeeperStatus: String?
    let firewallEnabled: Bool?
    let xprotectVersion: String?
    let autoLoginDisabled: Bool?
    let remoteDesktopEnabled: Bool?
    let activationLockEnabled: Bool?
    let recoveryLockEnabled: Bool?
    let secureBootLevel: String?
    let externalBootLevel: String?
    let bootstrapTokenAllowed: Bool?
    let bootstrapTokenEscrowedStatus: String?
}

// MARK: - Application Model

struct ComputerInventoryApplication: Codable, Hashable {
    let name: String?
    let path: String?
    let version: String?
    let macAppStore: Bool?
    let sizeMegabytes: Int?
    let bundleId: String?
    let updateAvailable: Bool?
    let externalVersionId: String?
}

// MARK: - Software Update Model

struct ComputerInventorySoftwareUpdate: Codable, Hashable {
    let name: String?
    let version: String?
    let packageName: String?
}
// MARK: - Purchasing Model

struct ComputerInventoryPurchasing: Codable, Hashable {
    let purchased: Bool?
    let leased: Bool?
    let poNumber: String?
    let lifeExpectancy: Int?
    let purchasePrice: String?
    let purchasingAccount: String?
    let purchasingContact: String?
    let appleCareId: String?
    let vendor: String?
    let leaseDate: String?
    let poDate: String?
    let warrantyDate: String?
}

