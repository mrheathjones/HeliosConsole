//
//  CleanupActionsSheet.swift
//  HeliosConsole
//
//  Pick the actions to run against the selected stale devices, confirm,
//  watch progress, review per-device results. Styled to match Helios's
//  prompt/modal design language (dark card, tinted icon circle, split
//  confirm buttons), not SwiftUI's grouped Form.
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

    private enum Phase { case configure, running, done }

    // Helios dark-theme tokens
    private let cardBG = Color.white.opacity(0.05)
    private let panelBG = Color(white: 0.11)

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

    private var canRun: Bool {
        !plan.isEmpty && !model.selectedDevices.isEmpty && !(addToGroup && selectedGroupID == 0)
    }

    var body: some View {
        ZStack {
            panelBG.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().background(Color.white.opacity(0.08))
                switch phase {
                case .configure: configureView
                case .running:   runningView
                case .done:      resultsView
                }
            }

            if confirming { confirmationOverlay }
        }
        .frame(width: 560, height: 600)
        .task { await model.loadLookups() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Actions")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            Spacer()
            Button(phase == .done ? "Close" : "Cancel") { dismiss() }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.gray)
                .disabled(phase == .running)
        }
        .padding(20)
    }

    // MARK: - Configure

    private var configureView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    selectedCard

                    section("Jamf Pro", icon: "server.rack", color: .blue) {
                        toggleRow("Send Unmanage command",
                                  icon: "antenna.radiowaves.left.and.right.slash",
                                  iconColor: .orange, isOn: $unmanage)

                        toggleRow("Add to static group",
                                  icon: "rectangle.stack.badge.plus",
                                  iconColor: .blue, isOn: $addToGroup)
                        if addToGroup { groupPicker }

                        toggleRow("Move to site",
                                  icon: "building.2",
                                  iconColor: .teal, isOn: $moveToSite)
                        if moveToSite { sitePicker }
                    }

                    section("Cleanup", icon: "trash", color: .red) {
                        if model.settings.isProtectConfigured {
                            toggleRow("Delete from Jamf Protect",
                                      icon: "shield.slash", iconColor: .pink,
                                      isOn: $deleteFromProtect,
                                      disabled: autoProtectCleanup && deleteRecord)
                        }
                        toggleRow("Delete Jamf Pro record",
                                  icon: "trash", iconColor: .red,
                                  isOn: $deleteRecord, destructive: true)
                            .onChange(of: deleteRecord) { _, isOn in
                                if autoProtectCleanup && isOn { deleteFromProtect = true }
                            }

                        if autoProtectCleanup && deleteRecord {
                            footnote("Jamf Protect cleanup is automatic when deleting records (enabled in Settings).")
                        }
                        if deleteRecord {
                            footnote("Deleting a record does not unenroll the device. If it ever checks in again it will re-enroll as a new record.")
                        }
                    }
                }
                .padding(20)
            }

            // Bottom run bar
            VStack(spacing: 0) {
                Divider().background(Color.white.opacity(0.08))
                Button { confirming = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "bolt.fill").font(.system(size: 13))
                        Text("Run \(plan.summary.count) action\(plan.summary.count == 1 ? "" : "s") on \(model.selectedDevices.count) device\(model.selectedDevices.count == 1 ? "" : "s")")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(canRun
                                  ? AnyShapeStyle(LinearGradient(colors: [.blue, .blue.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                                  : AnyShapeStyle(Color.white.opacity(0.08)))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canRun)
                .padding(20)
            }
        }
    }

    private var selectedCard: some View {
        HStack {
            Text("Selected devices")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
            Spacer()
            Text("\(model.selectedDevices.count)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .monospacedDigit()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(cardBG))
    }

    private var groupPicker: some View {
        Picker("Static group", selection: $selectedGroupID) {
            Text("Choose…").tag(0)
            ForEach(model.staticGroups) { group in Text(group.name).tag(group.id) }
        }
        .pickerStyle(.menu)
        .tint(.blue)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(cardBG))
    }

    private var sitePicker: some View {
        Picker("Site", selection: $selectedSiteID) {
            Text("None").tag(-1)
            ForEach(model.sites) { site in Text(site.name).tag(site.intID) }
        }
        .pickerStyle(.menu)
        .tint(.teal)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(cardBG))
    }

    // MARK: - Running

    private var runningView: some View {
        VStack(spacing: 18) {
            Spacer()
            ProgressView(value: model.actionProgress)
                .progressViewStyle(.linear)
                .tint(.blue)
                .frame(maxWidth: 360)
            Text("Working… \(model.actionResults.count) operations finished")
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .monospacedDigit()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Results

    private var resultsView: some View {
        let failures = model.actionResults.filter { !$0.success }

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: failures.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(failures.isEmpty ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(failures.isEmpty ? "All actions completed" : "\(failures.count) operations failed")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        Text("\(model.actionResults.count) total operations")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    Spacer()
                }

                if !failures.isEmpty {
                    resultGroup("Failures", results: failures)
                }
                resultGroup("All results", results: model.actionResults)
            }
            .padding(20)
        }
    }

    private func resultGroup(_ title: String, results: [ActionResult]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.gray)
                .padding(.bottom, 8)
            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(result.success ? .green : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(result.deviceName) — \(result.action.rawValue)")
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                        if !result.success {
                            Text(result.message)
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
                if index < results.count - 1 {
                    Divider().background(Color.white.opacity(0.06))
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(cardBG))
    }

    // MARK: - Confirmation overlay (Helios prompt design)

    private var confirmationOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { confirming = false }

            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill((plan.isDestructive ? Color.red : Color.blue).opacity(0.15))
                            .frame(width: 56, height: 56)
                        Image(systemName: plan.isDestructive ? "exclamationmark.triangle.fill" : "bolt.fill")
                            .font(.system(size: 26))
                            .foregroundColor(plan.isDestructive ? .red : .blue)
                    }
                    Text("Run on \(model.selectedDevices.count) device\(model.selectedDevices.count == 1 ? "" : "s")?")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.top, 24)
                .padding(.bottom, 14)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(plan.summary, id: \.self) { line in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "circle.fill").font(.system(size: 4)).foregroundColor(.gray).padding(.top, 6)
                            Text(line).font(.system(size: 13)).foregroundColor(.gray)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

                Divider().background(Color.white.opacity(0.1))

                HStack(spacing: 0) {
                    Button { confirming = false } label: {
                        Text("Cancel")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 50)
                    }
                    .buttonStyle(.plain)

                    Divider().background(Color.white.opacity(0.1)).frame(height: 50)

                    Button {
                        confirming = false
                        phase = .running
                        Task {
                            await model.runActions(plan)
                            phase = .done
                        }
                    } label: {
                        Text(plan.isDestructive ? "Run Actions" : "Run")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(plan.isDestructive ? .red : .blue)
                            .frame(maxWidth: .infinity).frame(height: 50)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 360)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.14)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 30)
        }
    }

    // MARK: - Building blocks

    private func section<Content: View>(
        _ title: String, icon: String, color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
            content()
        }
    }

    private func toggleRow(
        _ title: String, icon: String, iconColor: Color,
        isOn: Binding<Bool>, destructive: Bool = false, disabled: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(iconColor)
                .frame(width: 22)
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(destructive ? .red : .white)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(destructive ? .red : .blue)
                .disabled(disabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(cardBG))
        .opacity(disabled ? 0.5 : 1)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(.gray)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }
}
