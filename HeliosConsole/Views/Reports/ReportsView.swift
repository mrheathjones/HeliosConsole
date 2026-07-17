//
//  ReportsView.swift
//  Helios
//
//  Report Builder with saved reports and export functionality
//

import SwiftUI
import UniformTypeIdentifiers
import Combine

// MARK: - Filter Types

enum ReportFilterCategory: String, CaseIterable, Identifiable, Codable {
    case lastCheckIn = "Last Check-In"
    case supervision = "Supervision Status"
    case encryption = "Encryption"
    case osVersion = "OS Version"
    case model = "Device Model"
    case site = "Site"
    case applications = "Applications"
    case appleCare = "AppleCare"
    case softwareUpdates = "Software Updates"
    case staleDevices = "Stale Devices"
    case unmanaged = "Unmanaged"
    case protectCoverage = "Jamf Protect"
    case computerGroup = "Computer Group"
    case deviceGroup = "Device Group"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .lastCheckIn: return "clock.arrow.circlepath"
        case .supervision: return "lock.shield"
        case .encryption: return "lock.fill"
        case .osVersion: return "gear.badge"
        case .model: return "desktopcomputer"
        case .site: return "building.2"
        case .applications: return "app.badge"
        case .appleCare: return "checkmark.seal.fill"
        case .softwareUpdates: return "arrow.down.circle"
        case .staleDevices: return "clock.badge.exclamationmark"
        case .unmanaged: return "antenna.radiowaves.left.and.right.slash"
        case .protectCoverage: return "shield.lefthalf.filled"
        case .computerGroup: return "rectangle.3.group"
        case .deviceGroup: return "square.grid.3x3.fill"
        }
    }
    var color: Color {
        switch self {
        case .lastCheckIn: return .blue
        case .supervision: return .green
        case .encryption: return .orange
        case .osVersion: return .cyan
        case .model: return .indigo
        case .site: return .purple
        case .applications: return .pink
        case .appleCare: return .teal
        case .softwareUpdates: return .mint
        case .staleDevices: return .orange
        case .unmanaged: return .red
        case .protectCoverage: return .indigo
        case .computerGroup: return .blue
        case .deviceGroup: return .green
        }
    }
    var description: String {
        switch self {
        case .lastCheckIn: return "Filter by when devices last checked in"
        case .supervision: return "Filter by supervision status"
        case .encryption: return "Filter by FileVault/encryption status"
        case .osVersion: return "Filter by operating system version"
        case .model: return "Filter by device model"
        case .site: return "Filter by Jamf site assignment"
        case .applications: return "Filter by installed applications"
        case .appleCare: return "Filter by AppleCare coverage status"
        case .softwareUpdates: return "Filter by pending software updates"
        case .staleDevices: return "Cleanup: devices that have gone quiet (no check-in)"
        case .unmanaged: return "Cleanup: devices without active MDM management"
        case .protectCoverage: return "Cleanup: Jamf Protect agent coverage"
        case .computerGroup: return "Filter by computer smart/static group"
        case .deviceGroup: return "Filter by mobile device smart/static group"
        }
    }

    /// Height for the filter config overlay - some filters need more space
    var configOverlayHeight: CGFloat {
        switch self {
        case .computerGroup, .deviceGroup: return 540  // search + scrollable group list
        case .appleCare: return 520  // 5 options + info text needs more height
        case .softwareUpdates: return 480  // 4 options + info text
        case .protectCoverage: return 480  // 3 options + info text
        case .applications: return 460  // Has quick buttons
        case .site: return 440
        default: return 420
        }
    }
}

enum TimeRangeUnit: String, CaseIterable, Identifiable, Codable {
    case days = "Days", weeks = "Weeks", months = "Months", years = "Years"
    var id: String { rawValue }
    var seconds: TimeInterval {
        switch self {
        case .days: return 86400
        case .weeks: return 604800
        case .months: return 2592000
        case .years: return 31536000
        }
    }
}

enum TimeRangeComparison: String, CaseIterable, Identifiable, Codable {
    case within = "Within last", moreThan = "More than"
    var id: String { rawValue }
}

enum SupervisionFilter: String, CaseIterable, Identifiable, Codable {
    case all = "All Devices", supervised = "Supervised Only", unsupervised = "Unsupervised Only"
    var id: String { rawValue }
}

enum EncryptionFilter: String, CaseIterable, Identifiable, Codable {
    case all = "All Devices", encrypted = "Encrypted Only", notEncrypted = "Not Encrypted"
    var id: String { rawValue }
}

enum SiteFilterComparison: String, CaseIterable, Identifiable, Codable {
    case memberOf = "Member of"
    case notMemberOf = "Not member of"
    var id: String { rawValue }
}

enum ApplicationFilterType: String, CaseIterable, Identifiable, Codable {
    case hasApp = "Has Application"
    case missingApp = "Missing Application"
    var id: String { rawValue }
}

enum AppleCareFilter: String, CaseIterable, Identifiable, Codable {
    case all = "All Devices"
    case active = "Active Coverage"
    case expiringSoon = "Expiring Soon (90 days)"
    case expired = "Expired"
    case noCoverage = "No Coverage Data"
    var id: String { rawValue }
}

enum SoftwareUpdateFilter: String, CaseIterable, Identifiable, Codable {
    case all = "All Devices"
    case hasPendingUpdates = "Has Pending Updates"
    case upToDate = "Up to Date"
    case noUpdateData = "No Update Data"
    var id: String { rawValue }
}

// MARK: - Cleanup filters

enum StalenessLevel: String, CaseIterable, Identifiable, Codable {
    case over30 = "Over 30 days"
    case over90 = "Over 90 days"
    case over180 = "Over 180 days"
    case overOneYear = "Over 1 year"
    var id: String { rawValue }
    var days: Int {
        switch self {
        case .over30: return 30
        case .over90: return 90
        case .over180: return 180
        case .overOneYear: return 365
        }
    }
}

enum ManagedFilter: String, CaseIterable, Identifiable, Codable {
    case unmanagedOnly = "Unmanaged Only"
    case managedOnly = "Managed Only"
    var id: String { rawValue }
}

enum ProtectCoverageFilter: String, CaseIterable, Identifiable, Codable {
    case covered = "Has Protect Record"
    case notCovered = "Missing Protect Record"
    case protectStale = "Protect Stale"
    var id: String { rawValue }
}

// MARK: - Report Filter (Codable for persistence)

struct ReportFilter: Identifiable, Codable {
    let id: UUID
    let category: ReportFilterCategory
    var parameters: FilterParameters
    
    init(id: UUID = UUID(), category: ReportFilterCategory, parameters: FilterParameters) {
        self.id = id
        self.category = category
        self.parameters = parameters
    }
    
    enum FilterParameters: Codable {
        case lastCheckIn(comparison: TimeRangeComparison, value: Int, unit: TimeRangeUnit)
        case supervision(status: SupervisionFilter)
        case encryption(status: EncryptionFilter)
        case osVersion(version: String, comparison: String)
        case model(identifier: String)
        case site(name: String, comparison: SiteFilterComparison)
        case applications(type: ApplicationFilterType, appName: String)
        case appleCare(status: AppleCareFilter)
        case softwareUpdates(status: SoftwareUpdateFilter)
        case staleDevices(level: StalenessLevel)
        case unmanaged(status: ManagedFilter)
        case protectCoverage(status: ProtectCoverageFilter)
        case computerGroup(name: String)
        case deviceGroup(name: String)
    }
    
    var displayDescription: String {
        switch parameters {
        case .lastCheckIn(let c, let v, let u): return "\(c.rawValue) \(v) \(u.rawValue.lowercased())"
        case .supervision(let s): return s.rawValue
        case .encryption(let s): return s.rawValue
        case .osVersion(let v, let c): return "\(c) \(v)"
        case .model(let i): return i
        case .site(let s, let c): return "\(c.rawValue) \(s)"
        case .applications(let t, let n): return "\(t.rawValue): \(n)"
        case .appleCare(let s): return s.rawValue
        case .softwareUpdates(let s): return s.rawValue
        case .staleDevices(let l): return l.rawValue
        case .unmanaged(let s): return s.rawValue
        case .protectCoverage(let s): return s.rawValue
        case .computerGroup(let n): return n
        case .deviceGroup(let n): return n
        }
    }
}

// MARK: - Saved Report

struct SavedReport: Identifiable, Codable {
    let id: UUID
    var name: String
    var description: String
    var platforms: [String] // Store as strings for Codable
    var filters: [ReportFilter]
    // Devices scope + enrollment. Optional so reports saved before item 4b
    // still decode (missing keys → nil → defaults on load).
    var deviceScope: DeviceScope?
    var individualQuery: String?
    var includeEnrollment: Bool?
    let createdAt: Date
    var lastRunAt: Date?

    init(id: UUID = UUID(), name: String, description: String = "", platforms: Set<PlatformType>, filters: [ReportFilter], deviceScope: DeviceScope = .all, individualQuery: String = "", includeEnrollment: Bool = false, createdAt: Date = Date(), lastRunAt: Date? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.platforms = platforms.map { $0.rawValue }
        self.filters = filters
        self.deviceScope = deviceScope
        self.individualQuery = individualQuery
        self.includeEnrollment = includeEnrollment
        self.createdAt = createdAt
        self.lastRunAt = lastRunAt
    }

    var platformTypes: Set<PlatformType> {
        Set(platforms.compactMap { PlatformType(rawValue: $0) })
    }
}

// MARK: - Saved Reports Manager

@MainActor
class SavedReportsManager: ObservableObject {
    static let shared = SavedReportsManager()
    
    @Published var savedReports: [SavedReport] = []
    
    private let saveKey = "helios_saved_reports"
    
    private init() {
        loadReports()
    }
    
    func saveReport(_ report: SavedReport) {
        if let index = savedReports.firstIndex(where: { $0.id == report.id }) {
            savedReports[index] = report
        } else {
            savedReports.append(report)
        }
        persistReports()
    }
    
    func deleteReport(_ report: SavedReport) {
        savedReports.removeAll { $0.id == report.id }
        persistReports()
    }
    
    func updateLastRun(_ report: SavedReport) {
        if let index = savedReports.firstIndex(where: { $0.id == report.id }) {
            savedReports[index].lastRunAt = Date()
            persistReports()
        }
    }
    
    private func loadReports() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let reports = try? JSONDecoder().decode([SavedReport].self, from: data) {
            savedReports = reports
        }
    }
    
    private func persistReports() {
        if let data = try? JSONEncoder().encode(savedReports) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }
}

// MARK: - Report Device Result

struct ReportDeviceResult: Identifiable {
    let id: String
    let deviceName: String
    let serialNumber: String
    let platform: PlatformType
    let lastCheckIn: Date?
    let isSupervised: Bool
    let isEncrypted: Bool
    let osVersion: String
    let model: String
    let siteName: String
    let siteId: String
    /// False for a row synthesized from a Device Enrollment (ADE) record that
    /// has no matching Jamf inventory device.
    let inJamf: Bool
    /// Device Enrollment (ADE/DEP) record attached during a Devices-scope run.
    var enrollment: DeviceEnrollmentDevice?
    var enrollmentInstanceName: String?

    init(from computer: ComputerInventoryItem) {
        self.id = computer.id
        self.deviceName = computer.name
        self.serialNumber = computer.hardware?.serialNumber ?? "N/A"
        self.platform = .macOS
        self.lastCheckIn = computer.lastContactTime
        self.isSupervised = computer.isSupervised
        // Use boot partition encryption state for accurate encryption status
        self.isEncrypted = computer.diskEncryption?.isBootPartitionEncrypted ?? false
        self.osVersion = computer.operatingSystem?.version ?? "Unknown"
        self.model = computer.hardware?.modelIdentifier ?? computer.hardware?.model ?? "Unknown"
        self.siteName = computer.siteName ?? "None"
        self.siteId = computer.general?.site?.id ?? ""
        self.inJamf = true
    }

    init(from device: MobileDeviceInventoryItem) {
        self.id = device.id
        self.deviceName = device.displayName ?? "Unknown Device"
        self.serialNumber = device.serialNumber ?? "N/A"
        self.platform = device.platformType

        // Try to parse last inventory update date
        if let timestamp = device.general?.lastInventoryUpdateDate {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var parsedDate = formatter.date(from: timestamp)

            // Try without fractional seconds if that didn't work
            if parsedDate == nil {
                formatter.formatOptions = [.withInternetDateTime]
                parsedDate = formatter.date(from: timestamp)
            }

            self.lastCheckIn = parsedDate
        } else {
            self.lastCheckIn = nil
        }

        self.isSupervised = device.isSupervised
        // Use hardware encryption == 3 for accurate encryption status (full encryption)
        self.isEncrypted = device.security?.hardwareEncryption == 3
        self.osVersion = device.osVersion ?? "Unknown"
        self.model = device.modelIdentifier ?? device.model ?? "Unknown"
        // Mobile devices only have siteId, not site name
        self.siteName = device.general?.siteId ?? "None"
        self.siteId = device.general?.siteId ?? ""
        self.inJamf = true
    }

    /// A row synthesized from a Device Enrollment record that has no Jamf
    /// inventory device — the "in ADE, not in Jamf" case.
    init(orphan record: DeviceEnrollmentDevice, siteId: String, instanceName: String?) {
        self.id = "ade-\(record.serialNumber)"
        self.deviceName = record.description ?? record.model ?? "(Not in Jamf)"
        self.serialNumber = record.serialNumber
        self.platform = Self.inferPlatform(fromModel: record.model)
        self.lastCheckIn = nil
        self.isSupervised = false
        self.isEncrypted = false
        self.osVersion = "—"
        self.model = record.model ?? "—"
        self.siteName = "—"
        self.siteId = siteId
        self.inJamf = false
        self.enrollment = record
        self.enrollmentInstanceName = instanceName
    }

    private static func inferPlatform(fromModel model: String?) -> PlatformType {
        let m = (model ?? "").lowercased()
        if m.contains("iphone") { return .iOS }
        if m.contains("ipad") { return .iPadOS }
        if m.contains("vision") || m.contains("reality") { return .visionOS }
        return .macOS
    }
}

enum DeviceScope: String, CaseIterable, Identifiable, Codable {
    case all = "All Devices"
    case individual = "Individual Device"
    var id: String { rawValue }
}

enum ReportsTab: String, CaseIterable, Identifiable {
    case builder, scorecard, saved, scheduled
    var id: String { rawValue }
    var title: String {
        switch self {
        case .builder: return "Report Builder"
        case .scorecard: return "Health Scorecard"
        case .saved: return "Saved Reports"
        case .scheduled: return "Scheduled"
        }
    }
    var icon: String {
        switch self {
        case .builder: return "hammer"
        case .scorecard: return "heart.text.square"
        case .saved: return "bookmark"
        case .scheduled: return "calendar.badge.clock"
        }
    }
}

// MARK: - Reports View

struct ReportsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var computerCache = ComputerInventoryCache.shared
    @ObservedObject private var mobileCache = MobileDeviceInventoryCache.shared
    @ObservedObject private var savedReportsManager = SavedReportsManager.shared
    @ObservedObject private var healthCalc = HealthMetricsCalculator.shared
    
    @State private var selectedTab: ReportsTab = .builder
    @State private var selectedPlatforms: Set<PlatformType> = Set(PlatformType.displayCases)
    @State private var filters: [ReportFilter] = []
    @State private var reportResults: [ReportDeviceResult] = []
    @State private var isRunningReport = false
    @State private var hasRunReport = false
    @State private var showingFilterConfig = false
    @State private var selectedFilterCategory: ReportFilterCategory = .lastCheckIn
    
    // Save report dialog
    @State private var showingSaveDialog = false
    @State private var saveReportName = ""
    @State private var saveReportDescription = ""

    // Filter params
    @State private var timeComparison: TimeRangeComparison = .within
    @State private var timeValue: Int = 7
    @State private var timeUnit: TimeRangeUnit = .days
    @State private var supervisionFilter: SupervisionFilter = .supervised
    @State private var encryptionFilter: EncryptionFilter = .encrypted
    @State private var osVersionComparison = "At least"
    @State private var osVersion = "26.0"
    @State private var modelIdentifier = ""
    @State private var siteFilter = ""
    @State private var siteFilterComparison: SiteFilterComparison = .memberOf
    
    // New filter params
    @State private var applicationFilterType: ApplicationFilterType = .hasApp
    @State private var applicationName = ""
    @State private var appleCareFilter: AppleCareFilter = .active
    @State private var softwareUpdateFilter: SoftwareUpdateFilter = .hasPendingUpdates
    @State private var stalenessLevel: StalenessLevel = .over90
    @State private var managedFilter: ManagedFilter = .unmanagedOnly
    @State private var protectCoverageFilter: ProtectCoverageFilter = .covered
    @State private var computerGroupSelection = ""
    @State private var computerGroupQuery = ""
    @State private var deviceGroupSelection = ""
    @State private var deviceGroupQuery = ""

    // Jamf Protect coverage data, fetched at report-run when the filter is used.
    @State private var protectSerials: Set<String> = []
    @State private var protectStaleSerials: Set<String> = []

    // Collapsible builder sections
    @State private var expandedActiveFilters = true
    @State private var expandedPlatforms = true
    @State private var expandedScope = true
    @State private var expandedFilters = true

    // Devices scope + enrollment (item 4b)
    @State private var deviceScope: DeviceScope = .all
    @State private var individualQuery: String = ""
    @State private var includeEnrollment: Bool = false

    // Device detail navigation
    @State private var showingResults = false
    @State private var deviceLoadError: String?
    @State private var navigationPath = NavigationPath()
    
    private var isDark: Bool { colorScheme == .dark }
    private var totalDevices: Int { computerCache.totalCount + mobileCache.totalCount }

    /// Distinct computer groups (name + smart flag) across the cached fleet.
    private var computerGroupList: [(name: String, smart: Bool)] {
        var map: [String: Bool] = [:]
        for c in computerCache.computers {
            for g in c.groupMemberships ?? [] where !(g.groupName ?? "").isEmpty {
                map[g.groupName!] = g.smartGroup ?? false
            }
        }
        return map.map { (name: $0.key, smart: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Distinct mobile-device groups (name + smart flag) across the cached fleet.
    private var deviceGroupList: [(name: String, smart: Bool)] {
        var map: [String: Bool] = [:]
        for d in mobileCache.devices {
            for g in d.groups ?? [] where !(g.groupName ?? "").isEmpty {
                map[g.groupName!] = g.smart ?? false
            }
        }
        return map.map { (name: $0.key, smart: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                AnimatedBackgroundView(animate: .constant(true))
                VStack(spacing: 0) {
                    headerSection
                    tabBar
                    switch selectedTab {
                    case .builder: reportBuilderContent
                    case .scorecard: scorecardContent
                    case .saved: savedReportsContent
                    case .scheduled: placeholderContent(icon: "calendar.badge.clock", title: "No Scheduled Reports", desc: "Schedule reports to run automatically", color: .orange)
                    }
                }
                if showingFilterConfig { filterConfigOverlay }
                if showingSaveDialog { saveReportOverlay }
                if showingResults { resultsOverlay }
            }
        }
        .alert("Error", isPresented: .init(
            get: { deviceLoadError != nil },
            set: { if !$0 { deviceLoadError = nil } }
        )) {
            Button("OK") { deviceLoadError = nil }
        } message: {
            Text(deviceLoadError ?? "Unknown error")
        }
    }
    
    // MARK: - Results Overlay (modal)

    private var resultsOverlay: some View {
        ZStack {
            Color.black.opacity(isDark ? 0.6 : 0.45).ignoresSafeArea()
                .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showingResults = false } }
            ReportResultsView(
                results: reportResults,
                exportFilename: exportFilename,
                makeExportTable: buildExportTable,
                isDark: isDark,
                onClose: { withAnimation(.easeInOut(duration: 0.2)) { showingResults = false } }
            )
            .frame(maxWidth: 1240, maxHeight: 840)
            .padding(40)
        }
        .transition(.opacity)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Reports").font(.system(size: 28, weight: .bold)).foregroundColor(isDark ? .white : .primary)
                Text("\(totalDevices) devices in inventory").font(.system(size: 13)).foregroundColor(.gray)
            }
            Spacer()
            
            if selectedTab == .builder {
                HStack(spacing: 12) {
                    // Save button
                    if !filters.isEmpty {
                        Button { showingSaveDialog = true } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "bookmark.fill").font(.system(size: 12))
                                Text("Save").font(.system(size: 14, weight: .medium))
                            }
                            .foregroundColor(isDark ? .white : .primary)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                            .cornerRadius(10)
                        }.buttonStyle(.plain)
                    }
                    
                    // Run button — always available (runs all/individual even with no filters)
                    Button { runReport() } label: {
                        HStack(spacing: 8) {
                            if isRunningReport { ProgressView().scaleEffect(0.7).tint(.white) }
                            else { Image(systemName: "play.fill").font(.system(size: 12)) }
                            Text("Run Report").font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white).padding(.horizontal, 20).padding(.vertical, 10)
                        .background(LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing)).cornerRadius(10)
                    }.buttonStyle(ScaleButtonStyle()).disabled(isRunningReport)
                }
            }
        }.padding(.horizontal, 40).padding(.top, 24).padding(.bottom, 16)
    }
    
    // MARK: - Tab Bar
    
    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(ReportsTab.allCases) { tab in
                Button { withAnimation { selectedTab = tab } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.icon).font(.system(size: 14))
                        Text(tab.title).font(.system(size: 14, weight: .medium))
                        if tab == .saved && !savedReportsManager.savedReports.isEmpty {
                            Text("\(savedReportsManager.savedReports.count)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Color.purple))
                        }
                    }
                    .foregroundColor(selectedTab == tab ? (isDark ? .white : .primary) : .gray)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(selectedTab == tab ? (isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)) : Color.clear))
                }.buttonStyle(.plain)
            }
            Spacer()
        }.padding(.horizontal, 40).padding(.bottom, 16)
    }
    
    // MARK: - Report Builder Content
    
    private var reportBuilderContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !filters.isEmpty { activeFiltersSection }
                platformSection
                scopeSection
                filterCategoriesSection
            }.padding(40)
        }
    }
    
    // MARK: - Saved Reports Content
    
    private var savedReportsContent: some View {
        ScrollView {
            if savedReportsManager.savedReports.isEmpty {
                VStack(spacing: 24) {
                    Spacer().frame(height: 100)
                    ZStack { Circle().fill(Color.purple.opacity(0.1)).frame(width: 100, height: 100); Image(systemName: "bookmark.fill").font(.system(size: 40)).foregroundColor(.purple.opacity(0.6)) }
                    VStack(spacing: 12) {
                        Text("No Saved Reports").font(.system(size: 20, weight: .semibold)).foregroundColor(isDark ? .white : .primary)
                        Text("Save your report configurations for quick access later").font(.system(size: 14)).foregroundColor(.gray)
                    }
                    Spacer()
                }.frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    ForEach(savedReportsManager.savedReports) { report in
                        SavedReportCard(report: report, isDark: isDark) {
                            loadSavedReport(report)
                        } onDelete: {
                            savedReportsManager.deleteReport(report)
                        }
                    }
                }.padding(40)
            }
        }
    }
    
    private func loadSavedReport(_ report: SavedReport) {
        selectedPlatforms = report.platformTypes
        filters = report.filters
        deviceScope = report.deviceScope ?? .all
        individualQuery = report.individualQuery ?? ""
        includeEnrollment = report.includeEnrollment ?? false
        hasRunReport = false
        reportResults = []
        selectedTab = .builder
        savedReportsManager.updateLastRun(report)
    }

    // MARK: - Health Scorecard Content

    private var scorecardFilename: String {
        ExportNaming.filename("Helios", "Health-Scorecard", date: Date())
    }

    private var scorecardContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                card {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            sectionHeader("Environment Health Scorecard", icon: "heart.text.square", color: .pink)
                            Spacer()
                            ReportsExportMenu(
                                filename: scorecardFilename,
                                makeTable: { HealthScorecardExportBuilder.table(generatedAt: Date()) },
                                isDark: isDark,
                                prominent: true
                            )
                        }
                        Text("Compliance metrics and managed-device counts by OS, exportable to CSV, Excel, PDF, or Markdown.")
                            .font(.system(size: 13)).foregroundColor(.gray)
                    }
                }

                // Scorecard metrics
                card {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("Scorecard", icon: "checkmark.seal", color: .green)
                        if healthCalc.healthMetrics.isEmpty {
                            Text("No inventory loaded yet — open the Dashboard or Devices to load data.")
                                .font(.system(size: 13)).foregroundColor(.gray).padding(.vertical, 8)
                        } else {
                            ForEach(healthCalc.healthMetrics) { m in
                                HStack(spacing: 12) {
                                    Image(systemName: m.type.icon).font(.system(size: 14)).foregroundColor(.pink).frame(width: 22)
                                    Text(m.type.rawValue).font(.system(size: 14, weight: .medium)).foregroundColor(isDark ? .white : .primary)
                                    Spacer()
                                    Text("\(m.compliantCount)/\(m.totalCount)").font(.system(size: 12, design: .monospaced)).foregroundColor(.gray)
                                    Text("\(Int(m.percentage))%").font(.system(size: 14, weight: .semibold)).foregroundColor(isDark ? .white : .primary).frame(width: 48, alignment: .trailing)
                                }
                                .padding(.vertical, 4)
                            }
                            Divider().background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                            HStack {
                                Text("Overall Health").font(.system(size: 14, weight: .semibold)).foregroundColor(isDark ? .white : .primary)
                                Spacer()
                                Text(HealthScorecardExportBuilder.pct(HealthScorecardExportBuilder.overallHealth()))
                                    .font(.system(size: 16, weight: .bold)).foregroundColor(.pink)
                            }
                        }
                    }
                }

                // Managed devices by OS
                card {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("Managed Devices by OS", icon: "cpu", color: .blue)
                        let rows = HealthScorecardExportBuilder.osBreakdown()
                        HStack {
                            Text("OS").frame(maxWidth: .infinity, alignment: .leading)
                            Text("Total").frame(width: 80, alignment: .trailing)
                            Text("Managed").frame(width: 90, alignment: .trailing)
                            Text("Unmanaged").frame(width: 100, alignment: .trailing)
                        }
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(.gray)
                        Divider().background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                        if rows.isEmpty {
                            Text("No devices in inventory.").font(.system(size: 13)).foregroundColor(.gray).padding(.vertical, 8)
                        } else {
                            ForEach(rows) { row in
                                HStack {
                                    Text(row.label).font(.system(size: 13)).foregroundColor(isDark ? .white : .primary).frame(maxWidth: .infinity, alignment: .leading)
                                    Text("\(row.total)").font(.system(size: 13, design: .monospaced)).foregroundColor(.gray).frame(width: 80, alignment: .trailing)
                                    Text("\(row.managed)").font(.system(size: 13, design: .monospaced)).foregroundColor(.green).frame(width: 90, alignment: .trailing)
                                    Text("\(row.unmanaged)").font(.system(size: 13, design: .monospaced)).foregroundColor(row.unmanaged > 0 ? .orange : .gray).frame(width: 100, alignment: .trailing)
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }
                }
            }
            .padding(40)
        }
        .onAppear {
            if healthCalc.healthMetrics.isEmpty { healthCalc.recalculateMetrics() }
        }
    }


    // MARK: - Platform Section
    
    private var platformSection: some View {
        collapsibleCard("Platforms", icon: "rectangle.stack", color: .blue, isExpanded: $expandedPlatforms, trailing: {
            Button { selectedPlatforms = Set(PlatformType.displayCases); hasRunReport = false } label: {
                Text("Select All").font(.system(size: 12, weight: .medium)).foregroundColor(.blue)
            }.buttonStyle(.plain)
        }) {
            HStack(spacing: 12) {
                ForEach(PlatformType.displayCases) { p in platformTag(p) }
                Spacer()
            }
        }
    }
    
    private func platformTag(_ platform: PlatformType) -> some View {
        let selected = selectedPlatforms.contains(platform)
        return Button {
            if selected { if selectedPlatforms.count > 1 { selectedPlatforms.remove(platform) } }
            else { selectedPlatforms.insert(platform) }
            hasRunReport = false
        } label: {
            HStack(spacing: 8) {
                Image(systemName: platform.icon).font(.system(size: 14))
                Text(platform.rawValue).font(.system(size: 14, weight: .medium))
                if selected { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
            }
            .foregroundColor(selected ? .white : (isDark ? .white.opacity(0.8) : .primary.opacity(0.8)))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? platform.color : (isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))))
        }.buttonStyle(.plain)
    }

    // MARK: - Scope Section

    private var scopeSection: some View {
        collapsibleCard("Scope", icon: "scope", color: .teal, isExpanded: $expandedScope) {
            VStack(alignment: .leading, spacing: 16) {
                Picker("", selection: $deviceScope) {
                    ForEach(DeviceScope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)
                .onChange(of: deviceScope) { hasRunReport = false }

                if deviceScope == .individual {
                    TextField("Serial number or asset tag", text: $individualQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(10)
                        .background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                        .cornerRadius(8)
                        .frame(maxWidth: 340)
                        .onChange(of: individualQuery) { hasRunReport = false }
                }

                Toggle(isOn: $includeEnrollment) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include Device Enrollment (ADE) details")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(isDark ? .white : .primary)
                        Text("Attaches each device's Automated Device Enrollment record, and lists ADE serials that aren't in Jamf. Added to the export.")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: includeEnrollment) { hasRunReport = false }
            }
        }
    }

    // MARK: - Filter Categories

    private var filterCategoriesSection: some View {
        collapsibleCard("Add Filters", icon: "line.3.horizontal.decrease.circle", color: .purple, isExpanded: $expandedFilters) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                ForEach(ReportFilterCategory.allCases) { cat in filterCategoryCard(cat) }
            }
        }
    }
    
    private func filterCategoryCard(_ category: ReportFilterCategory) -> some View {
        let active = filters.contains { $0.category == category }
        return Button {
            selectedFilterCategory = category
            resetFilterParams(category)
            withAnimation { showingFilterConfig = true }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(category.color.opacity(isDark ? 0.2 : 0.15)).frame(width: 36, height: 36)
                        Image(systemName: category.icon).font(.system(size: 16, weight: .semibold)).foregroundColor(category.color)
                    }
                    Spacer()
                    Image(systemName: active ? "checkmark.circle.fill" : "plus.circle").font(.system(size: 16)).foregroundColor(active ? .green : .gray.opacity(0.5))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.rawValue).font(.system(size: 14, weight: .semibold)).foregroundColor(isDark ? .white : .primary)
                    Text(category.description).font(.system(size: 11)).foregroundColor(.gray).lineLimit(2)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(isDark ? Color.white.opacity(0.03) : Color.white.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(active ? category.color.opacity(0.5) : (isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.08)), lineWidth: 1))
        }.buttonStyle(.plain)
    }
    
    // MARK: - Active Filters
    
    private var activeFiltersSection: some View {
        collapsibleCard("Active Filters", icon: "checkmark.circle", color: .green, isExpanded: $expandedActiveFilters, trailing: {
            Button { filters.removeAll(); hasRunReport = false; reportResults = [] } label: {
                Text("Clear All").font(.system(size: 12, weight: .medium)).foregroundColor(.red)
            }.buttonStyle(.plain)
        }) {
            FlowLayout(spacing: 10) {
                ForEach(filters) { f in filterTag(f) }
            }
        }
    }
    
    private func filterTag(_ filter: ReportFilter) -> some View {
        HStack(spacing: 8) {
            Image(systemName: filter.category.icon).font(.system(size: 12)).foregroundColor(filter.category.color)
            Text(filter.category.rawValue).font(.system(size: 12, weight: .semibold)).foregroundColor(isDark ? .white : .primary)
            Text(filter.displayDescription).font(.system(size: 12)).foregroundColor(.gray)
            Button { filters.removeAll { $0.id == filter.id }; hasRunReport = false } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundColor(.gray)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(filter.category.color.opacity(0.3), lineWidth: 1))
    }
    
    // MARK: - Save Report Overlay
    
    private var saveReportOverlay: some View {
        ZStack {
            Color.black.opacity(isDark ? 0.6 : 0.4).ignoresSafeArea()
                .onTapGesture { showingSaveDialog = false }
            
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Save Report").font(.system(size: 18, weight: .semibold)).foregroundColor(isDark ? .white : .primary)
                        Text("Save this configuration for quick access").font(.system(size: 13)).foregroundColor(.gray)
                    }
                    Spacer()
                    Button { showingSaveDialog = false } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundColor(.gray)
                            .frame(width: 32, height: 32).background(Circle().fill(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)))
                    }.buttonStyle(.plain)
                }.padding(24).background(isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
                
                Divider().background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name").font(.system(size: 13, weight: .medium)).foregroundColor(.gray)
                        TextField("Report name", text: $saveReportName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .padding(12)
                            .background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                            .cornerRadius(8)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description (optional)").font(.system(size: 13, weight: .medium)).foregroundColor(.gray)
                        TextField("Brief description", text: $saveReportDescription)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .padding(12)
                            .background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                            .cornerRadius(8)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Summary").font(.system(size: 13, weight: .medium)).foregroundColor(.gray)
                        HStack(spacing: 16) {
                            Label("\(selectedPlatforms.count) platforms", systemImage: "rectangle.stack")
                            Label("\(filters.count) filters", systemImage: "line.3.horizontal.decrease.circle")
                        }
                        .font(.system(size: 12))
                        .foregroundColor(isDark ? .white.opacity(0.7) : .primary.opacity(0.7))
                    }
                }.padding(24)
                
                Divider().background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                
                HStack {
                    Button { showingSaveDialog = false; saveReportName = ""; saveReportDescription = "" } label: {
                        Text("Cancel").font(.system(size: 14, weight: .medium)).foregroundColor(isDark ? .white : .primary)
                            .frame(width: 100, height: 36).background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)).cornerRadius(8)
                    }.buttonStyle(.plain)
                    Spacer()
                    Button {
                        let report = SavedReport(name: saveReportName.isEmpty ? "Untitled Report" : saveReportName, description: saveReportDescription, platforms: selectedPlatforms, filters: filters, deviceScope: deviceScope, individualQuery: individualQuery, includeEnrollment: includeEnrollment)
                        savedReportsManager.saveReport(report)
                        showingSaveDialog = false
                        saveReportName = ""
                        saveReportDescription = ""
                    } label: {
                        Text("Save Report").font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                            .frame(width: 120, height: 36).background(Color.purple).cornerRadius(8)
                    }.buttonStyle(ScaleButtonStyle())
                }.padding(24)
            }
            .frame(width: 450)
            .background(isDark ? Color(white: 0.12) : Color.white)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.3), radius: 20)
        }
    }
    
    // MARK: - Filter Config Overlay
    
    private var filterConfigOverlay: some View {
        ZStack {
            Color.black.opacity(isDark ? 0.6 : 0.4).ignoresSafeArea()
                .onTapGesture { withAnimation { showingFilterConfig = false } }
            
            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8).fill(selectedFilterCategory.color.opacity(0.2)).frame(width: 40, height: 40)
                            Image(systemName: selectedFilterCategory.icon).font(.system(size: 18, weight: .semibold)).foregroundColor(selectedFilterCategory.color)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedFilterCategory.rawValue).font(.system(size: 18, weight: .semibold)).foregroundColor(isDark ? .white : .primary)
                            Text("Configure filter").font(.system(size: 13)).foregroundColor(.gray)
                        }
                    }
                    Spacer()
                    Button { withAnimation { showingFilterConfig = false } } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundColor(.gray)
                            .frame(width: 32, height: 32).background(Circle().fill(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)))
                    }.buttonStyle(.plain)
                }.padding(24).background(isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
                
                Divider().background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                
                ScrollView { VStack(alignment: .leading, spacing: 20) { filterConfigContent }.padding(24) }
                
                Divider().background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                
                HStack {
                    Button { withAnimation { showingFilterConfig = false } } label: {
                        Text("Cancel").font(.system(size: 14, weight: .medium)).foregroundColor(isDark ? .white : .primary)
                            .frame(width: 100, height: 36).background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)).cornerRadius(8)
                    }.buttonStyle(.plain)
                    Spacer()
                    Button { addFilter(); withAnimation { showingFilterConfig = false } } label: {
                        Text("Add Filter").font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                            .frame(width: 120, height: 36).background(selectedFilterCategory.color).cornerRadius(8)
                    }.buttonStyle(ScaleButtonStyle())
                }.padding(24)
            }
            .frame(width: 560, height: selectedFilterCategory.configOverlayHeight)
            .background(isDark ? Color(white: 0.12) : Color.white)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.3), radius: 20)
        }
    }
    
    @ViewBuilder
    private var filterConfigContent: some View {
        switch selectedFilterCategory {
        case .lastCheckIn:
            VStack(alignment: .leading, spacing: 16) {
                Text("Find devices that checked in:").font(.system(size: 14, weight: .medium)).foregroundColor(isDark ? .white : .primary)
                
                HStack(spacing: 20) {
                    Picker("", selection: $timeComparison) { ForEach(TimeRangeComparison.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    
                    TextField("", value: $timeValue, format: .number)
                        .textFieldStyle(.plain)
                        .frame(width: 50)
                        .multilineTextAlignment(.center)
                        .padding(8)
                        .background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                        .cornerRadius(6)
                    
                    Picker("", selection: $timeUnit) { ForEach(TimeRangeUnit.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented)
                        .frame(width: 240)
                }
                
                previewBox("\(timeComparison.rawValue) \(timeValue) \(timeUnit.rawValue.lowercased()) ago")
            }
        case .supervision:
            VStack(alignment: .leading, spacing: 16) {
                Text("Filter by supervision status:").font(.system(size: 14, weight: .medium)).foregroundColor(isDark ? .white : .primary)
                VStack(spacing: 8) { ForEach(SupervisionFilter.allCases) { f in radioButton(f.rawValue, selected: supervisionFilter == f) { supervisionFilter = f } } }
                previewBox(supervisionFilter.rawValue)
            }
        case .encryption:
            VStack(alignment: .leading, spacing: 16) {
                Text("Filter by encryption (FileVault):").font(.system(size: 14, weight: .medium)).foregroundColor(isDark ? .white : .primary)
                VStack(spacing: 8) { ForEach(EncryptionFilter.allCases) { f in radioButton(f.rawValue, selected: encryptionFilter == f) { encryptionFilter = f } } }
                previewBox(encryptionFilter.rawValue)
            }
        case .osVersion:
            VStack(alignment: .leading, spacing: 16) {
                Text("Filter by OS version:").font(.system(size: 14, weight: .medium)).foregroundColor(isDark ? .white : .primary)
                HStack(spacing: 12) {
                    Picker("", selection: $osVersionComparison) { Text("At least").tag("At least"); Text("Exactly").tag("Exactly"); Text("Below").tag("Below") }.pickerStyle(.segmented).frame(width: 200)
                    TextField("", text: $osVersion).textFieldStyle(.plain).frame(width: 80).padding(8).background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)).cornerRadius(6)
                }
                HStack(spacing: 8) { ForEach(["26.0", "15.0", "14.0"], id: \.self) { v in Button { osVersion = v } label: { Text(v).font(.system(size: 12)).foregroundColor(osVersion == v ? .white : .gray).padding(.horizontal, 12).padding(.vertical, 6).background(osVersion == v ? selectedFilterCategory.color : (isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))).cornerRadius(6) }.buttonStyle(.plain) } }
                previewBox("\(osVersionComparison) \(osVersion)")
            }
        case .model:
            VStack(alignment: .leading, spacing: 16) {
                Text("Filter by model:").font(.system(size: 14, weight: .medium)).foregroundColor(isDark ? .white : .primary)
                TextField("e.g. MacBookPro", text: $modelIdentifier).textFieldStyle(.plain).padding(10).background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)).cornerRadius(8)
                HStack(spacing: 8) { ForEach(["MacBookPro", "MacBookAir", "iMac", "iPhone", "iPad", "RealityDevice"], id: \.self) { m in Button { modelIdentifier = m } label: { Text(m == "RealityDevice" ? "Vision Pro" : m).font(.system(size: 12)).foregroundColor(modelIdentifier == m ? .white : .gray).padding(.horizontal, 10).padding(.vertical, 6).background(modelIdentifier == m ? selectedFilterCategory.color : (isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))).cornerRadius(6) }.buttonStyle(.plain) } }
                if !modelIdentifier.isEmpty { previewBox("Model contains: \(modelIdentifier)") }
            }
        case .site:
            VStack(alignment: .leading, spacing: 16) {
                Text("Filter by site:").font(.system(size: 14, weight: .medium)).foregroundColor(isDark ? .white : .primary)
                
                HStack(spacing: 12) {
                    Picker("", selection: $siteFilterComparison) {
                        ForEach(SiteFilterComparison.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                    
                    TextField("Site name", text: $siteFilter)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                        .cornerRadius(8)
                }
                
                HStack(spacing: 8) {
                    ForEach(["Enterprise", "GroundControl", "None"], id: \.self) { s in
                        Button { siteFilter = s } label: {
                            Text(s)
                                .font(.system(size: 12))
                                .foregroundColor(siteFilter == s ? .white : .gray)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(siteFilter == s ? selectedFilterCategory.color : (isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                if !siteFilter.isEmpty { previewBox("\(siteFilterComparison.rawValue) \(siteFilter)") }
            }
        
        case .applications:
            VStack(alignment: .leading, spacing: 16) {
                Text("Filter by applications:").font(.system(size: 14, weight: .medium)).foregroundColor(isDark ? .white : .primary)
                
                HStack(spacing: 12) {
                    Picker("", selection: $applicationFilterType) {
                        ForEach(ApplicationFilterType.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                }
                
                TextField("Application name (e.g. Falcon, Zscaler)", text: $applicationName)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    .cornerRadius(8)
                
                HStack(spacing: 8) {
                    ForEach(["Falcon", "Zscaler", "Cisco Secure Client", "JamfProtect", "QualysCloudAgent"], id: \.self) { app in
                        Button { applicationName = app } label: {
                            Text(app)
                                .font(.system(size: 11))
                                .foregroundColor(applicationName == app ? .white : .gray)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(applicationName == app ? selectedFilterCategory.color : (isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                if !applicationName.isEmpty {
                    previewBox("\(applicationFilterType.rawValue): \(applicationName)")
                }
            }
        case .appleCare:
            VStack(alignment: .leading, spacing: 16) {
                Text("Filter by AppleCare coverage:").font(.system(size: 14, weight: .medium)).foregroundColor(isDark ? .white : .primary)
                
                VStack(spacing: 8) {
                    ForEach(AppleCareFilter.allCases) { filter in
                        radioButton(filter.rawValue, selected: appleCareFilter == filter) {
                            appleCareFilter = filter
                        }
                    }
                }
                
                previewBox(appleCareFilter.rawValue)
                
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("Uses Jamf Purchasing data (vendor & warrantyDate fields)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
        case .softwareUpdates:
            VStack(alignment: .leading, spacing: 16) {
                Text("Filter by software update status:").font(.system(size: 14, weight: .medium)).foregroundColor(isDark ? .white : .primary)
                
                VStack(spacing: 8) {
                    ForEach(SoftwareUpdateFilter.allCases) { filter in
                        radioButton(filter.rawValue, selected: softwareUpdateFilter == filter) {
                            softwareUpdateFilter = filter
                        }
                    }
                }
                
                previewBox(softwareUpdateFilter.rawValue)
                
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("Uses availableSoftwareUpdates from device inventory (macOS only)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
        case .staleDevices:
            VStack(alignment: .leading, spacing: 16) {
                Text("Find devices that haven't checked in for:").font(.system(size: 14, weight: .medium)).foregroundColor(isDark ? .white : .primary)
                VStack(spacing: 8) {
                    ForEach(StalenessLevel.allCases) { level in
                        radioButton(level.rawValue, selected: stalenessLevel == level) { stalenessLevel = level }
                    }
                }
                previewBox(stalenessLevel.rawValue)
            }
        case .unmanaged:
            VStack(alignment: .leading, spacing: 16) {
                Text("Filter by MDM management status:").font(.system(size: 14, weight: .medium)).foregroundColor(isDark ? .white : .primary)
                VStack(spacing: 8) {
                    ForEach(ManagedFilter.allCases) { filter in
                        radioButton(filter.rawValue, selected: managedFilter == filter) { managedFilter = filter }
                    }
                }
                previewBox(managedFilter.rawValue)
            }
        case .protectCoverage:
            VStack(alignment: .leading, spacing: 16) {
                Text("Filter by Jamf Protect coverage:").font(.system(size: 14, weight: .medium)).foregroundColor(isDark ? .white : .primary)
                VStack(spacing: 8) {
                    ForEach(ProtectCoverageFilter.allCases) { filter in
                        radioButton(filter.rawValue, selected: protectCoverageFilter == filter) { protectCoverageFilter = filter }
                    }
                }
                previewBox(protectCoverageFilter.rawValue)
                HStack(spacing: 6) {
                    Image(systemName: "info.circle").font(.system(size: 11)).foregroundColor(.secondary)
                    Text("Matched by serial against your Jamf Protect tenant (macOS only). Configure Protect in Settings → Cleanup.").font(.system(size: 11)).foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
        case .computerGroup:
            groupPicker(
                title: "Filter macOS devices by computer group:",
                prompt: "Search computer groups…",
                query: $computerGroupQuery,
                selection: $computerGroupSelection,
                groups: computerGroupList,
                emptyNote: "No computer groups loaded. Refresh your computer inventory to load group memberships."
            )
        case .deviceGroup:
            groupPicker(
                title: "Filter mobile devices by device group:",
                prompt: "Search device groups…",
                query: $deviceGroupQuery,
                selection: $deviceGroupSelection,
                groups: deviceGroupList,
                emptyNote: "No device groups loaded. Load your mobile device inventory first."
            )
        }
    }

    private func groupPicker(
        title: String,
        prompt: String,
        query: Binding<String>,
        selection: Binding<String>,
        groups: [(name: String, smart: Bool)],
        emptyNote: String
    ) -> some View {
        let q = query.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = q.isEmpty ? groups : groups.filter { $0.name.lowercased().contains(q) }
        return VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 14, weight: .medium)).foregroundColor(isDark ? .white : .primary)
            TextField(prompt, text: query)
                .textFieldStyle(.plain).font(.system(size: 14)).padding(10)
                .background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)).cornerRadius(8)
            if groups.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle").font(.system(size: 11)).foregroundColor(.secondary)
                    Text(emptyNote).font(.system(size: 11)).foregroundColor(.secondary)
                }.padding(.top, 4)
            } else if filtered.isEmpty {
                Text("No groups match your search.").font(.system(size: 12)).foregroundColor(.gray).padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(filtered, id: \.name) { group in
                            Button { selection.wrappedValue = group.name } label: {
                                HStack {
                                    Image(systemName: selection.wrappedValue == group.name ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selection.wrappedValue == group.name ? selectedFilterCategory.color : .gray)
                                    Text(group.name).font(.system(size: 13)).foregroundColor(isDark ? .white : .primary).lineLimit(1)
                                    Spacer()
                                    Text(group.smart ? "Smart" : "Static")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(group.smart ? .purple : .gray)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Capsule().fill((group.smart ? Color.purple : Color.gray).opacity(0.15)))
                                }
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 8).fill(selection.wrappedValue == group.name ? selectedFilterCategory.color.opacity(0.12) : Color.clear))
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 260)
                if !selection.wrappedValue.isEmpty { previewBox(selection.wrappedValue) }
            }
        }
    }

    private func radioButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundColor(selected ? selectedFilterCategory.color : .gray)
                Text(title).font(.system(size: 14)).foregroundColor(isDark ? .white : .primary)
                Spacer()
            }.padding(12).background(RoundedRectangle(cornerRadius: 8).fill(selected ? selectedFilterCategory.color.opacity(0.15) : (isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))))
        }.buttonStyle(.plain)
    }
    
    private func previewBox(_ text: String) -> some View {
        HStack {
            Image(systemName: "eye").foregroundColor(selectedFilterCategory.color)
            Text("Preview: ").font(.system(size: 13, weight: .medium)).foregroundColor(.gray)
            Text(text).font(.system(size: 13, weight: .semibold)).foregroundColor(isDark ? .white : .primary)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(selectedFilterCategory.color.opacity(0.1)).cornerRadius(8)
    }
    
    // MARK: - Helpers
    
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(isDark ? Color.white.opacity(0.03) : Color.white.opacity(0.8)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.08), lineWidth: 1))
            .shadow(color: isDark ? .clear : .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }

    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundColor(color)
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundColor(isDark ? .white : .primary)
        }
    }

    /// A card whose content collapses behind a tappable header + chevron.
    private func collapsibleCard<Trailing: View, Content: View>(
        _ title: String,
        icon: String,
        color: Color,
        isExpanded: Binding<Bool>,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) -> some View {
        card {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { isExpanded.wrappedValue.toggle() }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundColor(color)
                            Text(title).font(.system(size: 16, weight: .semibold)).foregroundColor(isDark ? .white : .primary)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.gray)
                                .rotationEffect(.degrees(isExpanded.wrappedValue ? 0 : -90))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    trailing()
                }
                if isExpanded.wrappedValue {
                    content()
                }
            }
        }
    }
    
    private func placeholderContent(icon: String, title: String, desc: String, color: Color) -> some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack { Circle().fill(color.opacity(0.1)).frame(width: 100, height: 100); Image(systemName: icon).font(.system(size: 40)).foregroundColor(color.opacity(0.6)) }
            VStack(spacing: 12) { Text(title).font(.system(size: 20, weight: .semibold)).foregroundColor(isDark ? .white : .primary); Text(desc).font(.system(size: 14)).foregroundColor(.gray) }
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func resetFilterParams(_ cat: ReportFilterCategory) {
        switch cat {
        case .lastCheckIn: timeComparison = .within; timeValue = 7; timeUnit = .days
        case .supervision: supervisionFilter = .supervised
        case .encryption: encryptionFilter = .encrypted
        case .osVersion: osVersionComparison = "At least"; osVersion = "26.0"
        case .model: modelIdentifier = ""
        case .site: siteFilter = ""; siteFilterComparison = .memberOf
        case .applications: applicationFilterType = .hasApp; applicationName = ""
        case .appleCare: appleCareFilter = .active
        case .softwareUpdates: softwareUpdateFilter = .hasPendingUpdates
        case .staleDevices: stalenessLevel = .over90
        case .unmanaged: managedFilter = .unmanagedOnly
        case .protectCoverage: protectCoverageFilter = .covered
        case .computerGroup: computerGroupSelection = ""; computerGroupQuery = ""
        case .deviceGroup: deviceGroupSelection = ""; deviceGroupQuery = ""
        }
    }
    
    private func addFilter() {
        let f: ReportFilter
        switch selectedFilterCategory {
        case .lastCheckIn: f = ReportFilter(category: selectedFilterCategory, parameters: .lastCheckIn(comparison: timeComparison, value: timeValue, unit: timeUnit))
        case .supervision: f = ReportFilter(category: selectedFilterCategory, parameters: .supervision(status: supervisionFilter))
        case .encryption: f = ReportFilter(category: selectedFilterCategory, parameters: .encryption(status: encryptionFilter))
        case .osVersion: f = ReportFilter(category: selectedFilterCategory, parameters: .osVersion(version: osVersion, comparison: osVersionComparison))
        case .model: guard !modelIdentifier.isEmpty else { return }; f = ReportFilter(category: selectedFilterCategory, parameters: .model(identifier: modelIdentifier))
        case .site: guard !siteFilter.isEmpty else { return }; f = ReportFilter(category: selectedFilterCategory, parameters: .site(name: siteFilter, comparison: siteFilterComparison))
        case .applications: guard !applicationName.isEmpty else { return }; f = ReportFilter(category: selectedFilterCategory, parameters: .applications(type: applicationFilterType, appName: applicationName))
        case .appleCare: f = ReportFilter(category: selectedFilterCategory, parameters: .appleCare(status: appleCareFilter))
        case .softwareUpdates: f = ReportFilter(category: selectedFilterCategory, parameters: .softwareUpdates(status: softwareUpdateFilter))
        case .staleDevices: f = ReportFilter(category: selectedFilterCategory, parameters: .staleDevices(level: stalenessLevel))
        case .unmanaged: f = ReportFilter(category: selectedFilterCategory, parameters: .unmanaged(status: managedFilter))
        case .protectCoverage: f = ReportFilter(category: selectedFilterCategory, parameters: .protectCoverage(status: protectCoverageFilter))
        case .computerGroup: guard !computerGroupSelection.isEmpty else { return }; f = ReportFilter(category: selectedFilterCategory, parameters: .computerGroup(name: computerGroupSelection))
        case .deviceGroup: guard !deviceGroupSelection.isEmpty else { return }; f = ReportFilter(category: selectedFilterCategory, parameters: .deviceGroup(name: deviceGroupSelection))
        }
        filters.removeAll { $0.category == selectedFilterCategory }
        filters.append(f)
        hasRunReport = false
    }
    
    // MARK: - Export

    private var exportFilename: String {
        ExportNaming.filename("Helios", "Device-Report", date: Date())
    }

    private func buildExportTable() -> ReportTable {
        ReportsExportBuilder.table(
            results: reportResults,
            platforms: selectedPlatforms,
            filters: filters,
            scope: deviceScope,
            individualQuery: individualQuery,
            includeEnrollment: includeEnrollment,
            generatedAt: Date()
        )
    }

    // MARK: - Run Report

    private func runReport() {
        isRunningReport = true
        Task {
            // Any data that must be fetched (not in the caches) is loaded first.
            await loadProtectDataIfNeeded()
            if deviceScope == .individual { EnrollmentService.shared.buildAssetTagMapping() }

            var enrollment: EnrollmentAggregate?
            if includeEnrollment {
                do {
                    enrollment = try await EnrollmentService.shared.fetchAllInstancesDevices()
                } catch {
                    deviceLoadError = "Failed to load Device Enrollment data: \(error.localizedDescription)"
                }
            }

            var results: [ReportDeviceResult] = []
            if selectedPlatforms.contains(.macOS) { results.append(contentsOf: computerCache.computers.map { ReportDeviceResult(from: $0) }) }
            if selectedPlatforms.contains(.iOS) { results.append(contentsOf: mobileCache.devices.filter { $0.platformType == .iOS }.map { ReportDeviceResult(from: $0) }) }
            if selectedPlatforms.contains(.iPadOS) { results.append(contentsOf: mobileCache.devices.filter { $0.platformType == .iPadOS }.map { ReportDeviceResult(from: $0) }) }
            if selectedPlatforms.contains(.visionOS) { results.append(contentsOf: mobileCache.devices.filter { $0.platformType == .visionOS }.map { ReportDeviceResult(from: $0) }) }

            results = applyScope(to: results)
            for f in filters { results = applyFilter(f, to: results) }

            // Attach enrollment records to matched devices, and surface ADE-only
            // (not-in-Jamf) serials. Orphans have no Jamf inventory to satisfy
            // content filters, so they're only appended for an unfiltered device
            // report — a filtered (compliance) query stays internally consistent
            // with its "Filters applied" preamble.
            if includeEnrollment, let agg = enrollment {
                results = results.map { attachEnrollment($0, from: agg) }
                if filters.isEmpty {
                    results.append(contentsOf: orphanRows(from: agg))
                }
            }

            reportResults = results
            hasRunReport = true
            isRunningReport = false
            withAnimation(.easeInOut(duration: 0.2)) { showingResults = true }
        }
    }

    /// Narrow the base device set by the selected scope (all device / one device).
    private func applyScope(to r: [ReportDeviceResult]) -> [ReportDeviceResult] {
        switch deviceScope {
        case .all:
            return r
        case .individual:
            let q = individualQuery.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !q.isEmpty else { return r }
            return r.filter {
                $0.serialNumber.uppercased() == q
                    || EnrollmentService.shared.assetTag(forSerial: $0.serialNumber)?.uppercased() == q
            }
        }
    }

    /// Attach a device's Device Enrollment record (matched by serial) if present.
    private func attachEnrollment(_ device: ReportDeviceResult, from agg: EnrollmentAggregate) -> ReportDeviceResult {
        var d = device
        let key = device.serialNumber.uppercased()
        guard key != "N/A", key != "—", !key.isEmpty, let record = agg.bySerial[key] else { return d }
        d.enrollment = record
        d.enrollmentInstanceName = agg.instanceName(for: record)
        return d
    }

    /// Rows for Device Enrollment serials that have no Jamf inventory record,
    /// respecting the active scope and platform selection.
    private func orphanRows(from agg: EnrollmentAggregate) -> [ReportDeviceResult] {
        var jamfSerials = Set(computerCache.computers.compactMap { $0.hardware?.serialNumber?.uppercased() })
        jamfSerials.formUnion(mobileCache.devices.compactMap { $0.serialNumber?.uppercased() })
        let individualQ = individualQuery.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        return agg.bySerial.values.compactMap { record -> ReportDeviceResult? in
            let key = record.serialNumber.uppercased()
            guard !key.isEmpty, !jamfSerials.contains(key) else { return nil }
            let orphan = ReportDeviceResult(
                orphan: record,
                siteId: agg.instanceSiteId(for: record) ?? "",
                instanceName: agg.instanceName(for: record)
            )
            guard selectedPlatforms.contains(orphan.platform) else { return nil }
            switch deviceScope {
            case .all:
                return orphan
            case .individual:
                guard !individualQ.isEmpty else { return nil }
                return key == individualQ ? orphan : nil
            }
        }
        .sorted { $0.serialNumber < $1.serialNumber }
    }

    /// If a Jamf Protect coverage filter is active, fetch the Protect computer
    /// list once and index it by serial (plus a stale subset). Failures surface
    /// via the device-load error alert and leave the sets empty (so those
    /// devices read as "not covered" rather than silently disappearing).
    private func loadProtectDataIfNeeded() async {
        let needsProtect = filters.contains {
            if case .protectCoverage = $0.parameters { return true }
            return false
        }
        guard needsProtect else { return }

        let settings = CleanupSettings()
        guard settings.isProtectConfigured, let url = settings.normalizedProtectURL else {
            protectSerials = []
            protectStaleSerials = []
            deviceLoadError = "Jamf Protect isn't configured. Add it in Settings → Cleanup to use the Protect coverage filter."
            return
        }
        do {
            let client = JamfProtectClient(baseURL: url, clientID: settings.protectClientID, password: settings.protectClientPassword)
            let devices = try await client.fetchAllComputers()
            await client.invalidate()
            let cutoff = Date().addingTimeInterval(-Double(settings.staleDays) * 86_400)
            func normalized(_ list: [ProtectDevice]) -> Set<String> {
                Set(list.map { $0.serial.uppercased() }.filter { !$0.isEmpty && $0 != "—" })
            }
            protectSerials = normalized(devices)
            protectStaleSerials = normalized(devices.filter { ($0.checkin ?? .distantPast) < cutoff })
        } catch {
            protectSerials = []
            protectStaleSerials = []
            deviceLoadError = "Failed to load Jamf Protect data: \(error.localizedDescription)"
        }
    }
    
    private func applyFilter(_ f: ReportFilter, to r: [ReportDeviceResult]) -> [ReportDeviceResult] {
        switch f.parameters {
        case .lastCheckIn(let cmp, let val, let unit):
            let cutoff = Date().addingTimeInterval(-Double(val) * unit.seconds)
            return r.filter { d in guard let lc = d.lastCheckIn else { return cmp == .moreThan }; return cmp == .within ? lc >= cutoff : lc < cutoff }
        case .supervision(let s): return s == .all ? r : r.filter { s == .supervised ? $0.isSupervised : !$0.isSupervised }
        case .encryption(let s): return s == .all ? r : r.filter { s == .encrypted ? $0.isEncrypted : !$0.isEncrypted }
        case .osVersion(let v, let cmp):
            return r.filter { d in guard d.osVersion != "Unknown" else { return false }; let c = d.osVersion.compare(v, options: .numeric); return cmp == "At least" ? c != .orderedAscending : (cmp == "Exactly" ? c == .orderedSame : c == .orderedAscending) }
        case .model(let id): return r.filter { $0.model.localizedCaseInsensitiveContains(id) }
        case .site(let name, let comparison):
            return r.filter {
                let matches = $0.siteName.localizedCaseInsensitiveContains(name)
                return comparison == .memberOf ? matches : !matches
            }
        case .applications(let type, let appName):
            return r.filter { device in
                guard device.platform == .macOS else { return type == .missingApp }
                guard let computer = computerCache.computers.first(where: { $0.id == device.id }) else { return type == .missingApp }
                let hasApp = computer.hasAppInstalled(appName)
                return type == .hasApp ? hasApp : !hasApp
            }
        case .appleCare(let status):
            return r.filter { device in
                let coverageInfo = getDeviceCoverageInfo(device)
                switch status {
                case .all: return true
                case .active: return coverageInfo.hasData && !coverageInfo.isExpired && !coverageInfo.isExpiringSoon
                case .expiringSoon: return coverageInfo.hasData && coverageInfo.isExpiringSoon
                case .expired: return coverageInfo.hasData && coverageInfo.isExpired
                case .noCoverage: return !coverageInfo.hasData
                }
            }
        case .softwareUpdates(let status):
            return r.filter { device in
                let updateInfo = getDeviceSoftwareUpdateInfo(device)
                switch status {
                case .all: return true
                case .hasPendingUpdates: return updateInfo.hasData && updateInfo.pendingCount > 0
                case .upToDate: return updateInfo.hasData && updateInfo.pendingCount == 0
                case .noUpdateData: return !updateInfo.hasData
                }
            }
        case .staleDevices(let level):
            let cutoff = Date().addingTimeInterval(-Double(level.days) * 86400)
            return r.filter { device in
                guard let lc = device.lastCheckIn else { return true }  // never checked in counts as stale
                return lc < cutoff
            }
        case .unmanaged(let status):
            return r.filter { device in
                // Management status is tracked only for macOS computers.
                guard device.platform == .macOS,
                      let computer = computerCache.computers.first(where: { $0.id == device.id }) else {
                    return false
                }
                return status == .managedOnly ? computer.isManaged : !computer.isManaged
            }
        case .protectCoverage(let status):
            return r.filter { device in
                // Jamf Protect covers macOS only; other platforms are excluded
                // entirely rather than reported as "missing coverage".
                guard device.platform == .macOS else { return false }
                let serial = device.serialNumber.uppercased()
                // Placeholder serials can't be matched — treat as "no record".
                guard serial != "N/A", serial != "—", !serial.isEmpty else {
                    return status == .notCovered
                }
                switch status {
                case .covered: return protectSerials.contains(serial)
                case .notCovered: return !protectSerials.contains(serial)
                case .protectStale: return protectStaleSerials.contains(serial)
                }
            }
        case .computerGroup(let name):
            return r.filter { device in
                guard device.platform == .macOS,
                      let computer = computerCache.computers.first(where: { $0.id == device.id }) else { return false }
                return (computer.groupMemberships ?? []).contains { $0.groupName?.caseInsensitiveCompare(name) == .orderedSame }
            }
        case .deviceGroup(let name):
            return r.filter { device in
                guard device.platform != .macOS,
                      let mobile = mobileCache.devices.first(where: { $0.id == device.id }) else { return false }
                return (mobile.groups ?? []).contains { $0.groupName?.caseInsensitiveCompare(name) == .orderedSame }
            }
        }
    }

    /// Get coverage info from a device result by looking up purchasing data
    private func getDeviceCoverageInfo(_ device: ReportDeviceResult) -> (hasData: Bool, isExpired: Bool, isExpiringSoon: Bool) {
        if device.platform == .macOS {
            guard let computer = computerCache.computers.first(where: { $0.id == device.id }) else {
                return (false, false, false)
            }
            
            let vendor = computer.purchasing?.vendor
            let hasVendor = vendor != nil && !vendor!.isEmpty
            
            var warrantyDate: Date? = nil
            if let warrantyDateStr = computer.purchasing?.warrantyDate, !warrantyDateStr.isEmpty {
                let isoFormatter = ISO8601DateFormatter()
                isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = isoFormatter.date(from: warrantyDateStr) {
                    warrantyDate = date
                } else {
                    isoFormatter.formatOptions = [.withInternetDateTime]
                    if let date = isoFormatter.date(from: warrantyDateStr) {
                        warrantyDate = date
                    } else {
                        let simpleFormatter = DateFormatter()
                        simpleFormatter.dateFormat = "yyyy-MM-dd"
                        warrantyDate = simpleFormatter.date(from: warrantyDateStr)
                    }
                }
            }
            
            let hasData = hasVendor || warrantyDate != nil
            
            var isExpired = false
            var isExpiringSoon = false
            if let date = warrantyDate {
                isExpired = date < Date()
                if !isExpired {
                    let daysRemaining = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
                    isExpiringSoon = daysRemaining <= 90
                }
            }
            
            return (hasData, isExpired, isExpiringSoon)
        }
        
        if let mobileDevice = mobileCache.devices.first(where: { $0.id == device.id }) {
            let vendor = mobileDevice.purchasing?.vendor
            let hasVendor = vendor != nil && !vendor!.isEmpty
            
            var warrantyDate: Date? = nil
            if let warrantyDateStr = mobileDevice.purchasing?.warrantyExpiresDate, !warrantyDateStr.isEmpty {
                let isoFormatter = ISO8601DateFormatter()
                isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = isoFormatter.date(from: warrantyDateStr) {
                    warrantyDate = date
                } else {
                    isoFormatter.formatOptions = [.withInternetDateTime]
                    if let date = isoFormatter.date(from: warrantyDateStr) {
                        warrantyDate = date
                    } else {
                        let simpleFormatter = DateFormatter()
                        simpleFormatter.dateFormat = "yyyy-MM-dd"
                        warrantyDate = simpleFormatter.date(from: warrantyDateStr)
                    }
                }
            }
            
            let hasData = hasVendor || warrantyDate != nil
            
            var isExpired = false
            var isExpiringSoon = false
            if let date = warrantyDate {
                isExpired = date < Date()
                if !isExpired {
                    let daysRemaining = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
                    isExpiringSoon = daysRemaining <= 90
                }
            }
            
            return (hasData, isExpired, isExpiringSoon)
        }
        
        return (false, false, false)
    }
    
    /// Get software update info from a device result
    private func getDeviceSoftwareUpdateInfo(_ device: ReportDeviceResult) -> (hasData: Bool, pendingCount: Int) {
        // Software updates only available for macOS currently
        if device.platform == .macOS {
            guard let computer = computerCache.computers.first(where: { $0.id == device.id }) else {
                return (false, 0)
            }
            
            // softwareUpdates is an array of pending updates from the inventory
            let updates = computer.softwareUpdates ?? []
            // hasData is true if we have the section (even if empty means up to date)
            // We consider having the computer record as having data
            return (true, updates.count)
        }
        
        // Mobile devices don't have software update data in the same way
        return (false, 0)
    }
    
    // MARK: - Device Detail Navigation
    
}

// MARK: - Saved Report Card

struct SavedReportCard: View {
    let report: SavedReport
    let isDark: Bool
    let onLoad: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    @State private var showingDeleteConfirm = false
    
    private var dateFormatter: DateFormatter {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.purple)
                Spacer()
                Menu {
                    Button { onLoad() } label: { Label("Load Report", systemImage: "arrow.right.circle") }
                    Divider()
                    Button(role: .destructive) { showingDeleteConfirm = true } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 14)).foregroundColor(.gray)
                        .frame(width: 28, height: 28).background(Circle().fill(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)))
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(report.name).font(.system(size: 15, weight: .semibold)).foregroundColor(isDark ? .white : .primary).lineLimit(1)
                if !report.description.isEmpty {
                    Text(report.description).font(.system(size: 12)).foregroundColor(.gray).lineLimit(2)
                }
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Label("\(report.platforms.count)", systemImage: "rectangle.stack").font(.system(size: 11)).foregroundColor(.gray)
                Label("\(report.filters.count)", systemImage: "line.3.horizontal.decrease.circle").font(.system(size: 11)).foregroundColor(.gray)
            }
            
            Divider().background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Created").font(.system(size: 10)).foregroundColor(.gray)
                    Text(dateFormatter.string(from: report.createdAt)).font(.system(size: 10, weight: .medium)).foregroundColor(isDark ? .white.opacity(0.7) : .primary.opacity(0.7))
                }
                Spacer()
                Button { onLoad() } label: {
                    Text("Load").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6).background(Color.purple).cornerRadius(6)
                }.buttonStyle(ScaleButtonStyle())
            }
        }
        .padding(16)
        .frame(height: 180)
        .background(RoundedRectangle(cornerRadius: 12).fill(isDark ? Color.white.opacity(isHovered ? 0.06 : 0.03) : Color.white.opacity(isHovered ? 0.9 : 0.7)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08), lineWidth: 1))
        .shadow(color: isDark ? .clear : .black.opacity(0.05), radius: 8, x: 0, y: 4)
        .onHover { isHovered = $0 }
        .alert("Delete Report?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { onDelete() }
        } message: {
            Text("This will permanently delete '\(report.name)'.")
        }
    }
}

// MARK: - Report Results View

/// The dedicated results screen (presented as a modal sheet): searchable,
/// sortable, with a prominent export and its own device-detail navigation.
struct ReportResultsView: View {
    let results: [ReportDeviceResult]
    let exportFilename: String
    let makeExportTable: () -> ReportTable
    let isDark: Bool
    let onClose: () -> Void

    @State private var path = NavigationPath()
    @State private var loadingDeviceId: String?
    @State private var isLoadingDeviceDetail = false
    @State private var deviceLoadError: String?
    @State private var search = ""
    @State private var sortColumn: Column = .name
    @State private var sortAscending = true

    enum Column: String, CaseIterable {
        case name = "Device Name", serial = "Serial", platform = "Platform"
        case checkIn = "Last Check-In", supervised = "Supervised", encrypted = "Encrypted"
        case os = "OS", model = "Model"
        var width: CGFloat {
            switch self {
            case .name: return 200
            case .serial, .checkIn, .model: return 140
            case .platform, .supervised, .encrypted: return 90
            case .os: return 80
            }
        }
    }

    private static let df: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short; return f
    }()

    private var displayed: [ReportDeviceResult] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = q.isEmpty ? results : results.filter { matches($0, q) }
        return base.sorted(by: lessThan)
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header
                searchBar
                tableHeaderRow
                Divider().background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                if displayed.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(displayed) { r in
                                row(r)
                                Divider().background(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.05))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(AnimatedBackgroundView(animate: .constant(true)))
            .navigationDestination(for: Computer.self) { computer in
                DeviceView(computer: computer)
            }
            .navigationDestination(for: MobileDevice.self) { device in
                MobileDeviceView(device: device)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 30, y: 10)
        .alert("Error Loading Device", isPresented: .init(
            get: { deviceLoadError != nil },
            set: { if !$0 { deviceLoadError = nil } }
        )) {
            Button("OK") { deviceLoadError = nil }
        } message: {
            Text(deviceLoadError ?? "Unknown error")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Button { onClose() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                    Text("Back").font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(isDark ? .white : .primary)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .help("Back to Report Builder")
            VStack(alignment: .leading, spacing: 4) {
                Text("Results").font(.system(size: 24, weight: .bold)).foregroundColor(isDark ? .white : .primary)
                Text("\(displayed.count) of \(results.count) devices").font(.system(size: 13)).foregroundColor(.gray)
            }
            Spacer()
            if !results.isEmpty {
                ReportsExportMenu(filename: exportFilename, makeTable: makeExportTable, isDark: isDark, prominent: true)
            }
        }
        .padding(.bottom, 16)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundColor(.gray)
            TextField("Search name, serial, model, OS, platform…", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundColor(.gray)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
        .cornerRadius(10)
        .padding(.bottom, 12)
    }

    private var tableHeaderRow: some View {
        HStack(spacing: 0) {
            ForEach(Column.allCases, id: \.self) { col in
                Button { toggleSort(col) } label: {
                    HStack(spacing: 4) {
                        Text(col.rawValue).font(.system(size: 12, weight: .semibold)).foregroundColor(sortColumn == col ? (isDark ? .white : .primary) : .gray)
                        if sortColumn == col {
                            Image(systemName: sortAscending ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .bold)).foregroundColor(.cyan)
                        }
                    }
                    .frame(width: col.width, alignment: .leading)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.vertical, 12)
    }

    private func row(_ r: ReportDeviceResult) -> some View {
        let isLoading = isLoadingDeviceDetail && loadingDeviceId == r.id
        return Button {
            handleDeviceTap(r)
        } label: {
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                    } else {
                        Image(systemName: r.platform.icon).font(.system(size: 12)).foregroundColor(r.platform.color)
                    }
                    Text(r.deviceName).font(.system(size: 12, weight: .medium)).foregroundColor(isDark ? .white : .primary).lineLimit(1)
                    if !r.inJamf {
                        Text("ADE").font(.system(size: 8, weight: .bold)).foregroundColor(.orange)
                            .padding(.horizontal, 4).padding(.vertical, 1).background(Capsule().fill(Color.orange.opacity(0.15)))
                    }
                }.frame(width: Column.name.width, alignment: .leading).padding(.horizontal, 8)
                Text(r.serialNumber).font(.system(size: 11, design: .monospaced)).foregroundColor(.gray).frame(width: Column.serial.width, alignment: .leading).padding(.horizontal, 8)
                Text(r.platform.rawValue).font(.system(size: 11)).foregroundColor(.gray).frame(width: Column.platform.width, alignment: .leading).padding(.horizontal, 8)
                Text(r.lastCheckIn.map { Self.df.string(from: $0) } ?? "N/A").font(.system(size: 11)).foregroundColor(.gray).frame(width: Column.checkIn.width, alignment: .leading).padding(.horizontal, 8)
                statusBadge(r.isSupervised).frame(width: Column.supervised.width, alignment: .leading).padding(.horizontal, 8)
                statusBadge(r.isEncrypted).frame(width: Column.encrypted.width, alignment: .leading).padding(.horizontal, 8)
                Text(r.osVersion).font(.system(size: 11)).foregroundColor(.gray).frame(width: Column.os.width, alignment: .leading).padding(.horizontal, 8)
                Text(r.model).font(.system(size: 11)).foregroundColor(.gray).lineLimit(1).frame(width: Column.model.width, alignment: .leading).padding(.horizontal, 8)
                Spacer()
            }
            .padding(.vertical, 8)
            .background(isDark ? Color.white.opacity(0.001) : Color.black.opacity(0.001))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .opacity(isLoading ? 0.6 : 1.0)
    }

    private func statusBadge(_ v: Bool) -> some View {
        Text(v ? "Yes" : "No").font(.system(size: 10, weight: .medium)).foregroundColor(v ? .green : .orange)
            .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(v ? Color.green.opacity(0.15) : Color.orange.opacity(0.15)))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass").font(.system(size: 40)).foregroundColor(.gray.opacity(0.5))
            Text(results.isEmpty ? "No devices match the report" : "No devices match your search")
                .font(.system(size: 15)).foregroundColor(.gray)
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func toggleSort(_ col: Column) {
        if sortColumn == col { sortAscending.toggle() }
        else { sortColumn = col; sortAscending = true }
    }

    private func matches(_ r: ReportDeviceResult, _ q: String) -> Bool {
        r.deviceName.lowercased().contains(q)
            || r.serialNumber.lowercased().contains(q)
            || r.platform.rawValue.lowercased().contains(q)
            || r.osVersion.lowercased().contains(q)
            || r.model.lowercased().contains(q)
            || r.siteName.lowercased().contains(q)
            || (r.enrollment?.profileStatus?.displayName.lowercased().contains(q) ?? false)
            || (r.enrollmentInstanceName?.lowercased().contains(q) ?? false)
    }

    private func lessThan(_ a: ReportDeviceResult, _ b: ReportDeviceResult) -> Bool {
        // Reverse by direction of comparison, never by negating the result —
        // negation returns true for equal keys and breaks strict-weak-ordering
        // (unstable order and a possible sorted(by:) trap on ties).
        let order = compare(a, b)
        guard order != .orderedSame else { return false }
        return sortAscending ? order == .orderedAscending : order == .orderedDescending
    }

    private func compare(_ a: ReportDeviceResult, _ b: ReportDeviceResult) -> ComparisonResult {
        switch sortColumn {
        case .name: return a.deviceName.localizedCaseInsensitiveCompare(b.deviceName)
        case .serial: return a.serialNumber.localizedCaseInsensitiveCompare(b.serialNumber)
        case .platform: return a.platform.rawValue.localizedCaseInsensitiveCompare(b.platform.rawValue)
        case .checkIn: return Self.compareDates(a.lastCheckIn, b.lastCheckIn)
        case .supervised: return Self.compareBools(a.isSupervised, b.isSupervised)
        case .encrypted: return Self.compareBools(a.isEncrypted, b.isEncrypted)
        case .os: return a.osVersion.compare(b.osVersion, options: .numeric)
        case .model: return a.model.localizedCaseInsensitiveCompare(b.model)
        }
    }

    private static func compareDates(_ a: Date?, _ b: Date?) -> ComparisonResult {
        let x = a ?? .distantPast, y = b ?? .distantPast
        if x == y { return .orderedSame }
        return x < y ? .orderedAscending : .orderedDescending
    }

    private static func compareBools(_ a: Bool, _ b: Bool) -> ComparisonResult {
        if a == b { return .orderedSame }
        return (!a && b) ? .orderedAscending : .orderedDescending
    }

    // MARK: - Device detail navigation (within the modal)

    private func handleDeviceTap(_ device: ReportDeviceResult) {
        guard !isLoadingDeviceDetail else { return }
        // ADE-only rows have no Jamf record to open.
        guard device.inJamf else { return }

        if device.platform == .macOS {
            if let computer = ComputerInventoryCache.shared.computers.first(where: { $0.id == device.id }) {
                path.append(Computer.fromInventoryItem(computer))
            }
        } else {
            fetchMobileDeviceAndShow(device)
        }
    }

    private func fetchMobileDeviceAndShow(_ device: ReportDeviceResult) {
        isLoadingDeviceDetail = true
        loadingDeviceId = device.id
        Task {
            do {
                let mobileDevice = try await fetchMobileDeviceDetail(id: device.id)
                isLoadingDeviceDetail = false
                loadingDeviceId = nil
                path.append(mobileDevice)
            } catch {
                isLoadingDeviceDetail = false
                loadingDeviceId = nil
                deviceLoadError = "Failed to load device details: \(error.localizedDescription)"
            }
        }
    }

    private func fetchMobileDeviceDetail(id: String) async throws -> MobileDevice {
        let config = MDMConfigurationManager.shared.configuration
        let jamfURL = config.jamfURL
        let masterClientID = config.masterClientID
        let masterClientSecret = config.masterClientSecret

        guard let tokenURL = URL(string: "\(jamfURL)/api/v1/oauth/token") else {
            throw NSError(domain: "ReportResultsView", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var tokenRequest = URLRequest(url: tokenURL)
        tokenRequest.httpMethod = "POST"
        tokenRequest.setValue("application/json", forHTTPHeaderField: "accept")
        tokenRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
        tokenRequest.httpBody = "grant_type=client_credentials&client_id=\(masterClientID)&client_secret=\(masterClientSecret)".data(using: .utf8)

        let (tokenData, tokenResponse) = try await URLSession.shared.data(for: tokenRequest)
        guard let httpTokenResponse = tokenResponse as? HTTPURLResponse,
              (200...299).contains(httpTokenResponse.statusCode) else {
            throw NSError(domain: "ReportResultsView", code: 401, userInfo: [NSLocalizedDescriptionKey: "Authentication failed"])
        }

        struct TokenResponse: Codable { let access_token: String }
        let token = try JSONDecoder().decode(TokenResponse.self, from: tokenData).access_token

        let sections = [
            "GENERAL", "HARDWARE", "USER_AND_LOCATION", "PURCHASING", "SECURITY",
            "APPLICATIONS", "EBOOKS", "NETWORK", "SERVICE_SUBSCRIPTIONS",
            "CERTIFICATES", "PROFILES", "GROUPS", "EXTENSION_ATTRIBUTES",
        ]
        let sectionParams = sections.map { "section=\($0)" }.joined(separator: "&")
        guard let url = URL(string: "\(jamfURL)/api/v2/mobile-devices/\(id)/detail?\(sectionParams)") else {
            throw NSError(domain: "ReportResultsView", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid device URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = NetworkTuning.connectionTimeout
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "ReportResultsView", code: 404, userInfo: [NSLocalizedDescriptionKey: "Device not found"])
        }
        return try JSONDecoder().decode(MobileDevice.self, from: data)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 10
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing).size }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (i, s) in subviews.enumerated() { s.place(at: CGPoint(x: bounds.minX + r.positions[i].x, y: bounds.minY + r.positions[i].y), proposal: .unspecified) }
    }
    struct FlowResult {
        var size: CGSize = .zero; var positions: [CGPoint] = []
        init(in maxW: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0, y: CGFloat = 0, lh: CGFloat = 0
            for s in subviews { let sz = s.sizeThatFits(.unspecified); if x + sz.width > maxW && x > 0 { x = 0; y += lh + spacing; lh = 0 }; positions.append(CGPoint(x: x, y: y)); lh = max(lh, sz.height); x += sz.width + spacing; size.width = max(size.width, x) }
            size.height = y + lh
        }
    }
}

#if DEBUG
#Preview("Reports") { ReportsView().frame(width: 1400, height: 900) }
#endif
