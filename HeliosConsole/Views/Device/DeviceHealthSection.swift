//
//  DeviceHealthSection.swift
//  Helios
//
//  Device Health Section showing health metrics specific to a device
//  Matches the Environment Health Scorecard but for individual device evaluation
//

import SwiftUI

// MARK: - Device Health Status

enum DeviceHealthStatus: String {
    case compliant = "Compliant"
    case nonCompliant = "Non-Compliant"
    case unknown = "Unknown"
    case excluded = "Excluded"
    
    var color: Color {
        switch self {
        case .compliant: return .green
        case .nonCompliant: return .red
        case .unknown: return .yellow
        case .excluded: return .gray
        }
    }
    
    var icon: String {
        switch self {
        case .compliant: return "checkmark.circle.fill"
        case .nonCompliant: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        case .excluded: return "minus.circle.fill"
        }
    }
}

// MARK: - Device Health Metric Result

struct DeviceHealthMetricResult: Identifiable {
    let id = UUID()
    let type: HealthMetricType
    let status: DeviceHealthStatus
    let reasons: [String]  // Reasons for non-compliance (empty if compliant)
}

// MARK: - Device Health Evaluator

struct DeviceHealthEvaluator {
    
    // Tunables are per-target now and resolved inside HealthPolicy from whichever
    // target matched this device, so the panel no longer reads them directly.

    // MARK: - Evaluate Computer Health
    
    /// Routes every metric through HealthEvaluator — the same implementation the
    /// fleet scorecard uses. This struct previously held a third copy of the
    /// metric logic, which had drifted from the fleet in four places: a stricter
    /// app matcher, a different FileVault pass-set, a contradiction between its
    /// own Encrypted and Secured checks, and string-level check-in fallback.
    static func evaluateComputer(_ computer: Computer) -> [DeviceHealthMetricResult] {
        let policy = HealthPolicy.current()
        let input = healthInput(computer)
        let facts = computer.scopeFacts()

        return HealthMetricType.allCases.map { metric in
            // .deviceDetail: a site the admin carved out of the SCORECARD still
            // shows its real per-metric value here. The exclusion only removes
            // the device from the fleet numerator/denominator, and it should
            // not blank out the device's own health page.
            let evaluation = HealthEvaluator.evaluate(
                metric, computer: input, facts: facts, policy: policy, mode: .deviceDetail
            )
            return DeviceHealthMetricResult(
                type: metric,
                status: status(for: evaluation.verdict),
                reasons: evaluation.reasons
            )
        }
    }
    
    // MARK: - Evaluation

    /// The per-device fetch (ComputerSearchService) requests every inventory
    /// section, so a nil top-level object here means this Computer came from a
    /// lossy projection — fromDeviceListItem and fromInventoryItem drop
    /// applications, security and site — rather than that the Mac lacks the data.
    /// Declaring the section unavailable makes the panel report "cannot evaluate"
    /// instead of a confident wrong answer such as "FileVault is not enabled" on
    /// an encrypted Mac opened from Reports.
    private static func availability(for computer: Computer) -> SectionAvailability {
        var known: Set<String> = []
        if computer.general != nil { known.insert("GENERAL") }
        if computer.hardware != nil { known.insert("HARDWARE") }
        if computer.operatingSystem != nil { known.insert("OPERATING_SYSTEM") }
        if computer.applications != nil { known.insert("APPLICATIONS") }
        if computer.security != nil { known.insert("SECURITY") }
        if computer.diskEncryption != nil { known.insert("DISK_ENCRYPTION") }
        if computer.groupMemberships != nil { known.insert("GROUP_MEMBERSHIPS") }
        return SectionAvailability(
            known: known,
            configKey: "this device's inventory record"
        )
    }

    private static func healthInput(_ computer: Computer) -> ComputerHealthInput {
        ComputerHealthInput(
            deviceID: computer.id,
            rawSiteName: computer.general?.site?.name,
            checkInDate: HealthEvaluator.resolveCheckIn(
                lastContactTime: computer.general?.lastContactTime,
                reportDate: computer.general?.reportDate
            ),
            isManaged: computer.isManaged,
            isSupervised: computer.isSupervised,
            ddmEnabled: computer.general?.declarativeDeviceManagementEnabled ?? false,
            osVersion: computer.operatingSystem?.version,
            applicationNames: computer.applications.map { $0.compactMap(\.name) },
            firewallEnabled: computer.security?.firewallEnabled ?? false,
            sipStatus: computer.security?.sipStatus,
            gatekeeperStatus: computer.security?.gatekeeperStatus,
            bootstrapTokenEscrowedStatus: computer.security?.bootstrapTokenEscrowedStatus,
            encryptionState: BootEncryptionState.parse(
                partitionState: computer.diskEncryption?.bootPartitionEncryptionDetails?.partitionFileVault2State,
                fileVault2Enabled: computer.diskEncryption?.fileVault2Enabled,
                hasDiskEncryptionObject: computer.diskEncryption != nil
            ),
            availability: availability(for: computer)
        )
    }

    private static func status(for verdict: HealthVerdict) -> DeviceHealthStatus {
        switch verdict {
        case .compliant: return .compliant
        case .nonCompliant: return .nonCompliant
        case .unknown: return .unknown
        case .excluded: return .excluded
        }
    }
}

// MARK: - Device Health Section View

struct DeviceHealthSection: View {
    let computer: Computer
    
    @State private var healthResults: [DeviceHealthMetricResult] = []
    @State private var selectedMetric: HealthMetricType? = nil
    @State private var appleCareLoading: Bool = false
    @State private var appleCareData: [AppleCareCoverage] = []
    @State private var appleCareError: String? = nil
    
    // MARK: - Coverage Data Source
    
    private enum CoverageSource {
        case jamfPurchasing    // Data from Jamf inventory purchasing section
        case abmAPI            // Data from ABM API
        case none              // No data available
    }
    
    /// Determines if Jamf purchasing has AppleCare data
    private var jamfPurchasingCoverage: (hasData: Bool, vendor: String?, warrantyDate: Date?, isExpired: Bool, isExpiringSoon: Bool) {
        guard let purchasing = computer.purchasing else {
            return (false, nil, nil, false, false)
        }
        
        let vendor = purchasing.vendor
        let hasVendor = vendor != nil && !vendor!.isEmpty
        
        // Parse warranty date
        var warrantyDate: Date? = nil
        if let warrantyDateStr = purchasing.warrantyDate, !warrantyDateStr.isEmpty {
            // Try ISO8601 formats
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFormatter.date(from: warrantyDateStr) {
                warrantyDate = date
            } else {
                isoFormatter.formatOptions = [.withInternetDateTime]
                if let date = isoFormatter.date(from: warrantyDateStr) {
                    warrantyDate = date
                } else {
                    // Try simple date format
                    let simpleFormatter = DateFormatter()
                    simpleFormatter.dateFormat = "yyyy-MM-dd"
                    warrantyDate = simpleFormatter.date(from: warrantyDateStr)
                }
            }
        }
        
        // Only consider it valid if we have either a vendor or a warranty date
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
        
        return (hasData, vendor, warrantyDate, isExpired, isExpiringSoon)
    }
    
    /// The active coverage source being used
    private var coverageSource: CoverageSource {
        if jamfPurchasingCoverage.hasData {
            return .jamfPurchasing
        } else if !appleCareData.isEmpty {
            return .abmAPI
        } else {
            return .none
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "heart.text.square")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.pink, .red],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("Device Health")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Overall health indicator
                overallHealthBadge
            }
            
            // Health metrics grid
            HStack(spacing: 12) {
                ForEach(healthResults) { result in
                    healthMetricCard(result)
                }
            }
            .frame(height: 100)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.03))
                .background(.ultraThinMaterial.opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
        .onAppear {
            healthResults = DeviceHealthEvaluator.evaluateComputer(computer)
            loadAppleCareData()
        }
        // Re-evaluate when the record itself changes. A panel opened from the
        // device list or a health drill-down is first rendered from a lossy
        // projection, which now honestly reports Unknown for the sections that
        // projection cannot carry; without this the panel would keep showing
        // Unknown after DeviceView swaps in the full inventory record.
        .onChange(of: computer) { _, newValue in
            healthResults = DeviceHealthEvaluator.evaluateComputer(newValue)
        }
    }
    
    // MARK: - Load AppleCare Data
    
    private func loadAppleCareData() {
        // Priority 1: Check Jamf purchasing data first
        if jamfPurchasingCoverage.hasData {
            // We have Jamf data, no need to call ABM API
            return
        }
        
        // Priority 2: Fall back to ABM API
        guard ABMAPIService.shared.isConfigured else {
            appleCareError = "ABM not configured"
            return
        }
        guard let serialNumber = computer.hardware?.serialNumber, !serialNumber.isEmpty else {
            appleCareError = "No serial number available"
            return
        }
        
        // Check coverage cache first
        if let cached = ABMAPIService.shared.getCachedCoverage(forSerialNumber: serialNumber) {
            appleCareData = cached
            return
        }
        
        appleCareLoading = true
        appleCareError = nil
        
        Task {
            await loadAppleCareDataFromAPI(serialNumber: serialNumber)
        }
    }
    
    private func loadAppleCareDataFromAPI(serialNumber: String) async {
        do {
            let coverages = try await ABMAPIService.shared.getAppleCareCoverage(forSerialNumber: serialNumber)
            await MainActor.run {
                appleCareData = coverages
                appleCareLoading = false
                if coverages.isEmpty {
                    appleCareError = "No coverage records found"
                }
            }
        } catch let error as ABMError {
            await MainActor.run {
                appleCareError = error.errorDescription ?? error.localizedDescription
                appleCareLoading = false
            }
        } catch {
            await MainActor.run {
                appleCareError = error.localizedDescription
                appleCareLoading = false
            }
        }
    }
    
    // MARK: - Coverage Status (Unified across Jamf and ABM sources)
    
    /// The ABM coverage record that drives the card's status.
    ///
    /// A device commonly carries BOTH a Limited Warranty and an AppleCare
    /// agreement. Taking whichever ABM happened to return first meant an
    /// expired limited warranty could mask valid AppleCare and paint the card
    /// red. AppleCare always wins; within a tier a live plan beats an expired
    /// one, and the latest end date breaks any remaining tie.
    private var activeCoverage: AppleCareCoverage? {
        appleCareData
            .filter { $0.isActive }
            .max { coverageRank($0) < coverageRank($1) }
    }

    /// Sort key for `activeCoverage` — higher wins.
    private func coverageRank(_ coverage: AppleCareCoverage) -> (Int, Int, Date) {
        (
            coverage.isAppleCarePlan ? 1 : 0,
            coverage.isExpired ? 0 : 1,
            coverage.endDate ?? .distantPast
        )
    }
    
    /// Whether device has active coverage from any source
    private var hasActiveCoverage: Bool {
        switch coverageSource {
        case .jamfPurchasing:
            // If we have Jamf data, check if warranty is not expired
            return !jamfPurchasingCoverage.isExpired
        case .abmAPI:
            return activeCoverage != nil
        case .none:
            return false
        }
    }
    
    /// Whether coverage is expiring soon from any source
    private var isCoverageExpiringSoon: Bool {
        switch coverageSource {
        case .jamfPurchasing:
            return jamfPurchasingCoverage.isExpiringSoon
        case .abmAPI:
            return activeCoverage?.isExpiringSoon ?? false
        case .none:
            return false
        }
    }
    
    /// Whether coverage is expired from any source
    private var isCoverageExpired: Bool {
        switch coverageSource {
        case .jamfPurchasing:
            return jamfPurchasingCoverage.isExpired
        case .abmAPI:
            return activeCoverage?.isExpired ?? false
        case .none:
            return false
        }
    }
    
    // MARK: - Overall Health Badge
    
    private var overallHealthBadge: some View {
        let compliantCount = healthResults.filter { $0.status == .compliant }.count
        let totalEvaluated = healthResults.filter { $0.status != .excluded && $0.status != .unknown }.count
        let percentage = totalEvaluated > 0 ? (compliantCount * 100) / totalEvaluated : 0
        
        let color = HealthThresholds.color(forPercentage: Double(percentage))
        
        return HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(compliantCount)/\(healthResults.count) Compliant")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(color.opacity(0.15))
        )
    }
    
    // MARK: - Health Metric Card
    
    private func healthMetricCard(_ result: DeviceHealthMetricResult) -> some View {
        // For Coverage card, determine status from AppleCare data
        let displayStatus: DeviceHealthStatus
        let displayStatusLabel: String
        
        if result.type == .encrypted {
            // Coverage card - check Jamf purchasing first, then ABM API
            if jamfPurchasingCoverage.hasData {
                // Using Jamf purchasing data
                if jamfPurchasingCoverage.isExpired {
                    displayStatus = .nonCompliant
                    displayStatusLabel = "Expired"
                } else if jamfPurchasingCoverage.isExpiringSoon {
                    displayStatus = .nonCompliant
                    displayStatusLabel = "Expiring Soon"
                } else {
                    displayStatus = .compliant
                    displayStatusLabel = "Active"
                }
            } else if appleCareLoading {
                // Loading from ABM API
                displayStatus = .unknown
                displayStatusLabel = "Loading..."
            } else if !appleCareData.isEmpty {
                // Using ABM API data
                if let active = activeCoverage {
                    if active.isExpired {
                        displayStatus = .nonCompliant
                        displayStatusLabel = "Expired"
                    } else if active.isExpiringSoon {
                        displayStatus = .nonCompliant
                        displayStatusLabel = "Expiring Soon"
                    } else {
                        displayStatus = .compliant
                        displayStatusLabel = "Active"
                    }
                } else {
                    // Has coverage data but no active coverage
                    displayStatus = .nonCompliant
                    displayStatusLabel = "Expired"
                }
            } else if appleCareError != nil && !ABMAPIService.shared.isConfigured {
                // ABM not configured and no Jamf data
                displayStatus = .unknown
                displayStatusLabel = "Unknown"
            } else if appleCareError != nil {
                // ABM error
                displayStatus = .unknown
                displayStatusLabel = "Unknown"
            } else {
                // No data from any source
                displayStatus = .unknown
                displayStatusLabel = "Unknown"
            }
        } else {
            displayStatus = result.status
            displayStatusLabel = deviceHealthStatusLabel(for: result)
        }
        
        // Every status now has popover content, so every tile opens. Keying this
        // off reasons.isEmpty made Unknown tiles unclickable in exactly the case
        // where the admin most needs the explanation.
        let isClickable = true
        let reasonCount = result.reasons.count
        
        return VStack(alignment: .center, spacing: 6) {
            HStack {
                Spacer()
                // Count badge for non-compliant cards with reasons
                if result.status == .nonCompliant && reasonCount > 0 && result.type != .encrypted {
                    Text("\(reasonCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 18, height: 18)
                        .background(
                            Circle()
                                .fill(Color.red)
                        )
                }
            }
            
            // Status icon
            Image(systemName: displayStatus.icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(displayStatus.color)
            
            Spacer()
            
            // Metric name (show "Coverage" instead of "Encrypted" for device health)
            Text(deviceHealthTitle(for: result.type))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            // Status text
            Text(displayStatusLabel)
                .font(.system(size: 10))
                .foregroundColor(displayStatus.color.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        // Tinted from displayStatus, not result.status. The Coverage card is the
        // Encrypted metric repurposed to show AppleCare, so its icon and label
        // come from warranty data while result.status still holds the encryption
        // verdict — keying the fill and border off the latter painted the tile red
        // while it read "Coverage / Unknown". For every other card the two are the
        // same value, so nothing else changes.
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(displayStatus.color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(displayStatus.color.opacity(0.3), lineWidth: 1)
        )
        .popover(isPresented: binding(for: result.type)) {
            metricDetailPopover(result)
        }
        .onTapGesture {
            if isClickable {
                selectedMetric = result.type
            }
        }
    }
    
    // MARK: - Binding Helper
    
    private func binding(for type: HealthMetricType) -> Binding<Bool> {
        Binding(
            get: { selectedMetric == type },
            set: { if !$0 { selectedMetric = nil } }
        )
    }
    
    // MARK: - Metric Detail Popover
    
    private func metricDetailPopover(_ result: DeviceHealthMetricResult) -> some View {
        // For Coverage card, determine status from AppleCare data
        let displayStatus: DeviceHealthStatus
        let displayStatusLabel: String
        
        if result.type == .encrypted {
            if appleCareLoading {
                displayStatus = .unknown
                displayStatusLabel = "Loading..."
            } else if appleCareError != nil {
                displayStatus = .unknown
                displayStatusLabel = "Unknown"
            } else if let active = activeCoverage {
                // Mirrors the tile's ladder exactly (expired → expiring → active);
                // the missing expired case here used to let the popover claim
                // "Active" while the tile behind it said "Expired".
                if active.isExpired {
                    displayStatus = .nonCompliant
                    displayStatusLabel = "Expired"
                } else if active.isExpiringSoon {
                    displayStatus = .nonCompliant
                    displayStatusLabel = "Expiring Soon"
                } else {
                    displayStatus = .compliant
                    displayStatusLabel = "Active"
                }
            } else if !appleCareData.isEmpty {
                displayStatus = .nonCompliant
                displayStatusLabel = "Expired"
            } else {
                displayStatus = .unknown
                displayStatusLabel = "Unknown"
            }
        } else {
            displayStatus = result.status
            displayStatusLabel = deviceHealthStatusLabel(for: result)
        }
        
        return VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: result.type.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: result.type.gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(deviceHealthTitle(for: result.type))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 4) {
                        Image(systemName: displayStatus.icon)
                            .font(.system(size: 10))
                            .foregroundColor(displayStatus.color)
                        Text(displayStatusLabel)
                            .font(.system(size: 11))
                            .foregroundColor(displayStatus.color)
                    }
                }
                
                Spacer()
            }
            
            Divider()
            
            // Routed on status, never on whether reasons happen to be present.
            // Unknown results now carry an explanation ("no requirements are
            // defined for site X"), and the previous reasons-first ordering would
            // have rendered those in the orange "Requirements not met" panel.
            if result.type == .encrypted {
                // Coverage card - always show AppleCare content
                coveragePopoverContent()
            } else {
                switch result.status {
                case .compliant:    compliantContent(for: result.type)
                case .excluded:     excludedContent(for: result)
                case .unknown:      unknownContent(for: result)
                case .nonCompliant: nonCompliantContent(for: result)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
    }
    
    // MARK: - Coverage Popover Content
    
    private func coveragePopoverContent() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Priority 1: Show Jamf purchasing data if available
            if jamfPurchasingCoverage.hasData {
                jamfPurchasingCoverageContent()
            }
            // Priority 2: Show ABM API data
            else if appleCareLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading coverage from ABM...")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            } else if !appleCareData.isEmpty {
                // Show ABM AppleCare coverage with source indicator
                HStack(spacing: 6) {
                    Image(systemName: "building.2")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("Source: Apple Business Manager")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 4)
                
                ForEach(appleCareData) { coverage in
                    appleCareRow(coverage)
                }
            }
            // Priority 3: Show error or unknown state
            else if let error = appleCareError {
                if !ABMAPIService.shared.isConfigured {
                    HStack(spacing: 8) {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                        Text("No coverage data")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    Text("No purchasing data in Jamf inventory and ABM is not configured.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.orange)
                        Text("Unable to retrieve coverage")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                    Text("No coverage information")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                }
                Text("No coverage records found for this device.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Jamf Purchasing Coverage Content
    
    private func jamfPurchasingCoverageContent() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Source indicator
            HStack(spacing: 6) {
                Image(systemName: "server.rack")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("Source: Jamf Inventory")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 4)
            
            let coverage = jamfPurchasingCoverage
            
            HStack(alignment: .top, spacing: 12) {
                // Status icon
                Image(systemName: coverage.isExpired ? "xmark.seal.fill" : "checkmark.seal.fill")
                    .font(.system(size: 16))
                    .foregroundColor(coverage.isExpired ? .red : (coverage.isExpiringSoon ? .orange : .green))
                
                VStack(alignment: .leading, spacing: 4) {
                    // Vendor (AppleCare type)
                    if let vendor = coverage.vendor, !vendor.isEmpty {
                        Text(vendor)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                    } else {
                        Text("Warranty Coverage")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    
                    // Warranty date (Expiration)
                    if let warrantyDate = coverage.warrantyDate {
                        if coverage.isExpired {
                            Text("Expired: \(formatDate(warrantyDate))")
                                .font(.system(size: 11))
                                .foregroundColor(.red)
                        } else if coverage.isExpiringSoon {
                            let days = Calendar.current.dateComponents([.day], from: Date(), to: warrantyDate).day ?? 0
                            Text("Expires in \(days) days")
                                .font(.system(size: 11))
                                .foregroundColor(.orange)
                        } else {
                            Text("Expires: \(formatDate(warrantyDate))")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Status badge
                    HStack(spacing: 4) {
                        Circle()
                            .fill(coverage.isExpired ? Color.red : (coverage.isExpiringSoon ? Color.orange : Color.green))
                            .frame(width: 6, height: 6)
                        Text(coverage.isExpired ? "EXPIRED" : "ACTIVE")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(coverage.isExpired ? .red : .green)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - Popover Content Views
    
    private func compliantContent(for type: HealthMetricType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.green)
                Text("All requirements met")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
            }
            
            // Show what was checked
            Group {
                switch type {
                case .checkedIn:
                    requirementRow("Device checked in within 7 days", met: true)
                case .protected:
                    let siteName = computer.general?.site?.name ?? ""
                    if siteName.lowercased() == "enterprise" {
                        requirementRow("Cisco Secure Client installed", met: true)
                        requirementRow("Zscaler installed", met: true)
                        requirementRow("QualysCloudAgent installed", met: true)
                        requirementRow("Falcon installed", met: true)
                        requirementRow("JamfProtect installed", met: true)
                    } else if siteName.lowercased() == "groundcontrol" {
                        requirementRow("Falcon installed", met: true)
                    }
                    // No else: a site with no matching rule now evaluates to Unknown,
                    // so it never reaches this Compliant popover. It previously claimed
                    // "No specific requirements for this site" with a green check.
                case .encrypted:
                    // Handled by coveragePopoverContent() - this case should not be reached
                    EmptyView()
                case .secured:
                    let siteName = computer.general?.site?.name ?? ""
                    if siteName.lowercased() == "enterprise" {
                        requirementRow("Firewall enabled", met: true)
                        requirementRow("SIP enabled", met: true)
                        requirementRow("Gatekeeper configured", met: true)
                        requirementRow("Device managed", met: true)
                        requirementRow("Device supervised", met: true)
                        requirementRow("Disk encrypted", met: true)
                        requirementRow("Bootstrap token escrowed", met: true)
                        requirementRow("DDM enabled", met: true)
                    } else if siteName.lowercased() == "groundcontrol" {
                        requirementRow("Firewall enabled", met: true)
                        requirementRow("SIP enabled", met: true)
                        requirementRow("Device managed", met: true)
                        requirementRow("Device supervised", met: true)
                        requirementRow("Bootstrap token escrowed", met: true)
                        requirementRow("DDM enabled", met: true)
                    }
                    // No else — see .protected above.
                case .upToDate:
                    requirementRow("macOS version 26.0 or higher", met: true)
                }
            }
        }
    }
    
    private func nonCompliantContent(for result: DeviceHealthMetricResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.orange)
                Text("Requirements not met")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
            }
            
            ForEach(result.reasons, id: \.self) { reason in
                requirementRow(reason, met: false)
            }
        }
    }
    
    private func excludedContent(for result: DeviceHealthMetricResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                Text("Excluded from evaluation")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
            }
            
            if let reason = result.reasons.first {
                Text(reason)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.leading, 22)
            }
        }
    }
    
    private func unknownContent(for result: DeviceHealthMetricResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.yellow)
                Text("Unable to determine status")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
            }
            
            if let reason = result.reasons.first {
                Text(reason)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.leading, 22)
            }
        }
    }
    
    private func requirementRow(_ text: String, met: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: met ? "checkmark" : "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(met ? .green : .red)
                .frame(width: 14)
            
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(.leading, 8)
    }
    
    // MARK: - Device Health Display Helpers
    
    /// Returns the display title for device health cards
    /// Shows "Coverage" instead of "Encrypted" for the encryption metric
    private func deviceHealthTitle(for type: HealthMetricType) -> String {
        switch type {
        case .encrypted:
            return "Coverage"
        default:
            return type.rawValue
        }
    }
    
    /// Returns the status label for device health cards
    /// Shows "Covered/Not Covered" instead of "Encrypted/Not Encrypted"
    private func deviceHealthStatusLabel(for result: DeviceHealthMetricResult) -> String {
        if result.type == .encrypted {
            switch result.status {
            case .compliant:
                return "Covered"
            case .nonCompliant:
                return "Not Covered"
            case .unknown:
                return "Unknown"
            case .excluded:
                return "Excluded"
            }
        }
        return result.status.rawValue
    }
    
    // MARK: - AppleCare Display Helpers
    
    private func appleCareRow(_ coverage: AppleCareCoverage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: coverage.isActive ? "checkmark.seal.fill" : "seal")
                    .font(.system(size: 10))
                    .foregroundColor(appleCareStatusColor(coverage))
                
                Text(coverage.description)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text(coverage.status.capitalized)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(appleCareStatusColor(coverage))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(appleCareStatusColor(coverage).opacity(0.15))
                    )
            }
            
            if let endDate = coverage.endDate {
                HStack(spacing: 4) {
                    if coverage.isExpired {
                        // Show WHEN it lapsed, matching the active branch — the
                        // date is the useful part when triaging a claim.
                        Text("Expired: \(formatDate(endDate))")
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                    } else if coverage.isExpiringSoon, let days = coverage.daysRemaining {
                        Text("Expires in \(days) days")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    } else {
                        Text("Expires: \(formatDate(endDate))")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.leading, 16)
            }
        }
        .padding(.leading, 8)
    }
    
    private func appleCareStatusColor(_ coverage: AppleCareCoverage) -> Color {
        if !coverage.isActive {
            return .gray
        }
        if coverage.isExpired {
            return .red
        }
        if coverage.isExpiringSoon {
            return .orange
        }
        return .green
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Device Health Section") {
    DeviceHealthSection(computer: Computer.preview)
        .padding()
        .background(Color(white: 0.1))
        .preferredColorScheme(.dark)
}
#endif
