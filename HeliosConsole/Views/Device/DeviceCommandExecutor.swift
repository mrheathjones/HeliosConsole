//
//  DeviceCommandExecutor.swift
//  Helios
//
//  Executes device actions for one computer: Jamf token minting, MDM
//  command dispatch (restart/shutdown/Bluetooth/remote desktop/unlock/blank
//  push), LAPS + FileVault key reads, ABM unassign, Screen Share, and the
//  erase-acknowledgment state machine behind Erase Device / Return to
//  Service. Presentation-free: the device view renders the observable
//  result/progress state below and owns every dialog.
//

import SwiftUI
import Observation

@Observable
@MainActor
final class DeviceCommandExecutor {
    struct CommandResult {
        let success: Bool
        let title: String
        let message: String
    }

    /// The Return to Service plan the operator confirmed. Snapshotted when the
    /// confirmation dialog opens so the executed steps are exactly the steps
    /// that were shown, even if a profile re-push lands mid-dialog.
    struct ReturnToServicePlan {
        let options: AccessConfiguration.ReturnToServiceOptions
        let entraConfigured: Bool
    }

    /// The device commands target. Kept in sync by the view as full
    /// details load.
    var computer: Computer

    // MARK: - Observable command state

    var isExecutingCommand: Bool = false
    var commandResult: CommandResult?
    var showingCommandAlert: Bool = false
    /// Non-nil while a multi-stage flow (Return to Service / Erase Device) is
    /// processing; drives the progress modal and carries the current stage.
    var processingMessage: String? = nil
    /// Title shown on the processing overlay — set by whichever long-running
    /// flow is driving it (Return to Service vs. bare Erase Device).
    var processingTitle: String = "Return to Service"

    // Sensitive reads, shown until the operator dismisses them.
    var showingLocalAdminPassword: Bool = false
    var localAdminPassword: String = ""
    var localAdminUsername: String = ""
    var showingFileVaultKey: Bool = false
    var fileVaultKey: String = ""
    var fileVaultKeyStatus: String = ""
    var fileVaultEncryptionState: String = ""

    init(computer: Computer) {
        self.computer = computer
    }

    /// Read fresh on every execution path (strict fail-closed — see
    /// DeviceActionPolicy): the policy is a value type, so it must be rebuilt
    /// from the CURRENT configuration and capabilities.
    private var actionPolicy: DeviceActionPolicy {
        .currentForComputers
    }

    // MARK: - Action dispatch

    /// Runs a confirmed menu action. `returnToServicePlan` is the plan the
    /// operator confirmed (snapshotted when the dialog opened); sheet-owned
    /// actions are never routed here but stay exhaustive via `presentSheet`.
    func execute(
        _ action: DeviceAction,
        returnToServicePlan: ReturnToServicePlan?,
        openURL: OpenURLAction,
        presentSheet: (DeviceAction) -> Void
    ) async {
        // Defense in depth: the menu already filters by policy, but never
        // rely on UI alone — re-check the signed-in user's role capability
        // (the single gating layer) before any command fires, and audit-log
        // the denial.
        if let denial = actionPolicy.denialReason(for: action) {
            await reportActionDenial(denial, for: action)
            return
        }

        switch action {
        case .enableBluetooth:
            await sendBluetoothCommand(enable: true)
        case .disableBluetooth:
            await sendBluetoothCommand(enable: false)
        case .enableRemoteDesktop:
            await sendRemoteDesktopCommand(enable: true)
        case .disableRemoteDesktop:
            await sendRemoteDesktopCommand(enable: false)
        case .restart:
            await sendRestartCommand(notifyUser: true)
        case .restartSilent:
            await sendRestartCommand(notifyUser: false)
        case .shutdown:
            await sendShutdownCommand()
        case .wipe:
            await sendWipeCommand()
        case .returnToService:
            await sendEraseCommand(plan: returnToServicePlan)
        case .viewLocalAdminPassword:
            await fetchLocalAdminPassword()
        case .viewFileVaultKey:
            await fetchFileVaultKey()
        case .sendBlankPush:
            await sendBlankPushCommand()
        case .screenShare:
            await launchScreenShare(openURL: openURL)
            return // Screen Share handles its own logging
        case .unlockUserAccount:
            // Never routed here (the action flow opens the sheet directly), but
            // keep the switch exhaustive and safe.
            presentSheet(.unlockUserAccount)
            return
        case .abmAssign:
            // Never routed here (the action flow opens the sheet, which owns the
            // flow and its own audit logging) — keep the switch exhaustive.
            presentSheet(.abmAssign)
            return
        case .abmUnassign:
            await executeABMUnassign()
            return // logs internally with ABM-specific detail
        case .assignPreStage:
            // Never routed here (the action flow opens the sheet, which owns the
            // flow and its own audit logging) — keep the switch exhaustive.
            presentSheet(.assignPreStage)
            return
        case .moveToSite:
            // Never routed here (the action flow opens the sheet, which owns the
            // flow and its own audit logging) — keep the switch exhaustive.
            presentSheet(.moveToSite)
            return
        }
        
        // Centralized logging for all MDM commands (except Screen Share which logs internally)
        if let result = commandResult {
            ActionLogService.shared.logAction(
                actionName: action.logName,
                actionCategory: action.logCategory,
                deviceName: computer.displayName,
                deviceSerialNumber: computer.serialNumber ?? "Unknown",
                deviceId: computer.id,
                success: result.success,
                errorMessage: result.success ? nil : result.message
            )
        }
    }

    /// Removes this device's MDM assignment in Apple Business Manager.
    /// The grant's allowedMdmServers governs which servers the operator may
    /// unassign FROM — checked against the device's CURRENT server.
    private func executeABMUnassign() async {
        guard let serial = computer.serialNumber, !serial.isEmpty else {
            showABMResult(success: false, title: "Unassign from MDM Server",
                                message: "This device has no serial number to look up in Apple Business Manager.")
            return
        }

        await MainActor.run { isExecutingCommand = true }

        do {
            let device = try await ABMAssignmentExecutor.resolveDevice(serial: serial)
            let servers = try await ABMAssignmentExecutor.loadServers()
            guard let current = try await ABMAssignmentExecutor.currentServer(for: device, servers: servers) else {
                showABMResult(success: false, title: "Unassign from MDM Server",
                                    message: "The device is not assigned to any MDM server in Apple Business Manager — there is nothing to unassign.")
                return
            }

            guard actionPolicy.canAssignToMdmServer(named: current.serverName) else {
                showABMResult(success: false, title: "Not Permitted",
                                    message: "Your role's grant does not permit unassigning devices from \(current.serverName).")
                logABMAction(.abmUnassign, serial: serial, success: false,
                             error: "Denied by allowedMdmServers for server \(current.serverName)")
                return
            }

            let outcome = try await ABMAPIService.shared.performAssignment(
                .unassignDevices, deviceId: device.id, mdmServerId: current.id
            )

            switch outcome {
            case .succeeded:
                await MainActor.run {
                    ABMDeviceCache.shared.applyAssignment(deviceId: device.id, serverId: nil)
                }
                showABMResult(success: true, title: "Unassigned from \(current.serverName)",
                                    message: "The device no longer has an MDM server assignment in Apple Business Manager. Until it is reassigned, it cannot enroll via Automated Device Enrollment.")
                logABMAction(.abmUnassign, serial: serial, success: true, error: nil)
            case .completedWithErrors(let detail):
                showABMResult(success: false, title: "Completed With Errors",
                                    message: "Apple accepted the request but reported errors:\n\n\(detail)")
                logABMAction(.abmUnassign, serial: serial, success: false, error: "COMPLETED_WITH_ERROR")
            case .failed(let status):
                showABMResult(success: false, title: "Unassign Failed",
                                    message: "Apple Business Manager reported the activity as \(status).")
                logABMAction(.abmUnassign, serial: serial, success: false, error: status)
            case .stillRunning(let activityId):
                showABMResult(success: false, title: "Still Processing",
                                    message: "Apple accepted the request but it had not completed when polling stopped (activity \(activityId)). Check the ABM Lookup tab shortly to confirm.")
                logABMAction(.abmUnassign, serial: serial, success: false, error: "Timed out polling activity \(activityId)")
            }
        } catch {
            showABMResult(success: false, title: "Unassign Failed", message: error.localizedDescription)
            logABMAction(.abmUnassign, serial: serial, success: false, error: error.localizedDescription)
        }
    }

    private func showABMResult(success: Bool, title: String, message: String) {
        // Every executeABMUnassign path ends here, so the busy flag clears
        // before (never after) the result alert appears.
        isExecutingCommand = false
        commandResult = CommandResult(success: success, title: title, message: message)
        showingCommandAlert = true
    }

    func logABMAction(_ action: DeviceAction, serial: String, success: Bool, error: String?) {
        ActionLogService.shared.logAction(
            actionName: action.logName,
            actionCategory: action.logCategory,
            deviceName: computer.displayName,
            deviceSerialNumber: serial,
            deviceId: computer.id,
            success: success,
            errorMessage: error
        )
    }

    /// Shared denial handling for the defense-in-depth policy re-checks
    /// (executeAction and the Unlock Account sheet): surfaces the
    /// "Action Not Permitted" alert and audit-logs which layer denied.
    func reportActionDenial(_ denial: DeviceActionPolicy.DenialReason, for action: DeviceAction) async {
        // The operator-facing copy is the same either way — "not available for
        // your role" is true of both — but the AUDIT LOG distinguishes them,
        // because an emptyScope denial is a profile authoring mistake (the
        // action was granted, then scoped to nothing) and would otherwise be
        // indistinguishable from an intentional denial when someone asks why
        // a technician cannot see a button they were told they have.
        let auditDetail: String
        switch denial {
        case .roleCapability:
            auditDetail = "Blocked by role capability (no role held by this user grants '\(action.rawValue)' on computers; roles: \(signedInRolesDescription))"
        case .emptyScope:
            auditDetail = "Blocked by empty scope ('\(action.rawValue)' IS granted, but the role's target allow-list is empty — check allowedSites in the access profile; roles: \(signedInRolesDescription))"
        }

        await MainActor.run {
            commandResult = CommandResult(
                success: false,
                title: "Action Not Permitted",
                message: "\"\(action.logName)\" is not available for your role."
            )
            showingCommandAlert = true
        }
        ActionLogService.shared.logAction(
            actionName: action.logName,
            actionCategory: action.logCategory,
            deviceName: computer.displayName,
            deviceSerialNumber: computer.serialNumber ?? "Unknown",
            deviceId: computer.id,
            success: false,
            errorMessage: auditDetail
        )
    }

    /// The user's role names for audit copy — roles are arbitrary names
    /// defined by the profile, so the log records what they actually held.
    private var signedInRolesDescription: String {
        UserSession.shared.roles.isEmpty ? "none" : UserSession.shared.roles.joined(separator: ", ")
    }
    
    // MARK: - Screen Share
    
    private func launchScreenShare(openURL: OpenURLAction) async {
        // Prefer the VPN IP when the profile enables the lookup and identifies
        // the extension attribute that carries it (core
        // jamfPro.vpnIPExtensionAttributeEnabled / …ID; off = LAN IP).
        let vpnIP = MDMConfigurationManager.shared.configuration.vpnIPExtensionAttribute
            .flatMap { computer.extensionAttributeValue($0) }
        let hasVPN = vpnIP != nil && !vpnIP!.isEmpty && vpnIP!.uppercased() != "N/A"
        let targetIP = hasVPN ? vpnIP! : (computer.ipAddress ?? "")
        
        guard !targetIP.isEmpty else {
            commandResult = CommandResult(
                success: false,
                title: "Screen Share Failed",
                message: "No IP address available for this device."
            )
            showingCommandAlert = true
            ActionLogService.shared.logAction(
                actionName: "Screen Share",
                actionCategory: "Device Actions",
                deviceName: computer.displayName,
                deviceSerialNumber: computer.serialNumber ?? "Unknown",
                deviceId: computer.id,
                success: false,
                errorMessage: "No IP address available"
            )
            return
        }
        
        guard let url = URL(string: "vnc://\(targetIP)") else {
            commandResult = CommandResult(
                success: false,
                title: "Screen Share Failed",
                message: "Invalid IP address: \(targetIP)"
            )
            showingCommandAlert = true
            ActionLogService.shared.logAction(
                actionName: "Screen Share",
                actionCategory: "Device Actions",
                deviceName: computer.displayName,
                deviceSerialNumber: computer.serialNumber ?? "Unknown",
                deviceId: computer.id,
                ipAddressUsed: targetIP,
                success: false,
                errorMessage: "Invalid IP address"
            )
            return
        }
        
        openURL(url)
        
        ActionLogService.shared.logAction(
            actionName: "Screen Share",
            actionCategory: "Device Actions",
            deviceName: computer.displayName,
            deviceSerialNumber: computer.serialNumber ?? "Unknown",
            deviceId: computer.id,
            ipAddressUsed: targetIP,
            success: true
        )
        
        commandResult = CommandResult(
            success: true,
            title: "Screen Share Launched",
            message: "Opening Screen Sharing to \(targetIP)\(hasVPN ? " (VPN)" : "")"
        )
        showingCommandAlert = true
    }
    

    // MARK: - MDM Commands
    
    private func sendBluetoothCommand(enable: Bool) async {
        guard let managementId = computer.general?.managementId else {
            await MainActor.run {
                commandResult = CommandResult(
                    success: false,
                    title: "Error",
                    message: "Device management ID not available"
                )
                showingCommandAlert = true
            }
            return
        }
        
        await MainActor.run { isExecutingCommand = true }
        
        do {
            let config = MDMConfigurationManager.shared.configuration
            let jamfURL = config.jamfURL
            
            // Get bearer token
            let token = try await getBearerToken()
            
            // Build the command payload
            let parameters: [String: Any] = [
                "clientData": [["managementId": managementId]],
                "commandData": [
                    "commandType": "SETTINGS",
                    "bluetooth": enable
                ]
            ]
            
            let postData = try JSONSerialization.data(withJSONObject: parameters, options: [])
            
            guard let url = URL(string: "\(jamfURL)/api/v2/mdm/commands") else {
                throw NSError(domain: "DeviceView", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = NetworkTuning.connectionTimeout
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = postData
            
            NSLog("📤 Sending Bluetooth command (enable: \(enable)) to device: \(computer.displayName)")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "DeviceView", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }
            
            NSLog("📥 Bluetooth command response status: \(httpResponse.statusCode)")
            
            if (200...299).contains(httpResponse.statusCode) {
                await MainActor.run {
                    isExecutingCommand = false
                    commandResult = CommandResult(
                        success: true,
                        title: "Command Sent",
                        message: "Bluetooth \(enable ? "enable" : "disable") command has been sent to \(computer.displayName). The device will process this command shortly."
                    )
                    showingCommandAlert = true
                }
            } else {
                NSLog("❌ Bluetooth command failed: %@", String(data: data, encoding: .utf8) ?? "Unknown error")
                throw NSError(
                    domain: "DeviceView",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: JamfErrorFormatter.message(
                        status: httpResponse.statusCode,
                        body: data,
                        fallbackAction: "change Bluetooth"
                    )]
                )
            }
            
        } catch {
            NSLog("❌ Bluetooth command error: \(error.localizedDescription)")
            await MainActor.run {
                isExecutingCommand = false
                commandResult = CommandResult(
                    success: false,
                    title: "Command Failed",
                    message: error.localizedDescription
                )
                showingCommandAlert = true
            }
        }
    }
    
    /// Mints the Jamf token for a device operation. `scope` selects which
    /// routing category applies — MDM commands, the Return-to-Service legs,
    /// or the sensitive password/key reads — so each can be independently
    /// attributed to the operator (per-user, fail-closed) or the master client.
    private func getBearerToken(scope: CredentialScope = .mdmCommands) async throws -> String {
        let config = MDMConfigurationManager.shared.configuration

        if config.credentialSource(for: scope) == .user {
            return try await JamfUserSession.shared.bearerToken()
        }

        let jamfURL = config.jamfURL
        let masterClientID = config.masterClientID
        let masterClientSecret = config.masterClientSecret

        guard let tokenURL = URL(string: "\(jamfURL)/api/v1/oauth/token") else {
            throw NSError(domain: "DeviceView", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid token URL"])
        }
        
        var tokenRequest = URLRequest(url: tokenURL)
        tokenRequest.httpMethod = "POST"
        tokenRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        tokenRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyString = "grant_type=client_credentials&client_id=\(masterClientID)&client_secret=\(masterClientSecret)"
        tokenRequest.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: tokenRequest)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "DeviceView", code: 401, userInfo: [NSLocalizedDescriptionKey: "Failed to obtain access token"])
        }
        
        struct TokenResponse: Codable {
            let access_token: String
        }
        
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        return tokenResponse.access_token
    }
    
    // MARK: - Remote Desktop Commands
    
    private func sendRemoteDesktopCommand(enable: Bool) async {
        await sendSimpleCommand(
            commandType: enable ? "ENABLE_REMOTE_DESKTOP" : "DISABLE_REMOTE_DESKTOP",
            successMessage: "Remote Desktop \(enable ? "enable" : "disable") command has been sent to \(computer.displayName)."
        )
    }
    
    // MARK: - Restart Command
    
    private func sendRestartCommand(notifyUser: Bool) async {
        guard let managementId = computer.general?.managementId else {
            await showError("Device management ID not available")
            return
        }
        
        await MainActor.run { isExecutingCommand = true }
        
        do {
            let token = try await getBearerToken()
            let config = MDMConfigurationManager.shared.configuration
            
            var commandData: [String: Any] = ["commandType": "RESTART_DEVICE"]
            if notifyUser {
                commandData["notifyUser"] = true
            }
            
            let parameters: [String: Any] = [
                "clientData": [["managementId": managementId]],
                "commandData": commandData
            ]
            
            try await executeCommand(parameters: parameters, token: token, jamfURL: config.jamfURL)
            
            await MainActor.run {
                isExecutingCommand = false
                commandResult = CommandResult(
                    success: true,
                    title: "Command Sent",
                    message: "Restart command has been sent to \(computer.displayName).\(notifyUser ? " The user will be notified." : "")"
                )
                showingCommandAlert = true
            }
        } catch {
            await showError(error.localizedDescription)
        }
    }
    
    // MARK: - Shutdown Command
    
    private func sendShutdownCommand() async {
        await sendSimpleCommand(
            commandType: "SHUT_DOWN_DEVICE",
            successMessage: "Shutdown command has been sent to \(computer.displayName)."
        )
    }
    
    // MARK: - Erase Device (bare erase — Jamf record and Entra object kept)

    /// Bare erase: queue the ERASE_DEVICE command (with recovery PIN), WAIT for
    /// the device to acknowledge it, and stop there — the Jamf computer record
    /// and Entra device object are intentionally left in place. An erase is
    /// never fire-and-forget, so an unacknowledged command surfaces as a
    /// failure the operator must follow up on manually.
    private func sendWipeCommand() async {
        guard let managementId = computer.general?.managementId else {
            await showError("Device management ID not available — cannot erase this device.")
            return
        }

        let config = MDMConfigurationManager.shared.configuration
        let deviceName = computer.displayName
        let serial = computer.serialNumber ?? "Unknown"
        let deviceId = computer.id

        await MainActor.run {
            isExecutingCommand = true
            processingTitle = "Erase Device"
            processingMessage = "Sending erase command to \(deviceName)…"
        }

        do {
            let token = try await getBearerToken()

            let erase = try await performEraseAndAwaitAck(
                managementId: managementId, deviceName: deviceName,
                serial: serial, deviceId: deviceId, token: token, config: config
            )

            var summaryLines = erase.summaryLines
            if erase.acked {
                summaryLines.append("• Erase acknowledged. Jamf record and Entra object intentionally left in place.")
            } else {
                summaryLines.append("• Erase was NOT acknowledged in time — the command remains queued for delivery and the device record is untouched. Follow up manually.")
            }

            await MainActor.run {
                isExecutingCommand = false
                processingMessage = nil
                commandResult = CommandResult(
                    success: erase.acked,
                    title: erase.acked ? "Erase Acknowledged" : "Erase Not Acknowledged",
                    message: "\(deviceName):\n" + summaryLines.joined(separator: "\n")
                )
                showingCommandAlert = true
            }

        } catch {
            NSLog("❌ Erase Device error: \(error.localizedDescription)")
            await MainActor.run { processingMessage = nil }
            await showError(error.localizedDescription)
        }
    }

    // MARK: - Return to Service (Erase → configurable Jamf/Entra cleanup)

    /// Orchestrates the decommission: queue the ERASE_DEVICE command, WAIT for
    /// the device to acknowledge it, then run the cleanup steps the profile
    /// enables (options on the returnToService allow-list entry; both default
    /// ON, preserving the full decommission for already-deployed profiles).
    /// Ports the `after-ack` behavior of Erase_and_Delete_Devices.sh — and
    /// hardens it: NO cleanup step (Jamf delete OR Entra delete) may run until
    /// the erase is acknowledged, because deleting the Jamf record removes the
    /// MDM profile and unmanages the Mac — an unacknowledged command would then
    /// never be delivered. Each stage logs independently; Entra is best-effort.
    private func sendEraseCommand(plan: ReturnToServicePlan?) async {
        guard let managementId = computer.general?.managementId else {
            await showError("Device management ID not available — cannot erase this device.")
            return
        }

        let config = MDMConfigurationManager.shared.configuration
        // Execute exactly the plan the operator confirmed (snapshotted when
        // the dialog opened); fall back to the live policy defensively.
        let options = plan?.options ?? actionPolicy.returnToServiceOptions()
        let entraConfiguredAtConfirm = plan?.entraConfigured ?? config.isEntraConfigured
        let deviceName = computer.displayName
        let serial = computer.serialNumber ?? "Unknown"
        let deviceId = computer.id
        let category = "Device Actions"

        await MainActor.run {
            isExecutingCommand = true
            processingTitle = "Return to Service"
            processingMessage = "Sending erase command to \(deviceName)…"
        }

        var summaryLines: [String] = []
        var overallSuccess = true

        do {
            let token = try await getBearerToken(scope: .returnToService)

            // 1) Erase phase: queue the command (with PIN) and wait for the
            // device to acknowledge it.
            let erase = try await performEraseAndAwaitAck(
                managementId: managementId, deviceName: deviceName,
                serial: serial, deviceId: deviceId, token: token, config: config
            )
            summaryLines.append(contentsOf: erase.summaryLines)
            let acked = erase.acked

            // The ack wait can outlive the original bearer token — cleanup
            // uses a fresh one (falling back to the original if the refresh
            // fails; the delete then surfaces its own auth error).
            let cleanupToken = acked ? ((try? await getBearerToken(scope: .returnToService)) ?? token) : token

            // 2) Delete the Jamf record only after the erase is acknowledged,
            // and only when the profile hasn't disabled the step.
            if acked && options.effectiveDeleteJamfRecord {
                await MainActor.run { processingMessage = "Erase acknowledged. Removing Jamf record…" }
                do {
                    try await deleteJamfRecord(computerId: deviceId, token: cleanupToken, jamfURL: config.jamfURL)
                    summaryLines.append("• Erase acknowledged; Jamf record removed.")
                    ActionLogService.shared.logAction(
                        actionName: "Delete Jamf Record", actionCategory: category,
                        deviceName: deviceName, deviceSerialNumber: serial, deviceId: deviceId,
                        success: true, errorMessage: nil
                    )
                } catch {
                    overallSuccess = false
                    summaryLines.append("• Jamf record NOT removed: \(error.localizedDescription)")
                    ActionLogService.shared.logAction(
                        actionName: "Delete Jamf Record", actionCategory: category,
                        deviceName: deviceName, deviceSerialNumber: serial, deviceId: deviceId,
                        success: false, errorMessage: error.localizedDescription
                    )
                }
            } else if acked {
                // Policy-disabled skip — not a failure.
                summaryLines.append("• Jamf record kept (disabled by policy).")
            } else {
                overallSuccess = false
                // Compose the timeout line from the confirmed plan — never
                // invite the operator to manually run a step the profile
                // deliberately disabled.
                var notAckedLine = "• Erase was NOT acknowledged in time — the command remains queued for delivery"
                var skipped: [String] = []
                if options.effectiveDeleteJamfRecord {
                    skipped.append("the Jamf record was intentionally left in place (deleting it now would unmanage the Mac)")
                }
                if options.effectiveDeleteEntraObject && entraConfiguredAtConfirm {
                    skipped.append("Entra cleanup was skipped")
                }
                if !skipped.isEmpty { notAckedLine += "; " + skipped.joined(separator: " and ") }
                notAckedLine += ". Follow up manually."
                summaryLines.append(notAckedLine)
                // Audit the withheld delete only when one was actually
                // planned — a policy-disabled step was never going to run.
                if options.effectiveDeleteJamfRecord {
                    ActionLogService.shared.logAction(
                        actionName: "Delete Jamf Record", actionCategory: category,
                        deviceName: deviceName, deviceSerialNumber: serial, deviceId: deviceId,
                        success: false, errorMessage: "Erase not acknowledged; record intentionally not deleted (would unmanage the Mac)."
                    )
                }
            }

            // 3) Entra cleanup — HARD-gated on acknowledgment like every other
            // cleanup step, then on the profile option. Best effort, only when
            // configured. Never fatal.
            if acked && options.effectiveDeleteEntraObject && entraConfiguredAtConfirm {
                if let entra = EntraGraphService(configuration: config) {
                    let entraName = computer.general?.name ?? deviceName
                    await MainActor.run { processingMessage = "Removing '\(entraName)' from Microsoft Entra…" }
                    let result = await entra.deleteDevices(displayName: entraName)
                    var entraSuccess = true
                    switch result.outcome {
                    case .completed:
                        entraSuccess = result.failed == 0
                        summaryLines.append("• Entra: \(result.deleted) object(s) removed" + (result.failed > 0 ? ", \(result.failed) failed." : "."))
                    case .noMatch:
                        summaryLines.append("• Entra: no matching device object.")
                    case .authFailed, .lookupFailed, .notConfigured:
                        entraSuccess = false
                        summaryLines.append("• Entra cleanup did not complete: \(result.message)")
                    }
                    ActionLogService.shared.logAction(
                        actionName: "Entra Device Cleanup", actionCategory: category,
                        deviceName: entraName, deviceSerialNumber: serial, deviceId: deviceId,
                        success: entraSuccess, errorMessage: entraSuccess ? nil : result.message
                    )
                } else {
                    summaryLines.append("• Entra cleanup not configured — skipped.")
                }
            } else if acked && options.effectiveDeleteEntraObject {
                // Option on, but Entra wasn't configured when the operator
                // confirmed — nothing was promised, nothing runs.
                summaryLines.append("• Entra cleanup not configured — skipped.")
            } else if acked {
                // Policy-disabled skip — not a failure.
                summaryLines.append("• Entra cleanup disabled by policy — skipped.")
            }
            // Not acked: the step-2 summary line already covers the skipped
            // Entra cleanup — no cleanup runs on an unacknowledged erase.

            await MainActor.run {
                isExecutingCommand = false
                processingMessage = nil
                commandResult = CommandResult(
                    success: overallSuccess,
                    title: overallSuccess ? "Return to Service Complete" : "Return to Service — Attention Needed",
                    message: "\(deviceName):\n" + summaryLines.joined(separator: "\n")
                )
                showingCommandAlert = true
            }

        } catch {
            NSLog("❌ Return to Service error: \(error.localizedDescription)")
            await MainActor.run { processingMessage = nil }
            await showError(error.localizedDescription)
        }
    }

    // MARK: - Shared erase phase

    /// Result of the shared erase phase: whether the device acknowledged the
    /// erase, plus the summary lines accumulated so far.
    private struct ErasePhaseResult { let acked: Bool; let summaryLines: [String] }

    /// Issues ERASE_DEVICE (with recovery PIN) and ALWAYS waits for the device
    /// to acknowledge — an erase is never fire-and-forget, and callers must
    /// treat acked == false as "no further destructive steps may run".
    private func performEraseAndAwaitAck(managementId: String, deviceName: String, serial: String, deviceId: String, token: String, config: MDMConfiguration) async throws -> ErasePhaseResult {
        let category = "Device Actions"
        var summaryLines: [String] = []

        // EraseDevice always requires a 6-digit PIN in the API call, but the PIN
        // only MATTERS on Intel/T2 Macs — there it becomes the recovery PIN
        // needed to unlock the Mac after the wipe. Apple Silicon ignores it, so
        // the PIN is only surfaced/logged for non-Apple-Silicon hardware. When
        // the architecture is unknown, `isAppleSilicon` is false, so the PIN is
        // shown (safe default).
        let erasePIN = String(format: "%06d", Int.random(in: 0...999999))
        let showPIN = !computer.isAppleSilicon

        // 1) Queue the erase command (with PIN) and capture its UUID.
        let commandUUID = try await issueEraseCommand(managementId: managementId, pin: erasePIN, token: token, jamfURL: config.jamfURL)
        if showPIN {
            summaryLines.append("• Erase command queued. Recovery PIN: \(erasePIN) (needed to unlock this Intel/T2 Mac).")
        } else {
            summaryLines.append("• Erase command queued.")
        }
        ActionLogService.shared.logAction(
            actionName: showPIN ? "Erase Command Queued (recovery PIN \(erasePIN))" : "Erase Command Queued",
            actionCategory: category,
            deviceName: deviceName, deviceSerialNumber: serial, deviceId: deviceId,
            success: true, errorMessage: nil
        )

        // 2) WAIT until the device ACKNOWLEDGES the erase. Destructive
        // follow-up (e.g. deleting the Jamf record, which unmanages the Mac by
        // removing MDM) must not happen until the wipe is acknowledged/underway
        // or the command never processes.
        await MainActor.run { processingMessage = "Waiting for \(deviceName) to acknowledge the erase…" }
        let acked = await waitForAcknowledgment(uuid: commandUUID, deviceName: deviceName, token: token, jamfURL: config.jamfURL)

        return ErasePhaseResult(acked: acked, summaryLines: summaryLines)
    }

    /// POST an ERASE_DEVICE MDM command (with the required 6-digit PIN) and
    /// return its command UUID.
    private func issueEraseCommand(managementId: String, pin: String, token: String, jamfURL: String) async throws -> String {
        let parameters: [String: Any] = [
            "clientData": [["managementId": managementId]],
            "commandData": [
                "commandType": "ERASE_DEVICE",
                "pin": pin
            ]
        ]
        let postData = try JSONSerialization.data(withJSONObject: parameters, options: [])

        guard let url = URL(string: "\(jamfURL)/api/v2/mdm/commands") else {
            throw NSError(domain: "DeviceView", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = NetworkTuning.connectionTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = postData

        NSLog("📤 Sending Erase command to \(computer.displayName) (managementId: \(managementId))")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "DeviceView", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            NSLog("❌ Erase command rejected: \(errorMessage)")
            throw NSError(
                domain: "DeviceView",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: JamfErrorFormatter.message(
                    status: httpResponse.statusCode,
                    body: data,
                    fallbackAction: "send the erase command"
                )]
            )
        }

        let uuid = Self.extractCommandUUID(from: data) ?? ""
        NSLog("✅ Erase queued (command uuid: \(uuid.isEmpty ? "unknown" : uuid))")
        return uuid
    }

    /// Poll the erase command until the device ACKNOWLEDGES it (or it reports
    /// COMPLETED), so destructive follow-up steps only run once the wipe is
    /// actually underway. Returns false on NOT_NOW / ERROR / FAILED or on
    /// timeout — in which case the caller must NOT run any cleanup step
    /// (deleting the record would unmanage the Mac before the command is
    /// delivered). Timeout and poll interval come from the core domain
    /// (jamfPro.eraseAckTimeoutSeconds / jamfPro.eraseAckPollIntervalSeconds;
    /// the defaults mirror wait_for_ack in the script: 180s, 15s).
    private func waitForAcknowledgment(uuid: String, deviceName: String, token: String, jamfURL: String) async -> Bool {
        guard !uuid.isEmpty else {
            NSLog("⚠️ No command UUID to poll — cannot confirm acknowledgment")
            return false
        }

        let config = MDMConfigurationManager.shared.configuration
        let timeoutSeconds = config.eraseAckTimeoutSeconds
        let pollIntervalSeconds = config.eraseAckPollIntervalSeconds
        var waited = 0
        // The configurable wait (up to 30 min) can outlive the bearer token,
        // so the poll refreshes it on a 401 instead of silently retrying
        // with a dead token until timeout.
        var token = token

        while true {
            await MainActor.run {
                processingMessage = "Waiting for \(deviceName) to acknowledge the erase…  (\(waited)s)"
            }

            var components = URLComponents(string: "\(jamfURL)/api/v2/mdm/commands")
            components?.queryItems = [
                URLQueryItem(name: "page", value: "0"),
                URLQueryItem(name: "page-size", value: "1"),
                URLQueryItem(name: "filter", value: "uuid==\"\(uuid)\"")
            ]

            if let url = components?.url {
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.timeoutInterval = NetworkTuning.connectionTimeout
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                        let state = Self.extractCommandState(from: data)
                        let normalized = state.uppercased()
                            .replacingOccurrences(of: "_", with: "")
                            .replacingOccurrences(of: " ", with: "")
                        NSLog("🔎 Erase \(uuid) state=\(state.isEmpty ? "<none>" : state) (waited \(waited)s)")
                        switch normalized {
                        case "ACKNOWLEDGED", "COMPLETED":
                            return true
                        case "ERROR", "FAILED", "NOTNOW":
                            NSLog("❌ Erase \(uuid) returned \(state) — not deleting the record")
                            return false
                        default:
                            break // PENDING / empty — keep waiting
                        }
                    } else {
                        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                        NSLog("⚠️ Ack poll failed (HTTP \(code))")
                        if code == 401, let fresh = try? await getBearerToken(scope: .returnToService) {
                            token = fresh
                            NSLog("🔑 Bearer token refreshed for ack polling")
                        }
                    }
                } catch {
                    NSLog("⚠️ Ack poll error for \(uuid): \(error.localizedDescription)")
                }
            }

            // Exit only after a poll AT the timeout boundary: sleep exactly
            // the remaining window (never past it), then poll once more —
            // an ack landing during the final sleep is not missed, and a
            // poll interval larger than the timeout cannot overshoot it.
            if waited >= timeoutSeconds { break }
            let sleepSeconds = min(pollIntervalSeconds, timeoutSeconds - waited)
            try? await Task.sleep(nanoseconds: UInt64(sleepSeconds) * 1_000_000_000)
            waited += sleepSeconds
        }

        NSLog("⏱️ Timed out after \(timeoutSeconds)s waiting for ack of \(uuid)")
        return false
    }

    /// DELETE the Jamf computer-inventory record. Treats 200/204 as success.
    private func deleteJamfRecord(computerId: String, token: String, jamfURL: String) async throws {
        guard let url = URL(string: "\(jamfURL)/api/v1/computers-inventory/\(computerId)") else {
            throw NSError(domain: "DeviceView", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = NetworkTuning.connectionTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "DeviceView", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        guard httpResponse.statusCode == 204 || httpResponse.statusCode == 200 else {
            NSLog("❌ Jamf record delete failed: %@", String(data: data, encoding: .utf8) ?? "Unknown error")
            throw NSError(
                domain: "DeviceView",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: JamfErrorFormatter.message(
                    status: httpResponse.statusCode,
                    body: data,
                    fallbackAction: "delete the Jamf record"
                )]
            )
        }
        NSLog("🗑️ Deleted Jamf record id \(computerId)")
    }

    /// Pull a command UUID from the POST /api/v2/mdm/commands response. Shape
    /// varies by Jamf version (array of objects, or a single object).
    private static func extractCommandUUID(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        func uuid(_ dict: [String: Any]) -> String? {
            (dict["id"] as? String) ?? (dict["commandUuid"] as? String)
        }
        if let array = json as? [[String: Any]], let first = array.first {
            return uuid(first)
        }
        if let dict = json as? [String: Any] {
            if let results = dict["results"] as? [[String: Any]], let first = results.first {
                return uuid(first)
            }
            return uuid(dict)
        }
        return nil
    }

    /// Pull the command state from GET /api/v2/mdm/commands. Prefers
    /// `commandState`, falls back to `status`. Handles array / results / object.
    private static func extractCommandState(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return "" }
        func state(_ dict: [String: Any]) -> String {
            (dict["commandState"] as? String) ?? (dict["status"] as? String) ?? ""
        }
        if let array = json as? [[String: Any]], let first = array.first {
            return state(first)
        }
        if let dict = json as? [String: Any] {
            if let results = dict["results"] as? [[String: Any]], let first = results.first {
                return state(first)
            }
            return state(dict)
        }
        return ""
    }
    
    // MARK: - Unlock User Account Command
    
    func sendUnlockAccountCommand(username: String) async {
        // Defense in depth (same invariant as executeAction): the sheet is
        // only reachable via the policy-filtered menu, but enforcement must
        // never live only in the UI — re-check both layers and audit-log
        // which one denied.
        if let denial = actionPolicy.denialReason(for: .unlockUserAccount) {
            await reportActionDenial(denial, for: .unlockUserAccount)
            return
        }

        guard let managementId = computer.general?.managementId else {
            await showError("Device management ID not available")
            return
        }
        
        guard !username.isEmpty else {
            await showError("Username is required")
            return
        }
        
        await MainActor.run { isExecutingCommand = true }
        
        do {
            let token = try await getBearerToken()
            let config = MDMConfigurationManager.shared.configuration
            
            let parameters: [String: Any] = [
                "clientData": [["managementId": managementId]],
                "commandData": [
                    "commandType": "UNLOCK_USER_ACCOUNT",
                    "userName": username
                ]
            ]
            
            try await executeCommand(parameters: parameters, token: token, jamfURL: config.jamfURL)
            
            await MainActor.run {
                isExecutingCommand = false
                commandResult = CommandResult(
                    success: true,
                    title: "Command Sent",
                    message: "Unlock account command for user '\(username)' has been sent to \(computer.displayName)."
                )
                showingCommandAlert = true
            }
        } catch {
            await showError(error.localizedDescription)
        }
    }
    
    // MARK: - Helper Functions
    
    private func sendSimpleCommand(commandType: String, successMessage: String) async {
        guard let managementId = computer.general?.managementId else {
            await showError("Device management ID not available")
            return
        }
        
        await MainActor.run { isExecutingCommand = true }
        
        do {
            let token = try await getBearerToken()
            let config = MDMConfigurationManager.shared.configuration
            
            let parameters: [String: Any] = [
                "clientData": [["managementId": managementId]],
                "commandData": ["commandType": commandType]
            ]
            
            try await executeCommand(parameters: parameters, token: token, jamfURL: config.jamfURL)
            
            await MainActor.run {
                isExecutingCommand = false
                commandResult = CommandResult(
                    success: true,
                    title: "Command Sent",
                    message: successMessage
                )
                showingCommandAlert = true
            }
        } catch {
            await showError(error.localizedDescription)
        }
    }
    
    private func executeCommand(parameters: [String: Any], token: String, jamfURL: String) async throws {
        let postData = try JSONSerialization.data(withJSONObject: parameters, options: [])
        
        guard let url = URL(string: "\(jamfURL)/api/v2/mdm/commands") else {
            throw NSError(domain: "DeviceView", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = NetworkTuning.connectionTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = postData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "DeviceView", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            NSLog("❌ MDM command failed: %@", String(data: data, encoding: .utf8) ?? "Unknown error")
            throw NSError(
                domain: "DeviceView",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: JamfErrorFormatter.message(
                    status: httpResponse.statusCode,
                    body: data,
                    fallbackAction: "send this command"
                )]
            )
        }
    }
    
    private func showError(_ message: String) async {
        await MainActor.run {
            isExecutingCommand = false
            commandResult = CommandResult(
                success: false,
                title: "Command Failed",
                message: message
            )
            showingCommandAlert = true
        }
    }
    
    // MARK: - Local Admin Password (LAPS)
    
    private func fetchLocalAdminPassword() async {
        guard let managementId = computer.general?.managementId else {
            await showError("Device management ID not available")
            return
        }
        
        let config = MDMConfigurationManager.shared.configuration
        let username = config.localAdminUsername
        
        await MainActor.run { isExecutingCommand = true }
        
        do {
            let token = try await getBearerToken(scope: .sensitiveReads)
            let jamfURL = config.jamfURL

            // Build the LAPS API URL
            guard let url = URL(string: "\(jamfURL)/api/v2/local-admin-password/\(managementId)/account/\(username)/password") else {
                throw NSError(domain: "DeviceView", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = NetworkTuning.connectionTimeout
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            NSLog("📤 Fetching local admin password for device: \(computer.displayName) (managementId: \(managementId), user: \(username))")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "DeviceView", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }
            
            NSLog("📥 LAPS response status: \(httpResponse.statusCode)")
            
            if (200...299).contains(httpResponse.statusCode) {
                // Parse the response
                struct LAPSResponse: Codable {
                    let password: String
                }
                
                let lapsResponse = try JSONDecoder().decode(LAPSResponse.self, from: data)
                
                await MainActor.run {
                    isExecutingCommand = false
                    localAdminUsername = username
                    localAdminPassword = lapsResponse.password
                    showingLocalAdminPassword = true
                }
            } else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                NSLog("❌ LAPS fetch failed: \(errorMessage)")
                
                // Provide more helpful error messages
                var userMessage = "Failed to retrieve password."
                if httpResponse.statusCode == 404 {
                    userMessage = "Local admin password not found for user '\(username)' on this device. LAPS may not be configured."
                } else if httpResponse.statusCode == 403 {
                    userMessage = "Access denied. Insufficient privileges to view local admin passwords."
                }
                
                throw NSError(domain: "DeviceView", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: userMessage])
            }
            
        } catch {
            NSLog("❌ LAPS fetch error: \(error.localizedDescription)")
            await showError(error.localizedDescription)
        }
    }
    
    // MARK: - FileVault Key
    
    private func fetchFileVaultKey() async {
        let deviceId = computer.id
        
        await MainActor.run { isExecutingCommand = true }
        
        do {
            let token = try await getBearerToken(scope: .sensitiveReads)
            let config = MDMConfigurationManager.shared.configuration
            let jamfURL = config.jamfURL

            // Build the FileVault API URL
            guard let url = URL(string: "\(jamfURL)/api/v3/computers-inventory/\(deviceId)/filevault") else {
                throw NSError(domain: "DeviceView", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = NetworkTuning.connectionTimeout
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            NSLog("📤 Fetching FileVault key for device: \(computer.displayName) (id: \(deviceId))")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "DeviceView", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }
            
            NSLog("📥 FileVault response status: \(httpResponse.statusCode)")
            
            if (200...299).contains(httpResponse.statusCode) {
                // Parse the response
                struct FileVaultResponse: Codable {
                    let computerId: String?
                    let name: String?
                    let personalRecoveryKey: String?
                    let bootPartitionEncryptionDetails: BootPartitionDetails?
                    let individualRecoveryKeyValidityStatus: String?
                    let institutionalRecoveryKeyPresent: Bool?
                    let diskEncryptionConfigurationName: String?
                    
                    struct BootPartitionDetails: Codable {
                        let partitionName: String?
                        let partitionFileVault2State: String?
                        let partitionFileVault2Percent: Int?
                    }
                }
                
                let fvResponse = try JSONDecoder().decode(FileVaultResponse.self, from: data)
                
                // Check if we have a recovery key
                guard let recoveryKey = fvResponse.personalRecoveryKey, !recoveryKey.isEmpty else {
                    var errorMessage = "No personal recovery key found for this device."
                    
                    // Add more context from the response
                    if let state = fvResponse.bootPartitionEncryptionDetails?.partitionFileVault2State {
                        if state == "NOT_ENCRYPTED" {
                            errorMessage = "This device is not encrypted with FileVault."
                        } else if state == "ENCRYPTING" {
                            errorMessage = "FileVault encryption is in progress. Recovery key may not be available yet."
                        } else if state == "DECRYPTING" {
                            errorMessage = "FileVault is being decrypted. Recovery key is no longer valid."
                        }
                    }
                    
                    throw NSError(domain: "DeviceView", code: 404, userInfo: [NSLocalizedDescriptionKey: errorMessage])
                }
                
                await MainActor.run {
                    isExecutingCommand = false
                    fileVaultKey = recoveryKey
                    fileVaultKeyStatus = fvResponse.individualRecoveryKeyValidityStatus ?? "UNKNOWN"
                    fileVaultEncryptionState = fvResponse.bootPartitionEncryptionDetails?.partitionFileVault2State ?? ""
                    showingFileVaultKey = true
                }
            } else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                NSLog("❌ FileVault fetch failed: \(errorMessage)")
                
                // Provide more helpful error messages
                var userMessage = "Failed to retrieve FileVault key."
                if httpResponse.statusCode == 404 {
                    userMessage = "FileVault information not found for this device. The device may not be encrypted or escrowed."
                } else if httpResponse.statusCode == 403 {
                    userMessage = "Access denied. Insufficient privileges to view FileVault recovery keys."
                }
                
                throw NSError(domain: "DeviceView", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: userMessage])
            }
            
        } catch {
            NSLog("❌ FileVault fetch error: \(error.localizedDescription)")
            await showError(error.localizedDescription)
        }
    }
    
    // MARK: - Send Blank Push
    
    private func sendBlankPushCommand() async {
        guard let managementId = computer.general?.managementId else {
            await showError("Device management ID not available")
            return
        }
        
        await MainActor.run { isExecutingCommand = true }
        
        do {
            let token = try await getBearerToken()
            let config = MDMConfigurationManager.shared.configuration
            let jamfURL = config.jamfURL
            
            // Build the blank push payload
            let parameters: [String: Any] = [
                "clientManagementIds": [managementId]
            ]
            
            let postData = try JSONSerialization.data(withJSONObject: parameters, options: [])
            
            guard let url = URL(string: "\(jamfURL)/api/v2/mdm/blank-push") else {
                throw NSError(domain: "DeviceView", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = NetworkTuning.connectionTimeout
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = postData
            
            NSLog("📤 Sending Blank Push to device: \(computer.displayName) (managementId: \(managementId))")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "DeviceView", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }
            
            NSLog("📥 Blank Push response status: \(httpResponse.statusCode)")
            
            if (200...299).contains(httpResponse.statusCode) {
                await MainActor.run {
                    isExecutingCommand = false
                    commandResult = CommandResult(
                        success: true,
                        title: "Blank Push Sent",
                        message: "An APNs notification has been sent to \(computer.displayName). The device should check in shortly if it's online and reachable."
                    )
                    showingCommandAlert = true
                }
            } else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                NSLog("❌ Blank Push failed: \(errorMessage)")
                
                var userMessage = "Failed to send blank push."
                if httpResponse.statusCode == 404 {
                    userMessage = "Device not found or not enrolled in MDM."
                } else if httpResponse.statusCode == 403 {
                    userMessage = "Access denied. Insufficient privileges to send push notifications."
                }
                
                throw NSError(domain: "DeviceView", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: userMessage])
            }
            
        } catch {
            NSLog("❌ Blank Push error: \(error.localizedDescription)")
            await showError(error.localizedDescription)
        }
    }
}

// MARK: - Current Policy

extension DeviceActionPolicy {
    /// The computer Actions policy for the signed-in user, built from the
    /// CURRENT configuration and role capabilities (strict fail-closed).
    @MainActor
    static var currentForComputers: DeviceActionPolicy {
        MDMConfigurationManager.shared.configuration
            .computerActionPolicy(capabilities: UserSession.shared.capabilities)
    }
}
