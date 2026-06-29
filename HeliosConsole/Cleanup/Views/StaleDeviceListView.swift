//
//  StaleDeviceListView.swift
//  HeliosConsole
//
//  Filtered, multi-selectable list of stale devices (macOS Table with a
//  checkbox column and a tri-state select-all). Pushed from the cleanup
//  dashboard with a DeviceFilter. Ported from Clean Slate's DeviceListView.
//

import SwiftUI

struct StaleDeviceListView: View {
    @Environment(CleanupViewModel.self) private var model
    let filter: DeviceFilter

    @State private var showActions = false
    @State private var searchText = ""
    @State private var sortOrder = [KeyPathComparator(\StaleDevice.lastContactTime, order: .forward)]

    /// Devices matching the dashboard filter (before search).
    private var filterMatches: [StaleDevice] {
        model.devices.filter(filter.matches)
    }

    /// What the list actually shows: filter + search + sort.
    private var visibleDevices: [StaleDevice] {
        let base = searchText.isEmpty ? filterMatches : filterMatches.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.userEmail.localizedCaseInsensitiveContains(searchText)
                || $0.serialNumber.localizedCaseInsensitiveContains(searchText)
        }
        return base.sorted(using: sortOrder)
    }

    private var visibleSelectedCount: Int {
        visibleDevices.count(where: { model.selection.contains($0.id) })
    }

    private var allVisibleSelected: Bool {
        !visibleDevices.isEmpty && visibleSelectedCount == visibleDevices.count
    }

    var body: some View {
        deviceTable
            .navigationTitle(filter.title)
            .searchable(text: $searchText, prompt: "Name, email, or serial")
            .safeAreaInset(edge: .top, spacing: 0) { countBar }
            .safeAreaInset(edge: .bottom) {
                if !model.selection.isEmpty {
                    selectionBar
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isLoading)
                }
            }
            .sheet(isPresented: $showActions) {
                CleanupActionsSheet()
                    .environment(model)
            }
            .refreshable {
                await model.refresh()
            }
            .overlay {
                if visibleDevices.isEmpty {
                    emptyOverlay
                }
            }
    }

    // MARK: - Count bar (always visible)

    private var countBar: some View {
        HStack(spacing: 10) {
            CleanupCheckBox(state: checkAllState) {
                model.toggleSelectAll(in: visibleDevices)
            }
            .help("Select all shown devices")

            Group {
                if searchText.isEmpty {
                    Text("\(visibleDevices.count) devices")
                } else {
                    Text("\(visibleDevices.count) of \(filterMatches.count) devices")
                }
            }
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()

            switch filter {
            case .site(let name):
                FilterChip(text: name, icon: "building.2")
            case .overOneYear:
                FilterChip(text: "365+ days", icon: "clock.badge.exclamationmark")
            case .unmanaged:
                FilterChip(text: "unmanaged", icon: "antenna.radiowaves.left.and.right.slash")
            case .allStale:
                FilterChip(text: "\(model.settings.staleDays)+ days", icon: "clock")
            }

            Spacer()

            if visibleSelectedCount > 0 {
                Text("\(visibleSelectedCount) selected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var checkAllState: CleanupCheckBox.State {
        if visibleDevices.isEmpty || visibleSelectedCount == 0 { return .off }
        return allVisibleSelected ? .on : .mixed
    }

    // MARK: - Table

    private var deviceTable: some View {
        @Bindable var model = model

        return Table(visibleDevices, selection: $model.selection, sortOrder: $sortOrder) {
            TableColumn("") { device in
                CleanupCheckBox(state: model.selection.contains(device.id) ? .on : .off) {
                    model.toggleSelection(device.id)
                }
            }
            .width(30)

            TableColumn("Computer Name", value: \.name) { device in
                HStack(spacing: 8) {
                    Image(systemName: "laptopcomputer")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(device.name)
                        Text(device.serialNumber)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .width(min: 180, ideal: 230)

            TableColumn("Assigned User", value: \.userEmail) { device in
                Text(device.userEmail.isEmpty ? "—" : device.userEmail)
                    .foregroundStyle(device.userEmail.isEmpty ? .secondary : .primary)
            }
            .width(min: 160, ideal: 220)

            TableColumn("Last Check-in", value: \.sortableLastContact) { device in
                HStack(spacing: 8) {
                    Text(CleanupFormatters.lastContactString(device.lastContactTime))
                    StaleBadge(days: device.daysSinceContact)
                }
            }
            .width(min: 170, ideal: 210)

            TableColumn("Site", value: \.siteName)
                .width(min: 80, ideal: 120)

            TableColumn("Managed") { device in
                Image(systemName: device.isManaged ? "checkmark.circle.fill" : "minus.circle")
                    .foregroundStyle(device.isManaged ? Color.green : Color.secondary)
            }
            .width(70)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Empty / selection bar

    private var emptyOverlay: some View {
        VStack(spacing: 10) {
            Image(systemName: model.isLoading ? "arrow.clockwise" : "sparkles")
                .font(.system(size: 38))
                .foregroundStyle(.tint)
            Text(model.isLoading ? "Loading…" : "Nothing matches this filter")
                .font(.headline)
            if !searchText.isEmpty {
                Text("Try a different search.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .glassCard()
    }

    private var selectionBar: some View {
        HStack(spacing: 14) {
            Text("\(model.selection.count) selected")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()

            Button("None") { model.clearSelection() }
                .font(.subheadline)

            Spacer()

            Button {
                showActions = true
            } label: {
                Label("Actions", systemImage: "bolt.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private struct FilterChip: View {
    let text: String
    let icon: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.tint.opacity(0.14), in: Capsule())
            .foregroundStyle(.tint)
    }
}

extension StaleDevice {
    /// Table sorting needs a non-optional value; never-contacted sorts oldest.
    var sortableLastContact: Date { lastContactTime ?? .distantPast }
}
