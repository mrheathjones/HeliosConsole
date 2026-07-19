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
            .effectiveHealthScorecard.effectiveMetric(id: HealthMetricType.checkedIn.configID)?
            .effectiveCheckedInDays ?? 7
    }

    /// Minimum compliant OS major versions for the "Up to Date" metric —
    /// features domain healthScorecard.metrics[id=upToDate].minimumOSVersions.
    /// Profiles written against the old schema addressed this as
    /// `softwareUpdateCompliance`; effectiveMetric(id:) still honours that.
    var minimumOSVersions: FeaturesConfiguration.HealthMetricSetting.MinimumOSVersions {
        MDMConfigurationManager.shared.configuration.features?
            .effectiveHealthScorecard.effectiveMetric(id: HealthMetricType.upToDate.configID)?
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
        
        // Calculate each metric — one implementation, five metrics.
        func calculate(_ metric: HealthMetricType) -> HealthMetricData {
            calculateMetric(metric,
                            computers: computerCache.computers,
                            mobileDevices: mobileCache.devices)
        }

        let checkedIn = calculate(.checkedIn)
        let protected = calculate(.protected)
        let encrypted = calculate(.encrypted)
        let secured = calculate(.secured)
        let upToDate = calculate(.upToDate)

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
    /// One metric, evaluated for every device through the shared evaluator.
    ///
    /// This replaced five near-identical calculate*Metric functions. Each of them
    /// inlined the same pass/fail logic as its get*Devices twin, which is how the
    /// two paths drifted apart in the first place — both now tally verdicts from
    /// one implementation, so a card and its drill-down cannot disagree.
    private func calculateMetric(
        _ metric: HealthMetricType,
        computers: [ComputerInventoryItem],
        mobileDevices: [MobileDeviceInventoryItem]
    ) -> HealthMetricData {
        let policy = HealthPolicy.current(checkedInDays: checkInThresholdDays,
                                          minimums: minimumOSVersions)
        let computerAvailability = SectionAvailability.computers(configuredComputerSections)
        let mobileAvailability = SectionAvailability.mobileDevices(configuredMobileSections)

        noteDataGap(metric, .computers, missingComputerSections(for: metric))
        noteDataGap(metric, .mobileDevices, missingMobileSections(for: metric))

        var compliantCount = 0
        var nonCompliantCount = 0
        var unknownCount = 0

        // Encryption-specific breakdown, populated only for .encrypted.
        var encryptedCount = 0
        var encryptingCount = 0
        var unencryptedCount = 0

        func tally(_ evaluation: HealthEvaluation) {
            switch evaluation.verdict {
            case .compliant: compliantCount += 1
            case .nonCompliant: nonCompliantCount += 1
            case .unknown: unknownCount += 1
            case .excluded: break   // out of scope: no bucket, no denominator
            }

            guard metric == .encrypted, let state = evaluation.encryptionState else { return }
            switch state.bucket {
            case .encrypted: encryptedCount += 1
            case .encrypting: encryptingCount += 1
            // Merged into unencrypted, preserving current display exactly. The
            // breakdown has a decrypting slot that has always been hard-coded to
            // zero; populating it is a deliberate change and lands on its own so
            // the before/after card comparison for this step stays clean.
            case .decrypting, .unencrypted: unencryptedCount += 1
            case .unknown: break
            }
        }

        for computer in computers {
            let evaluation = HealthEvaluator.evaluate(
                metric,
                computer: computer.healthInput(availability: computerAvailability),
                policy: policy
            )
            tally(evaluation)
            for cause in evaluation.causes {
                if case .unmatchedSite(let raw) = cause {
                    noteUnmatchedSite(raw, deviceID: computer.id)
                }
            }
        }

        for device in mobileDevices {
            tally(HealthEvaluator.evaluate(
                metric,
                mobile: device.healthInput(availability: mobileAvailability),
                policy: policy
            ))
        }

        return HealthMetricData(
            type: metric,
            compliantCount: compliantCount,
            nonCompliantCount: nonCompliantCount,
            unknownCount: unknownCount,
            encryptedCount: encryptedCount,
            encryptingCount: encryptingCount,
            decryptingCount: 0,
            unencryptedCount: unencryptedCount
        )
    }

    
    // Local parseISO8601Date and extractMajorVersion removed — HealthEvaluator
    // owns the single copy of each. Several duplicates of the date parser used a
    // default-options formatter that silently failed on every fractional-second
    // Jamf timestamp.

    // MARK: - Device Filtering for Health Views
    
    /// Get filtered devices for a specific health metric and segment type
    /// Returns DeviceListItem array for display in filtered views
    func getFilteredDevices(
        for metricType: HealthMetricType,
        segment: HealthSegmentType
    ) -> [DeviceListItem] {
        let computerCache = ComputerInventoryCache.shared
        let mobileCache = MobileDeviceInventoryCache.shared

        // Routed through the shared evaluator. The five per-metric get*Devices
        // functions this replaced duplicated the pass/fail logic of the
        // calculate*Metric functions line for line, and had already drifted from
        // them in four places.
        let policy = HealthPolicy.current(checkedInDays: checkInThresholdDays,
                                          minimums: minimumOSVersions)
        let computerAvailability = SectionAvailability.computers(configuredComputerSections)
        let mobileAvailability = SectionAvailability.mobileDevices(configuredMobileSections)

        var devices: [DeviceListItem] = []

        for computer in computerCache.computers {
            let evaluation = HealthEvaluator.evaluate(
                metricType,
                computer: computer.healthInput(availability: computerAvailability),
                policy: policy
            )
            if Self.segment(for: evaluation.verdict) == segment {
                devices.append(computerToDeviceListItem(computer))
            }
        }

        for device in mobileCache.devices {
            let evaluation = HealthEvaluator.evaluate(
                metricType,
                mobile: device.healthInput(availability: mobileAvailability),
                policy: policy
            )
            if Self.segment(for: evaluation.verdict) == segment {
                devices.append(mobileDeviceToDeviceListItem(device))
            }
        }

        return devices
    }

    /// `excluded` maps to no segment — those devices are out of scope for the
    /// metric and belong in neither the numerator, the denominator, nor any list.
    private static func segment(for verdict: HealthVerdict) -> HealthSegmentType? {
        switch verdict {
        case .compliant: return .compliant
        case .nonCompliant: return .nonCompliant
        case .unknown: return .unknown
        case .excluded: return nil
        }
    }

    // MARK: - Checked-In Device Filtering
    
    // The five per-metric get*Devices functions that lived here were removed:
    // getFilteredDevices now routes every metric through HealthEvaluator, so
    // the drill-down and the percentage can no longer disagree by drifting.

    private func computerToDeviceListItem(_ computer: ComputerInventoryItem) -> DeviceListItem {
        // Same resolver the Checked-In metric uses, so the date column cannot
        // disagree with the verdict. The previous version fell back at the string
        // level — a present-but-unparseable lastContactTime returned nil without
        // ever trying reportDate, leaving an empty cell on a compliant row.
        let lastCheckIn = HealthEvaluator.resolveCheckIn(
            lastContactTime: computer.general?.lastContactTime,
            reportDate: computer.general?.reportDate
        )

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
