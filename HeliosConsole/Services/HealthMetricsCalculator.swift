//
//  HealthMetricsCalculator.swift
//  Helios
//
//  Calculates health metrics from cached computer and mobile device inventory data
//

import Foundation
import Combine

@MainActor
final class HealthMetricsCalculator: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = HealthMetricsCalculator()
    
    // MARK: - Published Properties
    
    @Published private(set) var healthMetrics: [HealthMetricData] = []
    @Published private(set) var isCalculating: Bool = false
    @Published private(set) var lastCalculationDate: Date?

    /// Distinct Jamf site names seen in the last calculation that matched no
    /// Protected/Secured site rule. Those devices score Unknown, so surfacing
    /// the site names tells an admin exactly which rules are missing.
    @Published private(set) var unmatchedSiteNames: [String] = []

    /// Device count per unmatched site, largest first. Distinguishes a site that
    /// needs a rule written from one that should be excluded outright.
    @Published private(set) var unmatchedSiteCounts: [(site: String, count: Int)] = []

    /// Metrics that could not be evaluated because the Jamf inventory sections
    /// they depend on were never requested. Surfaced so a missing section reads
    /// as "cannot evaluate" instead of silently scoring every device as failing.
    @Published private(set) var metricDataGaps: [MetricDataGap] = []

    struct MetricDataGap: Identifiable {
        let metric: HealthMetricType
        let platform: Platform
        let missingSections: [String]

        enum Platform: String { case computers = "Macs", mobileDevices = "mobile devices" }

        var id: String { "\(metric.rawValue)-\(platform.rawValue)" }
        /// The profile key an admin edits to fix this. Names the managed domain
        /// plus the top-level key as delivered — there is no wrapping `features`
        /// dictionary in the plist, so a `features.computers.…` path would send
        /// the admin looking for a key that does not exist.
        var configKey: String {
            let key = platform == .computers ? "computers" : "mobileDevices"
            return "com.herojoneslabs.helios.console.features → \(key).inventorySections"
        }
    }
    
    // Individual metrics for easy access
    @Published private(set) var checkedInMetric: HealthMetricData?
    @Published private(set) var protectedMetric: HealthMetricData?
    @Published private(set) var encryptedMetric: HealthMetricData?
    @Published private(set) var securedMetric: HealthMetricData?
    @Published private(set) var upToDateMetric: HealthMetricData?
    
    // MARK: - Configuration

    /// Number of days to consider a device as "recently checked in" —
    /// features domain healthScorecard.metrics[id=checkedIn].checkedInDays
    /// (schema default 7).
    var checkInThresholdDays: Int {
        MDMConfigurationManager.shared.configuration.features?
            .effectiveHealthScorecard.effectiveMetric(id: "checkedIn")?
            .effectiveCheckedInDays ?? 7
    }

    /// Minimum compliant OS major versions for the "Up to Date" metric —
    /// features domain healthScorecard.metrics[id=softwareUpdateCompliance]
    /// .minimumOSVersions. The single source for BOTH the scorecard
    /// percentage and the drill-down list (they previously hard-coded
    /// different macOS baselines and disagreed).
    var minimumOSVersions: FeaturesConfiguration.HealthMetricSetting.MinimumOSVersions {
        MDMConfigurationManager.shared.configuration.features?
            .effectiveHealthScorecard.effectiveMetric(id: "softwareUpdateCompliance")?
            .effectiveMinimumOSVersions ?? .empty
    }
    
    // MARK: - Inventory Section Requirements

    /// Jamf inventory sections each metric's evaluation depends on.
    ///
    /// A section that was never requested comes back nil on the model, and the
    /// evaluation code reads nil as failure (`?? false`, `guard … else { return
    /// false }`) — so an admin who trims `inventorySections` gets a confidently
    /// wrong percentage with no error. These tables let a metric report Unknown
    /// and name the missing section instead.
    ///
    /// Deliberately keyed off the REQUESTED section list rather than model
    /// nil-ness: Jamf may return an empty array for a device that genuinely has
    /// no applications, which is indistinguishable at the model level from a
    /// section that was never asked for.
    private enum SectionRequirement {
        static func computers(_ metric: HealthMetricType) -> [String] {
            switch metric {
            case .checkedIn: return ["GENERAL"]
            case .protected: return ["GENERAL", "APPLICATIONS"]
            // GENERAL because the GroundControl site exclusion reads siteName —
            // without it that skip silently never fires and excluded Macs are
            // folded into the numerator.
            case .encrypted: return ["GENERAL", "DISK_ENCRYPTION"]
            // DISK_ENCRYPTION is only read by the Enterprise branch, so a
            // GroundControl-only fleet is blanked slightly conservatively. Left
            // deliberately coarse until PR 3 makes the site requirements
            // configurable and the dependency can be derived per rule.
            case .secured:   return ["GENERAL", "SECURITY", "DISK_ENCRYPTION"]
            case .upToDate:  return ["OPERATING_SYSTEM"]
            }
        }

        /// Mobile section names are a different set from the computer ones —
        /// there is no mobile OPERATING_SYSTEM section, for instance; mobile
        /// osVersion lives in GENERAL.
        static func mobileDevices(_ metric: HealthMetricType) -> [String] {
            switch metric {
            case .checkedIn: return ["GENERAL"]
            case .protected: return ["GENERAL"]
            case .encrypted: return ["SECURITY"]
            // NOT HARDWARE: platformType resolves from the top-level deviceType
            // field, and HARDWARE only refines iOS into iPadOS — a distinction
            // Secured never branches on (its only split is visionOS vs the rest).
            case .secured:   return ["GENERAL", "SECURITY"]
            // HARDWARE here genuinely matters: it selects the iOS vs iPadOS
            // baseline, so without it iPads are graded against the wrong minimum
            // with no Unknowns and no other signal.
            case .upToDate:  return ["GENERAL", "HARDWARE"]
            }
        }
    }

    /// Inventory sections the profile is actually requesting, per platform.
    var configuredComputerSections: [String] {
        (MDMConfigurationManager.shared.configuration.features?
            .effectiveComputers ?? .empty).validatedInventorySections
    }

    var configuredMobileSections: [String] {
        (MDMConfigurationManager.shared.configuration.features?
            .effectiveMobileDevices ?? .empty).validatedInventorySections
    }

    /// Sections this metric needs that the profile is not requesting.
    private func missingComputerSections(for metric: HealthMetricType) -> [String] {
        let configured = Set(configuredComputerSections)
        return SectionRequirement.computers(metric).filter { !configured.contains($0) }
    }

    private func missingMobileSections(for metric: HealthMetricType) -> [String] {
        let configured = Set(configuredMobileSections)
        return SectionRequirement.mobileDevices(metric).filter { !configured.contains($0) }
    }

    /// Records a gap once per metric+platform so the banner can name it.
    private func noteDataGap(_ metric: HealthMetricType, _ platform: MetricDataGap.Platform, _ missing: [String]) {
        guard !missing.isEmpty else { return }
        dataGapAccumulator.append(MetricDataGap(metric: metric, platform: platform, missingSections: missing))
    }

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()

    /// Accumulates data gaps across a single recalculation pass.
    private var dataGapAccumulator: [MetricDataGap] = []

    /// Accumulates unmatched sites across a single recalculation pass, keyed by
    /// site name to the set of device ids seen there. Device ids rather than a
    /// running tally because Protected and Secured each walk the same computer
    /// list — a plain counter would double every device.
    private var unmatchedSitesAccumulator: [String: Set<String>] = [:]
    
    // MARK: - Initialization
    
    private init() {
        // Observe cache changes to recalculate metrics
        setupCacheObservers()
    }
    
    // MARK: - Public Methods
    
    /// Recalculate all health metrics from current cache data
    func recalculateMetrics() {
        isCalculating = true
        unmatchedSitesAccumulator.removeAll()
        dataGapAccumulator.removeAll()

        let computerCache = ComputerInventoryCache.shared
        let mobileCache = MobileDeviceInventoryCache.shared
        
        // Calculate each metric
        let checkedIn = calculateCheckedInMetric(
            computers: computerCache.computers,
            mobileDevices: mobileCache.devices
        )
        
        let protected = calculateProtectedMetric(
            computers: computerCache.computers,
            mobileDevices: mobileCache.devices
        )
        
        let encrypted = calculateEncryptedMetric(
            computers: computerCache.computers,
            mobileDevices: mobileCache.devices
        )
        
        let secured = calculateSecuredMetric(
            computers: computerCache.computers,
            mobileDevices: mobileCache.devices
        )
        
        let upToDate = calculateUpToDateMetric(
            computers: computerCache.computers,
            mobileDevices: mobileCache.devices
        )
        
        // Update published properties
        checkedInMetric = checkedIn
        protectedMetric = protected
        encryptedMetric = encrypted
        securedMetric = secured
        upToDateMetric = upToDate
        
        healthMetrics = [checkedIn, protected, encrypted, secured, upToDate]
        lastCalculationDate = Date()
        unmatchedSiteCounts = unmatchedSitesAccumulator
            .map { (site: $0.key, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.site < $1.site }
        unmatchedSiteNames = unmatchedSiteCounts.map(\.site)
        metricDataGaps = dataGapAccumulator
        isCalculating = false

        NSLog("📊 HealthMetricsCalculator: Recalculated metrics - Checked-In: %d/%d (%.1f%%)",
              checkedIn.compliantCount, checkedIn.totalCount, checkedIn.percentage)

        if !unmatchedSiteNames.isEmpty {
            NSLog("⚠️ HealthMetricsCalculator: %d site(s) matched no Protected/Secured rule and scored Unknown: %@",
                  unmatchedSiteNames.count, unmatchedSiteNames.joined(separator: ", "))
        }

        runParityCheck(computers: computerCache.computers, mobileDevices: mobileCache.devices)
    }

    /// Compares the unified HealthEvaluator against this class's live logic on the
    /// real fleet. Temporary migration scaffolding — see HealthParityCheck.
    private func runParityCheck(
        computers: [ComputerInventoryItem],
        mobileDevices: [MobileDeviceInventoryItem]
    ) {
        guard HealthParityCheck.isEnabled else { return }

        HealthParityCheck.run(
            computers: computers,
            mobileDevices: mobileDevices,
            policy: .current(checkedInDays: checkInThresholdDays, minimums: minimumOSVersions),
            computerSections: configuredComputerSections,
            mobileSections: configuredMobileSections,
            oldVerdicts: { [weak self] metric in
                guard let self else { return [:] }
                // Derive the CURRENT per-device verdict from the existing
                // drill-down rather than reimplementing it — a second copy of the
                // logic here would compare the new evaluator against itself.
                var map: [String: String] = [:]
                let segments: [(HealthSegmentType, HealthVerdict)] = [
                    (.compliant, .compliant),
                    (.nonCompliant, .nonCompliant),
                    (.unknown, .unknown)
                ]
                for (segment, verdict) in segments {
                    for item in self.getFilteredDevices(for: metric, segment: segment) {
                        map[item.originalId] = verdict.rawValue
                    }
                }
                return map
            }
        )
    }

    /// Records a device whose site fell through the Protected/Secured site cascade.
    /// Empty site names are normalised so "device has no site" is distinguishable
    /// from a real site in the diagnostic.
    private func noteUnmatchedSite(_ siteName: String, deviceID: String) {
        let trimmed = siteName.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = trimmed.isEmpty ? "(no site assigned)" : trimmed
        unmatchedSitesAccumulator[key, default: []].insert(deviceID)
    }
    
    /// Get a specific metric by type
    func metric(for type: HealthMetricType) -> HealthMetricData? {
        switch type {
        case .checkedIn: return checkedInMetric
        case .protected: return protectedMetric
        case .encrypted: return encryptedMetric
        case .secured: return securedMetric
        case .upToDate: return upToDateMetric
        }
    }
    
    // MARK: - Private Methods
    
    private func setupCacheObservers() {
        // Observe computer cache changes
        ComputerInventoryCache.shared.$computers
            .dropFirst() // Skip initial value
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.recalculateMetrics()
            }
            .store(in: &cancellables)
        
        // Observe mobile device cache changes
        MobileDeviceInventoryCache.shared.$devices
            .dropFirst() // Skip initial value
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.recalculateMetrics()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Checked-In Metric Calculation
    
    /// Calculate the "Checked-In" health metric
    /// Compliant = checked in within the last N days
    /// Non-Compliant = not checked in within the threshold
    /// Unknown = no check-in data available
    private func calculateCheckedInMetric(
        computers: [ComputerInventoryItem],
        mobileDevices: [MobileDeviceInventoryItem]
    ) -> HealthMetricData {
        
        let now = Date()
        let thresholdDate = Calendar.current.date(byAdding: .day, value: -checkInThresholdDays, to: now) ?? now
        
        var compliantCount = 0
        var nonCompliantCount = 0
        var unknownCount = 0
        
        let computerGaps = missingComputerSections(for: .checkedIn)
        noteDataGap(.checkedIn, .computers, computerGaps)
        let mobileGaps = missingMobileSections(for: .checkedIn)
        noteDataGap(.checkedIn, .mobileDevices, mobileGaps)

        // Process computers
        for computer in computers {
            guard computerGaps.isEmpty else { unknownCount += 1; continue }
            if let lastContactTime = computer.lastContactTime {
                if lastContactTime >= thresholdDate {
                    compliantCount += 1
                } else {
                    nonCompliantCount += 1
                }
            } else if let reportDateString = computer.general?.reportDate,
                      let reportDate = parseISO8601Date(reportDateString) {
                // Fall back to reportDate if lastContactTime is not available
                if reportDate >= thresholdDate {
                    compliantCount += 1
                } else {
                    nonCompliantCount += 1
                }
            } else {
                // No date information available
                unknownCount += 1
            }
        }
        
        // Process mobile devices using lastInventoryUpdate from the detail endpoint
        for device in mobileDevices {
            guard mobileGaps.isEmpty else { unknownCount += 1; continue }
            if let lastInventoryUpdate = device.lastInventoryUpdate {
                if lastInventoryUpdate >= thresholdDate {
                    compliantCount += 1
                } else {
                    nonCompliantCount += 1
                }
            } else {
                // No inventory update date available
                unknownCount += 1
            }
        }
        
        return HealthMetricData(
            type: .checkedIn,
            compliantCount: compliantCount,
            nonCompliantCount: nonCompliantCount,
            unknownCount: unknownCount
        )
    }
    
    // MARK: - Protected Metric Calculation
    
    /// Calculate the "Protected" health metric
    /// macOS: Site-based app requirements (Enterprise, GroundControl, others)
    /// iOS/iPadOS/visionOS: Managed + Supervised
    private func calculateProtectedMetric(
        computers: [ComputerInventoryItem],
        mobileDevices: [MobileDeviceInventoryItem]
    ) -> HealthMetricData {
        
        var compliantCount = 0
        var nonCompliantCount = 0
        var unknownCount = 0

        // Without APPLICATIONS the app checks all read false and every Mac would
        // report Not Protected. Score Unknown instead — we have no evidence either way.
        let computerGaps = missingComputerSections(for: .protected)
        noteDataGap(.protected, .computers, computerGaps)
        let mobileGaps = missingMobileSections(for: .protected)
        noteDataGap(.protected, .mobileDevices, mobileGaps)

        // Process computers - site-based protection requirements
        for computer in computers {
            guard computerGaps.isEmpty else { unknownCount += 1; continue }
            let siteName = computer.siteName ?? ""
            
            if siteName.lowercased() == "enterprise" {
                // Enterprise site (exact match) requires all protection apps
                let hasCiscoSecureClient = computer.hasAppInstalled("Cisco Secure Client")
                let hasZscaler = computer.hasAppInstalled("Zscaler")
                let hasQualys = computer.hasAppInstalled("QualysCloudAgent")
                let hasFalcon = computer.hasAppInstalled("Falcon")
                let hasJamfProtect = computer.hasAppInstalled("JamfProtect")
                
                if hasCiscoSecureClient && hasZscaler && hasQualys && hasFalcon && hasJamfProtect {
                    compliantCount += 1
                } else {
                    nonCompliantCount += 1
                }
            } else if siteName.lowercased() == "groundcontrol" {
                // GroundControl site (exact match) requires only Falcon
                let hasFalcon = computer.hasAppInstalled("Falcon")
                
                if hasFalcon {
                    compliantCount += 1
                } else {
                    nonCompliantCount += 1
                }
            } else {
                // No site rule matched. Scored Unknown, never Compliant: passing an
                // unevaluated device reports a compliance verdict we have no evidence
                // for, which inflates the metric and hides the gap from the admin.
                noteUnmatchedSite(siteName, deviceID: computer.id)
                unknownCount += 1
            }
        }
        
        // Process mobile devices - Managed + Supervised = Protected
        for device in mobileDevices {
            guard mobileGaps.isEmpty else { unknownCount += 1; continue }
            if device.isManaged && device.isSupervised {
                compliantCount += 1
            } else {
                nonCompliantCount += 1
            }
        }
        
        return HealthMetricData(
            type: .protected,
            compliantCount: compliantCount,
            nonCompliantCount: nonCompliantCount,
            unknownCount: unknownCount
        )
    }
    
    // MARK: - Encrypted Metric Calculation
    
    /// Calculate the "Encrypted" health metric
    /// macOS: Boot partition FileVault2 state = ENCRYPTED or ENCRYPTING (compliant)
    /// iOS/iPadOS/visionOS: Hardware encryption == 3 (full encryption)
    /// Note: GroundControl site devices are excluded from evaluation
    private func calculateEncryptedMetric(
        computers: [ComputerInventoryItem],
        mobileDevices: [MobileDeviceInventoryItem]
    ) -> HealthMetricData {
        
        var compliantCount = 0
        var nonCompliantCount = 0
        var unknownCount = 0
        
        // Encryption-specific breakdown (4 states)
        var encryptedCount = 0
        var encryptingCount = 0
        var unencryptedCount = 0  // Includes decrypting and other non-compliant states
        // unknownCount is shared

        let computerGaps = missingComputerSections(for: .encrypted)
        noteDataGap(.encrypted, .computers, computerGaps)
        let mobileGaps = missingMobileSections(for: .encrypted)
        noteDataGap(.encrypted, .mobileDevices, mobileGaps)

        // Process computers - check boot partition FileVault state
        // Exclude GroundControl site
        for computer in computers {
            // Site exclusion is evaluated BEFORE the data-gap guard: an excluded
            // Mac belongs in no bucket at all, so letting the guard reach it first
            // would inflate the denominator by the excluded population whenever a
            // section is missing.
            let siteName = computer.siteName ?? ""

            // Skip GroundControl site devices
            if siteName.lowercased() == "groundcontrol" {
                continue
            }

            guard computerGaps.isEmpty else { unknownCount += 1; continue }
            
            if let diskEncryption = computer.diskEncryption {
                // Check boot partition encryption state
                if let bootState = diskEncryption.bootPartitionEncryptionDetails?.partitionFileVault2State?.uppercased() {
                    switch bootState {
                    case "ENCRYPTED":
                        compliantCount += 1
                        encryptedCount += 1
                    case "ENCRYPTING", "ENCRYPTING_PAUSED":
                        compliantCount += 1  // Encrypting is compliant
                        encryptingCount += 1
                    default:
                        // DECRYPTING, DECRYPTING_PAUSED, UNENCRYPTED, INELIGIBLE, DECRYPTED, UNKNOWN, etc.
                        nonCompliantCount += 1
                        unencryptedCount += 1
                    }
                } else {
                    // No boot partition details - fall back to fileVault2Enabled
                    if diskEncryption.fileVault2Enabled == true {
                        compliantCount += 1
                        encryptedCount += 1
                    } else {
                        nonCompliantCount += 1
                        unencryptedCount += 1
                    }
                }
            } else {
                // No encryption data - mark as unknown
                unknownCount += 1
            }
        }
        
        // Process mobile devices - check hardware encryption == 3 (full encryption)
        // Note: Mobile devices don't have site association in the same way, include all
        for device in mobileDevices {
            guard mobileGaps.isEmpty else { unknownCount += 1; continue }
            if let security = device.security {
                // Hardware encryption value of 3 = both block-level and file-level encryption
                let hasFullEncryption = security.hardwareEncryption == 3
                
                if hasFullEncryption {
                    compliantCount += 1
                    encryptedCount += 1
                } else {
                    nonCompliantCount += 1
                    unencryptedCount += 1
                }
            } else {
                // No security data available
                unknownCount += 1
            }
        }
        
        return HealthMetricData(
            type: .encrypted,
            compliantCount: compliantCount,
            nonCompliantCount: nonCompliantCount,
            unknownCount: unknownCount,
            encryptedCount: encryptedCount,
            encryptingCount: encryptingCount,
            decryptingCount: 0,  // Merged into unencrypted
            unencryptedCount: unencryptedCount
        )
    }
    
    // MARK: - Secured Metric Calculation
    
    /// Calculate the "Secured" health metric
    /// macOS: Site-based security requirements (Enterprise, GroundControl, others)
    /// iOS/iPadOS: Managed, Supervised, Not Jailbroken, Successful Attestation, DDM Enabled
    /// visionOS: Managed, Supervised, Not Jailbroken, DDM Enabled
    private func calculateSecuredMetric(
        computers: [ComputerInventoryItem],
        mobileDevices: [MobileDeviceInventoryItem]
    ) -> HealthMetricData {
        
        var compliantCount = 0
        var nonCompliantCount = 0
        var unknownCount = 0
        
        let computerGaps = missingComputerSections(for: .secured)
        noteDataGap(.secured, .computers, computerGaps)
        let mobileGaps = missingMobileSections(for: .secured)
        noteDataGap(.secured, .mobileDevices, mobileGaps)

        // Process computers - site-based security requirements
        for computer in computers {
            guard computerGaps.isEmpty else { unknownCount += 1; continue }
            let siteName = computer.siteName ?? ""

            if siteName.lowercased() == "enterprise" {
                // Enterprise site (exact match) - full security requirements
                let firewallEnabled = computer.security?.firewallEnabled ?? false
                let sipEnabled = computer.security?.sipStatus?.uppercased() == "ENABLED"
                let gatekeeperOK = computer.security?.gatekeeperStatus?.uppercased() == "APP_STORE_AND_IDENTIFIED_DEVELOPERS" ||
                                   computer.security?.gatekeeperStatus?.uppercased() == "APP_STORE"
                let isManaged = computer.isManaged
                let isSupervised = computer.isSupervised
                let isEncrypted = computer.diskEncryption?.isBootPartitionEncrypted ?? false
                let bootstrapEscrowed = computer.security?.bootstrapTokenEscrowedStatus?.uppercased() == "ESCROWED"
                let ddmEnabled = computer.general?.declarativeDeviceManagementEnabled ?? false
                
                if firewallEnabled && sipEnabled && gatekeeperOK && isManaged && isSupervised && isEncrypted && bootstrapEscrowed && ddmEnabled {
                    compliantCount += 1
                } else {
                    nonCompliantCount += 1
                }
            } else if siteName.lowercased() == "groundcontrol" {
                // GroundControl site (exact match) - reduced security requirements
                let firewallEnabled = computer.security?.firewallEnabled ?? false
                let sipEnabled = computer.security?.sipStatus?.uppercased() == "ENABLED"
                let isManaged = computer.isManaged
                let isSupervised = computer.isSupervised
                let bootstrapEscrowed = computer.security?.bootstrapTokenEscrowedStatus?.uppercased() == "ESCROWED"
                let ddmEnabled = computer.general?.declarativeDeviceManagementEnabled ?? false
                
                if firewallEnabled && sipEnabled && isManaged && isSupervised && bootstrapEscrowed && ddmEnabled {
                    compliantCount += 1
                } else {
                    nonCompliantCount += 1
                }
            } else {
                // No site rule matched — see calculateProtectedMetric. Unknown, not Compliant.
                noteUnmatchedSite(siteName, deviceID: computer.id)
                unknownCount += 1
            }
        }
        
        // Process mobile devices
        for device in mobileDevices {
            guard mobileGaps.isEmpty else { unknownCount += 1; continue }
            let isManaged = device.isManaged
            let isSupervised = device.isSupervised
            // Absent security data must not read as "not jailbroken". The double
            // negative below would otherwise pass the check on no evidence — and
            // visionOS skips attestation, so nothing else would catch it.
            guard let security = device.security else { unknownCount += 1; continue }
            let notJailbroken = !(security.jailBreakDetected ?? false)
            let ddmEnabled = device.general?.declarativeDeviceManagementEnabled ?? false

            // Check platform for attestation requirement
            let platform = device.platformType

            if platform == .visionOS {
                // visionOS: Managed, Supervised, Not Jailbroken, DDM Enabled
                if isManaged && isSupervised && notJailbroken && ddmEnabled {
                    compliantCount += 1
                } else {
                    nonCompliantCount += 1
                }
            } else {
                // iOS/iPadOS: Also requires successful attestation
                let successfulAttestation = device.security?.attestationStatus?.uppercased() == "SUCCESS"
                
                if isManaged && isSupervised && notJailbroken && successfulAttestation && ddmEnabled {
                    compliantCount += 1
                } else {
                    nonCompliantCount += 1
                }
            }
        }
        
        return HealthMetricData(
            type: .secured,
            compliantCount: compliantCount,
            nonCompliantCount: nonCompliantCount,
            unknownCount: unknownCount
        )
    }
    
    // MARK: - Up To Date Metric Calculation
    
    /// Calculate the "Up to Date" health metric
    /// This measures devices running recent OS versions
    /// Configurable minimum versions per platform
    private func calculateUpToDateMetric(
        computers: [ComputerInventoryItem],
        mobileDevices: [MobileDeviceInventoryItem]
    ) -> HealthMetricData {
        
        var compliantCount = 0
        var nonCompliantCount = 0
        var unknownCount = 0
        
        // Minimum "up to date" OS versions per platform (config-driven;
        // shared with getUpToDateDevices so both always agree)
        let minimumMacOSVersion = minimumOSVersions.effectiveMacOS
        let minimumIOSVersion = minimumOSVersions.effectiveIOS
        let minimumIPadOSVersion = minimumOSVersions.effectiveIPadOS
        let minimumVisionOSVersion = minimumOSVersions.effectiveVisionOS
        
        let computerGaps = missingComputerSections(for: .upToDate)
        noteDataGap(.upToDate, .computers, computerGaps)
        let mobileGaps = missingMobileSections(for: .upToDate)
        noteDataGap(.upToDate, .mobileDevices, mobileGaps)

        // Process computers (macOS)
        for computer in computers {
            guard computerGaps.isEmpty else { unknownCount += 1; continue }
            if let osVersion = computer.operatingSystem?.version {
                if let majorVersion = extractMajorVersion(from: osVersion) {
                    if majorVersion >= minimumMacOSVersion {
                        compliantCount += 1
                    } else {
                        nonCompliantCount += 1
                    }
                } else {
                    unknownCount += 1
                }
            } else {
                unknownCount += 1
            }
        }
        
        // Process mobile devices using osVersion from detail endpoint
        for device in mobileDevices {
            guard mobileGaps.isEmpty else { unknownCount += 1; continue }
            if let osVersion = device.osVersion {
                if let majorVersion = extractMajorVersion(from: osVersion) {
                    // Determine minimum version based on platform
                    let minimumVersion: Int
                    switch device.platformType {
                    case .iOS:
                        minimumVersion = minimumIOSVersion
                    case .iPadOS:
                        minimumVersion = minimumIPadOSVersion
                    case .visionOS:
                        minimumVersion = minimumVisionOSVersion
                    case .macOS, .all:
                        // These shouldn't appear for mobile devices, use iOS as fallback
                        minimumVersion = minimumIOSVersion
                    }
                    
                    if majorVersion >= minimumVersion {
                        compliantCount += 1
                    } else {
                        nonCompliantCount += 1
                    }
                } else {
                    unknownCount += 1
                }
            } else {
                unknownCount += 1
            }
        }
        
        return HealthMetricData(
            type: .upToDate,
            compliantCount: compliantCount,
            nonCompliantCount: nonCompliantCount,
            unknownCount: unknownCount
        )
    }
    
    // MARK: - Helper Methods
    
    /// Parse ISO 8601 date string to Date
    private func parseISO8601Date(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: dateString) {
            return date
        }
        
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString)
    }
    
    /// Extract major version number from version string (e.g., "14.2.1" -> 14)
    private func extractMajorVersion(from versionString: String) -> Int? {
        let components = versionString.split(separator: ".")
        guard let firstComponent = components.first,
              let majorVersion = Int(firstComponent) else {
            return nil
        }
        return majorVersion
    }
    
    // MARK: - Device Filtering for Health Views
    
    /// Get filtered devices for a specific health metric and segment type
    /// Returns DeviceListItem array for display in filtered views
    func getFilteredDevices(
        for metricType: HealthMetricType,
        segment: HealthSegmentType
    ) -> [DeviceListItem] {
        let computerCache = ComputerInventoryCache.shared
        let mobileCache = MobileDeviceInventoryCache.shared

        // When a metric's inventory sections were never fetched the percentage path
        // scores every affected device Unknown. Withhold those devices from
        // evaluation here too, then re-add them as Unknown below — otherwise the
        // drill-down would contradict the card that opened it.
        let computerBlocked = !missingComputerSections(for: metricType).isEmpty
        let mobileBlocked = !missingMobileSections(for: metricType).isEmpty
        let evaluableComputers = computerBlocked ? [] : computerCache.computers
        let evaluableMobile = mobileBlocked ? [] : mobileCache.devices

        var devices: [DeviceListItem] = []

        switch metricType {
        case .checkedIn:
            devices = getCheckedInDevices(
                computers: evaluableComputers,
                mobileDevices: evaluableMobile,
                segment: segment
            )
        case .protected:
            devices = getProtectedDevices(
                computers: evaluableComputers,
                mobileDevices: evaluableMobile,
                segment: segment
            )
        case .encrypted:
            devices = getEncryptedDevices(
                computers: evaluableComputers,
                mobileDevices: evaluableMobile,
                segment: segment
            )
        case .secured:
            devices = getSecuredDevices(
                computers: evaluableComputers,
                mobileDevices: evaluableMobile,
                segment: segment
            )
        case .upToDate:
            devices = getUpToDateDevices(
                computers: evaluableComputers,
                mobileDevices: evaluableMobile,
                segment: segment
            )
        }

        if segment == .unknown {
            if computerBlocked {
                devices += inScopeComputers(computerCache.computers, for: metricType)
                    .map { computerToDeviceListItem($0) }
            }
            if mobileBlocked {
                devices += mobileCache.devices.map { mobileDeviceToDeviceListItem($0) }
            }
        }

        return devices
    }

    /// Computers a metric evaluates at all. Encrypted deliberately excludes the
    /// GroundControl site, so devices withheld for a data gap must be filtered the
    /// same way — otherwise the drill-down lists devices the card never counted.
    private func inScopeComputers(
        _ computers: [ComputerInventoryItem],
        for metric: HealthMetricType
    ) -> [ComputerInventoryItem] {
        guard metric == .encrypted else { return computers }
        return computers.filter { ($0.siteName ?? "").lowercased() != "groundcontrol" }
    }
    
    // MARK: - Checked-In Device Filtering
    
    private func getCheckedInDevices(
        computers: [ComputerInventoryItem],
        mobileDevices: [MobileDeviceInventoryItem],
        segment: HealthSegmentType
    ) -> [DeviceListItem] {
        var devices: [DeviceListItem] = []
        let now = Date()
        let threshold = Calendar.current.date(byAdding: .day, value: -checkInThresholdDays, to: now)!
        
        // Process computers
        for computer in computers {
            let checkInStatus = getComputerCheckInStatus(computer, threshold: threshold)
            
            if checkInStatus == segment {
                devices.append(computerToDeviceListItem(computer))
            }
        }
        
        // Process mobile devices
        for device in mobileDevices {
            let checkInStatus = getMobileCheckInStatus(device, threshold: threshold)
            
            if checkInStatus == segment {
                devices.append(mobileDeviceToDeviceListItem(device))
            }
        }
        
        return devices
    }
    
    private func getComputerCheckInStatus(_ computer: ComputerInventoryItem, threshold: Date) -> HealthSegmentType {
        // Try lastContactTime first, then reportDate
        if let lastContactStr = computer.general?.lastContactTime,
           let lastContact = parseISO8601Date(lastContactStr) {
            return lastContact >= threshold ? .compliant : .nonCompliant
        }
        
        if let reportDateStr = computer.general?.reportDate,
           let reportDate = parseISO8601Date(reportDateStr) {
            return reportDate >= threshold ? .compliant : .nonCompliant
        }
        
        return .unknown
    }
    
    private func getMobileCheckInStatus(_ device: MobileDeviceInventoryItem, threshold: Date) -> HealthSegmentType {
        if let lastUpdate = device.lastInventoryUpdate {
            return lastUpdate >= threshold ? .compliant : .nonCompliant
        }
        return .unknown
    }
    
    // MARK: - Protected Device Filtering
    
    private func getProtectedDevices(
        computers: [ComputerInventoryItem],
        mobileDevices: [MobileDeviceInventoryItem],
        segment: HealthSegmentType
    ) -> [DeviceListItem] {
        var devices: [DeviceListItem] = []
        
        // Process computers - site-based protection requirements
        for computer in computers {
            let siteName = computer.siteName ?? ""
            let status: HealthSegmentType
            
            if siteName.lowercased() == "enterprise" {
                // Enterprise site (exact match) requires all protection apps
                let hasCiscoSecureClient = computer.hasAppInstalled("Cisco Secure Client")
                let hasZscaler = computer.hasAppInstalled("Zscaler")
                let hasQualys = computer.hasAppInstalled("QualysCloudAgent")
                let hasFalcon = computer.hasAppInstalled("Falcon")
                let hasJamfProtect = computer.hasAppInstalled("JamfProtect")
                
                status = (hasCiscoSecureClient && hasZscaler && hasQualys && hasFalcon && hasJamfProtect) ? .compliant : .nonCompliant
            } else if siteName.lowercased() == "groundcontrol" {
                // GroundControl site (exact match) requires only Falcon
                let hasFalcon = computer.hasAppInstalled("Falcon")
                
                status = hasFalcon ? .compliant : .nonCompliant
            } else {
                // No site rule matched — mirrors calculateProtectedMetric. Unknown, not Compliant.
                status = .unknown
            }
            
            if status == segment {
                devices.append(computerToDeviceListItem(computer))
            }
        }
        
        // Process mobile devices - Managed + Supervised = Protected
        for device in mobileDevices {
            let status: HealthSegmentType = (device.isManaged && device.isSupervised) ? .compliant : .nonCompliant
            if status == segment {
                devices.append(mobileDeviceToDeviceListItem(device))
            }
        }
        
        return devices
    }
    
    // MARK: - Encrypted Device Filtering
    
    private func getEncryptedDevices(
        computers: [ComputerInventoryItem],
        mobileDevices: [MobileDeviceInventoryItem],
        segment: HealthSegmentType
    ) -> [DeviceListItem] {
        var devices: [DeviceListItem] = []
        
        // Process computers - check boot partition FileVault state
        // Exclude GroundControl site
        for computer in computers {
            let siteName = computer.siteName ?? ""
            
            // Skip GroundControl site devices
            if siteName.lowercased() == "groundcontrol" {
                continue
            }
            
            let status: HealthSegmentType
            if let diskEncryption = computer.diskEncryption {
                // Check boot partition encryption state
                if let bootState = diskEncryption.bootPartitionEncryptionDetails?.partitionFileVault2State?.uppercased() {
                    switch bootState {
                    case "ENCRYPTED", "ENCRYPTING", "ENCRYPTING_PAUSED":
                        status = .compliant
                    default:
                        status = .nonCompliant
                    }
                } else {
                    // No boot partition details - fall back to fileVault2Enabled
                    status = (diskEncryption.fileVault2Enabled == true) ? .compliant : .nonCompliant
                }
            } else {
                status = .unknown
            }
            
            if status == segment {
                devices.append(computerToDeviceListItem(computer))
            }
        }
        
        // Process mobile devices - check hardware encryption == 3 (full encryption)
        for device in mobileDevices {
            let status: HealthSegmentType
            if let security = device.security {
                // Hardware encryption value of 3 = both block-level and file-level encryption
                let hasFullEncryption = security.hardwareEncryption == 3
                status = hasFullEncryption ? .compliant : .nonCompliant
            } else {
                status = .unknown
            }
            
            if status == segment {
                devices.append(mobileDeviceToDeviceListItem(device))
            }
        }
        
        return devices
    }
    
    // MARK: - Secured Device Filtering
    
    private func getSecuredDevices(
        computers: [ComputerInventoryItem],
        mobileDevices: [MobileDeviceInventoryItem],
        segment: HealthSegmentType
    ) -> [DeviceListItem] {
        var devices: [DeviceListItem] = []
        
        // Process computers - site-based security requirements
        for computer in computers {
            let siteName = computer.siteName ?? ""
            let status: HealthSegmentType
            
            if siteName.lowercased() == "enterprise" {
                // Enterprise site (exact match) - full security requirements
                let firewallEnabled = computer.security?.firewallEnabled ?? false
                let sipEnabled = computer.security?.sipStatus?.uppercased() == "ENABLED"
                let gatekeeperOK = computer.security?.gatekeeperStatus?.uppercased() == "APP_STORE_AND_IDENTIFIED_DEVELOPERS" ||
                                   computer.security?.gatekeeperStatus?.uppercased() == "APP_STORE"
                let isManaged = computer.isManaged
                let isSupervised = computer.isSupervised
                let isEncrypted = computer.diskEncryption?.isBootPartitionEncrypted ?? false
                let bootstrapEscrowed = computer.security?.bootstrapTokenEscrowedStatus?.uppercased() == "ESCROWED"
                let ddmEnabled = computer.general?.declarativeDeviceManagementEnabled ?? false
                
                status = (firewallEnabled && sipEnabled && gatekeeperOK && isManaged && isSupervised && isEncrypted && bootstrapEscrowed && ddmEnabled) ? .compliant : .nonCompliant
            } else if siteName.lowercased() == "groundcontrol" {
                // GroundControl site (exact match) - reduced security requirements
                let firewallEnabled = computer.security?.firewallEnabled ?? false
                let sipEnabled = computer.security?.sipStatus?.uppercased() == "ENABLED"
                let isManaged = computer.isManaged
                let isSupervised = computer.isSupervised
                let bootstrapEscrowed = computer.security?.bootstrapTokenEscrowedStatus?.uppercased() == "ESCROWED"
                let ddmEnabled = computer.general?.declarativeDeviceManagementEnabled ?? false
                
                status = (firewallEnabled && sipEnabled && isManaged && isSupervised && bootstrapEscrowed && ddmEnabled) ? .compliant : .nonCompliant
            } else {
                // No site rule matched — mirrors calculateSecuredMetric. Unknown, not Compliant.
                status = .unknown
            }
            
            if status == segment {
                devices.append(computerToDeviceListItem(computer))
            }
        }
        
        // Process mobile devices
        for device in mobileDevices {
            let isManaged = device.isManaged
            let isSupervised = device.isSupervised
            // Mirrors calculateSecuredMetric: absent security data is Unknown, not
            // "not jailbroken". Without this the card and this list disagree for
            // any device Jamf returns a null security object for.
            guard let security = device.security else {
                if segment == .unknown { devices.append(mobileDeviceToDeviceListItem(device)) }
                continue
            }
            let notJailbroken = !(security.jailBreakDetected ?? false)
            let ddmEnabled = device.general?.declarativeDeviceManagementEnabled ?? false

            let platform = device.platformType
            let status: HealthSegmentType

            if platform == .visionOS {
                // visionOS: Managed, Supervised, Not Jailbroken, DDM Enabled
                status = (isManaged && isSupervised && notJailbroken && ddmEnabled) ? .compliant : .nonCompliant
            } else {
                // iOS/iPadOS: Also requires successful attestation
                let successfulAttestation = security.attestationStatus?.uppercased() == "SUCCESS"
                status = (isManaged && isSupervised && notJailbroken && successfulAttestation && ddmEnabled) ? .compliant : .nonCompliant
            }
            
            if status == segment {
                devices.append(mobileDeviceToDeviceListItem(device))
            }
        }
        
        return devices
    }
    
    // MARK: - Up To Date Device Filtering
    
    private func getUpToDateDevices(
        computers: [ComputerInventoryItem],
        mobileDevices: [MobileDeviceInventoryItem],
        segment: HealthSegmentType
    ) -> [DeviceListItem] {
        var devices: [DeviceListItem] = []
        
        // Minimum "up to date" OS versions per platform (config-driven;
        // shared with calculateUpToDateMetric so both always agree)
        let minimumMacOSVersion = minimumOSVersions.effectiveMacOS
        let minimumIOSVersion = minimumOSVersions.effectiveIOS
        let minimumIPadOSVersion = minimumOSVersions.effectiveIPadOS
        let minimumVisionOSVersion = minimumOSVersions.effectiveVisionOS
        
        for computer in computers {
            let status: HealthSegmentType
            if let osVersion = computer.operatingSystem?.version,
               let majorVersion = extractMajorVersion(from: osVersion) {
                status = majorVersion >= minimumMacOSVersion ? .compliant : .nonCompliant
            } else {
                status = .unknown
            }
            
            if status == segment {
                devices.append(computerToDeviceListItem(computer))
            }
        }
        
        for device in mobileDevices {
            let status: HealthSegmentType
            if let osVersion = device.osVersion,
               let majorVersion = extractMajorVersion(from: osVersion) {
                // Determine minimum version based on platform
                let minimumVersion: Int
                switch device.platformType {
                case .iOS:
                    minimumVersion = minimumIOSVersion
                case .iPadOS:
                    minimumVersion = minimumIPadOSVersion
                case .visionOS:
                    minimumVersion = minimumVisionOSVersion
                case .macOS, .all:
                    // These shouldn't appear for mobile devices, use iOS as fallback
                    minimumVersion = minimumIOSVersion
                }
                
                status = majorVersion >= minimumVersion ? .compliant : .nonCompliant
            } else {
                status = .unknown
            }
            
            if status == segment {
                devices.append(mobileDeviceToDeviceListItem(device))
            }
        }
        
        return devices
    }
    
    // MARK: - Device Conversion Helpers
    
    private func computerToDeviceListItem(_ computer: ComputerInventoryItem) -> DeviceListItem {
        var lastCheckIn: Date? = nil
        if let lastContactStr = computer.general?.lastContactTime {
            lastCheckIn = parseISO8601Date(lastContactStr)
        } else if let reportDateStr = computer.general?.reportDate {
            lastCheckIn = parseISO8601Date(reportDateStr)
        }
        
        return DeviceListItem(
            id: "computer-\(computer.id)",
            originalId: computer.id,
            name: computer.general?.name ?? "Unknown",
            serialNumber: computer.hardware?.serialNumber ?? "N/A",
            model: computer.hardware?.model ?? "Unknown Mac",
            modelIdentifier: computer.hardware?.modelIdentifier,
            osVersion: computer.operatingSystem?.version ?? "N/A",
            assignedUser: computer.userAndLocation?.realname ?? computer.userAndLocation?.username,
            lastCheckIn: lastCheckIn,
            isManaged: computer.isManaged,
            isSupervised: computer.isSupervised,
            platform: .macOS
        )
    }
    
    private func mobileDeviceToDeviceListItem(_ device: MobileDeviceInventoryItem) -> DeviceListItem {
        return DeviceListItem(
            id: "mobile-\(device.id)",
            originalId: device.id,
            name: device.displayName ?? "Unknown",
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
}
