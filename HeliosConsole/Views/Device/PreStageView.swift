//
//  PreStageView.swift
//  HeliosConsole
//
//  Pre-Stage registration tab — the single-device flow from
//  Device_Enrollment_Prep.sh as a form: asset tag + serial + PreStage in,
//  then a two-step run (Inventory Preload upsert → PreStage scope assign)
//  with per-step progress. Nothing touches a running Mac: both writes only
//  take effect at the device's next Automated Device Enrollment.
//
//  The PreStage picker is FILTERED by the signed-in user's role
//  capabilities (allowedPrestages / the reserved "all" literal), and the
//  same check is re-run at execution time — the picker is UI, never the
//  gate. A role granting no PreStages replaces the form with a notice
//  (fail-closed, like ABMLookupView's not-configured state). Every
//  attempt — success, failure, or denial — is written to the action log.
//
//  Serials are normalized (trimmed, uppercased) before any Jamf call;
//  JamfPreStageService normalizes again on its side, so the value shown
//  in the UI and the value sent to Jamf can never disagree.
//

import SwiftUI

// MARK: - Step State

/// One row of the two-step progress list.
private enum PreStageStepState {
    case pending
    case running
    case success
    case failure
    /// Step never ran because an earlier step failed.
    case skipped
    /// Step failed in the informative, self-healing way (serial not yet
    /// synced from ABM) — orange, not red.
    case warning
}

// MARK: - Pre-Stage View

struct PreStageView: View {
    /// Observed so the PreStage picker re-filters (and the fail-closed
    /// notice appears/disappears) the moment a role change lands.
    @ObservedObject private var session = UserSession.shared

    // MARK: Form State

    @State private var assetTag = ""
    @State private var serialNumber = ""
    @State private var selectedPreStage: JamfPreStage?

    @FocusState private var isAssetTagFocused: Bool
    @FocusState private var isSerialFocused: Bool

    // MARK: PreStage List State

    @State private var allPreStages: [JamfPreStage] = []
    @State private var isLoadingPreStages = false
    @State private var preStageLoadError: String?
    /// True once fetchPreStages() has completed successfully — the empty
    /// filtered list only means "role grants nothing" AFTER a real load.
    @State private var hasLoadedPreStages = false

    // MARK: Execution State

    @State private var isExecuting = false
    @State private var showProgress = false
    @State private var preloadStepState: PreStageStepState = .pending
    @State private var assignStepState: PreStageStepState = .pending
    /// Fatal outcome message (red card).
    @State private var flowError: String?
    /// serialNotEligible outcome message (orange card — informative, the
    /// preload record WAS saved and a retry after Jamf's sync will work).
    @State private var flowWarning: String?
    /// The PreStage name the CURRENT/most recent run used — the progress
    /// card renders this, never the live picker selection, so changing the
    /// picker after a run cannot relabel its steps.
    @State private var executedPreStageName: String?
    /// Set only on full success — drives the green summary card.
    @State private var completedSummary: RegistrationSummary?

    private struct RegistrationSummary {
        let assetTag: String
        let serialNumber: String
        let preStageName: String
    }

    // MARK: - Derived Data

    /// The PreStages this user's roles permit. Recomputed on every body
    /// evaluation, so a capabilities change (observed via `session`)
    /// re-filters without a reload.
    private var filteredPreStages: [JamfPreStage] {
        allPreStages.filter { session.capabilities.canUsePrestage(named: $0.displayName) }
    }

    private var trimmedAssetTag: String {
        assetTag.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedSerial: String {
        serialNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// All three inputs present AND the selection still permitted — a role
    /// change can invalidate a selection that is already made, and the
    /// button must go dark the moment it does.
    private var isFormValid: Bool {
        guard !trimmedAssetTag.isEmpty, !normalizedSerial.isEmpty,
              let prestage = selectedPreStage else { return false }
        return session.capabilities.canUsePrestage(named: prestage.displayName)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Animated background matching app design
            AnimatedBackgroundView(animate: .constant(true))

            VStack(spacing: 0) {
                headerSection

                ScrollView {
                    VStack(spacing: 20) {
                        infoBanner

                        if isLoadingPreStages && !hasLoadedPreStages {
                            loadingCard
                        } else if let error = preStageLoadError, !hasLoadedPreStages {
                            errorCard(error: error)
                        } else if hasLoadedPreStages && filteredPreStages.isEmpty {
                            noPreStagesNotice
                        } else if hasLoadedPreStages {
                            formCard

                            if showProgress {
                                progressCard
                            }

                            if let summary = completedSummary {
                                successCard(summary)
                            } else if let warning = flowWarning {
                                warningCard(warning)
                            } else if let error = flowError {
                                failureCard(error)
                            }
                        }
                    }
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .padding(32)
                }
            }
        }
        .task {
            // First entry only — Try Again drives subsequent loads.
            if !hasLoadedPreStages && !isLoadingPreStages {
                await loadPreStages()
            }
        }
    }

    // MARK: - Data Loading

    /// Fetches the PreStage list. Filtering happens in `filteredPreStages`
    /// (not here) so a role change never requires a refetch.
    @MainActor
    private func loadPreStages() async {
        // Reentrancy guard: Try Again can be clicked while a fetch is
        // already in flight — never stack a second one.
        guard !isLoadingPreStages else { return }

        isLoadingPreStages = true
        preStageLoadError = nil

        do {
            allPreStages = try await JamfPreStageService.shared.fetchPreStages()
            hasLoadedPreStages = true
        } catch {
            preStageLoadError = error.localizedDescription
        }

        isLoadingPreStages = false
    }

    // MARK: - Registration Flow

    /// The two-step flow: Inventory Preload upsert, then PreStage scope
    /// assign. Step 1 failure stops the flow (step 2 is skipped — no
    /// PreStage change without its asset tag on record). Step 2 re-checks
    /// the role capability at execution time: the picker filtered the
    /// list, but the picker is never trusted. Every path audit-logs.
    @MainActor
    private func register() async {
        // Reentrancy guard: the button disables on isExecuting, but a
        // queued double-activation must still be a no-op.
        guard !isExecuting else { return }
        guard let prestage = selectedPreStage else { return }

        let serial = normalizedSerial
        let tag = trimmedAssetTag
        guard !serial.isEmpty, !tag.isEmpty else { return }

        // Reflect the normalization in the field so what the operator
        // sees is exactly what was sent.
        serialNumber = serial

        isExecuting = true
        defer { isExecuting = false }

        // Defense in depth FIRST — before ANY Jamf write. The filtered
        // picker is UI; this is the gate, and a denied attempt must not
        // leave a preload record behind.
        guard session.capabilities.canUsePrestage(named: prestage.displayName) else {
            showProgress = false
            flowError = "Your role does not permit assigning PreStage \"\(prestage.displayName)\". Nothing was changed."
            logAttempt(serial: serial, success: false,
                       error: "Denied by role capabilities: PreStage \"\(prestage.displayName)\" is not in allowedPrestages")
            return
        }

        // Freeze the names this run displays/logs — the picker stays live
        // behind the progress card and must not relabel a finished run.
        executedPreStageName = prestage.displayName

        showProgress = true
        preloadStepState = .running
        assignStepState = .pending
        flowError = nil
        flowWarning = nil
        completedSummary = nil

        // Step 1 — Inventory Preload upsert (asset tag on record first).
        do {
            try await JamfPreStageService.shared.upsertInventoryPreload(serial: serial, assetTag: tag)
            preloadStepState = .success
        } catch {
            preloadStepState = .failure
            assignStepState = .skipped
            flowError = "Saving the Inventory Preload record failed: \(error.localizedDescription)"
            logAttempt(serial: serial, success: false,
                       error: "Inventory Preload upsert failed: \(error.localizedDescription)")
            return
        }

        do {
            try await JamfPreStageService.shared.assign(serial: serial, toPreStage: prestage.id)
            assignStepState = .success
            completedSummary = RegistrationSummary(
                assetTag: tag,
                serialNumber: serial,
                preStageName: prestage.displayName
            )
            logAttempt(serial: serial, success: true,
                       error: "Assigned PreStage \"\(prestage.displayName)\" • asset tag \(tag)")
        } catch let error as PreStageError {
            if case .serialNotEligible = error {
                // Informative, not fatal: Jamf's ~2-minute ADE sync has not
                // picked the serial up yet. The service's message explains;
                // show it verbatim. The preload record from step 1 stands.
                assignStepState = .warning
                flowWarning = error.errorDescription
                    ?? "Jamf Pro does not yet recognize serial \(serial) as an ADE device."
                logAttempt(serial: serial, success: false, error: error.errorDescription)
            } else {
                assignStepState = .failure
                flowError = error.errorDescription ?? "PreStage assignment failed."
                logAttempt(serial: serial, success: false, error: error.errorDescription)
            }
        } catch {
            assignStepState = .failure
            flowError = error.localizedDescription
            logAttempt(serial: serial, success: false, error: error.localizedDescription)
        }
    }

    /// Resets the form for the next device. The PreStage list itself is
    /// kept — only inputs and outcome state clear.
    private func clearForm() {
        assetTag = ""
        serialNumber = ""
        selectedPreStage = nil
        showProgress = false
        preloadStepState = .pending
        assignStepState = .pending
        flowError = nil
        flowWarning = nil
        completedSummary = nil
        executedPreStageName = nil
    }

    private func logAttempt(serial: String, success: Bool, error: String?) {
        ActionLogService.shared.logAction(
            actionName: "PreStage Registration",
            actionCategory: "Pre-Stage",
            deviceName: serial,
            deviceSerialNumber: serial,
            deviceId: serial,
            success: success,
            errorMessage: error
        )
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 20) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.2), Color.indigo.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)

                    Image(systemName: "shippingbox")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .indigo],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Pre-Stage")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)

                    Text("Register devices for their next Automated Device Enrollment")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .background(Color.black.opacity(0.3))
    }

    // MARK: - Info Banner

    private var infoBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(
                    LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
                )

            Text("Nothing changes on any Mac now — the asset tag and PreStage apply at the device's next ADE (re-)enrollment. Asset tags are saved to Jamf Inventory Preload; serials are stored uppercase.")
                .font(.system(size: 13))
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Form Card

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Asset Tag
            VStack(alignment: .leading, spacing: 6) {
                Text("Asset Tag")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))

                TextField("", text: $assetTag, prompt: Text("e.g. SH123456")
                    .foregroundColor(.gray.opacity(0.6)))
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .focused($isAssetTagFocused)
                    .disabled(isExecuting)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isAssetTagFocused ? Color.purple.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                    )
            }

            // Serial Number
            VStack(alignment: .leading, spacing: 6) {
                Text("Serial Number")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))

                TextField("", text: $serialNumber, prompt: Text("e.g. C02XXXXXXXXX")
                    .foregroundColor(.gray.opacity(0.6)))
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.white)
                    .focused($isSerialFocused)
                    .disabled(isExecuting)
                    .onSubmit {
                        // Normalize in place so the operator sees exactly
                        // what will be sent (register() normalizes again).
                        serialNumber = normalizedSerial
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSerialFocused ? Color.purple.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                    )
            }

            // PreStage picker
            VStack(alignment: .leading, spacing: 6) {
                Text("PreStage")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))

                preStageMenu
            }

            // Register button
            HStack {
                Spacer()

                Button {
                    Task { await register() }
                } label: {
                    HStack(spacing: 8) {
                        if isExecuting {
                            ProgressView()
                                .scaleEffect(0.6)
                        } else {
                            Image(systemName: "shippingbox.and.arrow.backward")
                        }
                        Text(isExecuting ? "Registering..." : "Register")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(!isFormValid || isExecuting)
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var preStageMenu: some View {
        Menu {
            ForEach(filteredPreStages) { prestage in
                Button {
                    selectedPreStage = prestage
                } label: {
                    if selectedPreStage?.id == prestage.id {
                        Label(prestage.displayName, systemImage: "checkmark")
                    } else {
                        Text(prestage.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 12, weight: .medium))
                Text(selectedPreStage?.displayName ?? "Select a PreStage")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(selectedPreStage != nil ? .white : .white.opacity(0.7))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.05))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(isExecuting)
    }

    // MARK: - Progress Card

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Registration Progress")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()
                .background(Color.white.opacity(0.1))

            VStack(spacing: 0) {
                stepRow(
                    title: "Saving Inventory Preload record",
                    subtitle: nil,
                    state: preloadStepState
                )

                Divider()
                    .background(Color.white.opacity(0.06))

                stepRow(
                    title: "Assigning PreStage \(executedPreStageName ?? "")",
                    subtitle: assignStepState == .skipped ? "No PreStage change was made" : nil,
                    state: assignStepState
                )
            }
        }
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func stepRow(title: String, subtitle: String?, state: PreStageStepState) -> some View {
        HStack(spacing: 12) {
            stepIcon(for: state)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(state == .pending || state == .skipped ? .gray : .white)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.gray.opacity(0.8))
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func stepIcon(for state: PreStageStepState) -> some View {
        switch state {
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.gray.opacity(0.5))
        case .running:
            ProgressView()
                .scaleEffect(0.55)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.green)
        case .failure:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.red)
        case .skipped:
            Image(systemName: "minus.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.gray.opacity(0.5))
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.orange)
        }
    }

    // MARK: - Outcome Cards

    private func successCard(_ summary: RegistrationSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.green)

                Text("Device Registered")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(spacing: 8) {
                summaryRow(label: "Asset Tag", value: summary.assetTag)
                summaryRow(label: "Serial Number", value: summary.serialNumber, monospaced: true)
                summaryRow(label: "PreStage", value: summary.preStageName)
            }

            Text("Both changes take effect at the device's next Automated Device Enrollment.")
                .font(.system(size: 12))
                .foregroundColor(.gray)

            Button {
                clearForm()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle")
                    Text("Register Another")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.3))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }

    private func summaryRow(label: String, value: String, monospaced: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.gray)

            Spacer()

            Text(value)
                .font(.system(size: 13, weight: .medium, design: monospaced ? .monospaced : .default))
                .foregroundColor(.white)
                .textSelection(.enabled)
        }
    }

    /// serialNotEligible outcome — informative, not fatal. The service's
    /// message (shown verbatim) explains Jamf's ~2-minute ADE sync; the
    /// operator retries the same form once it has run.
    private func warningCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.orange)

                Text("PreStage Not Assigned Yet")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }

            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.orange)
                .fixedSize(horizontal: false, vertical: true)

            Text("The Inventory Preload record with the asset tag was saved. Once Jamf's sync has run, click Register again to complete the PreStage assignment.")
                .font(.system(size: 12))
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    private func failureCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.red)

                Text("Registration Failed")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }

            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Loading / Error / Fail-Closed States

    private var loadingCard: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading PreStages from Jamf Pro...")
                .font(.system(size: 14))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func errorCard(error: String) -> some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.red)
            }

            VStack(spacing: 8) {
                Text("Unable to Load PreStages")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)

                Text(error)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 450)
            }

            Button {
                Task {
                    await loadPreStages()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Try Again")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.purple)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(isLoadingPreStages)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    /// Fail-closed: the load succeeded but the role's allowedPrestages
    /// permits none of them (or is absent). No form — mirroring
    /// ABMLookupView's not-configured notice.
    private var noPreStagesNotice: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "shippingbox")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundColor(.purple.opacity(0.6))
            }

            VStack(spacing: 12) {
                Text("No PreStages Available")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)

                Text(allPreStages.isEmpty
                     ? "No computer PreStage enrollments exist in Jamf Pro yet — there is nothing to register devices into."
                     : "Your role does not grant any PreStages. Ask an administrator to add allowedPrestages to your role in the access profile.")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Pre-Stage") {
    PreStageView()
        .frame(width: 1200, height: 800)
}
#endif
