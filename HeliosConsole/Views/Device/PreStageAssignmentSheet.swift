//
//  PreStageAssignmentSheet.swift
//  HeliosConsole
//
//  The Assign-to-PreStage flow for the `assignPreStage` device action,
//  presented from the computer Device Details Actions menu. Registers the
//  device's serial to a Jamf Pro Computer PreStage Enrollment (and, when an
//  asset tag is entered, upserts an Inventory Preload record first). Nothing
//  touches a running Mac — both writes take effect at the device's next
//  Automated Device Enrollment.
//
//  Authorization model (identical to ABMAssignmentSheet): the host supplies
//  policyProvider, a closure that re-derives the LIVE DeviceActionPolicy. The
//  sheet consults it at open AND again at execution, so a role revocation or
//  config hot-reload while the sheet sits open still denies — nothing is
//  frozen at presentation. The PreStage picker is filtered by the grant's
//  allowedPrestages (with the reserved `all` literal), and the SAME check is
//  re-run at execute: the picker is UI, never the gate. A grant that permits
//  no PreStages that exist in Jamf replaces the form with a fail-closed
//  notice.
//
//  Audit model: onFinished fires for EVERY end state — success, the
//  informative not-yet-eligible outcome, thrown errors, and in-sheet
//  denials — so the host audit-logs executed and denied writes alike.
//
//  This is the COMPUTER-only flow: JamfPreStageService targets
//  /api/v3/computer-prestages and Inventory Preload deviceType "Computer".
//  Mobile-device PreStage support (a different Jamf API) is a follow-up.
//

import SwiftUI

struct PreStageAssignmentSheet: View {
    let serialNumber: String
    let deviceName: String
    /// Header title — the host passes the override-aware
    /// ActionBranding.label so a profile displayName rename carries through.
    let title: String
    /// Re-derives the LIVE policy. Consulted at open and again at execute.
    let policyProvider: () -> DeviceActionPolicy
    /// Fires for EVERY end state (success, not-yet-eligible, thrown error,
    /// in-sheet denial) so the host audit-logs all of them.
    let onFinished: (_ success: Bool, _ preStageName: String?, _ detail: String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private enum Phase {
        case loading
        case ready
        case executing
        /// success drives the green icon; the informative not-yet-eligible
        /// outcome sets success == false but is not a hard failure.
        case finished(success: Bool, title: String, message: String)
        case unavailable(String)
    }

    @State private var phase: Phase = .loading
    @State private var permittedPreStages: [JamfPreStage] = []
    @State private var selectedPreStageId: String?
    /// The serial's current PreStage displayName, resolved best-effort at
    /// open (a lookup failure just hides the row — never blocks the form).
    @State private var currentPreStageName: String?
    @State private var assetTag = ""

    private var isDark: Bool { colorScheme == .dark }

    private var isExecuting: Bool {
        if case .executing = phase { return true }
        return false
    }

    private var normalizedSerial: String {
        serialNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider().overlay(Color.primary.opacity(0.1))

            Group {
                switch phase {
                case .loading:
                    loadingBody
                case .unavailable(let message):
                    unavailableBody(message)
                case .ready, .executing:
                    formBody
                case .finished(let success, let title, let message):
                    finishedBody(success: success, title: title, message: message)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 480, height: 470)
        .background(isDark ? Color(red: 0.08, green: 0.08, blue: 0.1) : Color(white: 0.97))
        .interactiveDismissDisabled(isExecuting)
        .task { await prepare() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(colors: [Color.purple.opacity(0.2), Color.indigo.opacity(0.2)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 40, height: 40)
                Image(systemName: "shippingbox")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(LinearGradient(colors: [.purple, .indigo],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                Text("\(deviceName) • \(normalizedSerial)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isExecuting)
        }
        .padding(16)
    }

    // MARK: Phases

    private var loadingBody: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Loading PreStages from Jamf Pro…")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
    }

    private func unavailableBody(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundColor(.orange)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("Close") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding(24)
    }

    private var formBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let currentPreStageName {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CURRENT PRESTAGE")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text(currentPreStageName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("ASSIGN TO PRESTAGE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Picker("", selection: $selectedPreStageId) {
                    Text("Select a PreStage…").tag(String?.none)
                    ForEach(permittedPreStages) { prestage in
                        Text(prestage.displayName).tag(String?.some(prestage.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(isExecuting)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("ASSET TAG (OPTIONAL)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                TextField("Leave blank to assign the PreStage only", text: $assetTag)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .disabled(isExecuting)
                Text("When set, an Inventory Preload record is saved with this asset tag before the PreStage is assigned.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            if let selectedPreStageId,
               let current = currentPreStageName,
               let selected = permittedPreStages.first(where: { $0.id == selectedPreStageId }),
               selected.displayName != current {
                Label("The device is currently in \(current) — assigning will move it.",
                      systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
            }

            // Single source of truth for the safety copy — never restated
            // here where it could drift from the action's message.
            Text(DeviceAction.assignPreStage.message)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .disabled(isExecuting)
                Button {
                    Task { await executeAssign() }
                } label: {
                    if isExecuting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Assign")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedPreStageId == nil || isExecuting)
            }
        }
        .padding(20)
    }

    private func finishedBody(success: Bool, title: String, message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 38))
                .foregroundColor(success ? .green : .orange)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
            ScrollView {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxHeight: 150)

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }

    // MARK: Actions

    @MainActor
    private func prepare() async {
        let policy = policyProvider()
        guard policy.isAllowed(.assignPreStage) else {
            phase = .unavailable("Your current role does not permit assigning devices to a PreStage.")
            onFinished(false, nil, "Denied by policy at sheet open")
            return
        }
        guard !normalizedSerial.isEmpty else {
            phase = .unavailable("This device has no serial number to register in a PreStage.")
            onFinished(false, nil, "No serial number")
            return
        }

        do {
            let all = try await JamfPreStageService.shared.fetchPreStages()
            // canUsePrestage folds the `all` sentinel — never branch around it.
            let permitted = all.filter { policy.canUsePrestage(named: $0.displayName) }
            guard !permitted.isEmpty else {
                phase = .unavailable(all.isEmpty
                    ? "No computer PreStage enrollments exist in Jamf Pro yet — there is nothing to assign."
                    : "Your role permits no PreStages that exist in Jamf Pro. Ask an administrator to add allowedPrestages to your role in the access profile.")
                return
            }
            permittedPreStages = permitted

            // Best-effort current-PreStage lookup — a failure just hides the
            // row, it must never block the form or fail the sheet.
            if let currentId = try? await JamfPreStageService.shared.currentPreStageId(forSerial: normalizedSerial) {
                currentPreStageName = all.first(where: { $0.id == currentId })?.displayName
            }

            if permitted.count == 1 { selectedPreStageId = permitted[0].id }
            phase = .ready
        } catch {
            phase = .unavailable("Could not load PreStages from Jamf Pro: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func executeAssign() async {
        guard let prestageId = selectedPreStageId,
              let prestage = permittedPreStages.first(where: { $0.id == prestageId }) else { return }

        // Re-derive the LIVE policy — a revocation or config change while the
        // sheet sat open must deny here, whatever the picker shows.
        let policy = policyProvider()
        guard policy.isAllowed(.assignPreStage) else {
            phase = .finished(success: false, title: "Not Permitted",
                              message: "Your current role no longer permits assigning devices to a PreStage.")
            onFinished(false, prestage.displayName, "Denied by policy at execution")
            return
        }
        guard policy.canUsePrestage(named: prestage.displayName) else {
            phase = .finished(success: false, title: "Not Permitted",
                              message: "Your role's grant does not permit PreStage \"\(prestage.displayName)\".")
            onFinished(false, prestage.displayName, "Denied by allowedPrestages for PreStage \"\(prestage.displayName)\"")
            return
        }

        let serial = normalizedSerial
        let tag = assetTag.trimmingCharacters(in: .whitespacesAndNewlines)
        // Reflect the trimmed value so what the operator sees is what was
        // sent (and a post-failure retry re-uses the clean value).
        assetTag = tag

        phase = .executing

        // A failure AFTER the preload upsert must disclose the write that
        // already happened — a durable record misreported as a no-op is an
        // audit violation.
        var preloadSaved = false
        func preloadNote() -> String {
            preloadSaved ? " Note: the Inventory Preload record (asset tag \(tag)) WAS saved." : ""
        }

        do {
            if !tag.isEmpty {
                try await JamfPreStageService.shared.upsertInventoryPreload(serial: serial, assetTag: tag)
                preloadSaved = true
            }
            try await JamfPreStageService.shared.assign(serial: serial, toPreStage: prestage.id)
            phase = .finished(
                success: true,
                title: "Assigned to \(prestage.displayName)",
                message: "The PreStage\(tag.isEmpty ? "" : " and asset tag \(tag)") take\(tag.isEmpty ? "s" : "") effect at the device's next Automated Device Enrollment.")
            onFinished(true, prestage.displayName,
                       "Assigned PreStage \"\(prestage.displayName)\"\(tag.isEmpty ? "" : " • asset tag \(tag)")")
        } catch let error as PreStageError {
            if case .serialNotEligible = error {
                // Informative, not a hard failure: Jamf does not consider the
                // serial a valid ADE device (e.g. manually enrolled, or an
                // ABM assignment Jamf's ~2-minute sync hasn't picked up).
                phase = .finished(
                    success: false,
                    title: "PreStage Not Assigned",
                    message: (error.errorDescription ?? "Jamf Pro does not recognize this serial as an Automated Device Enrollment device.") + preloadNote())
                onFinished(false, prestage.displayName, (error.errorDescription ?? "serialNotEligible") + preloadNote())
            } else {
                phase = .finished(success: false, title: "Assignment Failed",
                                  message: (error.errorDescription ?? "PreStage assignment failed.") + preloadNote())
                onFinished(false, prestage.displayName, (error.errorDescription ?? "PreStage assignment failed.") + preloadNote())
            }
        } catch {
            phase = .finished(success: false, title: "Assignment Failed",
                              message: error.localizedDescription + preloadNote())
            onFinished(false, prestage.displayName, error.localizedDescription + preloadNote())
        }
    }
}
