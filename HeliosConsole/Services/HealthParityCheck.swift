//
//  HealthParityCheck.swift
//  Helios
//
//  Compares the unified HealthEvaluator against the live metric logic, device by
//  device, on real inventory. This repo has no test target, so this is the test
//  suite: it runs against the actual fleet rather than fixtures someone invented,
//  and every mismatch it reports must be an intended behavior change.
//
//  Output goes to a FILE, not NSLog. Managed Macs commonly ship a logging
//  configuration profile that drops third-party default-level messages, so the
//  unified log is not a dependable channel on exactly the machines that have a
//  real fleet to check against.
//
//  TEMPORARY — delete once every call site has been migrated.
//

import Foundation

@MainActor
enum HealthParityCheck {

    /// `defaults write com.herojoneslabs.helios.console healthParityCheck -bool NO`
    /// to silence it without a rebuild. Defaults on for the migration.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "healthParityCheck") as? Bool ?? true
    }

    private static let logURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Helios/Logs/health-parity.log")
    }()

    struct Mismatch {
        let metric: HealthMetricType
        let deviceID: String
        let site: String
        let old: String
        let new: String
        let cause: String
    }

    /// Runs the comparison and writes a report. Called after `recalculateMetrics`.
    ///
    /// Two oracles, because they expire at different points in the migration:
    ///
    /// - `oldVerdicts` is per-device and comes from the drill-down. It is the
    ///   sharpest check but stops being independent the moment the drill-down
    ///   itself is migrated (step 1) — from then on it compares the evaluator
    ///   against itself and passes vacuously. Pass nil once that happens.
    /// - `liveTallies` is the aggregate count from `calculate*Metric` and stays
    ///   independent until the percentage path migrates (step 2).
    static func run(
        computers: [ComputerInventoryItem],
        mobileDevices: [MobileDeviceInventoryItem],
        policy: HealthPolicy,
        computerSections: [String],
        mobileSections: [String],
        oldVerdicts: ((HealthMetricType) -> [String: String])?,
        liveTallies: [HealthMetricType: (compliant: Int, nonCompliant: Int, unknown: Int)] = [:]
    ) {
        guard isEnabled else { return }

        var lines: [String] = []
        var mismatches: [Mismatch] = []
        var matcherDelta: [String] = []

        let computerAvailability = SectionAvailability.computers(computerSections)
        let mobileAvailability = SectionAvailability.mobileDevices(mobileSections)

        var tallies: [HealthMetricType: (compliant: Int, nonCompliant: Int, unknown: Int)] = [:]

        for metric in HealthMetricType.allCases {
            let old = oldVerdicts?(metric)
            var tally = (compliant: 0, nonCompliant: 0, unknown: 0)

            for computer in computers {
                let input = computer.healthInput(availability: computerAvailability)
                let evaluation = HealthEvaluator.evaluate(metric, computer: input, policy: policy)
                let newVerdict = evaluation.verdict.rawValue
                switch evaluation.verdict {
                case .compliant: tally.compliant += 1
                case .nonCompliant: tally.nonCompliant += 1
                case .unknown: tally.unknown += 1
                case .excluded: break
                }
                // Devices in no segment are absent from the old map; the new
                // evaluator calls that `excluded`.
                if let old {
                    let oldVerdict = old[computer.id] ?? HealthVerdict.excluded.rawValue
                    if oldVerdict != newVerdict {
                        mismatches.append(Mismatch(
                            metric: metric, deviceID: computer.id,
                            site: computer.siteName ?? "(none)",
                            old: oldVerdict, new: newVerdict,
                            cause: evaluation.causes.first.map { "\($0)" } ?? "-"
                        ))
                    }
                }
            }

            for device in mobileDevices {
                let input = device.healthInput(availability: mobileAvailability)
                let evaluation = HealthEvaluator.evaluate(metric, mobile: input, policy: policy)
                let newVerdict = evaluation.verdict.rawValue
                switch evaluation.verdict {
                case .compliant: tally.compliant += 1
                case .nonCompliant: tally.nonCompliant += 1
                case .unknown: tally.unknown += 1
                case .excluded: break
                }
                if let old {
                    let oldVerdict = old[device.id] ?? HealthVerdict.excluded.rawValue
                    if oldVerdict != newVerdict {
                        mismatches.append(Mismatch(
                            metric: metric, deviceID: device.id, site: "(mobile)",
                            old: oldVerdict, new: newVerdict,
                            cause: evaluation.causes.first.map { "\($0)" } ?? "-"
                        ))
                    }
                }
            }

            tallies[metric] = tally
        }

        // The question PR 3 needs answered with data rather than assumption: how
        // far apart are substring and exact-or-".app" app matching on this fleet?
        var substringPass = 0
        var strictPass = 0
        var differing: [String] = []
        for computer in computers {
            guard let rule = policy.rule(forSite: computer.siteName) else { continue }
            let installed = (computer.applications ?? []).compactMap(\.name)
            let loose = rule.requiredApps.allSatisfy { HealthEvaluator.matches($0, in: installed) }
            let strict = rule.requiredApps.allSatisfy { HealthEvaluator.matchesStrict($0, in: installed) }
            if loose { substringPass += 1 }
            if strict { strictPass += 1 }
            if loose != strict, differing.count < 25 {
                let missed = rule.requiredApps.filter {
                    HealthEvaluator.matches($0, in: installed) != HealthEvaluator.matchesStrict($0, in: installed)
                }
                differing.append("  \(computer.id) site=\(computer.siteName ?? "-") differs on: \(missed.joined(separator: ", "))")
            }
        }
        matcherDelta.append("substring pass: \(substringPass)   exact-or-.app pass: \(strictPass)")
        if !differing.isEmpty {
            matcherDelta.append("devices where the two matchers disagree (max 25 shown):")
            matcherDelta.append(contentsOf: differing)
        }

        lines.append("=== Health evaluator parity check ===")
        lines.append("run at: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("computers: \(computers.count)   mobile: \(mobileDevices.count)")
        lines.append("computer sections: \(computerSections.sorted().joined(separator: ", "))")
        lines.append("mobile sections:   \(mobileSections.sorted().joined(separator: ", "))")
        lines.append("")
        lines.append("--- app matcher comparison ---")
        lines.append(contentsOf: matcherDelta)
        lines.append("")
        if liveTallies.isEmpty {
            lines.append("--- aggregate tallies: (live counts not supplied) ---")
        } else {
            var tallyMismatch = 0
            lines.append("--- aggregate tally vs live card ---")
            for metric in HealthMetricType.allCases {
                guard let mine = tallies[metric], let live = liveTallies[metric] else { continue }
                let agree = mine == live
                if !agree { tallyMismatch += 1 }
                lines.append("  \(agree ? "OK  " : "DIFF")  \(metric.rawValue): "
                    + "new \(mine.compliant)/\(mine.nonCompliant)/\(mine.unknown)  "
                    + "live \(live.compliant)/\(live.nonCompliant)/\(live.unknown)   (compliant/non/unknown)")
            }
            lines.append(tallyMismatch == 0
                ? "  all metrics agree with the live card"
                : "  \(tallyMismatch) metric(s) DISAGREE — investigate before migrating further")
        }

        lines.append("")
        if oldVerdicts == nil {
            lines.append("--- per-device comparison skipped (drill-down already migrated) ---")
        }
        lines.append("--- verdict mismatches: \(mismatches.count) ---")
        if mismatches.isEmpty {
            lines.append("none — unified evaluator agrees with live logic on every device")
        } else {
            var byMetric: [HealthMetricType: [Mismatch]] = [:]
            for m in mismatches { byMetric[m.metric, default: []].append(m) }
            for metric in HealthMetricType.allCases {
                guard let group = byMetric[metric], !group.isEmpty else { continue }
                lines.append("")
                lines.append("[\(metric.rawValue)] \(group.count) mismatches")
                // Summarise by transition so a systematic change reads as one line
                // rather than 600.
                var transitions: [String: Int] = [:]
                for m in group { transitions["\(m.old) -> \(m.new)", default: 0] += 1 }
                for (transition, count) in transitions.sorted(by: { $0.value > $1.value }) {
                    lines.append("  \(transition): \(count) devices")
                }
                for m in group.prefix(20) {
                    lines.append("    \(m.deviceID) site=\(m.site) \(m.old)->\(m.new) cause=\(m.cause)")
                }
                if group.count > 20 { lines.append("    … \(group.count - 20) more") }
            }
        }
        lines.append("")

        write(lines.joined(separator: "\n"))
    }

    private static func write(_ contents: String) {
        let directory = logURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? contents.write(to: logURL, atomically: true, encoding: .utf8)
        NSLog("📋 HealthParityCheck: report written to %@", logURL.path)
    }
}

// MARK: - Model projections

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
