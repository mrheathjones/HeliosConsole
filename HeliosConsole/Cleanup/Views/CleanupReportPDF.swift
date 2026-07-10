//
//  CleanupReportPDF.swift
//  HeliosConsole
//
//  Renders a ReportTable into a multi-page US-Letter PDF by drawing each
//  paginated SwiftUI page view into a CGContext via ImageRenderer. Ported
//  from Clean Slate's ReportPDF.
//

import SwiftUI
import CoreGraphics

enum ReportPDF {
    static let pageSize = CGSize(width: 612, height: 792) // US Letter @ 72dpi
    static let margin: CGFloat = 36
    private static let firstPageRows = 22
    private static let otherPageRows = 34

    @MainActor
    static func render(_ table: ReportTable) -> Data {
        let pages = paginate(table.rows)
        let pageData = NSMutableData()

        guard let consumer = CGDataConsumer(data: pageData as CFMutableData) else {
            return Data()
        }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        for (index, slice) in pages.enumerated() {
            let page = ReportPageView(
                table: table,
                rows: slice,
                pageIndex: index,
                pageCount: pages.count,
                isFirst: index == 0
            )
            .frame(width: pageSize.width, height: pageSize.height)
            .environment(\.colorScheme, .light)

            let renderer = ImageRenderer(content: page)
            renderer.proposedSize = ProposedViewSize(pageSize)
            renderer.scale = 1
            renderer.isOpaque = true
            renderer.render { _, drawInContext in
                context.beginPDFPage(nil)
                drawInContext(context)
                context.endPDFPage()
            }
        }

        context.closePDF()
        return pageData as Data
    }

    private static func paginate(_ rows: [[String]]) -> [[[String]]] {
        guard !rows.isEmpty else { return [[]] }
        var pages: [[[String]]] = []
        var index = 0
        var first = true
        while index < rows.count {
            let take = first ? firstPageRows : otherPageRows
            let end = min(index + take, rows.count)
            pages.append(Array(rows[index..<end]))
            index = end
            first = false
        }
        return pages
    }
}

// MARK: - Page view

private struct ReportPageView: View {
    let table: ReportTable
    let rows: [[String]]
    let pageIndex: Int
    let pageCount: Int
    let isFirst: Bool

    private let accent = Color(red: 0.05, green: 0.42, blue: 0.55)
    private var contentWidth: CGFloat { ReportPDF.pageSize.width - ReportPDF.margin * 2 }
    private var widths: [CGFloat] { table.columnWidths(total: contentWidth) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isFirst {
                titleBlock
                if !table.summary.isEmpty {
                    summaryBlock
                        .padding(.top, 14)
                }
                Text(table.sectionTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                    .padding(.top, 16)
                    .padding(.bottom, 4)
            } else {
                HStack {
                    Text(table.title)
                        .font(.system(size: 10, weight: .semibold))
                    Spacer()
                    Text("continued")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)
            }

            tableHeader
            Rectangle()
                .fill(accent.opacity(0.55))
                .frame(height: 1)

            ForEach(Array(rows.enumerated()), id: \.offset) { offset, row in
                tableRow(row, zebra: offset.isMultiple(of: 2))
            }

            Spacer(minLength: 0)

            HStack {
                Text("Helios Console")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Page \(pageIndex + 1) of \(pageCount)")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 6)
        }
        .padding(ReportPDF.margin)
        .frame(width: ReportPDF.pageSize.width, height: ReportPDF.pageSize.height, alignment: .topLeading)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18))
                    .foregroundStyle(accent)
                Text(table.title)
                    .font(.system(size: 20, weight: .bold))
            }
            if !table.subtitle.isEmpty {
                Text(table.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Text("Generated \(CleanupFormatters.report.string(from: table.generatedAt))")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Rectangle()
                .fill(accent)
                .frame(height: 3)
                .padding(.top, 6)
        }
    }

    private var summaryBlock: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(table.summary) { item in
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.label.uppercased())
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(item.value)
                        .font(.system(size: 12, weight: .semibold))
                }
            }
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(table.headers.enumerated()), id: \.offset) { index, header in
                Text(header)
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: widths[index], alignment: .leading)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }

    private func tableRow(_ row: [String], zebra: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(row.enumerated()), id: \.offset) { index, cell in
                Text(cell)
                    .font(.system(size: 8))
                    .frame(width: index < widths.count ? widths[index] : 60, alignment: .leading)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 2.5)
        .padding(.horizontal, 2)
        .background(zebra ? Color.black.opacity(0.04) : Color.clear)
    }
}
