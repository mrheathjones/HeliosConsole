//
//  PaginationControls.swift
//  Helios
//
//  "Showing X-Y of N" plus first/previous/next/last page buttons, and a
//  PaginatedRows container that pairs them with a PaginatedListState.
//

import SwiftUI

struct PaginationControls: View {
    @Binding var currentPage: Int
    let totalPages: Int
    let totalItems: Int
    /// 0-based index of the first row shown.
    let startIndex: Int
    /// 0-based index one past the last row shown.
    let endIndex: Int

    var body: some View {
        HStack(spacing: 16) {
            Text("Showing \(startIndex + 1)-\(endIndex) of \(totalItems)")
                .font(.system(size: 12))
                .foregroundColor(.gray)

            Spacer()

            HStack(spacing: 8) {
                pageButton("chevron.left.2", enabled: currentPage > 1) {
                    currentPage = 1
                }

                pageButton("chevron.left", enabled: currentPage > 1) {
                    currentPage = max(1, currentPage - 1)
                }

                Text("Page \(currentPage) of \(totalPages)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(6)

                pageButton("chevron.right", enabled: currentPage < totalPages) {
                    currentPage = min(totalPages, currentPage + 1)
                }

                pageButton("chevron.right.2", enabled: currentPage < totalPages) {
                    currentPage = totalPages
                }
            }
        }
        .padding(.top, 16)
    }

    private func pageButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(enabled ? .white : .gray.opacity(0.5))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Renders the current page of `rows` (already filtered through `state`) as a
/// lazy stack, with pagination controls when the rows span several pages.
struct PaginatedRows<Row: Identifiable, RowContent: View>: View {
    @Bindable var state: PaginatedListState<Row>
    let rows: [Row]
    @ViewBuilder let rowContent: (Row) -> RowContent

    var body: some View {
        let slice = state.slice(of: rows)

        LazyVStack(spacing: 8) {
            ForEach(slice.rows) { row in
                rowContent(row)
            }
        }

        if slice.needsPagination {
            PaginationControls(
                currentPage: $state.page,
                totalPages: slice.totalPages,
                totalItems: slice.totalItems,
                startIndex: slice.startIndex,
                endIndex: slice.endIndex
            )
        }
    }
}
