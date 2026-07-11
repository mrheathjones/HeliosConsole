//
//  CleanupReportPDF.swift
//  HeliosConsole
//
//  Renders a ReportTable into a multi-page US-Letter PDF by drawing each
//  paginated SwiftUI page view into a CGContext via ImageRenderer. Supports a
//  document header (title + active filters + summary) plus one or more titled
//  table blocks (the primary table and any extra sections). Ported from Clean
//  Slate's ReportPDF and extended for the Reports export.
//

import SwiftUI
import CoreGraphics
import AppKit

enum ReportPDF {
    static let pageSize = CGSize(width: 612, height: 792) // US Letter @ 72dpi
    static let margin: CGFloat = 36
    private static let plainFirstPageRows = 22   // block 0, page 1, no header block
    private static let headerFirstPageRows = 12  // block 0, page 1, with filters/summary header
    private static let otherPageRows = 34

    /// One rendered page: which block it belongs to and the rows it carries.
    fileprivate struct PageSpec {
        let documentHeader: Bool   // very first page: draw title + filters + summary
        let blockTitle: String
        let continued: Bool        // a wrapped continuation of the same block
        let headers: [String]
        let rows: [[String]]
    }

    private struct Block {
        let title: String
        let headers: [String]
        let rows: [[String]]
    }

    @MainActor
    static func render(_ table: ReportTable) -> Data {
        var blocks: [Block] = [Block(title: table.sectionTitle, headers: table.headers, rows: table.rows)]
        blocks += table.extraSections.map { Block(title: $0.title, headers: $0.headers, rows: $0.rows) }

        let specs = paginate(blocks: blocks, hasHeader: !table.criteria.isEmpty || !table.summary.isEmpty)

        let pageData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pageData as CFMutableData) else { return Data() }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }

        for (index, spec) in specs.enumerated() {
            let page = ReportPageView(
                table: table,
                spec: spec,
                pageIndex: index,
                pageCount: specs.count
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

    private static func paginate(blocks: [Block], hasHeader: Bool) -> [PageSpec] {
        var specs: [PageSpec] = []
        for (bi, block) in blocks.enumerated() {
            let firstBudget: Int = bi == 0
                ? (hasHeader ? headerFirstPageRows : plainFirstPageRows)
                : otherPageRows
            var index = 0
            var firstOfBlock = true
            repeat {
                let budget = firstOfBlock ? firstBudget : otherPageRows
                let end = min(index + budget, block.rows.count)
                specs.append(PageSpec(
                    documentHeader: bi == 0 && firstOfBlock,
                    blockTitle: block.title,
                    continued: !firstOfBlock,
                    headers: block.headers,
                    rows: Array(block.rows[index..<end])
                ))
                index = end
                firstOfBlock = false
            } while index < block.rows.count
        }
        return specs.isEmpty ? [PageSpec(documentHeader: true, blockTitle: "", continued: false, headers: [], rows: [])] : specs
    }
}

// MARK: - Page view

private struct ReportPageView: View {
    let table: ReportTable
    let spec: ReportPDF.PageSpec
    let pageIndex: Int
    let pageCount: Int

    private let accent = Color(red: 0.05, green: 0.42, blue: 0.55)
    private var contentWidth: CGFloat { ReportPDF.pageSize.width - ReportPDF.margin * 2 }
    private var widths: [CGFloat] { ReportTable.columnWidths(for: spec.headers, total: contentWidth) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if spec.documentHeader {
                titleBlock
                if !table.criteria.isEmpty {
                    criteriaBlock.padding(.top, 12)
                }
                if !table.summary.isEmpty {
                    summaryBlock.padding(.top, 12)
                }
                Text(spec.blockTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                    .padding(.top, 16)
                    .padding(.bottom, 4)
            } else if spec.continued {
                HStack {
                    Text(spec.blockTitle)
                        .font(.system(size: 10, weight: .semibold))
                    Spacer()
                    Text("continued")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)
            } else {
                // A fresh extra section starting on its own page.
                Text(spec.blockTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                    .padding(.bottom, 4)
            }

            tableHeader
            Rectangle()
                .fill(accent.opacity(0.55))
                .frame(height: 1)

            ForEach(Array(spec.rows.enumerated()), id: \.offset) { offset, row in
                tableRow(row, zebra: offset.isMultiple(of: 2))
            }

            Spacer(minLength: 0)

            HStack {
                Text(Branding.productName)
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
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
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

    private var criteriaBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("FILTERS APPLIED")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(accent)
            ForEach(table.criteria) { c in
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(c.category):")
                        .font(.system(size: 9, weight: .semibold))
                    Text(c.detail)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
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
            ForEach(Array(spec.headers.enumerated()), id: \.offset) { index, header in
                Text(header)
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: index < widths.count ? widths[index] : 60, alignment: .leading)
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
