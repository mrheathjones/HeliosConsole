//
//  ProtectDeviceListView.swift
//  HeliosConsole
//
//  Jamf Protect computer records, independent of Jamf Pro. The only
//  action here is deleting the Protect record — Jamf Pro is never touched
//  from this view. Ported from Clean Slate.
//

import SwiftUI

struct ProtectDeviceListView: View {
    @Environment(CleanupViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let filter: ProtectFilter

    @State private var selection: Set<String> = []
    @State private var searchText = ""
    @State private var confirmingDelete = false
    @State private var isDeleting = false
    @State private var results: [ActionResult]?
    /// Observed so the delete gate re-evaluates when capabilities land
    /// after sign-in.
    @ObservedObject private var session = UserSession.shared

    /// The only action in this view is deleting the Jamf Protect record.
    private var canDeleteFromProtect: Bool {
        session.capabilities.canRunCleanupAction(.deleteFromProtect)
    }

    private var filterMatches: [ProtectDevice] {
        model.protectDevices(for: filter)
    }

    private var visibleDevices: [ProtectDevice] {
        let base = searchText.isEmpty ? filterMatches : filterMatches.filter {
            $0.hostName.localizedCaseInsensitiveContains(searchText)
                || $0.serial.localizedCaseInsensitiveContains(searchText)
        }
        return base.sorted { ($0.checkin ?? .distantPast) < ($1.checkin ?? .distantPast) }
    }

    private var selectedDevices: [ProtectDevice] {
        filterMatches.filter { selection.contains($0.uuid) }
    }

    private var visibleSelectedCount: Int {
        visibleDevices.count(where: { selection.contains($0.uuid) })
    }

    private var exportFilename: String {
        ExportNaming.filename(Branding.title, filter.title, date: Date())
    }

    private func buildTable() -> ReportTable {
        var subtitle = "Jamf Protect • \(filter.title)"
        if !searchText.isEmpty {
            subtitle += " • search “\(searchText)”"
        }
        return ReportBuilders.protectTable(
            title: "\(Branding.title) Cleanup — \(filter.title)",
            subtitle: subtitle,
            devices: visibleDevices,
            staleDays: model.settings.staleDays,
            includeSummary: true,
            generatedAt: Date()
        )
    }

    var body: some View {
        List(visibleDevices) { device in
            ProtectRow(
                device: device,
                isSelected: selection.contains(device.uuid)
            ) {
                toggle(device.uuid)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .navigationTitle(filter.title)
        .navigationBarBackButtonHidden(true)
        .searchable(text: $searchText, prompt: "Host name or serial")
        .safeAreaInset(edge: .top, spacing: 0) { countBar }
        .safeAreaInset(edge: .bottom) {
            // No Protect delete grant → no delete bar; the list stays
            // browsable and exportable, but read-only.
            if !selection.isEmpty, canDeleteFromProtect {
                deleteBar
            }
        }
        .overlay {
            if visibleDevices.isEmpty {
                emptyOverlay
            }
        }
        .sheet(item: resultsBox) { box in
            ProtectResultsSheet(results: box.results)
        }
        .confirmationDialog(
            "Delete \(selectedDevices.count) records from Jamf Protect?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete from Jamf Protect", role: .destructive) {
                runDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Jamf Pro is not affected — only the Jamf Protect records are removed.")
        }
    }

    // MARK: - Delete flow

    private func runDelete() {
        // Defense in depth: the delete bar is not rendered without the
        // grant, but enforcement must never live only in the UI.
        guard canDeleteFromProtect else { return }
        let targets = selectedDevices
        isDeleting = true
        Task {
            let outcome = await model.deleteProtectDevices(targets)
            selection.subtract(outcome.filter(\.success).compactMap { result in
                targets.first { $0.hostName == result.deviceName }?.uuid
            })
            results = outcome
            isDeleting = false
        }
    }

    /// Identifiable wrapper so the results sheet can be item-driven.
    private struct ResultsBox: Identifiable {
        let id = UUID()
        let results: [ActionResult]
    }

    private var resultsBox: Binding<ResultsBox?> {
        Binding(
            get: { results.map(ResultsBox.init) },
            set: { if $0 == nil { results = nil } }
        )
    }

    // MARK: - Bars

    private var countBar: some View {
        HStack(spacing: 10) {
            CleanupBackButton { dismiss() }

            CleanupCheckBox(state: checkAllState) {
                let ids = Set(visibleDevices.map(\.uuid))
                if ids.isSubset(of: selection) {
                    selection.subtract(ids)
                } else {
                    selection.formUnion(ids)
                }
            }

            Group {
                if searchText.isEmpty {
                    Text("\(visibleDevices.count) devices")
                } else {
                    Text("\(visibleDevices.count) of \(filterMatches.count) devices")
                }
            }
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()

            if filter == .stale {
                Label("\(model.settings.staleDays)+ days", systemImage: "shield.slash")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.tint.opacity(0.14), in: Capsule())
                    .foregroundStyle(.tint)
            }

            Spacer()

            if visibleSelectedCount > 0 {
                Text("\(visibleSelectedCount) selected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            CleanupExportMenu(filename: exportFilename, makeTable: buildTable)
                .disabled(visibleDevices.isEmpty)
                .controlSize(.small)

            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(model.isLoading || isDeleting)
            .help("Refresh")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var checkAllState: CleanupCheckBox.State {
        if visibleDevices.isEmpty || visibleSelectedCount == 0 { return .off }
        return visibleSelectedCount == visibleDevices.count ? .on : .mixed
    }

    private var deleteBar: some View {
        HStack(spacing: 14) {
            Text("\(selection.count) selected")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()

            Button("None") { selection.removeAll() }
                .font(.subheadline)

            Spacer()

            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                if isDeleting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Delete from Protect", systemImage: "shield.slash")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(isDeleting)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var emptyOverlay: some View {
        VStack(spacing: 10) {
            Image(systemName: model.isLoading ? "arrow.clockwise" : "shield.checkered")
                .font(.system(size: 38))
                .foregroundStyle(.tint)
            Text(model.isLoading ? "Loading…" : "Nothing matches this filter")
                .font(.headline)
        }
        .glassCard()
    }

    private func toggle(_ uuid: String) {
        if selection.contains(uuid) {
            selection.remove(uuid)
        } else {
            selection.insert(uuid)
        }
    }
}

// MARK: - Row

private struct ProtectRow: View {
    let device: ProtectDevice
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CleanupCheckBox(state: isSelected ? .on : .off, action: toggle)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(device.hostName)
                        .font(.body.weight(.medium))
                    Spacer()
                    StaleBadge(days: device.daysSinceCheckin)
                }
                Text(device.serial)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Last check-in: \(CleanupFormatters.lastContactString(device.checkin))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
    }
}

// MARK: - Results sheet

private struct ProtectResultsSheet: View {
    let results: [ActionResult]
    @Environment(\.dismiss) private var dismiss

    private var failures: [ActionResult] { results.filter { !$0.success } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: failures.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .font(.title)
                            .foregroundStyle(failures.isEmpty ? Color.green : .orange)
                        VStack(alignment: .leading) {
                            Text(failures.isEmpty ? "Protect records deleted" : "\(failures.count) deletions failed")
                                .font(.headline)
                            Text("\(results.count) total")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                ForEach(results) { result in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(result.success ? Color.green : Color.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.deviceName)
                                .font(.callout)
                            if !result.success {
                                Text(result.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Results")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 380)
    }
}
