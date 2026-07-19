//
//  HealthEvaluator.swift
//  Helios
//
//  Single source of truth for health-metric verdicts.
//
//  The scorecard's metric logic historically existed in three independently
//  maintained copies — the fleet percentage path (`calculate*Metric`), the fleet
//  drill-down path (`get*Devices`), and the per-device panel
//  (`DeviceHealthEvaluator`) — plus a fourth copy in the popover checklists that
//  restates the requirements as display text. They drifted: the FileVault
//  pass-set had three different answers, Encrypted and Secured disagreed about
//  what "encrypted" means inside one panel, and app matching used substring in
//  one place and exact-or-".app" in another.
//
//  This type replaces all of them. It is deliberately platform-complete and
//  model-agnostic: callers project their own device type into a
//  ComputerHealthInput / MobileHealthInput and get back a verdict plus the
//  ordered requirement rows that produced it, so the display text can no longer
//  disagree with the logic it describes.
//
//  LANDED DARK — nothing calls this yet. HealthParityCheck compares it against
//  the live logic on real inventory before any call site is migrated.
//

import Foundation

// MARK: - Verdict

enum HealthVerdict: String, Equatable {
    case compliant
    case nonCompliant
    case unknown
    /// Deliberately out of scope for the metric — not a pass, not a fail, and
    /// absent from the denominator. Today only the Encrypted metric's site
    /// exclusion produces this; per-metric device exclusions will also land here.
    case excluded
}

/// Why a verdict came out the way it did. Drives popover text and diagnostics.
enum HealthCause: Equatable {
    case sectionGap(missing: [String], configKey: String)
    case unmatchedSite(raw: String)
    case missingField(String)
    case unparseableField(name: String, value: String)
    case requirementFailed(String)
    case excludedBySite(String)
}

/// One condition the evaluator actually checked. The single source for both the
/// "requirements met" checklist and the failure reason strings.
struct HealthRequirement: Equatable {
    enum Outcome: Equatable {
        case met
        case failed
        case notEvaluated
    }

    let id: String
    let label: String
    let outcome: Outcome

    /// Failure text in the phrasing the per-device panel has always used, so
    /// migrating that view does not change any user-visible string.
    let failureText: String?
}

struct HealthEvaluation: Equatable {
    let metric: HealthMetricType
    let verdict: HealthVerdict
    let causes: [HealthCause]
    let requirements: [HealthRequirement]
    /// Populated only for `.encrypted`, which reports a 4-state breakdown
    /// alongside its pass/fail verdict.
    let encryptionState: BootEncryptionState?

    init(
        metric: HealthMetricType,
        verdict: HealthVerdict,
        causes: [HealthCause] = [],
        requirements: [HealthRequirement] = [],
        encryptionState: BootEncryptionState? = nil
    ) {
        self.metric = metric
        self.verdict = verdict
        self.causes = causes
        self.requirements = requirements
        self.encryptionState = encryptionState
    }

    var reasons: [String] { causes.compactMap { Self.reasonText($0) } }

    private static func reasonText(_ cause: HealthCause) -> String? {
        switch cause {
        case .sectionGap(let missing, let key):
            return "Required inventory data is not being fetched (\(missing.joined(separator: ", "))) — see \(key)"
        case .unmatchedSite(let raw):
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "Device has no Jamf site assigned, so no requirements could be evaluated"
                : "No requirements are defined for site \"\(trimmed)\", so compliance could not be evaluated"
        case .missingField(let what):
            return "No \(what) available"
        case .unparseableField(let name, let value):
            return "Could not interpret \(name) \"\(value)\""
        case .requirementFailed(let text):
            return text
        case .excludedBySite:
            return nil
        }
    }
}

/// The FileVault boot-partition state, parsed exactly once.
///
/// Encrypted and Secured deliberately consume this differently — in-progress
/// conversion trends compliant for Encrypted but not for Secured — but they now
/// share one interpretation of the underlying Jamf strings instead of three.
enum BootEncryptionState: Equatable {
    case encrypted
    case encrypting
    case encryptingPaused
    case decrypting
    case decryptingPaused
    case other(String)
    /// No partition detail; falls back to the `fileVault2Enabled` flag.
    case flagOnly(Bool)
    /// The diskEncryption object itself was absent.
    case noData

    static func parse(
        partitionState: String?,
        fileVault2Enabled: Bool?,
        hasDiskEncryptionObject: Bool
    ) -> BootEncryptionState {
        guard hasDiskEncryptionObject else { return .noData }
        guard let raw = partitionState?.uppercased() else {
            return .flagOnly(fileVault2Enabled == true)
        }
        switch raw {
        case "ENCRYPTED": return .encrypted
        case "ENCRYPTING": return .encrypting
        case "ENCRYPTING_PAUSED": return .encryptingPaused
        case "DECRYPTING": return .decrypting
        case "DECRYPTING_PAUSED": return .decryptingPaused
        default: return .other(raw)
        }
    }

    /// Encrypted metric: conversion in progress counts as compliant.
    var passesEncryptedMetric: Bool {
        switch self {
        case .encrypted, .encrypting, .encryptingPaused: return true
        case .flagOnly(let on): return on
        case .decrypting, .decryptingPaused, .other: return false
        case .noData: return false
        }
    }

    /// Secured metric: stricter. A partition state that exists must be
    /// ENCRYPTED; the flag is only consulted when no state was reported.
    var passesSecuredMetric: Bool {
        switch self {
        case .encrypted: return true
        case .flagOnly(let on): return on
        case .encrypting, .encryptingPaused, .decrypting, .decryptingPaused, .other, .noData:
            return false
        }
    }

    /// Which breakdown bucket this state belongs to on the Encrypted card.
    enum Bucket { case encrypted, encrypting, decrypting, unencrypted, unknown }

    var bucket: Bucket {
        switch self {
        case .encrypted: return .encrypted
        case .encrypting, .encryptingPaused: return .encrypting
        case .decrypting, .decryptingPaused: return .decrypting
        case .other: return .unencrypted
        case .flagOnly(let on): return on ? .encrypted : .unencrypted
        case .noData: return .unknown
        }
    }
}

// MARK: - Policy

/// The tunables and site rules a metric is evaluated against. Hard-coded for now
/// and populated from `HealthMetricsCalculator`'s existing config accessors; PR 3
/// replaces the initialiser body with profile-driven values without changing any
/// consumer of this type.
struct HealthPolicy {
    struct SiteRule {
        let siteName: String
        let requiredApps: [String]
        /// Security checks this site must satisfy for the Secured metric.
        let securedChecks: Set<SecuredCheck>
    }

    enum SecuredCheck: String, CaseIterable {
        case firewall, sip, gatekeeper, managed, supervised, diskEncrypted, bootstrapToken, ddm
    }

    let checkedInDays: Int
    let minimumMacOS: Int
    let minimumIOS: Int
    let minimumIPadOS: Int
    let minimumVisionOS: Int
    let siteRules: [SiteRule]
    /// Sites removed from the Encrypted metric entirely.
    let encryptedExcludedSites: [String]

    /// Mirrors the literals the calculator uses today, so the evaluator can be
    /// compared against live behavior before anything becomes configurable.
    static func current(
        checkedInDays: Int,
        minimums: FeaturesConfiguration.HealthMetricSetting.MinimumOSVersions
    ) -> HealthPolicy {
        HealthPolicy(
            checkedInDays: checkedInDays,
            minimumMacOS: minimums.effectiveMacOS,
            minimumIOS: minimums.effectiveIOS,
            minimumIPadOS: minimums.effectiveIPadOS,
            minimumVisionOS: minimums.effectiveVisionOS,
            siteRules: [
                SiteRule(
                    siteName: "enterprise",
                    requiredApps: ["Cisco Secure Client", "Zscaler", "QualysCloudAgent", "Falcon", "JamfProtect"],
                    securedChecks: Set(SecuredCheck.allCases)
                ),
                SiteRule(
                    siteName: "groundcontrol",
                    requiredApps: ["Falcon"],
                    securedChecks: [.firewall, .sip, .managed, .supervised, .bootstrapToken, .ddm]
                )
            ],
            encryptedExcludedSites: ["groundcontrol"]
        )
    }

    func rule(forSite site: String?) -> SiteRule? {
        let normalized = (site ?? "").lowercased()
        return siteRules.first { $0.siteName == normalized }
    }

    func isEncryptedExcluded(site: String?) -> Bool {
        let normalized = (site ?? "").lowercased()
        return encryptedExcludedSites.contains(normalized)
    }
}

// MARK: - Inputs

/// Which Jamf inventory sections the caller's fetch actually requested.
///
/// The fleet path passes the profile's configured list; the per-device path
/// passes its own (larger, hard-coded) envelope. That asymmetry is real — a
/// device page can legitimately evaluate something the fleet card cannot — and
/// is now declared rather than accidental.
struct SectionAvailability {
    let known: Set<String>
    let configKey: String

    func missing(_ required: [String]) -> [String] {
        required.filter { !known.contains($0) }
    }

    static func computers(_ sections: [String]) -> SectionAvailability {
        SectionAvailability(
            known: Set(sections.map { $0.uppercased() }),
            configKey: "com.herojoneslabs.helios.console.features → computers.inventorySections"
        )
    }

    static func mobileDevices(_ sections: [String]) -> SectionAvailability {
        SectionAvailability(
            known: Set(sections.map { $0.uppercased() }),
            configKey: "com.herojoneslabs.helios.console.features → mobileDevices.inventorySections"
        )
    }
}

struct ComputerHealthInput {
    let deviceID: String
    let rawSiteName: String?

    // GENERAL
    let checkInDate: Date?
    let isManaged: Bool
    let isSupervised: Bool
    let ddmEnabled: Bool

    // OPERATING_SYSTEM
    let osVersion: String?

    // APPLICATIONS — nil means the section was absent, which is not the same as
    // a Mac that genuinely has no applications.
    let applicationNames: [String]?

    // SECURITY
    let firewallEnabled: Bool
    let sipStatus: String?
    let gatekeeperStatus: String?
    let bootstrapTokenEscrowedStatus: String?

    // DISK_ENCRYPTION
    let encryptionState: BootEncryptionState

    let availability: SectionAvailability
}

struct MobileHealthInput {
    let deviceID: String
    let platform: PlatformType
    /// Mobile check-in comes from `lastInventoryUpdate`, already resolved to a
    /// Date by the inventory model.
    let resolvedCheckIn: Date?
    let osVersion: String?
    let isManaged: Bool
    let isSupervised: Bool
    let ddmEnabled: Bool
    let hasSecurityObject: Bool
    let jailBreakDetected: Bool?
    let attestationStatus: String?
    let hardwareEncryption: Int?
    let availability: SectionAvailability
}

// MARK: - Section requirements

enum HealthSectionRequirement {
    static func computers(_ metric: HealthMetricType) -> [String] {
        switch metric {
        case .checkedIn: return ["GENERAL"]
        case .protected: return ["GENERAL", "APPLICATIONS"]
        case .encrypted: return ["GENERAL", "DISK_ENCRYPTION"]
        case .secured:   return ["GENERAL", "SECURITY", "DISK_ENCRYPTION"]
        case .upToDate:  return ["OPERATING_SYSTEM"]
        }
    }

    static func mobileDevices(_ metric: HealthMetricType) -> [String] {
        switch metric {
        case .checkedIn: return ["GENERAL"]
        case .protected: return ["GENERAL"]
        case .encrypted: return ["SECURITY"]
        case .secured:   return ["GENERAL", "SECURITY"]
        case .upToDate:  return ["GENERAL", "HARDWARE"]
        }
    }
}

// MARK: - Evaluator

enum HealthEvaluator {

    // MARK: Computers

    static func evaluate(
        _ metric: HealthMetricType,
        computer input: ComputerHealthInput,
        policy: HealthPolicy
    ) -> HealthEvaluation {
        // Site exclusion precedes the data-gap check: an excluded device belongs
        // in no bucket, so a missing section must not pull it into the denominator.
        if metric == .encrypted, policy.isEncryptedExcluded(site: input.rawSiteName) {
            return HealthEvaluation(
                metric: metric,
                verdict: .excluded,
                causes: [.excludedBySite(input.rawSiteName ?? "")]
            )
        }

        let missing = input.availability.missing(HealthSectionRequirement.computers(metric))
        if !missing.isEmpty {
            return HealthEvaluation(
                metric: metric,
                verdict: .unknown,
                causes: [.sectionGap(missing: missing, configKey: input.availability.configKey)]
            )
        }

        switch metric {
        case .checkedIn:  return evaluateCheckedIn(computer: input, policy: policy)
        case .protected:  return evaluateProtected(computer: input, policy: policy)
        case .encrypted:  return evaluateEncrypted(computer: input)
        case .secured:    return evaluateSecured(computer: input, policy: policy)
        case .upToDate:   return evaluateUpToDate(computer: input, policy: policy)
        }
    }

    private static func evaluateCheckedIn(
        computer input: ComputerHealthInput,
        policy: HealthPolicy
    ) -> HealthEvaluation {
        guard let date = input.checkInDate else {
            return HealthEvaluation(metric: .checkedIn, verdict: .unknown,
                                    causes: [.missingField("check-in date")])
        }
        let threshold = Calendar.current.date(byAdding: .day, value: -policy.checkedInDays, to: Date())
        let passed = threshold.map { date >= $0 } ?? false
        return HealthEvaluation(
            metric: .checkedIn,
            verdict: passed ? .compliant : .nonCompliant,
            causes: passed ? [] : [.requirementFailed("Device has not checked in within \(policy.checkedInDays) days")],
            requirements: [HealthRequirement(
                id: "checkedInWindow",
                label: "Device checked in within \(policy.checkedInDays) days",
                outcome: passed ? .met : .failed,
                failureText: "Device has not checked in within \(policy.checkedInDays) days"
            )]
        )
    }

    private static func evaluateProtected(
        computer input: ComputerHealthInput,
        policy: HealthPolicy
    ) -> HealthEvaluation {
        guard let rule = policy.rule(forSite: input.rawSiteName) else {
            return HealthEvaluation(metric: .protected, verdict: .unknown,
                                    causes: [.unmatchedSite(raw: input.rawSiteName ?? "")])
        }
        guard let installed = input.applicationNames else {
            return HealthEvaluation(metric: .protected, verdict: .unknown,
                                    causes: [.missingField("application inventory")])
        }

        var requirements: [HealthRequirement] = []
        var causes: [HealthCause] = []
        for app in rule.requiredApps {
            let present = matches(app, in: installed)
            let failure = "\(app) not installed"
            requirements.append(HealthRequirement(
                id: "appInstalled", label: "\(app) installed",
                outcome: present ? .met : .failed, failureText: failure
            ))
            if !present { causes.append(.requirementFailed(failure)) }
        }

        return HealthEvaluation(
            metric: .protected,
            verdict: causes.isEmpty ? .compliant : .nonCompliant,
            causes: causes,
            requirements: requirements
        )
    }

    /// Substring, case-insensitive — the fleet's historical rule. The per-device
    /// panel used exact-or-".app", which is stricter and arguably more correct,
    /// but the fleet number is the published one. PR 3 replaces both with
    /// configurable per-app matching against bundle identifiers.
    static func matches(_ required: String, in installed: [String]) -> Bool {
        let needle = required.lowercased()
        return installed.contains { $0.lowercased().contains(needle) }
    }

    /// The stricter matcher, retained only so the parity harness can measure how
    /// far apart the two rules actually are on a real fleet before PR 3 chooses.
    static func matchesStrict(_ required: String, in installed: [String]) -> Bool {
        let needle = required.lowercased()
        return installed.contains { $0.lowercased() == needle || $0.lowercased() == "\(needle).app" }
    }

    private static func evaluateEncrypted(computer input: ComputerHealthInput) -> HealthEvaluation {
        let state = input.encryptionState
        if state == .noData {
            return HealthEvaluation(metric: .encrypted, verdict: .unknown,
                                    causes: [.missingField("encryption data")],
                                    encryptionState: state)
        }
        let passed = state.passesEncryptedMetric
        return HealthEvaluation(
            metric: .encrypted,
            verdict: passed ? .compliant : .nonCompliant,
            causes: passed ? [] : [.requirementFailed("Boot partition is not encrypted")],
            requirements: [HealthRequirement(
                id: "diskEncrypted", label: "Boot partition encrypted",
                outcome: passed ? .met : .failed,
                failureText: "Boot partition is not encrypted"
            )],
            encryptionState: state
        )
    }

    private static func evaluateSecured(
        computer input: ComputerHealthInput,
        policy: HealthPolicy
    ) -> HealthEvaluation {
        guard let rule = policy.rule(forSite: input.rawSiteName) else {
            return HealthEvaluation(metric: .secured, verdict: .unknown,
                                    causes: [.unmatchedSite(raw: input.rawSiteName ?? "")])
        }

        var requirements: [HealthRequirement] = []
        var causes: [HealthCause] = []

        func check(_ id: HealthPolicy.SecuredCheck, _ label: String, _ failure: String, _ passed: Bool) {
            guard rule.securedChecks.contains(id) else { return }
            requirements.append(HealthRequirement(
                id: id.rawValue, label: label,
                outcome: passed ? .met : .failed, failureText: failure
            ))
            if !passed { causes.append(.requirementFailed(failure)) }
        }

        let gatekeeper = input.gatekeeperStatus?.uppercased()
        check(.firewall, "Firewall enabled", "Firewall is disabled", input.firewallEnabled)
        check(.sip, "SIP enabled", "System Integrity Protection (SIP) is not enabled",
              input.sipStatus?.uppercased() == "ENABLED")
        check(.gatekeeper, "Gatekeeper configured",
              "Gatekeeper not set to App Store & Identified Developers",
              gatekeeper == "APP_STORE_AND_IDENTIFIED_DEVELOPERS" || gatekeeper == "APP_STORE")
        check(.managed, "Device managed", "Device is not managed", input.isManaged)
        check(.supervised, "Device supervised", "Device is not supervised", input.isSupervised)
        check(.diskEncrypted, "Disk encrypted", "Boot partition is not encrypted",
              input.encryptionState.passesSecuredMetric)
        check(.bootstrapToken, "Bootstrap token escrowed", "Bootstrap token is not escrowed",
              input.bootstrapTokenEscrowedStatus?.uppercased() == "ESCROWED")
        check(.ddm, "DDM enabled", "Declarative Device Management (DDM) is not enabled",
              input.ddmEnabled)

        return HealthEvaluation(
            metric: .secured,
            verdict: causes.isEmpty ? .compliant : .nonCompliant,
            causes: causes,
            requirements: requirements
        )
    }

    private static func evaluateUpToDate(
        computer input: ComputerHealthInput,
        policy: HealthPolicy
    ) -> HealthEvaluation {
        guard let version = input.osVersion else {
            return HealthEvaluation(metric: .upToDate, verdict: .unknown,
                                    causes: [.missingField("OS version")])
        }
        guard let major = majorVersion(version) else {
            return HealthEvaluation(metric: .upToDate, verdict: .unknown,
                                    causes: [.unparseableField(name: "OS version", value: version)])
        }
        let passed = major >= policy.minimumMacOS
        let failure = "macOS \(major) is below the minimum supported version \(policy.minimumMacOS)"
        return HealthEvaluation(
            metric: .upToDate,
            verdict: passed ? .compliant : .nonCompliant,
            causes: passed ? [] : [.requirementFailed(failure)],
            requirements: [HealthRequirement(
                id: "osMinimum", label: "macOS version \(policy.minimumMacOS) or higher",
                outcome: passed ? .met : .failed, failureText: failure
            )]
        )
    }

    // MARK: Mobile devices

    static func evaluate(
        _ metric: HealthMetricType,
        mobile input: MobileHealthInput,
        policy: HealthPolicy
    ) -> HealthEvaluation {
        let missing = input.availability.missing(HealthSectionRequirement.mobileDevices(metric))
        if !missing.isEmpty {
            return HealthEvaluation(
                metric: metric,
                verdict: .unknown,
                causes: [.sectionGap(missing: missing, configKey: input.availability.configKey)]
            )
        }

        switch metric {
        case .checkedIn:
            // Mobile check-in is resolved by the caller (lastInventoryUpdate).
            guard let date = input.resolvedCheckIn else {
                return HealthEvaluation(metric: metric, verdict: .unknown,
                                        causes: [.missingField("inventory update date")])
            }
            let threshold = Calendar.current.date(byAdding: .day, value: -policy.checkedInDays, to: Date())
            let passed = threshold.map { date >= $0 } ?? false
            return HealthEvaluation(metric: metric, verdict: passed ? .compliant : .nonCompliant)

        case .protected:
            return HealthEvaluation(
                metric: metric,
                verdict: (input.isManaged && input.isSupervised) ? .compliant : .nonCompliant
            )

        case .encrypted:
            guard input.hasSecurityObject else {
                return HealthEvaluation(metric: metric, verdict: .unknown,
                                        causes: [.missingField("security data")],
                                        encryptionState: .noData)
            }
            let passed = input.hardwareEncryption == 3
            return HealthEvaluation(
                metric: metric,
                verdict: passed ? .compliant : .nonCompliant,
                encryptionState: passed ? .encrypted : .flagOnly(false)
            )

        case .secured:
            guard input.hasSecurityObject else {
                return HealthEvaluation(metric: metric, verdict: .unknown,
                                        causes: [.missingField("security data")])
            }
            let notJailbroken = !(input.jailBreakDetected ?? false)
            if input.platform == .visionOS {
                let passed = input.isManaged && input.isSupervised && notJailbroken && input.ddmEnabled
                return HealthEvaluation(metric: metric, verdict: passed ? .compliant : .nonCompliant)
            }
            let attested = input.attestationStatus?.uppercased() == "SUCCESS"
            let passed = input.isManaged && input.isSupervised && notJailbroken && attested && input.ddmEnabled
            return HealthEvaluation(metric: metric, verdict: passed ? .compliant : .nonCompliant)

        case .upToDate:
            guard let version = input.osVersion else {
                return HealthEvaluation(metric: metric, verdict: .unknown,
                                        causes: [.missingField("OS version")])
            }
            guard let major = majorVersion(version) else {
                return HealthEvaluation(metric: metric, verdict: .unknown,
                                        causes: [.unparseableField(name: "OS version", value: version)])
            }
            let minimum: Int
            switch input.platform {
            case .iOS:            minimum = policy.minimumIOS
            case .iPadOS:         minimum = policy.minimumIPadOS
            case .visionOS:       minimum = policy.minimumVisionOS
            case .macOS, .all:    minimum = policy.minimumIOS
            }
            return HealthEvaluation(metric: metric,
                                    verdict: major >= minimum ? .compliant : .nonCompliant)
        }
    }

    // MARK: Shared helpers

    /// The single major-version parser. Four separate copies of this existed.
    static func majorVersion(_ version: String) -> Int? {
        guard let first = version.split(separator: ".").first, let major = Int(first) else { return nil }
        return major
    }

    /// The single ISO8601 parser. Jamf emits both fractional and non-fractional
    /// stamps; several copies used a default-options formatter that silently
    /// failed on every fractional one.
    static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    /// Check-in precedence: lastContactTime, then reportDate, at the parsed-date
    /// level rather than the raw-string level, so an unparseable primary does not
    /// suppress a usable fallback.
    static func resolveCheckIn(lastContactTime: String?, reportDate: String?) -> Date? {
        parseDate(lastContactTime) ?? parseDate(reportDate)
    }
}

// MARK: - Fleet model projections

extension ComputerInventoryItem {
    func healthInput(availability: SectionAvailability) -> ComputerHealthInput {
        ComputerHealthInput(
            deviceID: id,
            rawSiteName: siteName,
            checkInDate: HealthEvaluator.resolveCheckIn(
                lastContactTime: general?.lastContactTime,
                reportDate: general?.reportDate
            ),
            isManaged: isManaged,
            isSupervised: isSupervised,
            ddmEnabled: general?.declarativeDeviceManagementEnabled ?? false,
            osVersion: operatingSystem?.version,
            applicationNames: applications.map { $0.compactMap(\.name) },
            firewallEnabled: security?.firewallEnabled ?? false,
            sipStatus: security?.sipStatus,
            gatekeeperStatus: security?.gatekeeperStatus,
            bootstrapTokenEscrowedStatus: security?.bootstrapTokenEscrowedStatus,
            encryptionState: BootEncryptionState.parse(
                partitionState: diskEncryption?.bootPartitionEncryptionDetails?.partitionFileVault2State,
                fileVault2Enabled: diskEncryption?.fileVault2Enabled,
                hasDiskEncryptionObject: diskEncryption != nil
            ),
            availability: availability
        )
    }
}

extension MobileDeviceInventoryItem {
    func healthInput(availability: SectionAvailability) -> MobileHealthInput {
        MobileHealthInput(
            deviceID: id,
            platform: platformType,
            resolvedCheckIn: lastInventoryUpdate,
            osVersion: osVersion,
            isManaged: isManaged,
            isSupervised: isSupervised,
            ddmEnabled: general?.declarativeDeviceManagementEnabled ?? false,
            hasSecurityObject: security != nil,
            jailBreakDetected: security?.jailBreakDetected,
            attestationStatus: security?.attestationStatus,
            hardwareEncryption: security?.hardwareEncryption,
            availability: availability
        )
    }
}
