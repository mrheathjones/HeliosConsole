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
    
    // Configuration — same features-domain keys the scorecard uses, so the
    // per-device health panel and the fleet scorecard can never disagree.
    static var checkInThresholdDays: Int {
        MDMConfigurationManager.shared.configuration.features?
            .effectiveHealthScorecard.effectiveMetric(id: "checkedIn")?
            .effectiveCheckedInDays ?? 7
    }
    static var minimumMacOSVersion: Int {
        (MDMConfigurationManager.shared.configuration.features?
            .effectiveHealthScorecard.effectiveMetric(id: "softwareUpdateCompliance")?
            .effectiveMinimumOSVersions ?? .empty).effectiveMacOS
    }
    
    // MARK: - Evaluate Computer Health
    
    static func evaluateComputer(_ computer: Computer) -> [DeviceHealthMetricResult] {
        var results: [DeviceHealthMetricResult] = []
        
        // 1. Checked-In
        results.append(evaluateCheckedIn(computer))
        
        // 2. Protected
        results.append(evaluateProtected(computer))
        
        // 3. Encrypted
        results.append(evaluateEncrypted(computer))
        
        // 4. Secured
        results.append(evaluateSecured(computer))
        
        // 5. Up to Date
        results.append(evaluateUpToDate(computer))
        
        return results
    }
    
    // MARK: - Checked-In Evaluation
    
    private static func evaluateCheckedIn(_ computer: Computer) -> DeviceHealthMetricResult {
        var reasons: [String] = []
        
        guard let lastContactStr = computer.general?.lastContactTime ?? computer.general?.reportDate else {
            return DeviceHealthMetricResult(
                type: .checkedIn,
                status: .unknown,
                reasons: ["No check-in date available"]
            )
        }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        var lastContactDate = formatter.date(from: lastContactStr)
        if lastContactDate == nil {
            formatter.formatOptions = [.withInternetDateTime]
            lastContactDate = formatter.date(from: lastContactStr)
        }
        
        guard let checkInDate = lastContactDate else {
            return DeviceHealthMetricResult(
                type: .checkedIn,
                status: .unknown,
                reasons: ["Unable to parse check-in date"]
            )
        }
        
        let thresholdDate = Calendar.current.date(byAdding: .day, value: -checkInThresholdDays, to: Date()) ?? Date()
        
        if checkInDate >= thresholdDate {
            return DeviceHealthMetricResult(type: .checkedIn, status: .compliant, reasons: [])
        } else {
            let daysSinceCheckIn = Calendar.current.dateComponents([.day], from: checkInDate, to: Date()).day ?? 0
            reasons.append("Last check-in was \(daysSinceCheckIn) days ago (threshold: \(checkInThresholdDays) days)")
            return DeviceHealthMetricResult(type: .checkedIn, status: .nonCompliant, reasons: reasons)
        }
    }
    
    // MARK: - Protected Evaluation
    
    private static func evaluateProtected(_ computer: Computer) -> DeviceHealthMetricResult {
        var reasons: [String] = []
        let siteName = computer.general?.site?.name ?? ""
        
        if siteName.lowercased() == "enterprise" {
            // Enterprise site requires all protection apps
            let requiredApps = [
                ("Cisco Secure Client", hasApp(computer, "Cisco Secure Client")),
                ("Zscaler", hasApp(computer, "Zscaler")),
                ("QualysCloudAgent", hasApp(computer, "QualysCloudAgent")),
                ("Falcon", hasApp(computer, "Falcon")),
                ("JamfProtect", hasApp(computer, "JamfProtect"))
            ]
            
            var allInstalled = true
            for (appName, installed) in requiredApps {
                if !installed {
                    allInstalled = false
                    reasons.append("\(appName) not installed")
                }
            }
            
            return DeviceHealthMetricResult(
                type: .protected,
                status: allInstalled ? .compliant : .nonCompliant,
                reasons: reasons
            )
            
        } else if siteName.lowercased() == "groundcontrol" {
            // GroundControl requires only Falcon
            let hasFalcon = hasApp(computer, "Falcon")
            
            if !hasFalcon {
                reasons.append("Falcon not installed")
            }
            
            return DeviceHealthMetricResult(
                type: .protected,
                status: hasFalcon ? .compliant : .nonCompliant,
                reasons: reasons
            )
            
        } else {
            // All other sites - Protected by default
            return DeviceHealthMetricResult(
                type: .protected,
                status: .compliant,
                reasons: []
            )
        }
    }
    
    // MARK: - Encrypted Evaluation
    
    private static func evaluateEncrypted(_ computer: Computer) -> DeviceHealthMetricResult {
        var reasons: [String] = []
        let siteName = computer.general?.site?.name ?? ""
        
        // GroundControl site is excluded from encryption evaluation
        if siteName.lowercased() == "groundcontrol" {
            return DeviceHealthMetricResult(
                type: .encrypted,
                status: .excluded,
                reasons: ["GroundControl site excluded from encryption evaluation"]
            )
        }
        
        // Check boot partition encryption state
        if let bootState = computer.diskEncryption?.bootPartitionEncryptionDetails?.partitionFileVault2State?.uppercased() {
            switch bootState {
            case "ENCRYPTED":
                return DeviceHealthMetricResult(type: .encrypted, status: .compliant, reasons: [])
            case "ENCRYPTING":
                return DeviceHealthMetricResult(type: .encrypted, status: .compliant, reasons: [])
            case "DECRYPTING", "DECRYPTING_PAUSED":
                reasons.append("Boot partition is decrypting (state: \(bootState))")
                return DeviceHealthMetricResult(type: .encrypted, status: .nonCompliant, reasons: reasons)
            default:
                reasons.append("Boot partition not encrypted (state: \(bootState))")
                return DeviceHealthMetricResult(type: .encrypted, status: .nonCompliant, reasons: reasons)
            }
        }
        
        // Fallback to fileVault2Enabled
        if computer.diskEncryption?.fileVault2Enabled == true {
            return DeviceHealthMetricResult(type: .encrypted, status: .compliant, reasons: [])
        } else if computer.diskEncryption != nil {
            reasons.append("FileVault is not enabled")
            return DeviceHealthMetricResult(type: .encrypted, status: .nonCompliant, reasons: reasons)
        }
        
        return DeviceHealthMetricResult(
            type: .encrypted,
            status: .unknown,
            reasons: ["No encryption data available"]
        )
    }
    
    // MARK: - Secured Evaluation
    
    private static func evaluateSecured(_ computer: Computer) -> DeviceHealthMetricResult {
        var reasons: [String] = []
        let siteName = computer.general?.site?.name ?? ""
        
        if siteName.lowercased() == "enterprise" {
            // Enterprise site - full security requirements
            var allMet = true
            
            let firewallEnabled = computer.security?.firewallEnabled ?? false
            if !firewallEnabled {
                allMet = false
                reasons.append("Firewall is disabled")
            }
            
            let sipEnabled = computer.security?.sipStatus?.uppercased() == "ENABLED"
            if !sipEnabled {
                allMet = false
                reasons.append("System Integrity Protection (SIP) is not enabled")
            }
            
            let gatekeeperStatus = computer.security?.gatekeeperStatus?.uppercased() ?? ""
            let gatekeeperOK = gatekeeperStatus == "APP_STORE_AND_IDENTIFIED_DEVELOPERS" || gatekeeperStatus == "APP_STORE"
            if !gatekeeperOK {
                allMet = false
                reasons.append("Gatekeeper not set to App Store & Identified Developers")
            }
            
            let isManaged = computer.isManaged
            if !isManaged {
                allMet = false
                reasons.append("Device is not managed")
            }
            
            let isSupervised = computer.isSupervised
            if !isSupervised {
                allMet = false
                reasons.append("Device is not supervised")
            }
            
            let isEncrypted = computer.diskEncryption?.bootPartitionEncryptionDetails?.partitionFileVault2State?.uppercased() == "ENCRYPTED" ||
                              computer.diskEncryption?.fileVault2Enabled == true
            if !isEncrypted {
                allMet = false
                reasons.append("Boot partition is not encrypted")
            }
            
            let bootstrapEscrowed = computer.security?.bootstrapTokenEscrowedStatus?.uppercased() == "ESCROWED"
            if !bootstrapEscrowed {
                allMet = false
                reasons.append("Bootstrap token is not escrowed")
            }
            
            let ddmEnabled = computer.general?.declarativeDeviceManagementEnabled ?? false
            if !ddmEnabled {
                allMet = false
                reasons.append("Declarative Device Management (DDM) is not enabled")
            }
            
            return DeviceHealthMetricResult(
                type: .secured,
                status: allMet ? .compliant : .nonCompliant,
                reasons: reasons
            )
            
        } else if siteName.lowercased() == "groundcontrol" {
            // GroundControl site - reduced security requirements
            var allMet = true
            
            let firewallEnabled = computer.security?.firewallEnabled ?? false
            if !firewallEnabled {
                allMet = false
                reasons.append("Firewall is disabled")
            }
            
            let sipEnabled = computer.security?.sipStatus?.uppercased() == "ENABLED"
            if !sipEnabled {
                allMet = false
                reasons.append("System Integrity Protection (SIP) is not enabled")
            }
            
            let isManaged = computer.isManaged
            if !isManaged {
                allMet = false
                reasons.append("Device is not managed")
            }
            
            let isSupervised = computer.isSupervised
            if !isSupervised {
                allMet = false
                reasons.append("Device is not supervised")
            }
            
            let bootstrapEscrowed = computer.security?.bootstrapTokenEscrowedStatus?.uppercased() == "ESCROWED"
            if !bootstrapEscrowed {
                allMet = false
                reasons.append("Bootstrap token is not escrowed")
            }
            
            let ddmEnabled = computer.general?.declarativeDeviceManagementEnabled ?? false
            if !ddmEnabled {
                allMet = false
                reasons.append("Declarative Device Management (DDM) is not enabled")
            }
            
            return DeviceHealthMetricResult(
                type: .secured,
                status: allMet ? .compliant : .nonCompliant,
                reasons: reasons
            )
            
        } else {
            // All other sites - Secured by default
            return DeviceHealthMetricResult(
                type: .secured,
                status: .compliant,
                reasons: []
            )
        }
    }
    
    // MARK: - Up to Date Evaluation
    
    private static func evaluateUpToDate(_ computer: Computer) -> DeviceHealthMetricResult {
        var reasons: [String] = []
        
        guard let osVersion = computer.operatingSystem?.version else {
            return DeviceHealthMetricResult(
                type: .upToDate,
                status: .unknown,
                reasons: ["No OS version information available"]
            )
        }
        
        guard let majorVersion = extractMajorVersion(from: osVersion) else {
            return DeviceHealthMetricResult(
                type: .upToDate,
                status: .unknown,
                reasons: ["Unable to parse OS version: \(osVersion)"]
            )
        }
        
        if majorVersion >= minimumMacOSVersion {
            return DeviceHealthMetricResult(type: .upToDate, status: .compliant, reasons: [])
        } else {
            reasons.append("macOS \(osVersion) is below minimum version \(minimumMacOSVersion).0")
            return DeviceHealthMetricResult(type: .upToDate, status: .nonCompliant, reasons: reasons)
        }
    }
    
    // MARK: - Helper Methods
    
    private static func hasApp(_ computer: Computer, _ appName: String) -> Bool {
        guard let apps = computer.applications else { return false }
        let searchName = appName.lowercased()
        return apps.contains { app in
            guard let name = app.name?.lowercased() else { return false }
            // Check for exact match or .app suffix match
            return name == searchName || name == "\(searchName).app"
        }
    }
    
    private static func extractMajorVersion(from version: String) -> Int? {
        let components = version.split(separator: ".")
        guard let firstComponent = components.first,
              let major = Int(firstComponent) else {
            return nil
        }
        return major
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
    
    /// Active ABM coverage (if using ABM API)
    private var activeCoverage: AppleCareCoverage? {
        appleCareData.first { $0.isActive }
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
        
        let isClickable = !result.reasons.isEmpty || result.status == .compliant || result.type == .encrypted
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
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(result.status.color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(result.status.color.opacity(0.3), lineWidth: 1)
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
                if active.isExpiringSoon {
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
            
            // Content based on type and status
            if result.type == .encrypted {
                // Coverage card - always show AppleCare content
                coveragePopoverContent()
            } else if result.status == .compliant {
                compliantContent(for: result.type)
            } else if result.status == .excluded {
                excludedContent(for: result)
            } else if !result.reasons.isEmpty {
                nonCompliantContent(for: result)
            } else {
                unknownContent(for: result)
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
                    } else {
                        requirementRow("No specific requirements for this site", met: true)
                    }
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
                    } else {
                        requirementRow("No specific requirements for this site", met: true)
                    }
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
                        Text("Expired")
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
