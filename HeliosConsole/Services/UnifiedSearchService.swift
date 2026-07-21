//
//  UnifiedDeviceSearchService.swift
//  Helios
//
//  Unified search service that searches both computers and mobile devices
//  Searches by name or serial number across all device types
//

import Foundation
import Combine

// MARK: - Unified Search Result

/// A unified search result that can represent either a computer or mobile device
enum UnifiedSearchResult: Identifiable, Hashable {
    case computer(Computer)
    case mobileDevice(MobileDevice)
    
    var id: String {
        switch self {
        case .computer(let computer):
            return "computer-\(computer.id)"
        case .mobileDevice(let device):
            return "mobile-\(device.id)"
        }
    }
    
    var name: String {
        switch self {
        case .computer(let computer):
            return computer.general?.name ?? "Unknown"
        case .mobileDevice(let device):
            return device.displayName
        }
    }
    
    var serialNumber: String {
        switch self {
        case .computer(let computer):
            return computer.hardware?.serialNumber ?? "N/A"
        case .mobileDevice(let device):
            return device.serialNumber ?? "N/A"
        }
    }
    
    var model: String {
        switch self {
        case .computer(let computer):
            return computer.hardware?.model ?? "Mac"
        case .mobileDevice(let device):
            return device.model
        }
    }
    
    var platform: PlatformType {
        switch self {
        case .computer:
            return .macOS
        case .mobileDevice(let device):
            return device.platformType
        }
    }
    
    var osVersion: String {
        switch self {
        case .computer(let computer):
            return computer.operatingSystem?.version ?? "N/A"
        case .mobileDevice(let device):
            return device.osVersion ?? "N/A"
        }
    }
    
    var isManaged: Bool {
        switch self {
        case .computer(let computer):
            return computer.general?.remoteManagement?.managed ?? false
        case .mobileDevice(let device):
            return device.managed ?? false
        }
    }
    
    var isSupervised: Bool {
        switch self {
        case .computer(let computer):
            return computer.general?.supervised ?? false
        case .mobileDevice(let device):
            return device.isSupervised
        }
    }
    
    var assignedUser: String? {
        switch self {
        case .computer(let computer):
            return computer.userAndLocation?.realname ?? computer.userAndLocation?.username
        case .mobileDevice(let device):
            return device.location?.realName ?? device.location?.username
        }
    }
}

// MARK: - Unified Device Search Service

@MainActor
final class UnifiedDeviceSearchService: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var searchResults: [UnifiedSearchResult] = []
    @Published var isSearching: Bool = false
    @Published var errorMessage: String?
    
    // Individual results for debugging/display
    @Published var computerResults: [Computer] = []
    @Published var mobileDeviceResults: [MobileDevice] = []
    
    // MARK: - Private Properties
    
    private let keychain = KeychainManager.shared
    private var cachedBearerToken: String?
    private var tokenExpiration: Date?

    /// When true, authenticate with the MDM-supplied master client instead of
    /// the per-user credentials in the Keychain. The menu bar companion uses
    /// this so it is self-sufficient and does NOT need a shared Keychain with
    /// the main app.
    private let useMasterCredentials: Bool

    init(useMasterCredentials: Bool = false) {
        self.useMasterCredentials = useMasterCredentials
    }

    private var configuration: MDMConfiguration {
        MDMConfigurationManager.shared.configuration
    }
    
    private var jamfURL: String {
        configuration.jamfURL
    }
    
    // MARK: - Public Methods
    
    /// Search for devices by name or serial number across all device types
    /// - Parameter query: The search query (name or serial number)
    func searchDevices(query: String) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        errorMessage = nil
        searchResults = []
        computerResults = []
        mobileDeviceResults = []
        
        do {
            let token = try await getBearerToken()

            // features domain module gates: a disabled platform is excluded
            // from unified search (main window AND the menu bar companion).
            let features = MDMConfigurationManager.shared.configuration.features
            let computersEnabled = features?.effectiveComputers.effectiveEnabled ?? true
            let mobilesEnabled = features?.effectiveMobileDevices.effectiveEnabled ?? true

            // Search computers and mobile devices in parallel
            // Each search checks both name AND serial number
            async let computersTask = computersEnabled
                ? searchComputers(query: trimmedQuery, token: token)
                : []
            async let mobilesTask = mobilesEnabled
                ? searchMobileDevices(query: trimmedQuery, token: token)
                : []

            let (computers, mobiles) = await (computersTask, mobilesTask)
            
            // Store results
            computerResults = computers
            mobileDeviceResults = mobiles
            
            // Create unified results
            var unified: [UnifiedSearchResult] = []
            unified.append(contentsOf: computers.map { .computer($0) })
            unified.append(contentsOf: mobiles.map { .mobileDevice($0) })
            
            // Sort by name
            searchResults = unified.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            
            NSLog("✅ UnifiedSearch: Found %d computers, %d mobile devices", computers.count, mobiles.count)
            
            if searchResults.isEmpty {
                errorMessage = "No devices found matching '\(trimmedQuery)'"
            }
            
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
            NSLog("❌ UnifiedSearch: %@", error.localizedDescription)
        }
        
        isSearching = false
    }
    
    // MARK: - Private Methods - Computer Search
    
    private func searchComputers(query: String, token: String) async -> [Computer] {
        // Search by name
        let byName = await searchComputersByName(query: query, token: token)
        
        // Search by serial
        let bySerial = await searchComputersBySerial(query: query, token: token)
        
        // Deduplicate
        var seen = Set<String>()
        var results: [Computer] = []
        
        for computer in byName + bySerial {
            if !seen.contains(computer.id) {
                seen.insert(computer.id)
                results.append(computer)
            }
        }
        
        return results
    }
    
    private func searchComputersByName(query: String, token: String) async -> [Computer] {
        // For computers, the filter uses == with wildcards: name=="*query*"
        let filter = "general.name==\"*\(query)*\""
        let encodedFilter = filter.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filter
        
        return await fetchComputerSearch(filter: encodedFilter, token: token)
    }
    
    private func searchComputersBySerial(query: String, token: String) async -> [Computer] {
        // For serial numbers, also use wildcard for partial matches
        let filter = "hardware.serialNumber==\"*\(query)*\""
        let encodedFilter = filter.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filter
        
        return await fetchComputerSearch(filter: encodedFilter, token: token)
    }
    
    private func fetchComputerSearch(filter: String, token: String) async -> [Computer] {
        let sections = [
            "GENERAL", "HARDWARE", "OPERATING_SYSTEM", "USER_AND_LOCATION",
            "DISK_ENCRYPTION", "SECURITY", "APPLICATIONS", "CONFIGURATION_PROFILES",
            "PRINTERS", "CERTIFICATES", "GROUP_MEMBERSHIPS", "EXTENSION_ATTRIBUTES",
            "LOCAL_USER_ACCOUNTS"
        ]
        
        let sectionParams = sections.map { "section=\($0)" }.joined(separator: "&")
        let endpoint = "/api/v1/computers-inventory"
        let queryParams = "\(sectionParams)&page=0&page-size=50&filter=\(filter)"
        
        guard let url = URL(string: "\(jamfURL)\(endpoint)?\(queryParams)") else {
            return []
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = NetworkTuning.connectionTimeout
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return []
            }
            
            struct ComputerSearchResponse: Codable {
                let totalCount: Int
                let results: [ComputerSearchResult]
            }
            
            let searchResponse = try JSONDecoder().decode(ComputerSearchResponse.self, from: data)
            return searchResponse.results.map { Computer.fromSearchResult($0) }
        } catch {
            NSLog("❌ Computer search error: %@", error.localizedDescription)
            return []
        }
    }
    
    // MARK: - Private Methods - Mobile Device Search
    
    /// Search mobile devices by name OR serial number (checks both)
    private func searchMobileDevices(query: String, token: String) async -> [MobileDevice] {
        // Use the cache if available
        let cache = MobileDeviceInventoryCache.shared
        
        if cache.hasCachedData {
            NSLog("📱 Mobile search: Using cached inventory (%d devices)", cache.devices.count)
            
            // Filter cached devices - check both name AND serial
            let matchingDevices = cache.devices.filter { device in
                let nameMatches = device.name?.localizedCaseInsensitiveContains(query) ?? false
                let serialMatches = device.serialNumber?.localizedCaseInsensitiveContains(query) ?? false
                return nameMatches || serialMatches
            }
            
            NSLog("📱 Mobile search: Found %d matches in cache", matchingDevices.count)
            
            // Fetch full details for matching devices only
            var detailedDevices: [MobileDevice] = []
            for basicDevice in matchingDevices {
                if let device = await fetchMobileDeviceDetail(id: basicDevice.id, token: token) {
                    detailedDevices.append(device)
                }
            }
            
            return detailedDevices
        }
        
        // No cache - fetch basic list first
        NSLog("📱 Mobile search: Fetching device list (no cache)")
        
        guard var urlComponents = URLComponents(string: "\(jamfURL)/api/v2/mobile-devices") else {
            return []
        }
        
        urlComponents.queryItems = [
            URLQueryItem(name: "page", value: "0"),
            URLQueryItem(name: "page-size", value: "100"),
            URLQueryItem(name: "sort", value: "name:asc")
        ]
        
        guard let url = urlComponents.url else {
            return []
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = NetworkTuning.connectionTimeout
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return []
            }
            
            struct BasicMobileDeviceResponse: Codable {
                let totalCount: Int
                let results: [BasicMobileDevice]
            }
            
            struct BasicMobileDevice: Codable {
                let id: String
                let name: String?
                let serialNumber: String?
            }
            
            let basicResponse = try JSONDecoder().decode(BasicMobileDeviceResponse.self, from: data)
            NSLog("📱 Mobile search: Got %d devices from API", basicResponse.results.count)
            
            // Filter client-side - check both name AND serial
            let matchingDevices = basicResponse.results.filter { device in
                let nameMatches = device.name?.localizedCaseInsensitiveContains(query) ?? false
                let serialMatches = device.serialNumber?.localizedCaseInsensitiveContains(query) ?? false
                return nameMatches || serialMatches
            }
            
            NSLog("📱 Mobile search: %d matches after filtering", matchingDevices.count)
            
            // Fetch full details for matches only
            var detailedDevices: [MobileDevice] = []
            for basicDevice in matchingDevices {
                if let device = await fetchMobileDeviceDetail(id: basicDevice.id, token: token) {
                    detailedDevices.append(device)
                }
            }
            
            return detailedDevices
            
        } catch {
            NSLog("❌ Mobile search error: %@", error.localizedDescription)
            return []
        }
    }
    
    /// Fetch full details for a single mobile device by ID
    private func fetchMobileDeviceDetail(id: String, token: String) async -> MobileDevice? {
        let sections = [
            "GENERAL", "HARDWARE", "USER_AND_LOCATION", "PURCHASING", "SECURITY",
            "APPLICATIONS", "EBOOKS", "NETWORK", "SERVICE_SUBSCRIPTIONS",
            "CERTIFICATES", "PROFILES", "GROUPS", "EXTENSION_ATTRIBUTES"
        ]
        
        let sectionParams = sections.map { "section=\($0)" }.joined(separator: "&")
        let endpoint = "/api/v2/mobile-devices/\(id)/detail"
        
        guard let url = URL(string: "\(jamfURL)\(endpoint)?\(sectionParams)") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = NetworkTuning.connectionTimeout
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }
            
            let device = try JSONDecoder().decode(MobileDevice.self, from: data)
            return device
        } catch {
            NSLog("❌ Mobile device detail fetch error for ID %@: %@", id, error.localizedDescription)
            return nil
        }
    }
    
    // MARK: - Token Management
    
    /// Get bearer token using user's API credentials
    private func getBearerToken() async throws -> String {
        // Resolve the source: the menu bar companion forces master (it is
        // self-sufficient and shares no Keychain with the main app); otherwise
        // the `deviceSearch` scope decides. A user result delegates to the
        // shared per-user session (fail-closed — no silent master fallback).
        let source: CredentialSource = useMasterCredentials
            ? .master
            : configuration.credentialSource(for: .deviceSearch)
        if source == .user {
            return try await JamfUserSession.shared.bearerToken()
        }

        // Check if we have a valid cached (master) token
        if let token = cachedBearerToken,
           let expiration = tokenExpiration,
           expiration > Date().addingTimeInterval(60) {
            return token
        }

        // Master client from the MDM profile.
        let clientID = configuration.masterClientID
        let clientSecret = configuration.masterClientSecret
        guard !clientID.isEmpty, clientID != "your-master-client-id",
              !clientSecret.isEmpty, clientSecret != "your-master-client-secret" else {
            throw NSError(domain: "UnifiedSearch", code: 401, userInfo: [NSLocalizedDescriptionKey: "No credentials available"])
        }

        // Request new bearer token
        guard let url = URL(string: "\(jamfURL)/api/v1/oauth/token") else {
            throw NSError(domain: "UnifiedSearch", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = NetworkTuning.connectionTimeout
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")

        let bodyString = "grant_type=client_credentials&client_id=\(clientID)&client_secret=\(clientSecret)"
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "UnifiedSearch", code: 401, userInfo: [NSLocalizedDescriptionKey: "Authentication failed"])
        }
        
        struct TokenResponse: Codable {
            let access_token: String
            let expires_in: Int
        }
        
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        
        cachedBearerToken = tokenResponse.access_token
        tokenExpiration = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in))
        
        return tokenResponse.access_token
    }
}
