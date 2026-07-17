//
//  DeviceListView.swift
//  Helios
//
//  Displays a paginated list of all devices for a specific platform type
//

import SwiftUI
// AppKit removed - using pure SwiftUI

struct DeviceListView: View {
    let platform: PlatformType
    @Binding var navigationPath: NavigationPath
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText: String = ""
    @State private var sortOrder: DeviceSortOrder = .nameAscending
    @State private var isLoading: Bool = false
    @State private var devices: [DeviceListItem] = []
    @State private var loadError: String?
    
    // Platform filter (only used when platform == .all)
    @State private var selectedPlatformFilter: PlatformType = .all
    
    // Pagination state
    @State private var currentPage: Int = 1
    @State private var itemsPerPage: Int = 25
    @State private var totalDeviceCount: Int = 0
    
    @FocusState private var isSearchFocused: Bool
    
    // Services for fetching devices
    @StateObject private var computerInventoryService = ComputerInventoryService()
    @StateObject private var mobileDeviceService = MobileDeviceInventoryService()
    
    // Mobile device detail fetching
    @State private var isLoadingDeviceDetail: Bool = false
    @State private var loadingDeviceId: String?
    
    private let itemsPerPageOptions = [10, 25, 50, 100]
    
    // Show platform filter only when viewing all devices
    private var showPlatformFilter: Bool {
        platform == .all
    }
    
    var body: some View {
        ZStack {
            AnimatedBackgroundView(animate: .constant(true))
            
            VStack(spacing: 0) {
                headerSection
                toolbarSection
                
                // Error banner
                if let error = loadError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Error loading devices: \(error)")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        Spacer()
                        Button("Retry") {
                            loadDevices()
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.1))
                }
                
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
        
        // Apply platform filter if showing all devices
        if platform == .all && selectedPlatformFilter != .all {
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
        (currentPage - 1) * itemsPerPage + 1
    }
    
    private var endItemIndex: Int {
        min(currentPage * itemsPerPage, filteredDevices.count)
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack(alignment: .center, spacing: 20) {
            
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: platform.gradientColors.map { $0.opacity(0.2) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: platform.icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: platform.gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(platform == .all ? "All Devices" : "\(platform.rawValue) Devices")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("\(filteredDevices.count.formatted()) devices")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            // Platform filter (only for All Devices view)
            if showPlatformFilter {
                platformFilterMenu
            }
            
            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray)
                
                TextField("", text: $searchText, prompt: Text("Search devices...")
                    .foregroundColor(.gray.opacity(0.6)))
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .focused($isSearchFocused)
                    .onChange(of: searchText) { _, _ in
                        currentPage = 1
                    }
                
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
        .padding(.vertical, 24)
        .background(Color.black.opacity(0.3))
    }
    
    // MARK: - Platform Filter Menu
    
    private var platformFilterMenu: some View {
        Menu {
            ForEach(PlatformType.filterCases) { filterPlatform in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedPlatformFilter = filterPlatform
                    }
                } label: {
                    HStack {
                        Image(systemName: filterPlatform.icon)
                        Text(filterPlatform == .all ? "All Platforms" : filterPlatform.rawValue)
                        if selectedPlatformFilter == filterPlatform {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selectedPlatformFilter.icon)
                    .font(.system(size: 14))
                    .foregroundColor(selectedPlatformFilter.color)
                
                Text(selectedPlatformFilter == .all ? "All Platforms" : selectedPlatformFilter.rawValue)
                    .font(.system(size: 13, weight: .medium))
                
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selectedPlatformFilter == .all ? Color.white.opacity(0.05) : selectedPlatformFilter.color.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selectedPlatformFilter == .all ? Color.white.opacity(0.1) : selectedPlatformFilter.color.opacity(0.3), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
    }
    
    // MARK: - Toolbar Section
    
    private var toolbarSection: some View {
        HStack(spacing: 16) {
            if !searchText.isEmpty || (platform == .all && selectedPlatformFilter != .all) {
                Text("\(filteredDevices.count) of \(devices.count) shown")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Menu {
                ForEach(itemsPerPageOptions, id: \.self) { count in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            itemsPerPage = count
                        }
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
                .foregroundColor(.gray)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)
            }
            .menuStyle(.borderlessButton)
            
            Menu {
                ForEach(DeviceSortOrder.allCases) { order in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            sortOrder = order
                        }
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
                .foregroundColor(.gray)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)
            }
            .menuStyle(.borderlessButton)
            
            // Refresh button
            Button {
                loadDevices(forceRefresh: true)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
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
            .disabled(isLoading)
            .help("Refresh device list")
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.15))
    }
    
    // MARK: - Device List Section
    
    private var deviceListSection: some View {
        ZStack {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(paginatedDevices) { device in
                        DeviceListRow(
                            device: device,
                            platform: device.platform,
                            isLoading: isLoadingDeviceDetail && loadingDeviceId == device.id
                        ) {
                            handleDeviceTap(device)
                        }
                    }
                }
                .padding(32)
            }
            
            // Loading overlay when fetching device details
            if isLoadingDeviceDetail {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text("Loading device details...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(32)
                .background(Color.black.opacity(0.8))
                .cornerRadius(16)
            }
        }
    }
    
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
            throw NSError(domain: "DeviceList", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
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
            throw NSError(domain: "DeviceList", code: 401, userInfo: [NSLocalizedDescriptionKey: "Authentication failed"])
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
            throw NSError(domain: "DeviceList", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid device URL"])
        }
        
        NSLog("📥 DeviceListView: Fetching mobile device detail from %@", url.absoluteString)
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = NetworkTuning.connectionTimeout
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "DeviceList", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        NSLog("📥 DeviceListView: Mobile device detail response status %d", httpResponse.statusCode)
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            NSLog("❌ DeviceListView: Mobile device detail error: %@", errorMessage)
            throw NSError(domain: "DeviceList", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Device not found (HTTP \(httpResponse.statusCode))"])
        }
        
        let device = try JSONDecoder().decode(MobileDevice.self, from: data)
        return device
    }
    
    // MARK: - Pagination Footer
    
    private var paginationFooter: some View {
        HStack(spacing: 20) {
            Text("Showing \(startItemIndex)-\(endItemIndex) of \(filteredDevices.count)")
                .font(.system(size: 13))
                .foregroundColor(.gray)
            
            Spacer()
            
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentPage = 1
                    }
                } label: {
                    Image(systemName: "chevron.left.2")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(currentPage > 1 ? .white : .gray.opacity(0.4))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(currentPage > 1 ? 0.05 : 0.02))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(currentPage <= 1)
                
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentPage = max(1, currentPage - 1)
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(currentPage > 1 ? .white : .gray.opacity(0.4))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(currentPage > 1 ? 0.05 : 0.02))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(currentPage <= 1)
                
                pageNumbers
                
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentPage = min(totalPages, currentPage + 1)
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(currentPage < totalPages ? .white : .gray.opacity(0.4))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(currentPage < totalPages ? 0.05 : 0.02))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(currentPage >= totalPages)
                
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentPage = totalPages
                    }
                } label: {
                    Image(systemName: "chevron.right.2")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(currentPage < totalPages ? .white : .gray.opacity(0.4))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(currentPage < totalPages ? 0.05 : 0.02))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(currentPage >= totalPages)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
        .background(Color.black.opacity(0.3))
    }
    
    @ViewBuilder
    private var pageNumbers: some View {
        let visiblePages = calculateVisiblePages()
        
        HStack(spacing: 4) {
            ForEach(visiblePages, id: \.self) { page in
                if page == -1 {
                    Text("...")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                        .frame(width: 32, height: 32)
                } else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            currentPage = page
                        }
                    } label: {
                        Text("\(page)")
                            .font(.system(size: 13, weight: page == currentPage ? .semibold : .regular))
                            .foregroundColor(page == currentPage ? .white : .gray)
                            .frame(width: 32, height: 32)
                            .background(
                                page == currentPage
                                    ? Color.blue.opacity(0.3)
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
        if totalPages <= 7 {
            return Array(1...totalPages)
        }
        
        var pages: [Int] = []
        
        if currentPage <= 3 {
            pages = [1, 2, 3, 4, -1, totalPages]
        } else if currentPage >= totalPages - 2 {
            pages = [1, -1, totalPages - 3, totalPages - 2, totalPages - 1, totalPages]
        } else {
            pages = [1, -1, currentPage - 1, currentPage, currentPage + 1, -1, totalPages]
        }
        
        return pages
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
                .tint(.blue)
            Text("Loading devices...")
                .font(.system(size: 14))
                .foregroundColor(.gray)
            Spacer()
        }
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(platform.color.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: platform.icon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(platform.color.opacity(0.5))
            }
            
            VStack(spacing: 8) {
                Text(searchText.isEmpty && selectedPlatformFilter == .all ? "No Devices Found" : "No Results")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(searchText.isEmpty && selectedPlatformFilter == .all
                     ? "There are no \(platform.rawValue) devices enrolled."
                     : "No devices match your search criteria.")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            
            if !searchText.isEmpty || selectedPlatformFilter != .all {
                Button {
                    searchText = ""
                    selectedPlatformFilter = .all
                } label: {
                    Text("Clear Filters")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
        }
        .padding(40)
    }
    
    // MARK: - Load Devices
    
    private func loadDevices(forceRefresh: Bool = false) {
        isLoading = true
        currentPage = 1
        loadError = nil
        
        Task {
            await loadAllDevicesFromCache(forceRefresh: forceRefresh)
        }
    }
    
    @MainActor
    private func loadAllDevicesFromCache(forceRefresh: Bool = false) async {
        var allDevices: [DeviceListItem] = []
        
        // Determine what to load based on platform
        let needsComputers = platform == .macOS || platform == .all
        let needsMobileDevices = platform == .iOS || platform == .iPadOS || platform == .visionOS || platform == .all
        
        // Get computer cache
        let computerCache = ComputerInventoryCache.shared
        let mobileCache = MobileDeviceInventoryCache.shared
        
        // Load computers from cache if needed
        if needsComputers {
            if forceRefresh || !computerCache.hasCachedData {
                // Only fetch if forced or no cache - uses master API
                await computerInventoryService.fetchAllComputers(forceRefresh: forceRefresh)
            }
            
            if computerInventoryService.errorMessage == nil || computerCache.hasCachedData {
                // Use cache data (populated either now or at app launch)
                let computers = computerCache.computers
                let computerDevices = computers.map { computer in
                    DeviceListItem(
                        id: "computer-\(computer.id)",
                        originalId: computer.id,
                        name: computer.general?.name ?? "Unknown",
                        serialNumber: computer.hardware?.serialNumber ?? "N/A",
                        model: computer.hardware?.model ?? "Mac",
                        modelIdentifier: computer.hardware?.modelIdentifier,
                        osVersion: computer.operatingSystem?.version ?? "N/A",
                        assignedUser: computer.userAndLocation?.realname ?? computer.userAndLocation?.username ?? computer.general?.lastLoggedInUsernameBinary,
                        lastCheckIn: computer.lastContactTime,
                        isManaged: computer.isManaged,
                        isSupervised: computer.isSupervised,
                        platform: .macOS
                    )
                }
                allDevices.append(contentsOf: computerDevices)
            } else if let error = computerInventoryService.errorMessage {
                loadError = parseAPIError(error)
            }
        }
        
        // Load mobile devices from cache if needed
        if needsMobileDevices {
            if forceRefresh || !mobileCache.hasCachedData {
                // Only fetch if forced or no cache - uses master API
                await mobileDeviceService.fetchAllDevices(forceRefresh: forceRefresh)
            }
            
            if mobileDeviceService.errorMessage == nil || mobileCache.hasCachedData {
                // Use cache data (populated either now or at app launch)
                let mobileDevicesToAdd: [MobileDeviceInventoryItem]
                if platform == .all {
                    mobileDevicesToAdd = mobileCache.devices
                } else {
                    mobileDevicesToAdd = mobileCache.devices.filter { $0.platformType == platform }
                }
                
                let mobileListItems = mobileDevicesToAdd.map { device in
                    DeviceListItem(
                        id: "mobile-\(device.id ?? "unknown")",
                        originalId: device.id ?? "unknown",
                        name: device.displayName ?? "Unknown Device",
                        serialNumber: device.serialNumber ?? "N/A",
                        model: device.displayModel,
                        modelIdentifier: device.modelIdentifier,
                        osVersion: device.osVersion ?? "N/A",
                        assignedUser: device.assignedUser,
                        lastCheckIn: device.lastInventoryUpdate,
                        isManaged: device.isManaged,
                        isSupervised: device.isSupervised,
                        platform: device.platformType
                    )
                }
                allDevices.append(contentsOf: mobileListItems)
            } else if let error = mobileDeviceService.errorMessage, loadError == nil {
                loadError = parseAPIError(error)
            }
        }
        
        // Sort the combined list
        devices = sortDevices(allDevices)
        totalDeviceCount = devices.count
        isLoading = false
    }
    
    /// Parse API error JSON for cleaner display
    private func parseAPIError(_ error: String) -> String {
        // Try to extract meaningful message from JSON error
        if error.contains("INVALID_PRIVILEGE") {
            return "Permission denied. Please verify API client privileges in Jamf Pro."
        }
        
        // Try to parse JSON error
        if let data = error.data(using: .utf8) {
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errors = json["errors"] as? [[String: Any]],
                   let firstError = errors.first,
                   let code = firstError["code"] as? String,
                   let description = firstError["description"] as? String {
                    return "\(code): \(description)"
                }
            } catch {
                // Not JSON, return original
            }
        }
        
        return error
    }
    
    private func sortDevices(_ deviceList: [DeviceListItem]) -> [DeviceListItem] {
        deviceList.sorted { first, second in
            switch sortOrder {
            case .nameAscending:
                return first.name.localizedCompare(second.name) == .orderedAscending
            case .nameDescending:
                return first.name.localizedCompare(second.name) == .orderedDescending
            case .lastCheckIn:
                let firstDate = first.lastCheckIn ?? Date.distantPast
                let secondDate = second.lastCheckIn ?? Date.distantPast
                return firstDate > secondDate
            case .serialNumber:
                return first.serialNumber.localizedCompare(second.serialNumber) == .orderedAscending
            }
        }
    }
    
    private func sortOrderToAPIParams(_ order: DeviceSortOrder) -> (String, String) {
        switch order {
        case .nameAscending:
            return ("general.name", "asc")
        case .nameDescending:
            return ("general.name", "desc")
        case .lastCheckIn:
            return ("general.lastContactTime", "desc")
        case .serialNumber:
            return ("hardware.serialNumber", "asc")
        }
    }
    
}

// MARK: - Previews

#if DEBUG
#Preview("Device List - All with Filter") {
    @Previewable @State var path = NavigationPath()
    DeviceListView(platform: .all, navigationPath: $path)
        .frame(width: 1200, height: 800)
}
#endif
