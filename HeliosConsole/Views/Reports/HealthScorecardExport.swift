//
//  HealthScorecardExport.swift
//  HeliosConsole
//
//  Builds the Environment Health Scorecard report — the five health metrics
//  plus a managed-device-count breakdown by OS — into the shared, multi-section
//  ReportTable so it exports to CSV / Excel / PDF / Markdown like every other
//  Helios report.
//

import Foundation

enum HealthScorecardExportBuilder {
    /// One OS-version bucket with its managed/unmanaged split.
    struct OSRow: Identifiable, Hashable {
        let label: String
        let total: Int
        let managed: Int
        var unmanaged: Int { total - managed }
        var id: String { label }
    }

    // MARK: - Shared computations (used by both the on-screen view and the export)

    /// Managed-device counts grouped by platform + OS major version, e.g.
    /// "macOS 15", "iOS 26". Sorted by platform then version (newest first).
    @MainActor
    static func osBreakdown() -> [OSRow] {
        struct Key: Hashable { let platform: String; let major: String }
        var groups: [Key: (total: Int, managed: Int)] = [:]

        for c in ComputerInventoryCache.shared.computers {
            let key = Key(platform: "macOS", major: majorVersion(c.operatingSystem?.version))
            var g = groups[key] ?? (0, 0)
            g.total += 1
            if c.isManaged { g.managed += 1 }
            groups[key] = g
        }
        for d in MobileDeviceInventoryCache.shared.devices {
            let key = Key(platform: d.platformType.rawValue, major: majorVersion(d.osVersion))
            var g = groups[key] ?? (0, 0)
            g.total += 1
            if d.isManaged { g.managed += 1 }
            groups[key] = g
        }

        return groups
            .map { OSRow(label: "\($0.key.platform) \($0.key.major)", total: $0.value.total, managed: $0.value.managed) }
            .sorted { lhs, rhs in
                // Group by platform, then newest OS major version first.
                let lp = lhs.label.components(separatedBy: " ").first ?? lhs.label
                let rp = rhs.label.components(separatedBy: " ").first ?? rhs.label
                if lp != rp { return lp < rp }
                return lhs.label.compare(rhs.label, options: .numeric) == .orderedDescending
            }
    }

    /// Plain average of the five metric percentages (matches the dashboard).
    @MainActor
    static func overallHealth() -> Double {
        let metrics = HealthMetricsCalculator.shared.healthMetrics
        guard !metrics.isEmpty else { return 0 }
        return metrics.map(\.percentage).reduce(0, +) / Double(metrics.count)
    }

    // MARK: - Report table

    @MainActor
    static func table(generatedAt: Date) -> ReportTable {
        let metrics = HealthMetricsCalculator.shared.healthMetrics
        let osRows = osBreakdown()

        let scorecardRows: [[String]] = metrics.map { m in
            [m.type.rawValue, "\(m.compliantCount)", "\(m.totalCount)", pct(m.percentage)]
        }

        // Derive totals from the same population the OS breakdown iterates, so
        // Total == Managed + Unmanaged always reconciles with the OS table.
        let totalDevices = osRows.reduce(0) { $0 + $1.total }
        let totalManaged = osRows.reduce(0) { $0 + $1.managed }

        let summary: [ReportTable.SummaryItem] = [
            .init(label: "Overall health", value: pct(overallHealth())),
            .init(label: "Total devices", value: "\(totalDevices)"),
            .init(label: "Managed devices", value: "\(totalManaged)"),
            .init(label: "Unmanaged devices", value: "\(max(totalDevices - totalManaged, 0))"),
        ]

        let osTableRows: [[String]] = osRows.map { [$0.label, "\($0.total)", "\($0.managed)", "\($0.unmanaged)"] }

        return ReportTable(
            title: "Environment Health Scorecard",
            subtitle: "Device compliance and managed-device breakdown by OS",
            sectionTitle: "Health Scorecard",
            generatedAt: generatedAt,
            summary: summary,
            headers: ["Metric", "Compliant", "Total", "Percentage"],
            rows: scorecardRows,
            extraSections: [
                .init(title: "Managed Devices by OS", headers: ["OS", "Total", "Managed", "Unmanaged"], rows: osTableRows)
            ]
        )
    }

    // MARK: - Helpers

    static func pct(_ value: Double) -> String {
        // Truncate (not round) to match the Dashboard scorecard and the
        // on-screen preview, which both display Int(percentage).
        "\(Int(value))%"
    }

    private static func majorVersion(_ version: String?) -> String {
        guard let version,
              let first = version.split(separator: ".").first,
              !first.isEmpty else { return "Unknown" }
        return String(first)
    }
}
