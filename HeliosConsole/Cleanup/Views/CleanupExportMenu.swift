//
//  CleanupExportMenu.swift
//  HeliosConsole
//
//  Reusable "Export" menu (CSV / Markdown / PDF) backed by the native file
//  exporter. Drops into any toolbar; the table is built lazily so PDF
//  rendering only happens on the chosen format. Ported from Clean Slate.
//

import SwiftUI
import UniformTypeIdentifiers

/// A FileDocument whose bytes and type are supplied at export time.
struct ExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText, .markdownReport, .pdf, .plainText, .excelWorkbook]
    static let writableContentTypes: [UTType] = [.commaSeparatedText, .markdownReport, .pdf, .plainText, .excelWorkbook]

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

@MainActor
func exportData(_ table: ReportTable, as format: CleanupExportFormat) -> Data {
    switch format {
    case .csv: table.csvData()
    case .markdown: Data(table.markdownString().utf8)
    case .pdf: ReportPDF.render(table)
    }
}

struct CleanupExportMenu: View {
    /// Base filename without extension.
    let filename: String
    /// Built lazily when a format is chosen.
    let makeTable: () -> ReportTable
    var titleKey: String = "Export"

    @State private var document: ExportDocument?
    @State private var contentType: UTType = .commaSeparatedText
    @State private var isExporting = false

    var body: some View {
        Menu {
            ForEach(CleanupExportFormat.allCases) { format in
                Button {
                    prepare(format)
                } label: {
                    Label(format.displayName, systemImage: format.systemImage)
                }
            }
        } label: {
            Label(titleKey, systemImage: "square.and.arrow.up")
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

    private func prepare(_ format: CleanupExportFormat) {
        let table = makeTable()
        document = ExportDocument(data: exportData(table, as: format))
        contentType = format.utType
        isExporting = true
    }
}
