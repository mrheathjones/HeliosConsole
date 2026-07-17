//
//  EnrollmentsView.swift
//  Helios
//
//  ADE enrollment data layer (models + EnrollmentService). The Enrollments
//  VIEW was retired when the ABM Lookup tab (Views/Device/ABMLookupView.swift)
//  replaced the module — the service stays because Reports depends on it
//  (asset-tag mapping + fetchAllInstancesDevices aggregation).
//

import SwiftUI
import Combine

// MARK: - Device Enrollment Models

struct DeviceEnrollmentDevice: Codable, Identifiable, Hashable {
    let id: String
    let deviceEnrollmentProgramInstanceId: String?
    let prestageId: String?
    let serialNumber: String
    let description: String?
    let model: String?
    let color: String?
    let assetTag: String?
    let profileStatus: ProfileStatus?
    let syncState: SyncState?
    let profileAssignTime: String?
    let profilePushTime: String?
    let deviceAssignedDate: String?
    
    enum ProfileStatus: String, Codable, CaseIterable {
        case empty = "EMPTY"
        case assigned = "ASSIGNED"
        case pushed = "PUSHED"
        case removed = "REMOVED"
        
        var displayName: String {
            switch self {
            case .empty: return "Not Assigned"
            case .assigned: return "Assigned"
            case .pushed: return "Pushed"
            case .removed: return "Removed"
            }
        }
        
        var color: Color {
            switch self {
            case .empty: return .gray
            case .assigned: return .blue
            case .pushed: return .green
            case .removed: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .empty: return "circle.dashed"
            case .assigned: return "checkmark.circle"
            case .pushed: return "checkmark.circle.fill"
            case .removed: return "xmark.circle"
            }
        }
    }
    
    struct SyncState: Codable, Hashable {
        let id: Int?
        let serialNumber: String?
        let profileUUID: String?
        let syncStatus: String?
        let failureCount: Int?
        let timestamp: Int?
    }
    
    /// Derive model identifier from model string for icon lookup
    var derivedModelIdentifier: String? {
        guard let model = model?.lowercased() else { return nil }
        
        // Try to derive a model identifier based on model name
        if model.contains("macbook pro 16") {
            return "Mac15,7"
        } else if model.contains("macbook pro 14") {
            return "Mac15,6"
        } else if model.contains("macbook pro") {
            return "MacBookPro"
        } else if model.contains("macbook air 15") {
            return "Mac15,12"
        } else if model.contains("macbook air") {
            return "MacBookAir"
        } else if model.contains("mac studio") {
            return "Mac13,2"
        } else if model.contains("mac mini") {
            return "Macmini"
        } else if model.contains("mac pro") {
            return "Mac14,8"
        } else if model.contains("imac 24") || model.contains("imac") {
            return "iMac21,1"
        }
        
        return nil
    }
}

struct DeviceEnrollmentSearchResults: Codable {
    let totalCount: Int
    let results: [DeviceEnrollmentDevice]
}

// MARK: - Enrollment Service

@MainActor
class EnrollmentService: ObservableObject {
    static let shared = EnrollmentService()
    
    @Published var isLoading = false
    @Published var devices: [DeviceEnrollmentDevice] = []
    @Published var error: String?
    @Published var lastFetchTime: Date?
    @Published var totalDeviceCount: Int = 0
    
    // Available enrollment instances
    @Published var enrollmentInstances: [DeviceEnrollmentInstance] = []
    @Published var selectedInstanceId: String?
    
    // Asset tag to serial number mapping (from computer inventory cache)
    private var assetTagToSerialMap: [String: String] = [:]
    private var serialToAssetTagMap: [String: String] = [:]
    
    // OAuth token caching
    private var cachedBearerToken: String?
    private var tokenExpiration: Date?
    
    private init() {
        // Build asset tag mapping from computer inventory cache
        buildAssetTagMapping()
    }
    
    /// Build mapping between asset tags and serial numbers from computer inventory cache
    func buildAssetTagMapping() {
        let computerCache = ComputerInventoryCache.shared
        
        assetTagToSerialMap.removeAll()
        serialToAssetTagMap.removeAll()
        
        for computer in computerCache.computers {
            if let serial = computer.hardware?.serialNumber,
               let assetTag = computer.general?.assetTag,
               !assetTag.isEmpty {
                assetTagToSerialMap[assetTag.uppercased()] = serial.uppercased()
                serialToAssetTagMap[serial.uppercased()] = assetTag
            }
        }
        
        NSLog("📋 EnrollmentService: Built asset tag mapping with %d entries", assetTagToSerialMap.count)
    }
    
    /// Get asset tag for a serial number (if known)
    func assetTag(forSerial serial: String) -> String? {
        return serialToAssetTagMap[serial.uppercased()]
    }
    
    /// Fetch all devices from device enrollment instance
    func fetchDevices() async {
        isLoading = true
        error = nil
        
        // Refresh asset tag mapping
        buildAssetTagMapping()
        
        let serverURL = MDMConfigurationManager.shared.configuration.jamfURL
        
        do {
            // Get OAuth bearer token using master API
            let token = try await getBearerToken(serverURL: serverURL)
            
            // First, fetch available enrollment instances if we don't have them
            if enrollmentInstances.isEmpty {
                try await fetchEnrollmentInstances(serverURL: serverURL, token: token)
            }
            
            // Use selected instance or first available
            guard let instanceId = selectedInstanceId ?? enrollmentInstances.first?.id else {
                error = "No device enrollment instances found in Jamf Pro. Please configure Apple Business Manager / Apple School Manager integration."
                isLoading = false
                return
            }
            
            let urlString = "\(serverURL)/api/v1/device-enrollments/\(instanceId)/devices"
            guard let url = URL(string: urlString) else {
                error = "Invalid URL"
                isLoading = false
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = NetworkTuning.connectionTimeout
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            NSLog("📋 EnrollmentService: Fetching devices from enrollment instance %@", instanceId)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                error = "Invalid server response"
                isLoading = false
                return
            }
            
            switch httpResponse.statusCode {
            case 200...299:
                let results = try JSONDecoder().decode(DeviceEnrollmentSearchResults.self, from: data)
                devices = results.results
                totalDeviceCount = results.totalCount
                lastFetchTime = Date()
                NSLog("✅ EnrollmentService: Loaded %d devices", totalDeviceCount)
                
            case 401:
                cachedBearerToken = nil
                tokenExpiration = nil
                error = "Authentication failed. Please try again."
                
            case 403:
                let errorBody = String(data: data, encoding: .utf8) ?? ""
                error = "Access denied. Please verify API client privileges in Jamf Pro.\n\n\(errorBody)"
                
            default:
                let errorBody = String(data: data, encoding: .utf8) ?? ""
                error = "Server error (\(httpResponse.statusCode)): \(errorBody)"
            }
            
        } catch {
            self.error = "Failed to fetch enrollment data: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    /// Get bearer token using master API credentials
    private func getBearerToken(serverURL: String) async throws -> String {
        // Check if we have a valid cached token
        if let token = cachedBearerToken,
           let expiration = tokenExpiration,
           expiration > Date().addingTimeInterval(60) {
            return token
        }
        
        // Get master API credentials
        let config = MDMConfigurationManager.shared.configuration
        let masterClientID = config.masterClientID
        let masterClientSecret = config.masterClientSecret
        
        guard let url = URL(string: "\(serverURL)/api/v1/oauth/token") else {
            throw EnrollmentError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = NetworkTuning.connectionTimeout
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
        
        let bodyString = "grant_type=client_credentials&client_id=\(masterClientID)&client_secret=\(masterClientSecret)"
        request.httpBody = bodyString.data(using: .utf8)
        
        NSLog("🔐 EnrollmentService: Getting bearer token using master API")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw EnrollmentError.authenticationFailed(message)
        }
        
        struct TokenResponse: Codable {
            let access_token: String
            let token_type: String?
            let scope: String?
            let expires_in: Int
        }
        
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        cachedBearerToken = tokenResponse.access_token
        tokenExpiration = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in))
        
        NSLog("✅ EnrollmentService: Got bearer token using master API")
        return tokenResponse.access_token
    }
    
    /// Fetch available enrollment instances
    private func fetchEnrollmentInstances(serverURL: String, token: String) async throws {
        let urlString = "\(serverURL)/api/v1/device-enrollments"
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = NetworkTuning.connectionTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            return
        }
        
        let results = try JSONDecoder().decode(DeviceEnrollmentInstanceSearchResults.self, from: data)
        enrollmentInstances = results.results
        
        if let first = enrollmentInstances.first {
            selectedInstanceId = first.id
        }
        
        NSLog("📋 EnrollmentService: Found %d enrollment instances", enrollmentInstances.count)
    }
    
    /// Filter devices by search term - includes asset tag lookup
    func filterDevices(searchTerm: String, statusFilter: DeviceEnrollmentDevice.ProfileStatus?) -> [DeviceEnrollmentDevice] {
        var filtered = devices
        
        // Apply status filter first
        if let status = statusFilter {
            filtered = filtered.filter { $0.profileStatus == status }
        }
        
        // Apply search filter
        guard !searchTerm.isEmpty else { return filtered }
        
        let term = searchTerm.uppercased()
        
        // Check if search term is an asset tag and map to serial
        if let mappedSerial = assetTagToSerialMap[term] {
            // Search for the mapped serial number
            return filtered.filter { $0.serialNumber.uppercased() == mappedSerial }
        }
        
        // Normal search across all fields
        return filtered.filter { device in
            device.serialNumber.uppercased().contains(term) ||
            (device.model?.uppercased().contains(term) ?? false) ||
            (device.description?.uppercased().contains(term) ?? false) ||
            (device.assetTag?.uppercased().contains(term) ?? false) ||
            // Also check if serial matches any known asset tag
            (serialToAssetTagMap[device.serialNumber.uppercased()]?.uppercased().contains(term) ?? false)
        }
    }
}

// MARK: - Device Enrollment Instance Model

struct DeviceEnrollmentInstance: Codable, Identifiable {
    let id: String
    let name: String
    let supervisionIdentityId: String?
    let siteId: String?
    let serverName: String?
    let serverUuid: String?
    let adminId: String?
    let orgName: String?
    let orgEmail: String?
    let orgPhone: String?
    let orgAddress: String?
    let tokenExpirationDate: String?
}

struct DeviceEnrollmentInstanceSearchResults: Codable {
    let totalCount: Int
    let results: [DeviceEnrollmentInstance]
}

// MARK: - Reports aggregation

/// Device Enrollment (ADE/DEP) records aggregated across every instance,
/// keyed by uppercased serial, plus a lookup of instance id → name.
struct EnrollmentAggregate: Sendable {
    let bySerial: [String: DeviceEnrollmentDevice]
    let instanceNames: [String: String]
    let instanceSiteIds: [String: String]

    func instanceName(for device: DeviceEnrollmentDevice) -> String? {
        guard let id = device.deviceEnrollmentProgramInstanceId else { return nil }
        return instanceNames[id]
    }

    func instanceSiteId(for device: DeviceEnrollmentDevice) -> String? {
        guard let id = device.deviceEnrollmentProgramInstanceId else { return nil }
        return instanceSiteIds[id]
    }
}

extension EnrollmentService {
    /// Aggregate ADE devices across ALL enrollment instances without touching
    /// the @Published state the Enrollments view relies on. Used by the Reports
    /// "Devices" scope to attach enrollment records and surface DEP serials that
    /// aren't in Jamf inventory.
    func fetchAllInstancesDevices() async throws -> EnrollmentAggregate {
        let serverURL = MDMConfigurationManager.shared.configuration.jamfURL
        let token = try await getBearerToken(serverURL: serverURL)
        let instances = try await instanceList(serverURL: serverURL, token: token)

        var bySerial: [String: DeviceEnrollmentDevice] = [:]
        var instanceNames: [String: String] = [:]
        var instanceSiteIds: [String: String] = [:]
        for instance in instances {
            instanceNames[instance.id] = instance.name
            instanceSiteIds[instance.id] = instance.siteId ?? ""
            let devices = try await deviceList(instanceId: instance.id, serverURL: serverURL, token: token)
            for device in devices {
                let key = device.serialNumber.uppercased()
                guard !key.isEmpty else { continue }
                // On duplicate serials, keep the most advanced profile status.
                if let existing = bySerial[key],
                   Self.statusRank(existing.profileStatus) >= Self.statusRank(device.profileStatus) {
                    continue
                }
                bySerial[key] = device
            }
        }
        return EnrollmentAggregate(bySerial: bySerial, instanceNames: instanceNames, instanceSiteIds: instanceSiteIds)
    }

    private func instanceList(serverURL: String, token: String) async throws -> [DeviceEnrollmentInstance] {
        guard let url = URL(string: "\(serverURL)/api/v1/device-enrollments") else { throw EnrollmentError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = NetworkTuning.connectionTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return [] }
        return try JSONDecoder().decode(DeviceEnrollmentInstanceSearchResults.self, from: data).results
    }

    private func deviceList(instanceId: String, serverURL: String, token: String) async throws -> [DeviceEnrollmentDevice] {
        guard let url = URL(string: "\(serverURL)/api/v1/device-enrollments/\(instanceId)/devices") else { throw EnrollmentError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = NetworkTuning.connectionTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return [] }
        return try JSONDecoder().decode(DeviceEnrollmentSearchResults.self, from: data).results
    }

    private static func statusRank(_ status: DeviceEnrollmentDevice.ProfileStatus?) -> Int {
        switch status {
        case .pushed: return 4
        case .assigned: return 3
        case .removed: return 2
        case .empty: return 1
        case nil: return 0
        }
    }
}

// MARK: - Enrollment Errors

enum EnrollmentError: Error, LocalizedError {
    case noCredentials
    case invalidURL
    case networkError(String)
    case authenticationFailed(String)
    case accessDenied
    
    var errorDescription: String? {
        switch self {
        case .noCredentials:
            return "No API credentials found. Please log in again."
        case .invalidURL:
            return "Invalid server URL"
        case .networkError(let message):
            return "Network error: \(message)"
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .accessDenied:
            return "Access denied. The API client may not have the required permissions."
        }
    }
}

