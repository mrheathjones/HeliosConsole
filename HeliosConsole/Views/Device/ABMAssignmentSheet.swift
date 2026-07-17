//
//  ABMAssignmentSheet.swift
//  HeliosConsole
//
//  The shared Apple Business Manager assign flow, presented from Device
//  Details (abmAssign device action) and the ABM Lookup tab.
//
//  Authorization model: the host supplies policyProvider, a closure that
//  re-derives the LIVE DeviceActionPolicy — the sheet consults it at open
//  AND again at execution, so a role revocation or config hot-reload while
//  the sheet sits open still denies (nothing is frozen at presentation).
//  Server-level scoping (options.allowedMdmServers, with the reserved
//  `all` literal) is likewise re-read from the live policy at execution.
//
//  Audit model: onFinished fires for EVERY end state — success, Apple-side
//  errors, timeouts, thrown errors, and in-sheet denials — so the host can
//  audit-log executed and denied mutations alike.
//
//  Unassign has no picker, so it stays a confirm-dialog flow in the host
//  views — the shared resolve/execute pieces live in ABMAssignmentExecutor
//  so the two hosts can't drift apart.
//

import SwiftUI

// MARK: - Shared resolve/execute helpers

enum ABMAssignmentExecutor {

    enum ExecutorError: LocalizedError {
        case missingSerial
        case deviceNotInABM(String)
        case notAssigned
        case serverListUnavailable

        var errorDescription: String? {
            switch self {
            case .missingSerial:
                return "This device has no serial number to look up in Apple Business Manager."
            case .deviceNotInABM(let serial):
                return "Serial \(serial) was not found in Apple Business Manager."
            case .notAssigned:
                return "The device is not assigned to any MDM server in Apple Business Manager."
            case .serverListUnavailable:
                return "The MDM server list could not be loaded from Apple Business Manager."
            }
        }
    }

    /// Cache-first ABM device resolution — safe for identity (id/serial
    /// never change between sweeps); assignment state is NOT taken from
    /// this, see currentServer.
    @MainActor
    static func resolveDevice(serial: String) async throws -> ABMOrgDevice {
        let trimmed = serial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ExecutorError.missingSerial }

        if let cached = ABMDeviceCache.shared.device(forSerial: trimmed) {
            return cached
        }
        guard let device = try await ABMAPIService.shared.findOrgDevice(serialNumber: trimmed) else {
            throw ExecutorError.deviceNotInABM(trimmed.uppercased())
        }
        return device
    }

    /// The device's CURRENT MDM server — always resolved live from the
    /// relationships endpoint, never from the last sweep's snapshot: this
    /// value authorizes unassignment (allowedMdmServers is checked against
    /// it) and is the id the mutation submits, so staleness is not an
    /// option. The server LIST is cache-first but refreshed live once if
    /// the assigned id isn't in it (server created after the sweep).
    @MainActor
    static func currentServer(
        for device: ABMOrgDevice,
        servers: [ABMMdmServer]
    ) async throws -> ABMMdmServer? {
        guard let serverId = try await ABMAPIService.shared.fetchAssignedServerId(deviceId: device.id) else {
            return nil
        }
        if let match = servers.first(where: { $0.id == serverId }) {
            return match
        }
        let fresh = try await ABMAPIService.shared.fetchMdmServers()
        if let match = fresh.first(where: { $0.id == serverId }) {
            return match
        }
        // Unknown server: name-based grants can never match it (deny,
        // fail-closed); only an `all` grant may act on it.
        return ABMMdmServer(id: serverId, serverName: serverId, serverType: nil,
                            createdDateTime: nil, updatedDateTime: nil)
    }

    /// Cache-first MDM server list.
    @MainActor
    static func loadServers() async throws -> [ABMMdmServer] {
        let cached = ABMDeviceCache.shared.mdmServers
        if !cached.isEmpty { return cached }
        return try await ABMAPIService.shared.fetchMdmServers()
    }
}

// MARK: - Assign Sheet

struct ABMAssignmentSheet: View {
    let serialNumber: String
    let deviceName: String
    /// Header title — hosts pass the override-aware policy.menuLabel so a
    /// profile displayName rename carries through.
    let title: String
    /// Re-derives the LIVE policy. Consulted at open and again at execute.
    let policyProvider: () -> DeviceActionPolicy
    /// Fires for EVERY end state (success, Apple errors, timeout, thrown
    /// error, in-sheet denial) so the host audit-logs all of them.
    let onFinished: (_ success: Bool, _ server: ABMMdmServer?, _ error: String?) -> Void

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
    @State private var device: ABMOrgDevice?
    @State private var currentServer: ABMMdmServer?
    @State private var permittedServers: [ABMMdmServer] = []
    @State private var selectedServerId: String?

    private var isDark: Bool { colorScheme == .dark }

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
                        LinearGradient(colors: [Color.blue.opacity(0.2), Color.cyan.opacity(0.2)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 40, height: 40)
                Image(systemName: "externaldrive.badge.plus")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(LinearGradient(colors: [.blue, .cyan],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                Text("\(deviceName) • \(serialNumber.uppercased())")
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
            Text("Looking up the device in Apple Business Manager…")
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
                Text("CURRENT ASSIGNMENT")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    Circle()
                        .fill(currentServer == nil ? Color.orange : Color.green)
                        .frame(width: 8, height: 8)
                    Text(currentServer?.serverName ?? "Not assigned to any MDM server")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("ASSIGN TO")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Picker("", selection: $selectedServerId) {
                    Text("Select an MDM server…").tag(String?.none)
                    ForEach(permittedServers) { server in
                        Text(server.serverName).tag(String?.some(server.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            if let selectedServerId,
               let current = currentServer,
               selectedServerId != current.id {
                Label("The device is currently assigned to \(current.serverName) — assigning will move it.",
                      systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
            }

            // Single source of truth for the safety copy — never restated
            // here where it could drift from the confirmation-dialog text.
            Text(DeviceAction.abmAssign.message)
                .font(.system(size: 11))
                .foregroundColor(.secondary)

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
                        Text(assignButtonTitle)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedServerId == nil || isExecuting || selectedServerId == currentServer?.id)
            }
        }
        .padding(20)
    }

    private func finishedBody(success: Bool, title: String, message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .font(.system(size: 38))
                .foregroundColor(success ? .green : .red)
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

    private var isExecuting: Bool {
        if case .executing = phase { return true }
        return false
    }

    private var assignButtonTitle: String {
        if let current = currentServer, selectedServerId != nil, selectedServerId != current.id {
            return "Reassign"
        }
        return "Assign"
    }

    // MARK: Actions

    @MainActor
    private func prepare() async {
        let policy = policyProvider()
        guard policy.isAllowed(.abmAssign) else {
            phase = .unavailable("Your current role does not permit assigning devices to an MDM server.")
            onFinished(false, nil, "Denied by policy at sheet open")
            return
        }
        let options = policy.options(for: .abmAssign)

        do {
            let resolved = try await ABMAssignmentExecutor.resolveDevice(serial: serialNumber)
            let servers = try await ABMAssignmentExecutor.loadServers()
            let current = try await ABMAssignmentExecutor.currentServer(for: resolved, servers: servers)

            let permitted = options.allowsAllMdmServers
                ? servers
                : servers.filter { options.permitsMdmServer(named: $0.serverName) }

            guard !permitted.isEmpty else {
                phase = .unavailable("Your role's abmAssign grant lists no MDM servers that exist in this ABM tenant — there is nothing to assign to. Ask an administrator to update the profile's allowedMdmServers.")
                return
            }

            if permitted.count == 1, let current, permitted[0].id == current.id {
                phase = .unavailable("The device is already assigned to \(current.serverName), the only MDM server your grant permits — there is nothing to change.")
                return
            }

            device = resolved
            currentServer = current
            permittedServers = permitted
            if permitted.count == 1, permitted[0].id != current?.id {
                selectedServerId = permitted[0].id
            }
            phase = .ready
        } catch {
            phase = .unavailable(error.localizedDescription)
        }
    }

    @MainActor
    private func executeAssign() async {
        guard let device,
              let serverId = selectedServerId,
              let server = permittedServers.first(where: { $0.id == serverId }) else { return }

        // Re-derive the LIVE policy — a revocation or config change while
        // the sheet sat open must deny here, whatever the picker shows.
        let policy = policyProvider()
        guard policy.isAllowed(.abmAssign) else {
            phase = .finished(success: false, title: "Not Permitted",
                              message: "Your current role no longer permits assigning devices to an MDM server.")
            onFinished(false, server, "Denied by policy at execution")
            return
        }
        guard policy.options(for: .abmAssign).permitsMdmServer(named: server.serverName) else {
            phase = .finished(success: false, title: "Not Permitted",
                              message: "Your role's grant does not permit assigning to \(server.serverName).")
            onFinished(false, server, "Denied by allowedMdmServers for server \(server.serverName)")
            return
        }

        phase = .executing
        do {
            let outcome = try await ABMAPIService.shared.performAssignment(
                .assignDevices, deviceId: device.id, mdmServerId: server.id
            )
            switch outcome {
            case .succeeded:
                ABMDeviceCache.shared.applyAssignment(deviceId: device.id, serverId: server.id)
                phase = .finished(success: true, title: "Assigned to \(server.serverName)",
                                  message: "The assignment takes effect at the device's next Automated Device Enrollment.")
                onFinished(true, server, nil)
            case .completedWithErrors(let detail):
                phase = .finished(success: false, title: "Completed With Errors",
                                  message: "Apple accepted the request but reported errors:\n\n\(detail)")
                onFinished(false, server, "COMPLETED_WITH_ERROR")
            case .failed(let status):
                phase = .finished(success: false, title: "Assignment Failed",
                                  message: "Apple Business Manager reported the activity as \(status).")
                onFinished(false, server, status)
            case .stillRunning(let activityId):
                phase = .finished(success: false, title: "Still Processing",
                                  message: "Apple accepted the request but it had not completed when polling stopped (activity \(activityId)). Refresh the ABM Lookup tab shortly to confirm the result — the assignment may still apply.")
                onFinished(false, server, "Timed out polling activity \(activityId)")
            }
        } catch {
            phase = .finished(success: false, title: "Assignment Failed", message: error.localizedDescription)
            onFinished(false, server, error.localizedDescription)
        }
    }
}
