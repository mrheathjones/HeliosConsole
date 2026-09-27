//
//  PaginatedListState.swift
//  Helios
//
//  Search + page state for one client-side paginated list. The rows
//  themselves are not stored here: the owning view passes the current rows in,
//  so the state survives the model being replaced (e.g. once full device
//  details finish loading) without going stale.
//

import Foundation
import Observation

@Observable
final class PaginatedListState<Row> {
    /// Editing the search always returns the list to its first page.
    var searchText: String = "" {
        didSet { if searchText != oldValue { page = 1 } }
    }

    /// 1-based current page.
    var page: Int = 1

    let itemsPerPage: Int

    @ObservationIgnored private let matchesSearch: (Row, String) -> Bool

    /// - Parameter matchesSearch: whether a row matches the (non-empty) search
    ///   text. An empty search matches every row.
    init(itemsPerPage: Int = 25, matchesSearch: @escaping (Row, String) -> Bool) {
        self.itemsPerPage = itemsPerPage
        self.matchesSearch = matchesSearch
    }

    /// Call when a list-specific filter (tag chips, status picker, …) changes.
    func resetPage() {
        page = 1
    }

    /// Rows that pass the search text and the caller's extra filter.
    func filter(_ rows: [Row], where include: (Row) -> Bool = { _ in true }) -> [Row] {
        rows.filter { row in
            (searchText.isEmpty || matchesSearch(row, searchText)) && include(row)
        }
    }

    /// The current page of already-filtered rows.
    func slice(of rows: [Row]) -> PageSlice<Row> {
        let totalPages = max(1, Int(ceil(Double(rows.count) / Double(itemsPerPage))))
        let startIndex = (page - 1) * itemsPerPage
        let endIndex = min(startIndex + itemsPerPage, rows.count)
        return PageSlice(
            rows: Array(rows[startIndex..<endIndex]),
            totalItems: rows.count,
            totalPages: totalPages,
            startIndex: startIndex,
            endIndex: endIndex,
            needsPagination: rows.count > itemsPerPage
        )
    }
}

/// One page of a filtered list plus the numbers the pagination bar shows.
struct PageSlice<Row> {
    let rows: [Row]
    let totalItems: Int
    let totalPages: Int
    /// 0-based index of the first row on this page.
    let startIndex: Int
    /// 0-based index one past the last row on this page.
    let endIndex: Int
    /// False when everything fits on one page — the controls are hidden.
    let needsPagination: Bool
}
