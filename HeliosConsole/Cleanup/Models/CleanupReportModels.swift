//
//  CleanupReportModels.swift
//  HeliosConsole
//
//  Export plumbing for the Cleanup feature: a format-agnostic ReportTable
//  that CSV, Markdown, and PDF all render from, plus builders that turn
//  device lists into tables. Ported from Clean Slate's ReportModels.
//

import Foundation
import UniformTypeIdentifiers

// MARK: - Export format

enum CleanupExportFormat: String, CaseIterable, Identifiable, Sendable {
    case csv
    case markdown
    case pdf

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .csv: "CSV Spreadsheet"
        case .markdown: "Markdown"
        case .pdf: "PDF Document"
        }
    }

    var fileExtension: String {
        switch self {
        case .csv: "csv"
        case .markdown: "md"
        case .pdf: "pdf"
        }
    }

    var systemImage: String {
        switch self {
        case .csv: "tablecells"
        case .markdown: "text.alignleft"
        case .pdf: "doc.richtext"
        }
    }

    var utType: UTType {
        switch self {
        case .csv: .commaSeparatedText
        case .markdown: .markdownReport
        case .pdf: .pdf
        }
    }
}

extension UTType {
    /// Markdown is a system-declared type on current OSes; import it so
    /// the file exporter applies the .md extension.
    static let markdownReport = UTType(importedAs: "net.daringfireball.markdown")
}

// MARK: - Device report columns

enum ReportColumn: String, CaseIterable, Identifiable, Hashable, Sendable {
    case name, serial, user, lastCheckIn, daysStale, site, managed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: "Computer Name"
        case .serial: "Serial Number"
        case .user: "Assigned User"
        case .lastCheckIn: "Last Check-in"
        case .daysStale: "Days Stale"
        case .site: "Site"
        case .managed: "Managed"
        }
    }

    func value(_ device: StaleDevice) -> String {
        switch self {
        case .name: device.name
        case .serial: device.serialNumber
        case .user: device.userEmail.isEmpty ? "—" : device.userEmail
        case .lastCheckIn: CleanupFormatters.reportDate(device.lastContactTime)
        case .daysStale: device.daysSinceContact.map(String.init) ?? "Never"
        case .site: device.siteName
        case .managed: device.isManaged ? "Yes" : "No"
        }
    }
}

// MARK: - Report table

struct ReportTable: Sendable {
    struct SummaryItem: Identifiable, Sendable {
        let label: String
        let value: String
        var id: String { label }
    }

    var title: String
    var subtitle: String
    var sectionTitle: String
    var generatedAt: Date
    var summary: [SummaryItem]
    var headers: [String]
    var rows: [[String]]

    var isEmpty: Bool { rows.isEmpty }

    // MARK: CSV

    func csvData() -> Data {
        var lines: [String] = []
        lines.append(headers.map(Self.csvEscape).joined(separator: ","))
        for row in rows {
            lines.append(row.map(Self.csvEscape).joined(separator: ","))
        }
        // CRLF keeps Excel happy.
        return Data(lines.joined(separator: "\r\n").utf8)
    }

    private static func csvEscape(_ field: String) -> String {
        if field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    // MARK: Markdown

    func markdownString() -> String {
        var out = "# \(title)\n\n"
        if !subtitle.isEmpty {
            out += "\(subtitle)\n\n"
        }
        out += "_Generated \(CleanupFormatters.report.string(from: generatedAt))_\n\n"

        if !summary.isEmpty {
            out += "## Summary\n\n"
            for item in summary {
                out += "- **\(item.label):** \(item.value)\n"
            }
            out += "\n"
        }

        out += "## \(sectionTitle)\n\n"
        if rows.isEmpty {
            out += "_No devices._\n"
            return out
        }
        out += "| " + headers.map(Self.mdEscape).joined(separator: " | ") + " |\n"
        out += "| " + headers.map { _ in "---" }.joined(separator: " | ") + " |\n"
        for row in rows {
            out += "| " + row.map(Self.mdEscape).joined(separator: " | ") + " |\n"
        }
        return out
    }

    private static func mdEscape(_ field: String) -> String {
        field
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    /// Proportional column widths (summing to `total`) for PDF layout —
    /// gives identifying columns more room.
    func columnWidths(total: CGFloat) -> [CGFloat] {
        let weights = headers.map { header -> CGFloat in
            switch header {
            case ReportColumn.name.title, ReportColumn.user.title: 1.7
            case ReportColumn.serial.title, ReportColumn.lastCheckIn.title: 1.3
            default: 1.0
            }
        }
        let sum = weights.reduce(0, +)
        guard sum > 0 else { return headers.map { _ in total / CGFloat(max(headers.count, 1)) } }
        return weights.map { total * $0 / sum }
    }
}

// MARK: - Builders

enum ReportBuilders {
    static func deviceTable(
        title: String,
        subtitle: String,
        devices: [StaleDevice],
        columns: [ReportColumn],
        staleDays: Int,
        includeSummary: Bool,
        generatedAt: Date
    ) -> ReportTable {
        let orderedColumns = ReportColumn.allCases.filter(columns.contains)
        let headers = orderedColumns.map(\.title)
        let rows = devices.map { device in orderedColumns.map { $0.value(device) } }

        var summary: [ReportTable.SummaryItem] = []
        if includeSummary {
            let distinctSites = Set(devices.map(\.siteName)).count
            summary = [
                .init(label: "Devices in report", value: "\(devices.count)"),
                .init(label: "Stale threshold", value: "\(staleDays) days"),
                .init(label: "Managed", value: "\(devices.count(where: \.isManaged))"),
                .init(label: "Unmanaged", value: "\(devices.count(where: { !$0.isManaged }))"),
                .init(label: "Stale over 1 year", value: "\(devices.count(where: \.isStaleOverOneYear))"),
                .init(label: "Distinct sites", value: "\(distinctSites)"),
            ]
        }

        return ReportTable(
            title: title,
            subtitle: subtitle,
            sectionTitle: "Devices",
            generatedAt: generatedAt,
            summary: summary,
            headers: headers,
            rows: rows
        )
    }

    static func protectTable(
        title: String,
        subtitle: String,
        devices: [ProtectDevice],
        staleDays: Int,
        includeSummary: Bool,
        generatedAt: Date
    ) -> ReportTable {
        let headers = ["Host Name", "Serial Number", "Last Check-in", "Days Stale"]
        let rows = devices.map { device in
            [
                device.hostName,
                device.serial,
                CleanupFormatters.reportDate(device.checkin),
                device.daysSinceCheckin.map(String.init) ?? "Never",
            ]
        }

        var summary: [ReportTable.SummaryItem] = []
        if includeSummary {
            let staleCount = devices.count(where: {
                ($0.daysSinceCheckin ?? Int.max) >= staleDays
            })
            summary = [
                .init(label: "Devices in report", value: "\(devices.count)"),
                .init(label: "Stale threshold", value: "\(staleDays) days"),
                .init(label: "Stale in report", value: "\(staleCount)"),
            ]
        }

        return ReportTable(
            title: title,
            subtitle: subtitle,
            sectionTitle: "Jamf Protect Computers",
            generatedAt: generatedAt,
            summary: summary,
            headers: headers,
            rows: rows
        )
    }
}

// MARK: - Filename helper

enum ExportNaming {
    static func filename(_ parts: String..., date: Date) -> String {
        let slug = parts
            .joined(separator: "-")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return "\(slug)-\(CleanupFormatters.fileDate(date))"
    }
}
