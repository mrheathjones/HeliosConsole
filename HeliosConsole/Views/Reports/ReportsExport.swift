//
//  ReportsExport.swift
//  HeliosConsole
//
//  Real export for the Report Builder. Builds a format-agnostic ReportTable
//  from the on-screen device results and renders it to CSV, Excel (.xlsx),
//  PDF, or Markdown. CSV / Markdown / PDF reuse the shared Cleanup export
//  stack (ReportTable, ReportPDF, ExportDocument); Excel is produced by the
//  small, dependency-free OOXML/ZIP writer at the bottom of this file.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Export format

enum ReportsExportFormat: String, CaseIterable, Identifiable, Sendable {
    case csv
    case excel
    case pdf
    case markdown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .csv: "CSV Spreadsheet"
        case .excel: "Excel Workbook"
        case .pdf: "PDF Document"
        case .markdown: "Markdown"
        }
    }

    var fileExtension: String {
        switch self {
        case .csv: "csv"
        case .excel: "xlsx"
        case .pdf: "pdf"
        case .markdown: "md"
        }
    }

    var systemImage: String {
        switch self {
        case .csv: "tablecells"
        case .excel: "tablecells.badge.ellipsis"
        case .pdf: "doc.richtext"
        case .markdown: "text.alignleft"
        }
    }

    var utType: UTType {
        switch self {
        case .csv: .commaSeparatedText
        case .excel: .excelWorkbook
        case .pdf: .pdf
        case .markdown: .markdownReport
        }
    }
}

extension UTType {
    /// Office Open XML spreadsheet (.xlsx). Imported so the file exporter
    /// applies the right extension and content type.
    static let excelWorkbook = UTType(importedAs: "org.openxmlformats.spreadsheetml.sheet")
}

// MARK: - Table builder

/// Turns the Report Builder's on-screen results into a `ReportTable` —
/// the same format-agnostic structure the Cleanup exporters render from.
enum ReportsExportBuilder {
    // Base headers mirror the on-screen results table exactly.
    static let columnHeaders = [
        "Device Name", "Serial", "Platform", "Last Check-In",
        "Supervised", "Encrypted", "OS", "Model",
    ]

    // Appended when Device Enrollment (ADE) details are included.
    static let enrollmentHeaders = [
        "In Jamf?", "ADE Status", "DEP Assigned", "PreStage ID", "DEP Instance",
    ]

    /// Matches the on-screen results table so exports reflect exactly what the
    /// user sees: a short, locale-aware date and "N/A" for never-checked-in.
    private static let checkInFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    static func table(
        results: [ReportDeviceResult],
        platforms: Set<PlatformType>,
        filters: [ReportFilter],
        scope: DeviceScope,
        individualQuery: String,
        includeEnrollment: Bool,
        generatedAt: Date
    ) -> ReportTable {
        let headers = includeEnrollment ? columnHeaders + enrollmentHeaders : columnHeaders

        let rows: [[String]] = results.map { r in
            let checkIn = r.lastCheckIn.map { checkInFormatter.string(from: $0) } ?? "N/A"
            var row: [String] = [
                r.deviceName,
                r.serialNumber,
                r.platform.rawValue,
                checkIn,
                r.isSupervised ? "Yes" : "No",
                r.isEncrypted ? "Yes" : "No",
                r.osVersion,
                r.model,
            ]
            if includeEnrollment {
                row.append(r.inJamf ? "Yes" : "No")
                row.append(r.enrollment?.profileStatus?.displayName ?? "—")
                row.append(depDate(r.enrollment?.deviceAssignedDate))
                row.append(r.enrollment?.prestageId ?? "—")
                row.append(r.enrollmentInstanceName ?? "—")
            }
            return row
        }

        let platformList = PlatformType.displayCases
            .filter(platforms.contains)
            .map(\.rawValue)
            .joined(separator: ", ")
        let filterText = filters.isEmpty
            ? "No filters"
            : "\(filters.count) filter\(filters.count == 1 ? "" : "s")"

        var summary: [ReportTable.SummaryItem] = [
            .init(label: "Devices in report", value: "\(results.count)"),
            .init(label: "Platforms", value: platformList.isEmpty ? "—" : platformList),
            .init(label: "Filters applied", value: "\(filters.count)"),
            .init(label: "Supervised", value: "\(results.count(where: \.isSupervised))"),
            .init(label: "Encrypted", value: "\(results.count(where: \.isEncrypted))"),
            .init(label: "Distinct platforms", value: "\(Set(results.map(\.platform)).count)"),
        ]
        if includeEnrollment {
            summary.append(.init(label: "In Jamf", value: "\(results.count(where: \.inJamf))"))
            summary.append(.init(label: "ADE only (not in Jamf)", value: "\(results.count(where: { !$0.inJamf }))"))
        }

        // Surface each active filter (and the scope) so the export documents
        // exactly what data it represents.
        var criteria: [ReportTable.CriterionItem] = []
        switch scope {
        case .all: break
        case .individual: criteria.append(.init(category: "Scope", detail: "Device: \(individualQuery.isEmpty ? "—" : individualQuery)"))
        }
        criteria += filters.map {
            ReportTable.CriterionItem(category: $0.category.rawValue, detail: $0.displayDescription)
        }
        if includeEnrollment {
            criteria.append(.init(category: "Enrollment", detail: "Device Enrollment (ADE) details included"))
        }

        return ReportTable(
            title: "Device Report",
            subtitle: platformList.isEmpty ? filterText : "\(platformList) · \(filterText)",
            sectionTitle: "Devices",
            generatedAt: generatedAt,
            summary: summary,
            headers: headers,
            rows: rows,
            criteria: criteria
        )
    }

    private static func depDate(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "—" }
        // ADE dates are ISO8601 — show just the date part.
        return String(raw.prefix(10))
    }
}

// MARK: - Export menu

/// A styled "Export" menu offering every `ReportsExportFormat`, backed by the
/// native file exporter. The table is built lazily so PDF/Excel rendering only
/// happens for the chosen format.
struct ReportsExportMenu: View {
    /// Base filename without extension.
    let filename: String
    /// Built lazily when a format is chosen.
    let makeTable: () -> ReportTable
    var isDark: Bool = false
    /// When true, renders as a large gradient button (like Run Report).
    var prominent: Bool = false

    @State private var document: ExportDocument?
    @State private var contentType: UTType = .commaSeparatedText
    @State private var isExporting = false
    @State private var isRendering = false
    @State private var showFormats = false
    /// Observed so the export gate re-evaluates when capabilities land
    /// after sign-in.
    @ObservedObject private var session = UserSession.shared

    var body: some View {
        // Both Reports export entry points (the toolbar menu and the
        // prominent Run-Report button) render through this view, so the
        // allowExport gate lives here once: no grant, no control at all.
        if session.capabilities.allowExport {
            Group {
                if prominent {
                    prominentButton
                } else {
                    subtleMenu
                }
            }
            .fileExporter(
                isPresented: $isExporting,
                document: document,
                contentType: contentType,
                defaultFilename: filename
            ) { _ in
                document = nil
            }
        }
    }

    /// A large gradient button (matches Run Report) whose tap opens a popover
    /// of the four formats. A real Button renders the gradient reliably — a
    /// Menu label's custom background gets stripped by the borderless style.
    private var prominentButton: some View {
        Button {
            showFormats = true
        } label: {
            ExportButtonLabel(isBusy: isRendering)
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(isRendering)
        .popover(isPresented: $showFormats, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(ReportsExportFormat.allCases) { format in
                    Button {
                        showFormats = false
                        prepare(format)
                    } label: {
                        Label(format.displayName, systemImage: format.systemImage)
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .frame(width: 210)
        }
    }

    private var subtleMenu: some View {
        Menu {
            ForEach(ReportsExportFormat.allCases) { format in
                Button {
                    prepare(format)
                } label: {
                    Label(format.displayName, systemImage: format.systemImage)
                }
            }
        } label: {
            ExportButtonLabel(isBusy: isRendering)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(isRendering)
    }

    private func prepare(_ format: ReportsExportFormat) {
        // Defense in depth: the control is not rendered without the grant,
        // but never let enforcement live only in the UI.
        guard session.capabilities.allowExport else { return }
        // Snapshot the on-screen results now (on the main actor) so the export
        // reflects exactly what's visible, even if the report is re-run later.
        let table = makeTable()
        contentType = format.utType
        isRendering = true
        Task {
            let data = await render(table, as: format)
            document = ExportDocument(data: data)
            isRendering = false
            isExporting = true
        }
    }

    /// PDF must render on the main actor (ImageRenderer); the data-only formats
    /// run off the main actor so large reports don't freeze the UI.
    @MainActor
    private func render(_ table: ReportTable, as format: ReportsExportFormat) async -> Data {
        switch format {
        case .pdf:
            return ReportPDF.render(table)
        case .csv:
            return await Task.detached(priority: .userInitiated) { table.csvData() }.value
        case .markdown:
            return await Task.detached(priority: .userInitiated) { Data(table.markdownString().utf8) }.value
        case .excel:
            return await Task.detached(priority: .userInitiated) {
                ReportsXLSX.workbook(sheetName: table.sectionTitle, table: table)
            }.value
        }
    }
}

// MARK: - Minimal .xlsx (OOXML) writer

/// Builds a valid single-sheet `.xlsx` workbook with no third-party
/// dependencies. Cells are written as inline strings (so serials and OS
/// versions keep their exact text — leading zeros and all), with a bold
/// header row. The package is assembled as a STORED (uncompressed) ZIP.
enum ReportsXLSX {
    static func workbook(sheetName: String, table: ReportTable) -> Data {
        var zip = ZipBuilder()
        zip.add(path: "[Content_Types].xml", contents: Data(contentTypesXML.utf8))
        zip.add(path: "_rels/.rels", contents: Data(rootRelsXML.utf8))
        zip.add(path: "xl/workbook.xml", contents: Data(workbookXML(sheetName: sheetName).utf8))
        zip.add(path: "xl/_rels/workbook.xml.rels", contents: Data(workbookRelsXML.utf8))
        zip.add(path: "xl/styles.xml", contents: Data(stylesXML.utf8))
        zip.add(path: "xl/worksheets/sheet1.xml", contents: Data(sheetXML(table).utf8))
        return zip.finalize()
    }

    // MARK: Package parts

    private static let contentTypesXML = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/><Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/></Types>"

    private static let rootRelsXML = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>"

    private static let workbookRelsXML = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>"

    private static let stylesXML = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><fonts count=\"2\"><font><sz val=\"11\"/><name val=\"Calibri\"/></font><font><b/><sz val=\"11\"/><name val=\"Calibri\"/></font></fonts><fills count=\"2\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill></fills><borders count=\"1\"><border/></borders><cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs><cellXfs count=\"2\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/><xf numFmtId=\"0\" fontId=\"1\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyFont=\"1\"/></cellXfs><cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles></styleSheet>"

    private static func workbookXML(sheetName: String) -> String {
        let safe = esc(sanitizeSheetName(sheetName))
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets><sheet name=\"\(safe)\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>"
    }

    private static func sheetXML(_ table: ReportTable) -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>"
        var rowIndex = 1
        func appendRow(_ cells: [String], bold: Bool = false) {
            xml += "<row r=\"\(rowIndex)\">"
            for (col, value) in cells.enumerated() {
                let ref = "\(columnLetters(col))\(rowIndex)"
                let style = bold ? " s=\"1\"" : ""
                xml += "<c r=\"\(ref)\"\(style) t=\"inlineStr\"><is><t xml:space=\"preserve\">\(esc(value))</t></is></c>"
            }
            xml += "</row>"
            rowIndex += 1
        }
        func blank() { xml += "<row r=\"\(rowIndex)\"></row>"; rowIndex += 1 }

        appendRow(["Report", table.title], bold: true)
        if !table.subtitle.isEmpty { appendRow(["", table.subtitle]) }
        appendRow(["Generated", CleanupFormatters.report.string(from: table.generatedAt)])

        if !table.criteria.isEmpty {
            blank()
            appendRow(["Filters applied"], bold: true)
            for c in table.criteria { appendRow([c.category, c.detail]) }
        }
        if !table.summary.isEmpty {
            blank()
            appendRow(["Summary"], bold: true)
            for s in table.summary { appendRow([s.label, s.value]) }
        }

        blank()
        if !table.sectionTitle.isEmpty { appendRow([table.sectionTitle], bold: true) }
        if !table.headers.isEmpty { appendRow(table.headers, bold: true) }
        for row in table.rows { appendRow(row) }

        for section in table.extraSections {
            blank()
            appendRow([section.title], bold: true)
            if !section.headers.isEmpty { appendRow(section.headers, bold: true) }
            for row in section.rows { appendRow(row) }
        }

        xml += "</sheetData></worksheet>"
        return xml
    }

    // MARK: Helpers

    private static func sanitizeSheetName(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: ":\\/?*[]")
        let cleaned = name.components(separatedBy: forbidden).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = cleaned.isEmpty ? "Sheet1" : cleaned
        return String(base.prefix(31))
    }

    /// 0 -> "A", 25 -> "Z", 26 -> "AA", …
    private static func columnLetters(_ index: Int) -> String {
        var n = index
        var s = ""
        repeat {
            let r = n % 26
            s = String(UnicodeScalar(UInt8(65 + r))) + s
            n = n / 26 - 1
        } while n >= 0
        return s
    }

    private static func esc(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count + 8)
        for scalar in s.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default:
                // Keep only characters valid in XML 1.0. Surface stray control
                // codes as U+FFFD rather than silently dropping them, so the
                // export never diverges invisibly from the on-screen data.
                let v = scalar.value
                if v == 0x09 || v == 0x0A || v == 0x0D || (v >= 0x20 && v != 0xFFFE && v != 0xFFFF) {
                    out.unicodeScalars.append(scalar)
                } else {
                    out.append("\u{FFFD}")
                }
            }
        }
        return out
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB8_8320 : (crc >> 1)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    // MARK: ZIP container (stored / no compression)

    private struct ZipBuilder {
        private var data = Data()
        private struct Entry { let name: String; let crc: UInt32; let size: Int; let offset: Int }
        private var entries: [Entry] = []

        mutating func add(path: String, contents: Data) {
            // This writer is not ZIP64; a single >4GB entry would overflow the
            // UInt32 size fields. Device reports never approach this.
            assert(contents.count <= 0xFFFF_FFFF, "ZIP entry exceeds 4GB; ZIP64 not supported")
            let nameBytes = Array(path.utf8)
            let crc = ReportsXLSX.crc32(contents)
            let offset = data.count
            // Local file header.
            data.append(le32: 0x0403_4b50)
            data.append(le16: 20)   // version needed to extract
            data.append(le16: 0)    // general purpose flags
            data.append(le16: 0)    // compression method: stored
            data.append(le16: 0)    // mod time
            data.append(le16: 0)    // mod date
            data.append(le32: crc)
            data.append(le32: UInt32(contents.count))   // compressed size
            data.append(le32: UInt32(contents.count))   // uncompressed size
            data.append(le16: UInt16(nameBytes.count))
            data.append(le16: 0)    // extra field length
            data.append(contentsOf: nameBytes)
            data.append(contents)
            entries.append(Entry(name: path, crc: crc, size: contents.count, offset: offset))
        }

        mutating func finalize() -> Data {
            let cdStart = data.count
            for e in entries {
                let nameBytes = Array(e.name.utf8)
                data.append(le32: 0x0201_4b50)
                data.append(le16: 20)   // version made by
                data.append(le16: 20)   // version needed
                data.append(le16: 0)    // flags
                data.append(le16: 0)    // method
                data.append(le16: 0)    // mod time
                data.append(le16: 0)    // mod date
                data.append(le32: e.crc)
                data.append(le32: UInt32(e.size))
                data.append(le32: UInt32(e.size))
                data.append(le16: UInt16(nameBytes.count))
                data.append(le16: 0)    // extra length
                data.append(le16: 0)    // comment length
                data.append(le16: 0)    // disk number start
                data.append(le16: 0)    // internal attributes
                data.append(le32: 0)    // external attributes
                data.append(le32: UInt32(e.offset))
                data.append(contentsOf: nameBytes)
            }
            let cdSize = data.count - cdStart
            // End of central directory record.
            data.append(le32: 0x0605_4b50)
            data.append(le16: 0)    // disk number
            data.append(le16: 0)    // disk with central directory
            data.append(le16: UInt16(entries.count))
            data.append(le16: UInt16(entries.count))
            data.append(le32: UInt32(cdSize))
            data.append(le32: UInt32(cdStart))
            data.append(le16: 0)    // comment length
            return data
        }
    }
}

// MARK: - Little-endian Data helpers

private extension Data {
    mutating func append(le16 value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func append(le32 value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}
