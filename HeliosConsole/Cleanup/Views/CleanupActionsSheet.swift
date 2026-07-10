//
//  CleanupActionsSheet.swift
//  HeliosConsole
//
//  Pick the actions to run against the selected stale devices, confirm,
//  watch progress, review per-device results. Ported from Clean Slate's
//  ActionsSheet.
//

import SwiftUI

struct CleanupActionsSheet: View {
    @Environment(CleanupViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var unmanage = false
    @State private var addToGroup = false
    @State private var selectedGroupID: Int = 0
    @State private var moveToSite = false
    @State private var selectedSiteID: Int = -1
    @State private var deleteFromProtect = false
    @State private var deleteRecord = false
    @State private var confirming = false
    @State private var phase: Phase = .configure

    private enum Phase {
        case configure, running, done
    }

    /// When on, deleting a Jamf Pro record always deletes the matching
    /// Jamf Protect record too.
    private var autoProtectCleanup: Bool {
        model.settings.isProtectConfigured && model.settings.protectAutoCleanup
    }

    private var plan: ActionPlan {
        var plan = ActionPlan()
        plan.unmanage = unmanage
        if addToGroup, selectedGroupID != 0 {
            plan.addToGroupID = selectedGroupID
            plan.addToGroupName = model.staticGroups.first { $0.id == selectedGroupID }?.name
        }
        if moveToSite, selectedSiteID != -1 || model.sites.contains(where: { $0.intID == selectedSiteID }) {
            plan.moveToSiteID = selectedSiteID
            plan.moveToSiteName = model.sites.first { $0.intID == selectedSiteID }?.name ?? "None"
        }
        plan.deleteFromProtect = deleteFromProtect
        plan.deleteRecord = deleteRecord
        return plan
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .configure: configureForm
                case .running: runningView
                case .done: resultsView
                }
            }
            .navigationTitle("Actions")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(phase == .done ? "Close" : "Cancel") { dismiss() }
                        .disabled(phase == .running)
                }
            }
        }
        .task { await model.loadLookups() }
        .frame(minWidth: 480, minHeight: 460)
    }

    // MARK: - Configure

    private var configureForm: some View {
        Form {
            Section {
                LabeledContent("Selected devices", value: "\(model.selectedDevices.count)")
            }

            Section("Jamf Pro") {
                Toggle(isOn: $unmanage) {
                    Label("Send Unmanage command", systemImage: "antenna.radiowaves.left.and.right.slash")
                }

                Toggle(isOn: $addToGroup) {
                    Label("Add to static group", systemImage: "rectangle.stack.badge.plus")
                }
                if addToGroup {
                    Picker("Static group", selection: $selectedGroupID) {
                        Text("Choose…").tag(0)
                        ForEach(model.staticGroups) { group in
                            Text(group.name).tag(group.id)
                        }
                    }
                }

                Toggle(isOn: $moveToSite) {
                    Label("Move to site", systemImage: "building.2")
                }
                if moveToSite {
                    Picker("Site", selection: $selectedSiteID) {
                        Text("None").tag(-1)
                        ForEach(model.sites) { site in
                            Text(site.name).tag(site.intID)
                        }
                    }
                }
            }

            Section {
                if model.settings.isProtectConfigured {
                    Toggle(isOn: $deleteFromProtect) {
                        Label("Delete from Jamf Protect", systemImage: "shield.slash")
                    }
                    .disabled(autoProtectCleanup && deleteRecord)
                }
                Toggle(isOn: $deleteRecord) {
                    Label("Delete Jamf Pro record", systemImage: "trash")
                        .foregroundStyle(.red)
                }
                .onChange(of: deleteRecord) { _, isOn in
                    if autoProtectCleanup && isOn {
                        deleteFromProtect = true
                    }
                }
            } header: {
                Text("Cleanup")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if autoProtectCleanup && deleteRecord {
                        Text("Jamf Protect cleanup is automatic when deleting records (enabled in Settings).")
                    }
                    if deleteRecord {
                        Text("Deleting a record does not unenroll the device. If it ever checks in again it will re-enroll as a new record.")
                    }
                }
            }

            Section {
                Button {
                    confirming = true
                } label: {
                    Label("Run \(plan.summary.count) action\(plan.summary.count == 1 ? "" : "s") on \(model.selectedDevices.count) devices",
                          systemImage: "bolt.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(plan.isEmpty || model.selectedDevices.isEmpty
                          || (addToGroup && selectedGroupID == 0))
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Run on \(model.selectedDevices.count) devices?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button(plan.isDestructive ? "Run Actions" : "Run", role: plan.isDestructive ? .destructive : nil) {
                phase = .running
                Task {
                    await model.runActions(plan)
                    phase = .done
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(plan.summary.joined(separator: "\n"))
        }
    }

    // MARK: - Running

    private var runningView: some View {
        VStack(spacing: 16) {
            ProgressView(value: model.actionProgress)
                .progressViewStyle(.linear)
                .frame(maxWidth: 360)
            Text("Working… \(model.actionResults.count) operations finished")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results

    private var resultsView: some View {
        let failures = model.actionResults.filter { !$0.success }

        return List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: failures.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.title)
                        .foregroundStyle(failures.isEmpty ? Color.green : .orange)
                    VStack(alignment: .leading) {
                        Text(failures.isEmpty ? "All actions completed" : "\(failures.count) operations failed")
                            .font(.headline)
                        Text("\(model.actionResults.count) total operations")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !failures.isEmpty {
                Section("Failures") {
                    ForEach(failures) { ResultRow(result: $0) }
                }
            }

            Section("All results") {
                ForEach(model.actionResults) { ResultRow(result: $0) }
            }
        }
    }
}

private struct ResultRow: View {
    let result: ActionResult

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.success ? Color.green : Color.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(result.deviceName) — \(result.action.rawValue)")
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
