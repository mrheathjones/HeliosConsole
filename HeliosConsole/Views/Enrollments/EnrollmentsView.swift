//
//  EnrollmentsView.swift
//  Helios
//
//  View for looking up device enrollment status via Jamf API
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
            request.timeoutInterval = 30
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
        request.timeoutInterval = 15
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
        request.timeoutInterval = 15
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
        request.timeoutInterval = 15
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
        request.timeoutInterval = 30
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

// MARK: - Enrollments View

struct EnrollmentsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var enrollmentService = EnrollmentService.shared
    
    @State private var searchText = ""
    @State private var selectedDevice: DeviceEnrollmentDevice?
    @State private var showingDeviceDetail = false
    @State private var selectedStatusFilter: DeviceEnrollmentDevice.ProfileStatus?
    @FocusState private var isSearchFocused: Bool
    
    private var isDark: Bool { colorScheme == .dark }
    
    private var filteredDevices: [DeviceEnrollmentDevice] {
        enrollmentService.filterDevices(searchTerm: searchText, statusFilter: selectedStatusFilter)
    }
    
    // Status counts for filter badges
    private var statusCounts: [DeviceEnrollmentDevice.ProfileStatus: Int] {
        var counts: [DeviceEnrollmentDevice.ProfileStatus: Int] = [:]
        for status in DeviceEnrollmentDevice.ProfileStatus.allCases {
            counts[status] = enrollmentService.devices.filter { $0.profileStatus == status }.count
        }
        return counts
    }
    
    var body: some View {
        ZStack {
            // Animated background matching app design
            AnimatedBackgroundView(animate: .constant(true))
            
            VStack(spacing: 0) {
                headerSection
                toolbarSection
                
                if enrollmentService.isLoading && enrollmentService.devices.isEmpty {
                    loadingView
                } else if let error = enrollmentService.error {
                    errorView(error: error)
                } else if enrollmentService.devices.isEmpty {
                    emptyStateView
                } else {
                    contentView
                }
            }
        }
        .task {
            // Data is pre-loaded at app startup, but refresh if empty
            if enrollmentService.devices.isEmpty && !enrollmentService.isLoading && enrollmentService.error == nil {
                await enrollmentService.fetchDevices()
            }
        }
        .sheet(item: $selectedDevice) { device in
            DeviceEnrollmentDetailSheet(device: device, assetTag: enrollmentService.assetTag(forSerial: device.serialNumber))
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack(alignment: .center, spacing: 20) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.2), Color.pink.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "person.crop.rectangle.badge.plus")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Device Enrollments")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    
                    HStack(spacing: 8) {
                        if enrollmentService.totalDeviceCount > 0 {
                            Text("\(enrollmentService.totalDeviceCount) devices in enrollment")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                        
                        if let lastFetch = enrollmentService.lastFetchTime {
                            Text("•")
                                .foregroundColor(.gray)
                            Text("Updated: \(lastFetch.formatted(date: .omitted, time: .shortened))")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Refresh button
            Button {
                Task {
                    await enrollmentService.fetchDevices()
                }
            } label: {
                HStack(spacing: 6) {
                    if enrollmentService.isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Refresh")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(enrollmentService.isLoading)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .background(Color.black.opacity(0.3))
    }
    
    // MARK: - Toolbar Section
    
    private var toolbarSection: some View {
        HStack(spacing: 16) {
            // Status filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // All filter
                    filterChip(title: "All", count: enrollmentService.devices.count, isSelected: selectedStatusFilter == nil, color: .gray) {
                        selectedStatusFilter = nil
                    }
                    
                    // Status filters
                    ForEach(DeviceEnrollmentDevice.ProfileStatus.allCases, id: \.self) { status in
                        filterChip(
                            title: status.displayName,
                            count: statusCounts[status] ?? 0,
                            isSelected: selectedStatusFilter == status,
                            color: status.color
                        ) {
                            if selectedStatusFilter == status {
                                selectedStatusFilter = nil
                            } else {
                                selectedStatusFilter = status
                            }
                        }
                    }
                }
            }
            
            Spacer()
            
            // Results count
            if !searchText.isEmpty || selectedStatusFilter != nil {
                Text("\(filteredDevices.count) of \(enrollmentService.devices.count) shown")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
            }
            
            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray)
                
                TextField("", text: $searchText, prompt: Text("Search serial, model, asset tag...")
                    .foregroundColor(.gray.opacity(0.6)))
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .focused($isSearchFocused)
                
                if !searchText.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            searchText = ""
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(width: 280)
            .background(Color.white.opacity(0.05))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSearchFocused ? Color.blue.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.15))
    }
    
    private func filterChip(title: String, count: Int, isSelected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? Color.white.opacity(0.3) : color.opacity(0.2))
                    .cornerRadius(4)
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.8))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? color : Color.white.opacity(0.05))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? color : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Content
    
    private var contentView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filteredDevices) { device in
                    DeviceEnrollmentRow(
                        device: device,
                        assetTag: enrollmentService.assetTag(forSerial: device.serialNumber)
                    ) {
                        selectedDevice = device
                    }
                }
            }
            .padding(32)
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading device enrollments...")
                .font(.system(size: 14))
                .foregroundColor(.gray)
            Spacer()
        }
    }
    
    // MARK: - Error View
    
    private func errorView(error: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: error.contains("No device enrollment instances") ? "building.2" : "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(error.contains("No device enrollment instances") ? .orange : .red)
            }
            
            VStack(spacing: 8) {
                Text(error.contains("No device enrollment instances") ? "No Enrollment Instances" : "Unable to Load Enrollments")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(error)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 450)
            }
            
            Button {
                Task {
                    await enrollmentService.fetchDevices()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Try Again")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.blue)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundColor(.blue.opacity(0.6))
            }
            
            VStack(spacing: 12) {
                Text("No Enrolled Devices")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("No devices found in the device enrollment program.\nDevices will appear here once assigned in Apple Business Manager.")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            
            Button {
                Task {
                    await enrollmentService.fetchDevices()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.blue)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
    }
}

// MARK: - Device Enrollment Row

struct DeviceEnrollmentRow: View {
    let device: DeviceEnrollmentDevice
    let assetTag: String?
    let onTap: () -> Void
    
    @State private var isHovered = false
    
    /// Derive platform from model name
    private var derivedPlatform: PlatformType? {
        guard let model = device.model?.lowercased() else { return nil }
        if model.contains("iphone") { return .iOS }
        if model.contains("ipad") { return .iPadOS }
        if model.contains("vision") { return .visionOS }
        if model.contains("mac") || model.contains("imac") { return .macOS }
        return nil
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Device thumbnail - using realistic icon
                DeviceIconView(
                    modelIdentifier: device.derivedModelIdentifier,
                    modelName: device.model,
                    platform: derivedPlatform,
                    size: 48
                )
                
                // Device info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(device.serialNumber)
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                        
                        if let status = device.profileStatus {
                            HStack(spacing: 4) {
                                Image(systemName: status.icon)
                                    .font(.system(size: 10))
                                Text(status.displayName)
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(status.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(status.color.opacity(0.15))
                            .cornerRadius(4)
                        }
                    }
                    
                    HStack(spacing: 12) {
                        if let model = device.model {
                            Text(model)
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                        }
                        
                        if let description = device.description, !description.isEmpty {
                            Text("•")
                                .foregroundColor(.gray.opacity(0.5))
                            Text(description)
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    HStack(spacing: 12) {
                        // Show mapped asset tag if available
                        if let mappedAssetTag = assetTag {
                            HStack(spacing: 4) {
                                Image(systemName: "tag.fill")
                                    .font(.system(size: 10))
                                Text(mappedAssetTag)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.blue)
                        } else if let deviceAssetTag = device.assetTag, !deviceAssetTag.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "tag")
                                    .font(.system(size: 10))
                                Text(deviceAssetTag)
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(.gray.opacity(0.7))
                        }
                        
                        if let color = device.color, !color.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "paintpalette")
                                    .font(.system(size: 10))
                                Text(color.capitalized)
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(.gray.opacity(0.7))
                        }
                    }
                }
                
                Spacer()
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray.opacity(0.5))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(isHovered ? 0.06 : 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(isHovered ? 0.1 : 0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Device Enrollment Detail Sheet

struct DeviceEnrollmentDetailSheet: View {
    let device: DeviceEnrollmentDevice
    let assetTag: String?
    
    @Environment(\.dismiss) private var dismiss
    
    /// Derive platform from model name
    private var derivedPlatform: PlatformType? {
        guard let model = device.model?.lowercased() else { return nil }
        if model.contains("iphone") { return .iOS }
        if model.contains("ipad") { return .iPadOS }
        if model.contains("vision") { return .visionOS }
        if model.contains("mac") || model.contains("imac") { return .macOS }
        return nil
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with gradient accent
            VStack(spacing: 16) {
                HStack(alignment: .top) {
                    // Device icon
                    DeviceIconView(
                        modelIdentifier: device.derivedModelIdentifier,
                        modelName: device.model,
                        platform: derivedPlatform,
                        size: 72
                    )
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.08))
                    )
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(device.serialNumber)
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        
                        if let model = device.model {
                            Text(model)
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                        
                        // Status badge
                        if let status = device.profileStatus {
                            HStack(spacing: 6) {
                                Image(systemName: status.icon)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(status.displayName)
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(status.color)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(status.color.opacity(0.2))
                            .cornerRadius(6)
                        }
                    }
                    
                    Spacer()
                    
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.gray)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.white.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .background(Color.white.opacity(0.03))
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Content
            ScrollView {
                VStack(spacing: 16) {
                    // Device Information Card
                    detailCard(title: "Device Information", icon: "laptopcomputer", iconColors: [.blue, .cyan]) {
                        VStack(spacing: 0) {
                            detailRow(label: "Serial Number", value: device.serialNumber, isFirst: true)
                            
                            if let model = device.model {
                                detailRow(label: "Model", value: model)
                            }
                            
                            if let description = device.description, !description.isEmpty {
                                detailRow(label: "Description", value: description)
                            }
                            
                            if let color = device.color, !color.isEmpty {
                                detailRow(label: "Color", value: color.capitalized)
                            }
                            
                            if let mappedAssetTag = assetTag {
                                detailRow(label: "Asset Tag", value: mappedAssetTag, isLast: true)
                            } else if let deviceAssetTag = device.assetTag, !deviceAssetTag.isEmpty {
                                detailRow(label: "Asset Tag", value: deviceAssetTag, isLast: true)
                            }
                        }
                    }
                    
                    // Enrollment Details Card
                    detailCard(title: "Enrollment Details", icon: "square.and.arrow.down.on.square", iconColors: [.purple, .pink]) {
                        VStack(spacing: 0) {
                            detailRow(label: "Enrollment ID", value: device.id, isFirst: true)
                            
                            if let instanceId = device.deviceEnrollmentProgramInstanceId {
                                detailRow(label: "DEP Instance", value: instanceId)
                            }
                            
                            if let prestageId = device.prestageId {
                                detailRow(label: "PreStage ID", value: prestageId)
                            }
                            
                            if let assignedDate = device.deviceAssignedDate {
                                detailRow(label: "Assigned Date", value: formatDate(assignedDate))
                            }
                            
                            if let profileAssignTime = device.profileAssignTime {
                                detailRow(label: "Profile Assign Time", value: formatDate(profileAssignTime))
                            }
                            
                            if let profilePushTime = device.profilePushTime {
                                detailRow(label: "Profile Push Time", value: formatDate(profilePushTime), isLast: true)
                            }
                        }
                    }
                    
                    // Sync State Card
                    if let syncState = device.syncState {
                        detailCard(title: "Sync State", icon: "arrow.triangle.2.circlepath", iconColors: [.green, .mint]) {
                            VStack(spacing: 0) {
                                if let syncStatus = syncState.syncStatus {
                                    HStack {
                                        Text("Status")
                                            .font(.system(size: 13))
                                            .foregroundColor(.gray)
                                        Spacer()
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(syncStatus.contains("SUCCESS") ? Color.green : Color.orange)
                                                .frame(width: 8, height: 8)
                                            Text(syncStatus)
                                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                }
                                
                                if let failureCount = syncState.failureCount {
                                    detailRow(label: "Failure Count", value: "\(failureCount)")
                                }
                                
                                if let profileUUID = syncState.profileUUID {
                                    detailRow(label: "Profile UUID", value: profileUUID, monospaced: true, isLast: true)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 520, height: 640)
        .background(.ultraThinMaterial.opacity(0.8))
        .background(Color(white: 0.06).opacity(0.7))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    private func detailCard<Content: View>(
        title: String,
        icon: String,
        iconColors: [Color],
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card header
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(colors: iconColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            content()
        }
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
    
    private func detailRow(
        label: String,
        value: String,
        monospaced: Bool = false,
        isFirst: Bool = false,
        isLast: Bool = false
    ) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.gray)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 13, weight: .medium, design: monospaced ? .monospaced : .default))
                .foregroundColor(.white)
                .textSelection(.enabled)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        
        return dateString
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Enrollments View") {
    EnrollmentsView()
        .frame(width: 1200, height: 800)
}
#endif
