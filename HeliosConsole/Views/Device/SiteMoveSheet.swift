//
//  SiteMoveSheet.swift
//  HeliosConsole
//
//  The Move-to-Site flow for the `moveToSite` device action, presented from
//  the computer Device Details Actions menu. Changes which Jamf Pro site the
//  computer's record belongs to (PATCH computers-inventory-detail). Nothing
//  touches the running Mac — but site membership drives scoping, so
//  site-targeted policies, profiles and groups start or stop applying at the
//  device's next check-in.
//
//  Authorization model (identical to PreStageAssignmentSheet / ABMAssignmentSheet):
//  the host supplies policyProvider, a closure re-deriving the LIVE
//  DeviceActionPolicy. The sheet consults it at open AND again at execution,
//  so a role revocation or config hot-reload while the sheet sits open still
//  denies — nothing is frozen at presentation. The site picker is filtered by
//  the grant's allowedSites (with the reserved `all` literal), and the SAME
//  check is re-run at execute: the picker is UI, never the gate.
//
//  Sites are matched by ID, not name — a renamed site keeps its scope. The
//  picker always DISPLAYS the resolved site NAME; the id is only ever the
//  wire value. A grant whose allowedSites match no site that exists in Jamf
//  replaces the form with a fail-closed notice (the empty-scope case is
//  already hidden upstream by DeviceActionPolicy, so this covers the
//  narrower "every listed id was deleted in Jamf" race).
//
//  Audit model: onFinished fires for EVERY end state — success, thrown
//  errors, and in-sheet denials — so the host audit-logs executed and denied
//  writes alike.
//

import SwiftUI

struct SiteMoveSheet: View {
    /// Jamf INVENTORY id of the device being moved — Computer.id for a
    /// computer, MobileDevice.id for a mobile device (NOT the managementId
    /// either platform uses for MDM commands). Used only for the empty-guard
    /// and audit copy; the actual write goes through `performMove`, which the
    /// host binds to the right platform endpoint.
    let deviceID: String
    let deviceName: String
    let serialNumber: String
    /// The device's current site, read from the inventory record. Optional:
    /// a device may have no site ("None"/"Full Jamf Pro"), in which case the
    /// current-site row is hidden and any permitted site is a valid target.
    let currentSiteID: String?
    let currentSiteName: String?
    /// Header title — the host passes the override-aware ActionBranding.label
    /// so a profile displayName rename carries through.
    let title: String
    /// Re-derives the LIVE policy. Consulted at open and again at execute.
    /// The host binds this to the computer OR mobile-device policy, so the
    /// same sheet gates correctly on either platform's capability set.
    let policyProvider: () -> DeviceActionPolicy
    /// Performs the actual site move for the target site id. The host binds
    /// this to JamfSiteService.moveComputer or .moveMobileDevice — the sheet
    /// stays platform-agnostic and never names an endpoint itself.
    let performMove: (_ siteID: String) async throws -> Void
    /// Fires for EVERY end state (success, thrown error, in-sheet denial) so
    /// the host audit-logs all of them.
    let onFinished: (_ success: Bool, _ siteName: String?, _ detail: String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private enum Phase {
        case loading
        case ready
        case executing
        case finished(success: Bool, title: String, message: String)
        case unavailable(String)
    }

    @State private var phase: Phase = .loading
    @State private var permittedSites: [JamfSiteRecord] = []
    @State private var selectedSiteID: String?

    private var isDark: Bool { colorScheme == .dark }

    private var isExecuting: Bool {
        if case .executing = phase { return true }
        return false
    }

    private var normalizedSerial: String {
        serialNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// Move is a no-op (or disallowed) when nothing is chosen or the chosen
    /// site is the one the device is already in.
    private var canMove: Bool {
        guard let selectedSiteID, !isExecuting else { return false }
        return selectedSiteID != currentSiteID
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
        .frame(width: 480, height: 430)
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
                        LinearGradient(colors: [Color.indigo.opacity(0.2), Color.blue.opacity(0.2)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 40, height: 40)
                Image(systemName: "building.2")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(LinearGradient(colors: [.indigo, .blue],
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
            Text("Loading sites from Jamf Pro…")
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
            VStack(alignment: .leading, spacing: 6) {
                Text("CURRENT SITE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                    Text(currentSiteName ?? "None")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("MOVE TO SITE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Picker("", selection: $selectedSiteID) {
                    Text("Select a site…").tag(String?.none)
                    ForEach(permittedSites) { site in
                        // The current site is shown but reads as such, so the
                        // operator can see there is nowhere new to move to
                        // rather than the row simply being absent.
                        Text(pickerLabel(for: site))
                            .tag(String?.some(site.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(isExecuting)
            }

            // Single source of truth for the safety copy — never restated
            // here where it could drift from the action's message.
            Text(DeviceAction.moveToSite.message)
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
                    Task { await executeMove() }
                } label: {
                    if isExecuting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Move")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canMove)
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
            .frame(maxHeight: 130)

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }

    private func pickerLabel(for site: JamfSiteRecord) -> String {
        site.id == currentSiteID ? "\(site.name) (current)" : site.name
    }

    // MARK: Actions

    @MainActor
    private func prepare() async {
        let policy = policyProvider()
        guard policy.isAllowed(.moveToSite) else {
            phase = .unavailable("Your current role does not permit moving devices between sites.")
            onFinished(false, nil, "Denied by policy at sheet open")
            return
        }
        guard !deviceID.isEmpty else {
            phase = .unavailable("This device has no Jamf Pro record id — it cannot be moved.")
            onFinished(false, nil, "No device id")
            return
        }

        do {
            let all = try await JamfSiteService.shared.fetchSites()
            // canMoveDevice folds the `all` sentinel — never branch around it.
            let permitted = all.filter { policy.canMoveDevice(toSiteID: $0.id) }
            guard !permitted.isEmpty else {
                phase = .unavailable(all.isEmpty
                    ? "No sites exist in Jamf Pro yet — there is nowhere to move this device."
                    : "Your role permits no sites that exist in Jamf Pro. Ask an administrator to check allowedSites on your role in the access profile.")
                onFinished(false, nil, "No permitted site exists in Jamf")
                return
            }
            permittedSites = permitted

            // Preselect the sole target only when it is an actual MOVE — if the
            // one permitted site IS the current site there is nothing to do, so
            // leave the picker unselected (Move stays disabled).
            if permitted.count == 1, permitted[0].id != currentSiteID {
                selectedSiteID = permitted[0].id
            }
            phase = .ready
        } catch {
            phase = .unavailable("Could not load sites from Jamf Pro: \(error.localizedDescription)")
            onFinished(false, nil, "Site load failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func executeMove() async {
        guard let siteID = selectedSiteID,
              let site = permittedSites.first(where: { $0.id == siteID }) else { return }

        // Re-derive the LIVE policy — a revocation or config change while the
        // sheet sat open must deny here, whatever the picker shows.
        let policy = policyProvider()
        guard policy.isAllowed(.moveToSite) else {
            phase = .finished(success: false, title: "Not Permitted",
                              message: "Your current role no longer permits moving devices between sites.")
            onFinished(false, site.name, "Denied by policy at execution")
            return
        }
        guard policy.canMoveDevice(toSiteID: site.id) else {
            phase = .finished(success: false, title: "Not Permitted",
                              message: "Your role's grant does not permit the site \"\(site.name)\".")
            onFinished(false, site.name, "Denied by allowedSites for site id \(site.id) (\"\(site.name)\")")
            return
        }

        phase = .executing

        do {
            try await performMove(site.id)
            let fromClause = currentSiteName.map { "from \($0) " } ?? ""
            phase = .finished(
                success: true,
                title: "Moved to \(site.name)",
                message: "The device's record was moved \(fromClause)to \(site.name). Site-scoped policies, profiles and group memberships take effect at the device's next check-in.")
            onFinished(true, site.name,
                       "Moved to site \"\(site.name)\" (id \(site.id))\(currentSiteName.map { " from \"\($0)\"" } ?? "")")
        } catch {
            phase = .finished(success: false, title: "Move Failed",
                              message: error.localizedDescription)
            onFinished(false, site.name, error.localizedDescription)
        }
    }
}
