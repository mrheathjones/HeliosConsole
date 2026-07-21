//
//  HealthFilteredDeviceListView.swift
//  test
//
//  Created by heath on 1/21/26.
//

//
//  Displays devices filtered by health metric status (compliant, non-compliant, unknown)
//

import SwiftUI
// AppKit removed - using pure SwiftUI

// MARK: - Health Filtered Device List View

struct HealthFilteredDeviceListView: View {
    let healthItem: HealthNavigationItem
    @Binding var navigationPath: NavigationPath
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText: String = ""
    @State private var sortOrder: DeviceSortOrder = .nameAscending
    @State private var isLoading: Bool = false
    @State private var devices: [DeviceListItem] = []
    
    // Platform filter
    @State private var selectedPlatformFilter: PlatformType = .all
    
    // Pagination state
    @State private var currentPage: Int = 1
    @State private var itemsPerPage: Int = 25
    
    // Device detail loading state
    @State private var isLoadingDeviceDetail: Bool = false
    @State private var loadingDeviceId: String? = nil
    @State private var loadError: String? = nil
    
    @FocusState private var isSearchFocused: Bool
    
    private let itemsPerPageOptions = [10, 25, 50, 100]
    
    private var statusColor: Color {
        healthItem.segmentType.color
    }
    
    private var statusIcon: String {
        switch healthItem.segmentType {
        case .compliant:
            return "checkmark.circle.fill"
        case .nonCompliant:
            return "xmark.circle.fill"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }
    
    var body: some View {
        ZStack {
            AnimatedBackgroundView(animate: .constant(true))
            
            VStack(spacing: 0) {
                headerSection
                toolbarSection
                
                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 1)
                
                if isLoading {
                    loadingView
                } else if filteredDevices.isEmpty {
                    emptyStateView
                } else {
                    deviceListSection
                }
                
                if !filteredDevices.isEmpty {
                    paginationFooter
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            loadDevices()
        }
        .onChange(of: itemsPerPage) { _, _ in
            currentPage = 1
        }
        .onChange(of: selectedPlatformFilter) { _, _ in
            currentPage = 1
        }
    }
    
    // MARK: - Computed Properties
    
    private var filteredDevices: [DeviceListItem] {
        var filtered = devices
        
        // Apply platform filter
        if selectedPlatformFilter != .all {
            filtered = filtered.filter { $0.platform == selectedPlatformFilter }
        }
        
        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.serialNumber.localizedCaseInsensitiveContains(searchText) ||
                ($0.assignedUser ?? "").localizedCaseInsensitiveContains(searchText) ||
                $0.model.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Apply sorting
        return filtered.sorted { first, second in
            switch sortOrder {
            case .nameAscending:
                return first.name.localizedCompare(second.name) == .orderedAscending
            case .nameDescending:
                return first.name.localizedCompare(second.name) == .orderedDescending
            case .lastCheckIn:
                return (first.lastCheckIn ?? Date.distantPast) > (second.lastCheckIn ?? Date.distantPast)
            case .serialNumber:
                return first.serialNumber.localizedCompare(second.serialNumber) == .orderedAscending
            }
        }
    }
    
    private var totalPages: Int {
        max(1, Int(ceil(Double(filteredDevices.count) / Double(itemsPerPage))))
    }
    
    private var paginatedDevices: [DeviceListItem] {
        let startIndex = (currentPage - 1) * itemsPerPage
        let endIndex = min(startIndex + itemsPerPage, filteredDevices.count)
        guard startIndex < filteredDevices.count else { return [] }
        return Array(filteredDevices[startIndex..<endIndex])
    }
    
    private var startItemIndex: Int {
        filteredDevices.isEmpty ? 0 : (currentPage - 1) * itemsPerPage + 1
    }
    
    private var endItemIndex: Int {
        min(currentPage * itemsPerPage, filteredDevices.count)
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack(spacing: 16) {
            // Back button (circle style)
            Button {
                navigationPath.removeLast()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.05))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering {
                    // Cursor style handled by SwiftUI
                } else {
                    // Cursor style handled by SwiftUI
                }
            }
            
            // Status indicator with metric icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.2))
                    .frame(width: 44, height: 44)
                
                Image(systemName: healthItem.metricType.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [statusColor, statusColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            // Title and subtitle
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(healthItem.title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    
                    // Status badge
                    HStack(spacing: 4) {
                        Image(systemName: statusIcon)
                            .font(.system(size: 10))
                        Text("\(healthItem.percentageDisplay)%")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.15))
                    .cornerRadius(6)
                }
                
                Text("\(healthItem.metricType.rawValue) • \(healthItem.deviceCount) devices")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // Device count badge
            HStack(spacing: 6) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 12))
                Text("\(filteredDevices.count)")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.white.opacity(0.8))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.05))
            .cornerRadius(8)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
        .background(Color.black.opacity(0.2))
    }
    
    // MARK: - Toolbar Section
    
    private var toolbarSection: some View {
        HStack(spacing: 16) {
            // Search field
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                
                TextField("Search devices...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .focused($isSearchFocused)
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.05))
            .cornerRadius(10)
            .frame(maxWidth: 320)
            
            Spacer()
            
            // Platform filter
            Menu {
                ForEach(PlatformType.filterCases, id: \.self) { platform in
                    Button {
                        selectedPlatformFilter = platform
                    } label: {
                        HStack {
                            Image(systemName: platform.icon)
                            Text(platform.rawValue)
                            if selectedPlatformFilter == platform {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: selectedPlatformFilter.icon)
                        .font(.system(size: 12))
                    Text(selectedPlatformFilter.rawValue)
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)
            }
            .menuStyle(.borderlessButton)
            
            // Sort menu
            Menu {
                ForEach(DeviceSortOrder.allCases) { order in
                    Button {
                        sortOrder = order
                    } label: {
                        HStack {
                            Text(order.title)
                            if sortOrder == order {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 12))
                    Text(sortOrder.title)
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)
            }
            .menuStyle(.borderlessButton)
            
            // Items per page
            Menu {
                ForEach(itemsPerPageOptions, id: \.self) { count in
                    Button {
                        itemsPerPage = count
                    } label: {
                        HStack {
                            Text("\(count) per page")
                            if itemsPerPage == count {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "list.number")
                        .font(.system(size: 12))
                    Text("\(itemsPerPage) per page")
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)
            }
            .menuStyle(.borderlessButton)
            
            // Refresh button
            RefreshButton(isLoading: isLoading) {
                refreshDevices()
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.15))
    }
    
    // MARK: - Device List Section
    
    private var deviceListSection: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(paginatedDevices) { device in
                    HealthDeviceListRow(
                        device: device,
                        healthItem: healthItem,
                        isLoading: loadingDeviceId == device.id
                    ) {
                        handleDeviceTap(device)
                    }
                }
            }
            .padding(32)
        }
        .overlay {
            // Error banner
            if let error = loadError {
                VStack {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                        Spacer()
                        Button {
                            loadError = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
                    .padding(20)
                    
                    Spacer()
                }
            }
        }
    }
    
    // MARK: - Device Navigation
    
    private func handleDeviceTap(_ device: DeviceListItem) {
        // Check if this is a mobile device (iOS, iPadOS, visionOS)
        if device.platform == .iOS || device.platform == .iPadOS || device.platform == .visionOS {
            // Fetch full mobile device details
            fetchMobileDeviceAndNavigate(device)
        } else {
            // It's a computer - create Computer object and navigate
            let computer = Computer.fromDeviceListItem(device)
            navigationPath.append(computer)
        }
    }
    
    private func fetchMobileDeviceAndNavigate(_ device: DeviceListItem) {
        isLoadingDeviceDetail = true
        loadingDeviceId = device.id
        
        Task {
            do {
                let mobileDevice = try await fetchMobileDeviceDetail(id: device.originalId)
                
                await MainActor.run {
                    isLoadingDeviceDetail = false
                    loadingDeviceId = nil
                    navigationPath.append(mobileDevice)
                }
            } catch {
                await MainActor.run {
                    isLoadingDeviceDetail = false
                    loadingDeviceId = nil
                    loadError = "Failed to load device details: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func fetchMobileDeviceDetail(id: String) async throws -> MobileDevice {
        // Use master API credentials for device lookups
        let config = MDMConfigurationManager.shared.configuration
        let jamfURL = config.jamfURL
        let masterClientID = config.masterClientID
        let masterClientSecret = config.masterClientSecret
        
        // Get token using master API client
        guard let tokenURL = URL(string: "\(jamfURL)/api/v1/oauth/token") else {
            throw NSError(domain: "HealthFilteredDeviceList", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var tokenRequest = URLRequest(url: tokenURL)
        tokenRequest.httpMethod = "POST"
        tokenRequest.setValue("application/json", forHTTPHeaderField: "accept")
        tokenRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
        
        let bodyString = "grant_type=client_credentials&client_id=\(masterClientID)&client_secret=\(masterClientSecret)"
        tokenRequest.httpBody = bodyString.data(using: .utf8)
        
        let (tokenData, tokenResponse) = try await URLSession.shared.data(for: tokenRequest)
        
        guard let httpTokenResponse = tokenResponse as? HTTPURLResponse,
              (200...299).contains(httpTokenResponse.statusCode) else {
            throw NSError(domain: "HealthFilteredDeviceList", code: 401, userInfo: [NSLocalizedDescriptionKey: "Authentication failed"])
        }
        
        struct TokenResponse: Codable {
            let access_token: String
        }
        
        let tokenResult = try JSONDecoder().decode(TokenResponse.self, from: tokenData)
        let token = tokenResult.access_token
        
        // Fetch mobile device detail
        let sections = [
            "GENERAL", "HARDWARE", "USER_AND_LOCATION", "PURCHASING", "SECURITY",
            "APPLICATIONS", "EBOOKS", "NETWORK", "SERVICE_SUBSCRIPTIONS",
            "CERTIFICATES", "PROFILES", "GROUPS", "EXTENSION_ATTRIBUTES"
        ]
        
        let sectionParams = sections.map { "section=\($0)" }.joined(separator: "&")
        let endpoint = "/api/v2/mobile-devices/\(id)/detail"
        
        guard let url = URL(string: "\(jamfURL)\(endpoint)?\(sectionParams)") else {
            throw NSError(domain: "HealthFilteredDeviceList", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid device URL"])
        }
        
        NSLog("📥 HealthFilteredDeviceListView: Fetching mobile device detail from %@", url.absoluteString)
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = NetworkTuning.connectionTimeout
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "HealthFilteredDeviceList", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        NSLog("📥 HealthFilteredDeviceListView: Mobile device detail response status %d", httpResponse.statusCode)
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            NSLog("❌ HealthFilteredDeviceListView: Mobile device detail error: %@", errorMessage)
            throw NSError(domain: "HealthFilteredDeviceList", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Device not found (HTTP \(httpResponse.statusCode))"])
        }
        
        let device = try JSONDecoder().decode(MobileDevice.self, from: data)
        return device
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(statusColor)
            
            Text("Loading devices...")
                .font(.system(size: 14))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: statusIcon)
                    .font(.system(size: 32))
                    .foregroundColor(statusColor.opacity(0.6))
            }
            
            VStack(spacing: 8) {
                Text(searchText.isEmpty ? "No Devices Found" : "No Matching Devices")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(searchText.isEmpty
                     ? "No devices match this health metric filter."
                     : "Try adjusting your search or filters.")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    selectedPlatformFilter = .all
                } label: {
                    Text("Clear Filters")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(statusColor.opacity(0.3))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Pagination Footer
    
    private var paginationFooter: some View {
        HStack(spacing: 20) {
            Text("Showing \(startItemIndex)-\(endItemIndex) of \(filteredDevices.count)")
                .font(.system(size: 13))
                .foregroundColor(.gray)
            
            Spacer()
            
            HStack(spacing: 8) {
                // First page
                healthPaginationButton(icon: "chevron.left.2", isEnabled: currentPage > 1) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentPage = 1
                    }
                }
                
                // Previous page
                healthPaginationButton(icon: "chevron.left", isEnabled: currentPage > 1) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentPage = max(1, currentPage - 1)
                    }
                }
                
                // Page numbers
                pageNumbers
                
                // Next page
                healthPaginationButton(icon: "chevron.right", isEnabled: currentPage < totalPages) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentPage = min(totalPages, currentPage + 1)
                    }
                }
                
                // Last page
                healthPaginationButton(icon: "chevron.right.2", isEnabled: currentPage < totalPages) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentPage = totalPages
                    }
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
        .background(Color.black.opacity(0.2))
    }
    
    @ViewBuilder
    private func healthPaginationButton(icon: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isEnabled ? .white : .gray.opacity(0.4))
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(isEnabled ? 0.05 : 0.02))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
    
    @ViewBuilder
    private var pageNumbers: some View {
        let visiblePages = calculateVisiblePages()
        
        HStack(spacing: 4) {
            ForEach(visiblePages, id: \.self) { page in
                if page == -1 {
                    Text("...")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .frame(width: 32, height: 32)
                } else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            currentPage = page
                        }
                    } label: {
                        Text("\(page)")
                            .font(.system(size: 12, weight: currentPage == page ? .bold : .medium))
                            .foregroundColor(currentPage == page ? .white : .gray)
                            .frame(width: 32, height: 32)
                            .background(
                                currentPage == page
                                    ? statusColor.opacity(0.4)
                                    : Color.white.opacity(0.05)
                            )
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private func calculateVisiblePages() -> [Int] {
        guard totalPages > 1 else { return [1] }
        
        var pages: [Int] = []
        
        if totalPages <= 7 {
            pages = Array(1...totalPages)
        } else {
            pages.append(1)
            
            if currentPage > 3 {
                pages.append(-1) // Ellipsis
            }
            
            let start = max(2, currentPage - 1)
            let end = min(totalPages - 1, currentPage + 1)
            
            for page in start...end {
                if !pages.contains(page) {
                    pages.append(page)
                }
            }
            
            if currentPage < totalPages - 2 {
                pages.append(-1) // Ellipsis
            }
            
            if !pages.contains(totalPages) {
                pages.append(totalPages)
            }
        }
        
        return pages
    }
    
    // MARK: - Data Loading
    
    private func loadDevices() {
        isLoading = true
        
        // Load real filtered devices from HealthMetricsCalculator
        Task { @MainActor in
            let calculator = HealthMetricsCalculator.shared
            let filteredDevices = calculator.getFilteredDevices(
                for: healthItem.metricType,
                segment: healthItem.segmentType
            )
            
            devices = filteredDevices
            isLoading = false
            
            NSLog("📊 HealthFilteredDeviceListView: Loaded %d devices for %@ - %@",
                  devices.count,
                  healthItem.metricType.rawValue,
                  healthItem.segmentType.rawValue)
        }
    }
    
    private func refreshDevices() {
        isLoading = true
        
        Task { @MainActor in
            // Recalculate metrics first
            HealthMetricsCalculator.shared.recalculateMetrics()
            
            // Then get filtered devices
            let calculator = HealthMetricsCalculator.shared
            let filteredDevices = calculator.getFilteredDevices(
                for: healthItem.metricType,
                segment: healthItem.segmentType
            )
            
            devices = filteredDevices
            isLoading = false
        }
    }
    
    private func generateMockDevices() -> [DeviceListItem] {
        let count = healthItem.deviceCount
        var items: [DeviceListItem] = []
        
        let deviceNames = [
            "Mac Studio", "MacBook Pro 14\"", "MacBook Pro 16\"", "MacBook Air M2",
            "iMac 24\"", "Mac mini M2", "Mac Pro", "MacBook Air M3",
            "iPhone 15 Pro", "iPhone 15 Pro Max", "iPhone 15", "iPhone 14 Pro",
            "iPad Pro 12.9\"", "iPad Pro 11\"", "iPad Air", "iPad mini",
            "Apple Vision Pro"
        ]
        
        let users = [
            "John Smith", "Sarah Johnson", "Mike Chen", "Emily Davis",
            "Alex Wilson", "Chris Taylor", "Jordan Lee", "Sam Brown",
            nil, nil
        ]
        
        let platforms: [PlatformType] = [.macOS, .macOS, .macOS, .iOS, .iOS, .iPadOS, .visionOS]
        
        for i in 0..<min(count, 150) {
            let platform = platforms[i % platforms.count]
            let deviceName = deviceNames[i % deviceNames.count]
            let user = users[i % users.count]
            
            let item = DeviceListItem(
                id: UUID().uuidString,
                name: "\(deviceName) \(i + 1)",
                serialNumber: generateSerialNumber(),
                model: deviceName,
                modelIdentifier: generateModelIdentifier(for: deviceName),
                osVersion: generateOSVersion(for: platform),
                assignedUser: user,
                lastCheckIn: generateCheckInDate(),
                isManaged: true,
                isSupervised: Bool.random(),
                platform: platform
            )
            items.append(item)
        }
        
        return items
    }
    
    private func generateSerialNumber() -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<12).map { _ in chars.randomElement()! })
    }
    
    private func generateOSVersion(for platform: PlatformType) -> String {
        switch platform {
        case .macOS:
            return ["15.2", "15.1", "15.0", "14.7", "14.6"].randomElement()!
        case .iOS:
            return ["18.2", "18.1", "18.0", "17.7", "17.6"].randomElement()!
        case .iPadOS:
            return ["18.2", "18.1", "18.0", "17.7"].randomElement()!
        case .visionOS:
            return ["2.2", "2.1", "2.0", "1.2"].randomElement()!
        case .all:
            return "N/A"
        }
    }
    
    private func generateCheckInDate() -> Date {
        let daysAgo = Double.random(in: 0...30)
        return Date().addingTimeInterval(-daysAgo * 24 * 60 * 60)
    }
    
    private func generateModelIdentifier(for model: String) -> String {
        let identifiers: [String: String] = [
            "Mac Studio": "Mac13,2",
            "MacBook Pro 14\"": "Mac15,3",
            "MacBook Pro 16\"": "Mac15,7",
            "MacBook Air M2": "Mac14,2",
            "MacBook Air M3": "Mac15,12",
            "iMac 24\"": "Mac15,4",
            "Mac mini M2": "Mac14,3",
            "Mac Pro": "Mac14,8",
            "iPhone 15 Pro": "iPhone16,1",
            "iPhone 15 Pro Max": "iPhone16,2",
            "iPhone 15": "iPhone15,4",
            "iPhone 14 Pro": "iPhone15,2",
            "iPad Pro 12.9\"": "iPad14,5",
            "iPad Pro 11\"": "iPad14,3",
            "iPad Air": "iPad13,16",
            "iPad mini": "iPad14,1",
            "Apple Vision Pro": "RealityDevice14,1"
        ]
        return identifiers[model] ?? "Unknown"
    }
}

// MARK: - Health Device List Row

struct HealthDeviceListRow: View {
    let device: DeviceListItem
    let healthItem: HealthNavigationItem
    var isLoading: Bool = false
    let onTap: () -> Void
    
    @State private var isHovered: Bool = false
    
    private var statusColor: Color {
        healthItem.segmentType.color
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Device icon with status indicator
                ZStack(alignment: .bottomTrailing) {
                    DeviceIconView(
                        modelIdentifier: device.modelIdentifier,
                        modelName: device.model,
                        size: 48
                    )
                    
                    // Status indicator dot
                    Circle()
                        .fill(statusColor)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle()
                                .stroke(Color(white: 0.1), lineWidth: 2)
                        )
                        .offset(x: 2, y: 2)
                }
                
                // Device info
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(device.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        
                        if device.isSupervised {
                            healthStatusBadge("Supervised", color: .blue)
                        }
                        if device.isManaged {
                            healthStatusBadge("Managed", color: .green)
                        }
                    }
                    
                    HStack(spacing: 16) {
                        healthInfoLabel(icon: "number", text: device.serialNumber)
                        healthInfoLabel(icon: "desktopcomputer", text: device.model)
                        healthInfoLabel(icon: "gear", text: "\(device.platform.rawValue) \(device.osVersion)")
                    }
                }
                
                Spacer()
                
                // Assigned user and check-in time
                VStack(alignment: .trailing, spacing: 6) {
                    if let user = device.assignedUser {
                        HStack(spacing: 6) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 10))
                            Text(user)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.8))
                    } else {
                        Text("Unassigned")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    
                    if let checkIn = device.lastCheckIn {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                            Text(healthRelativeTimeString(from: checkIn))
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.gray)
                    }
                }
                
                // Loading spinner or chevron
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 20, height: 20)
                        .padding(.leading, 8)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.gray)
                        .padding(.leading, 8)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(isHovered ? 0.08 : 0.03))
                    .background(.ultraThinMaterial.opacity(0.3))
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isHovered ? statusColor.opacity(0.3) : Color.white.opacity(0.05),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
    
    private func healthStatusBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color))
    }
    
    private func healthInfoLabel(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 12))
                .lineLimit(1)
        }
        .foregroundColor(.gray)
    }
    
    private func healthRelativeTimeString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Health Filtered - Compliant") {
    @Previewable @State var path = NavigationPath()
    
    let mockMetric = HealthMetricData(
        type: .checkedIn,
        compliantCount: 5420,
        nonCompliantCount: 489,
        unknownCount: 98
    )
    
    let healthItem = HealthNavigationItem(
        metricType: .checkedIn,
        segmentType: .compliant,
        metricData: mockMetric
    )
    
    HealthFilteredDeviceListView(
        healthItem: healthItem,
        navigationPath: $path
    )
    .frame(width: 1200, height: 800)
}

#Preview("Health Filtered - Non-Compliant") {
    @Previewable @State var path = NavigationPath()
    
    let mockMetric = HealthMetricData(
        type: .encrypted,
        compliantCount: 5650,
        nonCompliantCount: 287,
        unknownCount: 70
    )
    
    let healthItem = HealthNavigationItem(
        metricType: .encrypted,
        segmentType: .nonCompliant,
        metricData: mockMetric
    )
    
    HealthFilteredDeviceListView(
        healthItem: healthItem,
        navigationPath: $path
    )
    .frame(width: 1200, height: 800)
}

#Preview("Health Filtered - Unknown") {
    @Previewable @State var path = NavigationPath()
    
    let mockMetric = HealthMetricData(
        type: .upToDate,
        compliantCount: 4870,
        nonCompliantCount: 1039,
        unknownCount: 98
    )
    
    let healthItem = HealthNavigationItem(
        metricType: .upToDate,
        segmentType: .unknown,
        metricData: mockMetric
    )
    
    HealthFilteredDeviceListView(
        healthItem: healthItem,
        navigationPath: $path
    )
    .frame(width: 1200, height: 800)
}
#endif
