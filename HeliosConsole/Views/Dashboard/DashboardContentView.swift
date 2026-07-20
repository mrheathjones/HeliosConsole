//
//  DashboardContentView.swift
//  Helios
//
//  Main dashboard content with health scorecard, device counts, and search
//

import SwiftUI
// AppKit removed - using pure SwiftUI

// PlatformType is defined in Models/PlatformType.swift

// MARK: - Health Navigation Item

struct HealthNavigationItem: Hashable {
    let metricType: HealthMetricType
    let segmentType: HealthSegmentType
    let metricData: HealthMetricData
    
    var title: String {
        switch segmentType {
        case .compliant:
            return metricType.compliantLabel
        case .nonCompliant:
            return metricType.nonCompliantLabel
        case .unknown:
            return metricType.unknownLabel
        }
    }
    
    var deviceCount: Int {
        switch segmentType {
        case .compliant:
            return metricData.compliantCount
        case .nonCompliant:
            return metricData.nonCompliantCount
        case .unknown:
            return metricData.unknownCount
        }
    }
    
    var percentageDisplay: Int {
        switch segmentType {
        case .compliant:
            return metricData.compliantPercentageDisplay
        case .nonCompliant:
            return metricData.nonCompliantPercentageDisplay
        case .unknown:
            return metricData.unknownPercentageDisplay
        }
    }
}

// MARK: - Responsive Grid Helper

/// Calculates responsive column count and compact mode from available width.
/// Used by both the health scorecard and managed devices grids.
private struct ResponsiveGridConfig {
    let columns: [GridItem]
    let compactMode: Bool
    let columnCount: Int
    
    /// Calculate layout for the health scorecard (5 items)
    static func healthGrid(for width: CGFloat) -> ResponsiveGridConfig {
        let spacing: CGFloat = 16
        let compactSpacing: CGFloat = 12
        
        // Calculate available card width at each column count
        let widthAt5 = (width - (4 * spacing)) / 5
        let widthAt4 = (width - (3 * spacing)) / 4
        let widthAt3 = (width - (2 * spacing)) / 3
        let widthAt2 = (width - spacing) / 2
        
        let idealMin: CGFloat = 200
        let compactMin: CGFloat = 160
        
        let (count, compact): (Int, Bool) = {
            if widthAt5 >= idealMin { return (5, false) }
            if widthAt5 >= compactMin { return (5, true) }
            if widthAt4 >= idealMin  { return (4, false) }
            if widthAt4 >= compactMin { return (4, true) }
            if widthAt3 >= idealMin  { return (3, false) }
            if widthAt3 >= compactMin { return (3, true) }
            if widthAt2 >= compactMin { return (2, true) }
            return (1, true)
        }()
        
        let s = compact ? compactSpacing : spacing
        let cols = Array(repeating: GridItem(.flexible(), spacing: s), count: count)
        return ResponsiveGridConfig(columns: cols, compactMode: compact, columnCount: count)
    }
    
    /// Calculate layout for the device count cards (4 items)
    static func devicesGrid(for width: CGFloat) -> ResponsiveGridConfig {
        let spacing: CGFloat = 16
        let compactSpacing: CGFloat = 12
        
        let widthAt4 = (width - (3 * spacing)) / 4
        let widthAt3 = (width - (2 * spacing)) / 3
        let widthAt2 = (width - spacing) / 2
        
        let idealMin: CGFloat = 180
        let compactMin: CGFloat = 140
        
        let (count, compact): (Int, Bool) = {
            if widthAt4 >= idealMin  { return (4, false) }
            if widthAt4 >= compactMin { return (4, true) }
            if widthAt3 >= idealMin  { return (3, false) }
            if widthAt3 >= compactMin { return (3, true) }
            if widthAt2 >= compactMin { return (2, true) }
            return (1, true)
        }()
        
        let s = compact ? compactSpacing : spacing
        let cols = Array(repeating: GridItem(.flexible(), spacing: s), count: count)
        return ResponsiveGridConfig(columns: cols, compactMode: compact, columnCount: count)
    }
}

// MARK: - Dashboard Content View

struct DashboardContentView: View {
    @Bindable var viewModel: DashboardViewModel
    @Binding var isInNestedView: Bool
    var initialDeviceCounts: DeviceCounts = DeviceCounts()
    
    @State private var searchText: String = ""
    @State private var navigationPath = NavigationPath()
    @State private var hasSearched: Bool = false
    @State private var searchResults: [UnifiedSearchResult] = []
    @State private var isSearching: Bool = false
    @State private var searchError: String?
    
    // Unified search service for computers and mobile devices
    @StateObject private var unifiedSearchService = UnifiedDeviceSearchService()
    
    // Inventory services for device counts
    @StateObject private var computerInventoryService = ComputerInventoryService()
    @StateObject private var mobileDeviceService = MobileDeviceInventoryService()
    
    // Cache references for observing changes
    @ObservedObject private var computerCache = ComputerInventoryCache.shared
    @ObservedObject private var mobileCache = MobileDeviceInventoryCache.shared
    @ObservedObject private var healthCalculator = HealthMetricsCalculator.shared
    
    @FocusState private var isSearchFocused: Bool
    
    // Device counts - populated from API or initial values
    @State private var deviceCounts: [PlatformType: Int] = [
        .macOS: 0,
        .iOS: 0,
        .iPadOS: 0,
        .visionOS: 0
    ]
    
    // Track if we've loaded the inventory
    @State private var hasLoadedInventory: Bool = false
    
    // Health metrics - computed from real inventory data
    private var healthMetrics: [HealthMetricData] {
        if healthCalculator.healthMetrics.isEmpty {
            // Return placeholder data while calculating
            return [
                HealthMetricData(type: .checkedIn, compliantCount: 0, nonCompliantCount: 0, unknownCount: 0),
                HealthMetricData(type: .protected, compliantCount: 0, nonCompliantCount: 0, unknownCount: 0),
                HealthMetricData(type: .encrypted, compliantCount: 0, nonCompliantCount: 0, unknownCount: 0),
                HealthMetricData(type: .secured, compliantCount: 0, nonCompliantCount: 0, unknownCount: 0),
                HealthMetricData(type: .upToDate, compliantCount: 0, nonCompliantCount: 0, unknownCount: 0)
            ]
        }
        return healthCalculator.healthMetrics
    }
    
    private var viewTitle: String {
        hasSearched ? "Device Search" : "Dashboard"
    }
    
    private var totalDeviceCount: Int {
        deviceCounts.values.reduce(0, +)
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                AnimatedBackgroundView(animate: .constant(true))
                
                VStack(spacing: 0) {
                    headerSection
                    toolbarSection
                    
                    if hasSearched {
                        searchResultsSection
                    } else {
                        dashboardContent
                    }
                }
            }
            .navigationDestination(for: Computer.self) { computer in
                DeviceView(computer: computer)
            }
            .navigationDestination(for: MobileDevice.self) { device in
                MobileDeviceView(device: device)
            }
            .navigationDestination(for: PlatformType.self) { platform in
                DeviceListView(platform: platform, navigationPath: $navigationPath)
            }
            .navigationDestination(for: HealthNavigationItem.self) { item in
                HealthFilteredDeviceListView(
                    healthItem: item,
                    navigationPath: $navigationPath
                )
            }
        }
        .task {
            await loadComputerInventory()
        }
        .onChange(of: computerCache.totalCount) { _, newValue in
            // Update macOS count when cache changes
            if newValue > 0 {
                deviceCounts[.macOS] = newValue
            }
        }
        .onChange(of: mobileCache.iOSCount) { _, newValue in
            deviceCounts[.iOS] = newValue
        }
        .onChange(of: mobileCache.iPadOSCount) { _, newValue in
            deviceCounts[.iPadOS] = newValue
        }
        .onChange(of: mobileCache.visionOSCount) { _, newValue in
            deviceCounts[.visionOS] = newValue
        }
        .onChange(of: navigationPath.count) { oldValue, newValue in
            withAnimation(.easeInOut(duration: 0.2)) {
                isInNestedView = newValue > 0 || hasSearched
            }
        }
        .onChange(of: hasSearched) { oldValue, newValue in
            withAnimation(.easeInOut(duration: 0.2)) {
                isInNestedView = navigationPath.count > 0 || newValue
            }
        }
    }
    
    // MARK: - Header Section
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool {
        colorScheme == .dark
    }
    
    private var headerSection: some View {
        HStack(alignment: .center) {
            HStack(spacing: 16) {
                if hasSearched {
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            hasSearched = false
                            searchResults = []
                            searchText = ""
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.1))
                                .frame(width: 36, height: 36)
                            
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(.plain)
                }
                
                Text(viewTitle)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            // Refresh button
            Button {
                // TODO: Implement refresh action
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
        }
        .padding(.horizontal, 40)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .background(Color.black.opacity(0.3))
    }
    
    // MARK: - Toolbar Section
    
    private var toolbarSection: some View {
        HStack(spacing: 16) {
            Spacer()
            
            // Search bar
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                    
                    TextField("", text: $searchText, prompt: Text("Search by name or serial...")
                        .foregroundColor(.gray.opacity(0.6)))
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .focused($isSearchFocused)
                        .onSubmit {
                            performSearch()
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
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: 320)
                .background(Color.white.opacity(0.05))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSearchFocused ? Color.blue.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                )
                
                Button(action: performSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            LinearGradient(
                                colors: [Color.blue, Color.cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(10)
                }
                .buttonStyle(ScaleButtonStyle())
            }
            .animation(.easeInOut(duration: 0.2), value: searchText.isEmpty)
            .animation(.easeInOut(duration: 0.2), value: isSearchFocused)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.15))
    }
    
    // MARK: - Dashboard Content
    
    private var dashboardContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // features domain: healthScorecard.enabled hides the whole
                // scorecard section.
                if MDMConfigurationManager.shared.configuration
                    .features?.effectiveHealthScorecard.effectiveEnabled != false {
                    environmentHealthSection
                }
                managedDevicesSection
            }
            .padding(40)
        }
    }

    /// Platforms whose dashboard device-count card the features domain
    /// allows (computers.showDashboardCard + mobileDevices.showDashboardCards
    /// per platform; all default true).
    private var visibleDashboardPlatforms: [PlatformType] {
        let features = MDMConfigurationManager.shared.configuration.features
        let mobileCards = features?.effectiveMobileDevices.effectiveShowDashboardCards
        return PlatformType.displayCases.filter { platform in
            switch platform {
            case .macOS:
                return features?.effectiveComputers.effectiveShowDashboardCard ?? true
            case .iOS:
                return mobileCards?.effectiveIOS ?? true
            case .iPadOS:
                return mobileCards?.effectiveIPadOS ?? true
            case .visionOS:
                return mobileCards?.effectiveVisionOS ?? true
            default:
                return true
            }
        }
    }
    
    // MARK: - Environment Health Scorecard Section
    
    private var environmentHealthSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Section header
            HStack(spacing: 12) {
                Image(systemName: "heart.text.square")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .mint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("Environment Health Scorecard")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                let overallHealth = calculateOverallHealth()
                HStack(spacing: 8) {
                    Circle()
                        .fill(healthColor(for: overallHealth))
                        .frame(width: 10, height: 10)
                    
                    Text("\(Int(overallHealth))% Overall Health")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)
            }
            
            missingSectionsBanner
            unmatchedSitesBanner

            // Responsive health cards grid — self-sizing via preference key
            ResponsiveHealthGrid(
                metrics: healthMetrics,
                onSegmentTap: { metric, segmentType in
                    let item = HealthNavigationItem(
                        metricType: metric.type,
                        segmentType: segmentType,
                        metricData: metric
                    )
                    navigationPath.append(item)
                }
            )
        }
    }
    
    /// Names metrics that could not be evaluated because the Jamf inventory
    /// sections they depend on are not being requested. Without this a missing
    /// section reads as "every device fails" — the failure mode that made
    /// Protected report 1% when APPLICATIONS was absent from the profile.
    @ViewBuilder
    private var missingSectionsBanner: some View {
        let gaps = healthCalculator.metricDataGaps
        if !gaps.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.orange)

                    Text("\(gaps.count) metric\(gaps.count == 1 ? "" : "s") cannot be evaluated — required inventory data is not being fetched")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)

                    Spacer(minLength: 0)
                }

                ForEach(gaps) { gap in
                    Text("• \(gap.metric.rawValue) (\(gap.platform.rawValue)) needs \(gap.missingSections.joined(separator: ", ")) — add to \(gap.configKey)")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 23)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )
            .cornerRadius(8)
        }
    }

    /// Names the Jamf sites that matched no Protected/Secured rule. Those devices
    /// score Unknown rather than silently passing, so the admin needs to see which
    /// sites are missing rules — this list is the exact input for configuring them.
    /// Rendered in-app deliberately: managed Macs often ship a logging profile that
    /// drops third-party NSLog, so a Console-only diagnostic is not dependable.
    @ViewBuilder
    private var unmatchedSitesBanner: some View {
        let sites = healthCalculator.unmatchedSiteCounts
        if !sites.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.yellow)

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(sites.count) site\(sites.count == 1 ? "" : "s") have no Protected or Secured requirements defined")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)

                    Text("Scored Unknown because there is nothing to evaluate them against: \(sites.map { "\($0.site) (\($0.count))" }.joined(separator: ", ")).")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.yellow.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.yellow.opacity(0.25), lineWidth: 1)
            )
            .cornerRadius(8)
        }
    }

    private func calculateOverallHealth() -> Double {
        guard !healthMetrics.isEmpty else { return 0 }
        let totalPercentage = healthMetrics.reduce(0.0) { $0 + $1.percentage }
        return totalPercentage / Double(healthMetrics.count)
    }
    
    private func healthColor(for percentage: Double) -> Color {
        HealthThresholds.color(forPercentage: percentage)
    }
    
    // MARK: - Managed Devices Section
    
    private var managedDevicesSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("Managed Devices")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button {
                    navigationPath.append(PlatformType.all)
                } label: {
                    HStack(spacing: 6) {
                        Text("\(totalDeviceCount.formatted()) total")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.gray)
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.gray.opacity(0.5))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(ScaleButtonStyle())
            }
            
            // Responsive device cards grid — self-sizing via preference key.
            // Platform cards are gated by the features domain (see
            // visibleDashboardPlatforms).
            ResponsiveDeviceGrid(
                platforms: visibleDashboardPlatforms,
                deviceCounts: deviceCounts,
                isLoadingPlatform: isLoadingPlatform,
                onPlatformTap: { platform in
                    navigationPath.append(platform)
                }
            )
        }
    }
    
    private func isLoadingPlatform(_ platform: PlatformType) -> Bool {
        switch platform {
        case .macOS:
            return computerInventoryService.isLoading
        case .iOS, .iPadOS, .visionOS:
            return mobileDeviceService.isLoading
        case .all:
            return computerInventoryService.isLoading || mobileDeviceService.isLoading
        }
    }
    
    // MARK: - Search Results Section
    
    private var searchResultsSection: some View {
        VStack(spacing: 0) {
            // Status bar
            HStack(spacing: 12) {
                if isSearching {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 16, height: 16)
                    Text("Searching...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                } else if let error = searchError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.orange)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("\(searchResults.count) device\(searchResults.count == 1 ? "" : "s") found")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                }
                
                Spacer()
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 16)
            .background(Color.black.opacity(0.2))
            
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 1)
            
            if isSearching {
                // Loading state
                VStack(spacing: 20) {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Searching Jamf Pro...")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.gray)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searchResults.isEmpty {
                // Empty state
                VStack(spacing: 20) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48, weight: .light))
                        .foregroundColor(.gray.opacity(0.5))
                    Text(searchError ?? "No devices found")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.gray)
                    Text("Try searching by device name or serial number")
                        .font(.system(size: 14))
                        .foregroundColor(.gray.opacity(0.7))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Results list
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(searchResults) { result in
                            SearchResultRow(result: result) {
                                // Navigate to appropriate detail view
                                switch result {
                                case .computer(let computer):
                                    navigationPath.append(computer)
                                case .mobileDevice(let device):
                                    navigationPath.append(device)
                                }
                            }
                        }
                    }
                    .padding(40)
                }
            }
        }
    }
    
    // MARK: - Actions
    
    @MainActor
    private func loadComputerInventory() async {
        // Use initial counts if provided (from loading screen)
        if initialDeviceCounts.total > 0 && !hasLoadedInventory {
            deviceCounts[.macOS] = initialDeviceCounts.macOS
            deviceCounts[.iOS] = initialDeviceCounts.iOS
            deviceCounts[.iPadOS] = initialDeviceCounts.iPadOS
            deviceCounts[.visionOS] = initialDeviceCounts.visionOS
            hasLoadedInventory = true
            
            // Calculate health metrics from cached data
            healthCalculator.recalculateMetrics()
            
            NSLog("📦 Dashboard: Using initial device counts - macOS: %d, iOS: %d, iPadOS: %d, visionOS: %d",
                  initialDeviceCounts.macOS, initialDeviceCounts.iOS, initialDeviceCounts.iPadOS, initialDeviceCounts.visionOS)
            return
        }
        
        // Skip if already loaded and caches are valid
        if hasLoadedInventory && computerCache.hasCachedData && mobileCache.hasCachedData {
            deviceCounts[.macOS] = computerCache.totalCount
            deviceCounts[.iOS] = mobileCache.iOSCount
            deviceCounts[.iPadOS] = mobileCache.iPadOSCount
            deviceCounts[.visionOS] = mobileCache.visionOSCount
            
            // Ensure health metrics are calculated
            if healthCalculator.healthMetrics.isEmpty {
                healthCalculator.recalculateMetrics()
            }
            
            NSLog("📦 Dashboard: Using cached device counts")
            return
        }
        
        NSLog("📥 Dashboard: Loading device inventory...")
        
        // Fetch both in parallel
        async let computersTask: () = computerInventoryService.fetchAllComputers()
        async let mobilesTask: () = mobileDeviceService.fetchAllDevices()
        
        _ = await (computersTask, mobilesTask)
        
        // Update counts
        deviceCounts[.macOS] = computerInventoryService.totalCount
        deviceCounts[.iOS] = mobileDeviceService.iOSCount
        deviceCounts[.iPadOS] = mobileDeviceService.iPadOSCount
        deviceCounts[.visionOS] = mobileDeviceService.visionOSCount
        hasLoadedInventory = true
        
        // Health metrics are automatically calculated via cache observers in HealthMetricsCalculator
        
        NSLog("✅ Dashboard: Loaded device counts - macOS: %d, iOS: %d, iPadOS: %d, visionOS: %d",
              deviceCounts[.macOS] ?? 0, deviceCounts[.iOS] ?? 0, deviceCounts[.iPadOS] ?? 0, deviceCounts[.visionOS] ?? 0)
    }
    
    private func performSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        
        isSearching = true
        searchError = nil
        
        Task {
            // Use unified search service to search both computers and mobile devices
            await unifiedSearchService.searchDevices(query: query)
            
            // Get results from the service
            searchResults = unifiedSearchService.searchResults
            searchError = unifiedSearchService.errorMessage
            
            NSLog("✅ Unified search complete: %d total results (computers: %d, mobile: %d)",
                  searchResults.count,
                  unifiedSearchService.computerResults.count,
                  unifiedSearchService.mobileDeviceResults.count)
            
            withAnimation(.easeInOut(duration: 0.3)) {
                hasSearched = true
                isSearching = false
            }
        }
    }
}

// MARK: - Width-Reading Container

/// Measures the available width of its parent *before* the content renders,
/// then passes it to a content builder. The GeometryReader is constrained to
/// zero height so it never steals vertical space — the actual content (LazyVGrid)
/// determines its own intrinsic height normally.
private struct WidthReader<Content: View>: View {
    @ViewBuilder var content: (_ width: CGFloat) -> Content
    
    @State private var measuredWidth: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Zero-height ruler that stretches to full available width
            GeometryReader { geo in
                Color.clear
                    .onAppear { measuredWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, newWidth in
                        measuredWidth = newWidth
                    }
            }
            .frame(height: 0)
            
            // Only render the grid once we have a valid measurement
            if measuredWidth > 0 {
                content(measuredWidth)
            }
        }
    }
}

// MARK: - Responsive Health Grid

/// Measures available width first, then renders the LazyVGrid with the correct
/// column count. The grid is the intrinsic-height element so the parent ScrollView
/// sizes correctly — no overlap.
private struct ResponsiveHealthGrid: View {
    let metrics: [HealthMetricData]
    let onSegmentTap: (HealthMetricData, HealthSegmentType) -> Void
    
    var body: some View {
        WidthReader { width in
            let config = ResponsiveGridConfig.healthGrid(for: width)
            
            LazyVGrid(columns: config.columns, spacing: config.compactMode ? 12 : 16) {
                ForEach(metrics) { metric in
                    HealthScorecardCard(
                        metric: metric,
                        onSegmentTap: { segmentType in
                            onSegmentTap(metric, segmentType)
                        },
                        compactMode: config.compactMode
                    )
                }
            }
        }
    }
}

// MARK: - Responsive Device Grid

/// Measures available width first, then renders the device card grid.
private struct ResponsiveDeviceGrid: View {
    let platforms: [PlatformType]
    let deviceCounts: [PlatformType: Int]
    let isLoadingPlatform: (PlatformType) -> Bool
    let onPlatformTap: (PlatformType) -> Void

    var body: some View {
        WidthReader { width in
            let config = ResponsiveGridConfig.devicesGrid(for: width)

            LazyVGrid(columns: config.columns, spacing: config.compactMode ? 12 : 16) {
                ForEach(platforms) { platform in
                    DeviceCountCard(
                        platform: platform,
                        count: deviceCounts[platform] ?? 0,
                        isLoading: isLoadingPlatform(platform),
                        compactMode: config.compactMode
                    ) {
                        onPlatformTap(platform)
                    }
                }
            }
        }
    }
}

// MARK: - Device Count Card

struct DeviceCountCard: View {
    let platform: PlatformType
    let count: Int
    let isLoading: Bool
    var compactMode: Bool
    let action: () -> Void
    
    init(platform: PlatformType, count: Int, isLoading: Bool = false, compactMode: Bool = false, action: @escaping () -> Void) {
        self.platform = platform
        self.count = count
        self.isLoading = isLoading
        self.compactMode = compactMode
        self.action = action
    }
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered: Bool = false
    
    private var isDark: Bool {
        colorScheme == .dark
    }
    
    // Adaptive sizes
    private var iconBoxSize: CGFloat { compactMode ? 38 : 48 }
    private var iconFontSize: CGFloat { compactMode ? 18 : 22 }
    private var countFontSize: CGFloat { compactMode ? 22 : 28 }
    private var platformFontSize: CGFloat { compactMode ? 12 : 14 }
    private var cardPadding: CGFloat { compactMode ? 14 : 20 }
    private var cornerRadius: CGFloat { compactMode ? 12 : 16 }
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: compactMode ? 10 : 16) {
                // Platform icon
                ZStack {
                    RoundedRectangle(cornerRadius: compactMode ? 8 : 12)
                        .fill(
                            LinearGradient(
                                colors: platform.gradientColors.map { $0.opacity(0.2) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: iconBoxSize, height: iconBoxSize)
                    
                    Image(systemName: platform.icon)
                        .font(.system(size: iconFontSize, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: platform.gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                // Count and platform name
                VStack(alignment: .leading, spacing: 4) {
                    if isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(.white)
                            Text("Loading...")
                                .font(.system(size: compactMode ? 12 : 14))
                                .foregroundColor(.gray)
                        }
                        .frame(height: compactMode ? 26 : 34)
                    } else {
                        Text(count.formatted())
                            .font(.system(size: countFontSize, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    Text(platform.rawValue)
                        .font(.system(size: platformFontSize, weight: .medium))
                        .foregroundColor(.gray)
                }
                
                Spacer(minLength: 0)
                
                // View all link
                HStack(spacing: 6) {
                    Text("View all")
                        .font(.system(size: compactMode ? 11 : 12, weight: .medium))
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: compactMode ? 9 : 10, weight: .semibold))
                }
                .foregroundColor(platform.color)
                .opacity(isHovered ? 1 : 0.7)
            }
            .padding(cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: compactMode ? 150 : 180)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white.opacity(isHovered ? 0.06 : 0.03))
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        isHovered
                            ? platform.color.opacity(0.3)
                            : Color.white.opacity(0.05),
                        lineWidth: 1
                    )
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Dashboard") {
    @Previewable @State var isNested = false
    DashboardContentView(viewModel: DashboardViewModel(), isInNestedView: $isNested)
        .frame(width: 1400, height: 900)
}

#Preview("Dashboard - Narrow") {
    @Previewable @State var isNested = false
    DashboardContentView(viewModel: DashboardViewModel(), isInNestedView: $isNested)
        .frame(width: 940, height: 800)
}
#endif
