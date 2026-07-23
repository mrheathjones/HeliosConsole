//
//  DeviceHistorySectionView.swift
//  HeliosConsole
//
//  Renders the Device Details "History" section: Jamf Policy Logs and MDM
//  command history (Management History), pulled from the Classic
//  `computerhistory` endpoint by ComputerHistoryService.
//
//  Two tabs (Policy Logs / Management History), mirroring the ABM Lookup /
//  Pre-Stage pill-tab strip. Each tab has its own "contains" search, status
//  filter chips, and pagination (page size is config-driven). Rows expand to
//  show all fields Jamf exposes — the Classic endpoint carries no per-run
//  execution detail (script/package output), so status + timestamps are the
//  full picture.
//
//  Standalone/parameterized on purpose — DeviceView owns the load state and
//  passes data (and page size) in, keeping this out of that large file and
//  free of any private-member coupling.
//

import SwiftUI

struct DeviceHistorySectionView: View {
    let history: ComputerHistory?
    let isLoading: Bool
    let errorMessage: String?
    let pageSize: Int
    let onRetry: () -> Void

    @State private var tab: HistoryTab = .policyLogs
    @State private var policySearch = ""
    @State private var policyFilter: PolicyStatusFilter = .all
    @State private var policyPage = 1
    @State private var commandSearch = ""
    @State private var commandFilter: CommandStatusFilter = .all
    @State private var commandPage = 1
    @State private var expanded: Set<String> = []
    @State private var newestFirst = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            tabStrip

            if isLoading && history == nil {
                loadingState
            } else if let errorMessage {
                errorState(errorMessage)
            } else {
                switch tab {
                case .policyLogs: policyTab
                case .managementHistory: commandTab
                }
            }
        }
    }

    // MARK: - Header + tabs

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.blue)
            Text("History")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
            Spacer()
            if isLoading && history != nil {
                ProgressView().scaleEffect(0.6)
            }
        }
    }

    private var tabStrip: some View {
        HStack(spacing: 8) {
            ForEach(HistoryTab.allCases) { t in tabChip(t) }
            Spacer()
        }
    }

    private func tabChip(_ t: HistoryTab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { tab = t }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: t.icon).font(.system(size: 11, weight: .medium))
                Text(t.title).font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(tab == t ? .white : .gray)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(tab == t ? Color.accentColor : Color.white.opacity(0.05)))
            .overlay(Capsule().stroke(tab == t ? Color.accentColor : Color.white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Policy Logs tab

    private var policyTab: some View {
        let source: [PolicyLogEntry] = history?.policyLogs ?? []
        let sorted = sortedByDate(source) { $0.date }
        let filtered: [PolicyLogEntry] = sorted.filter { entry in
            guard policyFilter.matches(entry) else { return false }
            if policySearch.isEmpty { return true }
            return (entry.policyName ?? "").localizedCaseInsensitiveContains(policySearch)
        }

        let page = Pagination(total: filtered.count, pageSize: pageSize, current: policyPage)
        let rows = page.slice(filtered).enumerated().map {
            Self.rowModel(policy: $0.element, index: page.start + $0.offset)
        }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(PolicyStatusFilter.allCases) { f in
                    filterChip(f.title, selected: policyFilter == f, color: f.color) { policyFilter = f }
                }
                Spacer()
                sortButton
            }
            searchField($policySearch, "Search policy logs by name…")

            if filtered.isEmpty {
                emptyState(policySearch.isEmpty && policyFilter == .all
                           ? "No policy logs recorded"
                           : "No policy logs match your filter")
            } else {
                rowList(rows)
                if page.showControls {
                    paginationBar(page: $policyPage, p: page)
                }
            }
        }
        .onChange(of: policySearch) { policyPage = 1 }
        .onChange(of: policyFilter) { policyPage = 1 }
        .onChange(of: newestFirst) { policyPage = 1 }
    }

    // MARK: - Management History tab

    private var commandTab: some View {
        let source = sortedByDate(taggedCommands()) { $0.entry.date }
        let filtered = source.filter { item in
            guard commandFilter.matches(item.state) else { return false }
            if commandSearch.isEmpty { return true }
            return (item.entry.name ?? "").localizedCaseInsensitiveContains(commandSearch)
        }

        let page = Pagination(total: filtered.count, pageSize: pageSize, current: commandPage)
        let rows = page.slice(filtered).enumerated().map {
            Self.rowModel(command: $0.element.entry, state: $0.element.state, index: page.start + $0.offset)
        }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(CommandStatusFilter.allCases) { f in
                    filterChip(f.title, selected: commandFilter == f, color: f.color) { commandFilter = f }
                }
                Spacer()
                sortButton
            }
            searchField($commandSearch, "Search commands by name…")

            if filtered.isEmpty {
                emptyState(commandSearch.isEmpty && commandFilter == .all
                           ? "No commands recorded"
                           : "No commands match your filter")
            } else {
                rowList(rows)
                if page.showControls {
                    paginationBar(page: $commandPage, p: page)
                }
            }
        }
        .onChange(of: commandSearch) { commandPage = 1 }
        .onChange(of: commandFilter) { commandPage = 1 }
        .onChange(of: newestFirst) { commandPage = 1 }
    }

    /// Flatten the three command buckets into (entry, state). Ordering is
    /// applied later by `sortedByDate`.
    private func taggedCommands() -> [(entry: CommandEntry, state: CommandState)] {
        let c = history?.commands
        var tagged: [(entry: CommandEntry, state: CommandState)] = []
        tagged += (c?.failed ?? []).map { (entry: $0, state: CommandState.failed) }
        tagged += (c?.pending ?? []).map { (entry: $0, state: CommandState.pending) }
        tagged += (c?.completed ?? []).map { (entry: $0, state: CommandState.completed) }
        return tagged
    }

    /// Sort by date when any entry has a parseable date; otherwise fall back to
    /// Jamf's returned order (observed oldest-first) and just reverse it for
    /// "newest first". This keeps the toggle working even when Policy Logs
    /// carry no parseable timestamp.
    private func sortedByDate<T>(_ items: [T], date: (T) -> Date?) -> [T] {
        let hasDates = items.contains { date($0) != nil }
        if hasDates {
            return items.sorted { a, b in
                let ka = date(a) ?? .distantPast
                let kb = date(b) ?? .distantPast
                return newestFirst ? ka > kb : ka < kb
            }
        }
        return newestFirst ? items.reversed() : items
    }

    private var sortButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { newestFirst.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: newestFirst ? "arrow.down" : "arrow.up")
                    .font(.system(size: 11, weight: .semibold))
                Text(newestFirst ? "Newest" : "Oldest")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.gray)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05)))
        }
        .buttonStyle(.plain)
        .help(newestFirst ? "Newest first (tap for oldest)" : "Oldest first (tap for newest)")
    }

    // MARK: - Row list + row

    private func rowList(_ rows: [RowModel]) -> some View {
        LazyVStack(spacing: 8) {
            ForEach(rows) { rowView($0) }
        }
    }

    private func rowView(_ m: RowModel) -> some View {
        let isOpen = expanded.contains(m.id)
        let color = m.color.color
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { toggle(m.id) }
            } label: {
                rowSummary(m, color: color, isOpen: isOpen)
            }
            .buttonStyle(.plain)

            if isOpen {
                rowDetail(m)
                    .padding(.top, 10)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .cornerRadius(8)
    }

    private func rowSummary(_ m: RowModel, color: Color, isOpen: Bool) -> some View {
        HStack(spacing: 12) {
            Circle().fill(color).frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(m.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if let badge = m.badge, !badge.isEmpty {
                        Text(badge)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(color.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
                timestampLine(date: m.date, raw: m.rawDate)
                if let err = m.errorDetail, !err.isEmpty, !isOpen {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundColor(.red.opacity(0.8))
                        .lineLimit(1)
                }
            }

            Spacer()

            if let username = m.username, !username.isEmpty {
                Text(username)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .frame(width: 120, alignment: .trailing)
                    .lineLimit(1)
            }

            Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.gray)
        }
    }

    private func rowDetail(_ m: RowModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(m.details) { pair in
                HStack(alignment: .top, spacing: 10) {
                    Text(pair.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.gray)
                        .frame(width: 90, alignment: .leading)
                    Text(pair.value)
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
            }
            if let err = m.errorDetail, !err.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Text("Error")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.gray)
                        .frame(width: 90, alignment: .leading)
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.9))
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.leading, 20)
        .padding(.top, 8)
        .overlay(Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1), alignment: .top)
    }

    @ViewBuilder
    private func timestampLine(date: Date?, raw: String?) -> some View {
        if let date {
            HStack(spacing: 8) {
                Text(date, style: .date).font(.system(size: 12)).foregroundColor(.gray)
                Text(date, style: .time).font(.system(size: 12)).foregroundColor(.gray)
            }
        } else if let raw, !raw.isEmpty {
            // Parsing failed but Jamf gave us *some* date string — show it
            // verbatim rather than a useless dash.
            Text(raw).font(.system(size: 12)).foregroundColor(.gray)
        } else {
            Text("—").font(.system(size: 12)).foregroundColor(.gray)
        }
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    // MARK: - Shared controls

    private func filterChip(_ label: String, selected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? .white : .gray)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selected ? color.opacity(0.3) : Color.white.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
    }

    private func searchField(_ text: Binding<String>, _ placeholder: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundColor(.gray)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(.white)
            if !text.wrappedValue.isEmpty {
                Button { text.wrappedValue = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }

    private func paginationBar(page: Binding<Int>, p: Pagination) -> some View {
        HStack(spacing: 16) {
            Text("Showing \(p.total == 0 ? 0 : p.start + 1)-\(p.end) of \(p.total)")
                .font(.system(size: 12))
                .foregroundColor(.gray)
            Spacer()
            pageButton("chevron.left", enabled: p.current > 1) {
                page.wrappedValue = max(1, p.current - 1)
            }
            Text("Page \(p.current) of \(p.totalPages)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.1))
                .cornerRadius(6)
            pageButton("chevron.right", enabled: p.current < p.totalPages) {
                page.wrappedValue = min(p.totalPages, p.current + 1)
            }
        }
        .padding(.top, 4)
    }

    private func pageButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(enabled ? .white : .gray.opacity(0.4))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading history…").font(.system(size: 13)).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.orange.opacity(0.7))
            Text("Couldn't load history").font(.system(size: 16, weight: .medium)).foregroundColor(.white)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            Button("Retry", action: onRetry).buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private func emptyState(_ text: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40))
                .foregroundColor(.gray.opacity(0.4))
            Text(text).font(.system(size: 15, weight: .medium)).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

// MARK: - Pagination helper

private struct Pagination {
    let total: Int
    let pageSize: Int
    let current: Int
    let totalPages: Int
    let start: Int
    let end: Int

    init(total: Int, pageSize: Int, current: Int) {
        let size = max(1, pageSize)
        self.total = total
        self.pageSize = size
        self.totalPages = max(1, Int(ceil(Double(total) / Double(size))))
        let clamped = min(max(1, current), totalPages)
        self.current = clamped
        self.start = (clamped - 1) * size
        self.end = min(start + size, total)
    }

    var showControls: Bool { total > pageSize }

    func slice<T>(_ items: [T]) -> [T] {
        guard total > 0, start < items.count else { return [] }
        return Array(items[start..<min(end, items.count)])
    }
}

// MARK: - Tabs & filters

private enum HistoryTab: String, CaseIterable, Identifiable {
    case policyLogs
    case managementHistory
    var id: String { rawValue }
    var title: String {
        switch self {
        case .policyLogs: return "Policy Logs"
        case .managementHistory: return "Management History"
        }
    }
    var icon: String {
        switch self {
        case .policyLogs: return "doc.text"
        case .managementHistory: return "terminal"
        }
    }
}

private enum PolicyStatusFilter: String, CaseIterable, Identifiable {
    case all, completed, failed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }
    var color: Color {
        switch self {
        case .all: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }
    func matches(_ e: PolicyLogEntry) -> Bool {
        switch self {
        case .all: return true
        case .completed: return e.isSuccess
        case .failed: return !e.isSuccess
        }
    }
}

private enum CommandStatusFilter: String, CaseIterable, Identifiable {
    case all, completed, pending, failed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .completed: return "Completed"
        case .pending: return "Pending"
        case .failed: return "Failed"
        }
    }
    var color: Color {
        switch self {
        case .all: return .blue
        case .completed: return .green
        case .pending: return .yellow
        case .failed: return .red
        }
    }
    func matches(_ state: CommandState) -> Bool {
        switch self {
        case .all: return true
        case .completed: return state == .completed
        case .pending: return state == .pending
        case .failed: return state == .failed
        }
    }
}

private enum CommandState {
    case completed, pending, failed
    var label: String {
        switch self {
        case .completed: return "Completed"
        case .pending: return "Pending"
        case .failed: return "Failed"
        }
    }
}

// MARK: - Row model (precomputed so SwiftUI's type-checker stays fast)

private enum RowColor {
    case green, red, yellow
    var color: Color {
        switch self {
        case .green: return .green
        case .red: return .red
        case .yellow: return .yellow
        }
    }
}

private struct DetailPair: Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

private struct RowModel: Identifiable {
    let id: String
    let color: RowColor
    let title: String
    let badge: String?
    let date: Date?
    /// Raw date string to display when `date` couldn't be parsed.
    let rawDate: String?
    let username: String?
    let errorDetail: String?
    let details: [DetailPair]
}

extension DeviceHistorySectionView {
    fileprivate static func rowModel(policy: PolicyLogEntry, index: Int) -> RowModel {
        let title: String
        if let name = policy.policyName, !name.isEmpty {
            title = name
        } else if let pid = policy.policyId {
            title = "Policy \(pid)"
        } else {
            title = "Policy"
        }

        var details: [DetailPair] = []
        if let pid = policy.policyId { details.append(.init(label: "Policy ID", value: "\(pid)")) }
        if let status = policy.status, !status.isEmpty { details.append(.init(label: "Status", value: status)) }
        if let user = policy.username, !user.isEmpty { details.append(.init(label: "User", value: user)) }
        if let when = policy.dateTime, !when.isEmpty { details.append(.init(label: "Executed", value: when)) }

        return RowModel(
            id: "policy-\(index)-\(policy.id)",
            color: policy.isSuccess ? .green : .red,
            title: title,
            badge: policy.status,
            date: policy.date,
            rawDate: policy.dateTime ?? policy.dateTimeUtc ?? policy.dateTimeEpoch,
            username: policy.username,
            errorDetail: nil,
            details: details
        )
    }

    fileprivate static func rowModel(command: CommandEntry, state: CommandState, index: Int) -> RowModel {
        let color: RowColor
        switch state {
        case .completed: color = .green
        case .pending: color = .yellow
        case .failed: color = .red
        }
        let title = (command.name?.isEmpty == false) ? command.name! : "Command"

        var details: [DetailPair] = []
        details.append(.init(label: "Type", value: state.label))
        if let user = command.username, !user.isEmpty { details.append(.init(label: "User", value: user)) }

        // Jamf overloads `status` with the error text on failure.
        let errorDetail = (state == .failed) ? command.status : nil

        return RowModel(
            id: "cmd-\(index)-\(state.label)-\(command.id)",
            color: color,
            title: title,
            badge: state.label,
            date: command.date,
            rawDate: command.completedUtc ?? command.issuedUtc ?? command.failedUtc,
            username: command.username,
            errorDetail: errorDetail,
            details: details
        )
    }
}
