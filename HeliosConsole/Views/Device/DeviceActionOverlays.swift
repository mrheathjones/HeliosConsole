//
//  DeviceActionOverlays.swift
//  Helios
//
//  Modal overlays for device actions: the command result, the two-stage
//  destructive confirmation (danger warning → typed ERASE), the Return to
//  Service / Erase progress card, the unlock-account prompt, and the LAPS /
//  FileVault secret readouts. Rendered as direct children of the device
//  view's root ZStack, in stacking order.
//

import SwiftUI

struct DeviceActionOverlays: View {
    let computer: Computer
    @Bindable var executor: DeviceCommandExecutor
    @Bindable var flow: DeviceActionFlow
    @ObservedObject private var configManager = MDMConfigurationManager.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        // Command result overlay
        commandResultOverlay

        // Destructive-action danger warning (stage 1 for erase/RTS)
        destructiveWarningOverlay

        // Action confirmation overlay
        actionConfirmationOverlay

        // Processing progress overlay (Return to Service multi-stage flow)
        processingOverlay

        // Unlock account sheet overlay
        unlockAccountOverlay

        // Local admin password overlay
        localAdminPasswordOverlay

        // FileVault key overlay
        fileVaultKeyOverlay
    }

    // MARK: - Processing Progress Overlay

    @ViewBuilder
    private var processingOverlay: some View {
        if let message = executor.processingMessage {
            ZStack {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()

                VStack(spacing: 18) {
                    Text(executor.processingTitle)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)

                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(width: 240)

                    Text(message)
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .frame(minHeight: 34)
                        .padding(.horizontal, 24)

                    Text("Please keep this window open — do not close the app.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.vertical, 28)
                .frame(width: 340)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(white: 0.12))
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 30)
            }
        }
    }

    @ViewBuilder
    private var commandResultOverlay: some View {
        if executor.showingCommandAlert, let result = executor.commandResult {
            ZStack {
                // Dimmed background
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) {
                            executor.showingCommandAlert = false
                            executor.commandResult = nil
                        }
                    }
                
                // Alert card
                VStack(spacing: 0) {
                    // Header with icon
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(result.success ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                                .frame(width: 56, height: 56)
                            
                            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(result.success ? .green : .red)
                        }
                        
                        Text(result.title)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                    
                    // Message
                    Text(result.message)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                    
                    // OK Button
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            executor.showingCommandAlert = false
                            executor.commandResult = nil
                        }
                    } label: {
                        Text("OK")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(result.success ? Color.green : Color.blue)
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: 320)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(white: 0.12))
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 30)
            }
        }
    }

    // MARK: - FileVault Key Overlay
    
    @ViewBuilder
    private var fileVaultKeyOverlay: some View {
        if executor.showingFileVaultKey {
            ZStack {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) {
                            executor.showingFileVaultKey = false
                            executor.fileVaultKey = ""
                            executor.fileVaultKeyStatus = ""
                            executor.fileVaultEncryptionState = ""
                        }
                    }
                
                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.15))
                                .frame(width: 56, height: 56)
                            
                            Image(systemName: "lock.shield")
                                .font(.system(size: 24))
                                .foregroundColor(.green)
                        }
                        
                        Text("FileVault Recovery Key")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text(computer.displayName)
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 20)
                    
                    // Key display
                    VStack(spacing: 12) {
                        // Recovery Key row
                        HStack {
                            Text("Recovery Key")
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                                .frame(width: 100, alignment: .leading)
                            
                            Text(executor.fileVaultKey)
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(executor.fileVaultKey, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(8)
                        
                        // Status row
                        HStack {
                            Text("Key Status")
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                                .frame(width: 100, alignment: .leading)
                            
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(executor.fileVaultKeyStatus == "VALID" ? Color.green : Color.orange)
                                    .frame(width: 8, height: 8)
                                Text(executor.fileVaultKeyStatus.capitalized)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(executor.fileVaultKeyStatus == "VALID" ? .green : .orange)
                            }
                            
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(8)
                        
                        // Encryption State row
                        if !executor.fileVaultEncryptionState.isEmpty {
                            HStack {
                                Text("Encryption")
                                    .font(.system(size: 13))
                                    .foregroundColor(.gray)
                                    .frame(width: 100, alignment: .leading)
                                
                                Text(formatEncryptionState(executor.fileVaultEncryptionState))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white)
                                
                                Spacer()
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                    
                    // Done button
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            executor.showingFileVaultKey = false
                            executor.fileVaultKey = ""
                            executor.fileVaultKeyStatus = ""
                            executor.fileVaultEncryptionState = ""
                        }
                    } label: {
                        Text("Done")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.green)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: 400)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(white: 0.12))
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 30)
            }
        }
    }
    
    private func formatEncryptionState(_ state: String) -> String {
        switch state {
        case "ENCRYPTED": return "Encrypted"
        case "ENCRYPTING": return "Encrypting..."
        case "DECRYPTING": return "Decrypting..."
        case "NOT_ENCRYPTED": return "Not Encrypted"
        default: return state.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    
    // MARK: - Local Admin Password Overlay
    
    @ViewBuilder
    private var localAdminPasswordOverlay: some View {
        if executor.showingLocalAdminPassword {
            ZStack {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) {
                            executor.showingLocalAdminPassword = false
                            executor.localAdminPassword = ""
                            executor.localAdminUsername = ""
                        }
                    }
                
                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.purple.opacity(0.15))
                                .frame(width: 56, height: 56)
                            
                            Image(systemName: "key.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.purple)
                        }
                        
                        Text("Local Admin Password")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text(computer.displayName)
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 20)
                    
                    // Credentials display
                    VStack(spacing: 12) {
                        // Username row
                        HStack {
                            Text("Username")
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                                .frame(width: 80, alignment: .leading)
                            
                            Text(executor.localAdminUsername)
                                .font(.system(size: 15, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(executor.localAdminUsername, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(8)
                        
                        // Password row
                        HStack {
                            Text("Password")
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                                .frame(width: 80, alignment: .leading)
                            
                            Text(executor.localAdminPassword)
                                .font(.system(size: 15, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(executor.localAdminPassword, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(8)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                    
                    // Done button
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            executor.showingLocalAdminPassword = false
                            executor.localAdminPassword = ""
                            executor.localAdminUsername = ""
                        }
                    } label: {
                        Text("Done")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.purple)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: 360)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(white: 0.12))
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 30)
            }
        }
    }
    
    // MARK: - Destructive Action Warning Overlay (stage 1 of 2)

    /// Stage 1 for Erase Device / Return to Service: states the damage in
    /// plain language and names the target, with no confirm control other
    /// than an explicit acknowledgement button. Clearing it opens the
    /// typed-ERASE dialog (stage 2), which carries the per-action specifics.
    @ViewBuilder
    private var destructiveWarningOverlay: some View {
        if flow.showingDestructiveWarning, let action = flow.pendingAction,
           let warning = action.dangerWarning {
            ZStack {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) {
                            flow.dismissConfirmation()
                        }
                    }

                VStack(spacing: 0) {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.15))
                                .frame(width: 64, height: 64)

                            Image(systemName: "exclamationmark.octagon.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.red)
                        }

                        Text("Destructive Action")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundColor(.red)

                        Text(ActionBranding.confirmationTitle(for: action))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                    .padding(.horizontal, 24)

                    Text(warning)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)

                    // Name the target explicitly — wrong-device is the most
                    // likely way this action goes wrong.
                    VStack(spacing: 4) {
                        Text(computer.displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)

                        if let serial = computer.serialNumber {
                            Text(serial)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.red.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.red.opacity(0.25), lineWidth: 1)
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)

                    Divider()
                        .background(Color.white.opacity(0.1))

                    HStack(spacing: 0) {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                flow.dismissConfirmation()
                            }
                        } label: {
                            Text("Cancel")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                        .buttonStyle(.plain)

                        Divider()
                            .background(Color.white.opacity(0.1))
                            .frame(height: 50)

                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                flow.showingDestructiveWarning = false
                                flow.showingActionConfirmation = true
                            }
                        } label: {
                            Text("I Understand — Continue")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 380)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(white: 0.12))
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.red.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 30)
            }
        }
    }

    // MARK: - Action Confirmation Overlay

    @ViewBuilder
    private var actionConfirmationOverlay: some View {
        if flow.showingActionConfirmation, let action = flow.pendingAction {
            // Destructive actions require the operator to type ERASE to confirm.
            let canConfirm = !action.isDestructive
                || flow.confirmationText.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare("ERASE") == .orderedSame

            ZStack {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) {
                            flow.dismissConfirmation()
                        }
                    }

                VStack(spacing: 0) {
                    // Warning header. Destructive actions carry the same red
                    // treatment as the stage-1 danger warning — octagon, red
                    // heading, red card border — so the severity doesn't drop
                    // off between the two steps of one flow.
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(action.iconColor.opacity(0.15))
                                .frame(width: action.isDestructive ? 64 : 56,
                                       height: action.isDestructive ? 64 : 56)

                            Image(systemName: destructiveConfirmIcon(for: action))
                                .font(.system(size: action.isDestructive ? 32 : 28))
                                .foregroundColor(action.iconColor)
                        }

                        if action.isDestructive {
                            Text("Destructive Action")
                                .font(.system(size: 19, weight: .bold))
                                .foregroundColor(.red)
                        }

                        // Titled with the ui-domain label override so a renamed
                        // action reads the same here as in the menu. Only the
                        // name follows the override — the body copy below and
                        // the typed-ERASE gate stay built-in.
                        Text(ActionBranding.confirmationTitle(for: action))
                            .font(.system(size: action.isDestructive ? 15 : 18,
                                          weight: .semibold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                    .padding(.horizontal, 24)

                    Text(confirmationMessage(for: action))
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)
                        .padding(.bottom, action.isDestructive ? 16 : 8)

                    if action.isDestructive {
                        // Same red target card as stage 1 — the operator sees
                        // exactly which Mac they are erasing at both steps.
                        VStack(spacing: 4) {
                            Text(computer.displayName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)

                            if let serial = computer.serialNumber {
                                Text(serial)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.red.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.red.opacity(0.25), lineWidth: 1)
                        )
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                    } else {
                        Text(computer.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.bottom, 24)
                    }

                    // Typed confirmation for destructive actions.
                    if action.isDestructive {
                        VStack(spacing: 6) {
                            Text("Type ERASE to confirm:")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                            TextField("ERASE", text: $flow.confirmationText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white.opacity(0.08))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(canConfirm ? Color.green.opacity(0.6) : Color.white.opacity(0.15), lineWidth: 1)
                                )
                                .frame(width: 260)
                        }
                        .padding(.bottom, 24)
                    }

                    Divider()
                        .background(Color.white.opacity(0.1))

                    // Buttons
                    HStack(spacing: 0) {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                flow.dismissConfirmation()
                            }
                        } label: {
                            Text("Cancel")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                        .buttonStyle(.plain)

                        Divider()
                            .background(Color.white.opacity(0.1))
                            .frame(height: 50)

                        Button {
                            let actionToExecute = action
                            withAnimation(.easeOut(duration: 0.2)) {
                                flow.dismissConfirmation()
                            }
                            flow.execute(actionToExecute, with: executor, openURL: openURL)
                        } label: {
                            Text(action.confirmButtonTitle)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(canConfirm ? (action.isDestructive ? .red : (action.isWarning ? .orange : .blue)) : .gray)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canConfirm)
                    }
                }
                // Destructive dialogs match stage 1's width and red border so
                // the two steps read as one flow rather than two dialogs.
                .frame(width: action.isDestructive ? 380 : 320)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(white: 0.12))
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(action.isDestructive ? Color.red.opacity(0.35) : Color.white.opacity(0.1),
                                lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 30)
            }
        }
    }

    /// Header symbol for the confirmation dialog: destructive actions get the
    /// stage-1 octagon, other warnings the triangle, everything else its own
    /// action icon.
    private func destructiveConfirmIcon(for action: DeviceAction) -> String {
        if action.isDestructive { return "exclamationmark.octagon.fill" }
        if action.isWarning { return "exclamationmark.triangle.fill" }
        return action.icon
    }

    /// Return to Service's confirmation copy is composed from the steps that
    /// will actually run — it never promises a disabled or unconfigured step.
    /// All other actions use their built-in copy. The typed-name confirmation
    /// for destructive actions is a permanent safeguard and is never relaxed.
    private func confirmationMessage(for action: DeviceAction) -> String {
        guard action == .returnToService else { return action.message }

        // Use the plan snapshotted when the dialog opened (DeviceActionFlow.trigger) so
        // the copy and the execution can never diverge mid-dialog.
        let options = flow.pendingRTSPlan?.options
            ?? DeviceActionPolicy.currentForComputers.returnToServiceOptions()
        let entraConfigured = flow.pendingRTSPlan?.entraConfigured
            ?? configManager.configuration.isEntraConfigured

        var cleanupSteps: [String] = []
        if options.effectiveDeleteJamfRecord {
            cleanupSteps.append("remove its record from Jamf Pro")
        }
        if options.effectiveDeleteEntraObject && entraConfigured {
            cleanupSteps.append("delete its device object from Microsoft Entra so the device can re-enroll cleanly")
        }

        // Disclose what the policy deliberately keeps, so an operator who
        // knows RTS as "full decommission" isn't surprised post-erase.
        var kept: [String] = []
        if !options.effectiveDeleteJamfRecord { kept.append("Jamf Pro record") }
        if !options.effectiveDeleteEntraObject { kept.append("Entra device object") }
        let keptSentence = kept.isEmpty
            ? ""
            : " The device's \(kept.joined(separator: " and ")) will be kept."

        if cleanupSteps.isEmpty {
            return "This will erase all data on the device and wait for the device to acknowledge the erase — no cleanup steps will run.\(keptSentence) This action cannot be undone."
        }

        let steps = ["erase all data on the device (the device must acknowledge the erase before any cleanup step runs)"] + cleanupSteps
        let numbered = steps.enumerated().map { "(\($0.offset + 1)) \($0.element)" }
        let joined = numbered.count == 2
            ? "\(numbered[0]) and \(numbered[1])"
            : numbered.dropLast().joined(separator: ", ") + ", and \(numbered[numbered.count - 1])"
        return "This will \(joined).\(keptSentence) This action cannot be undone."
    }

    // MARK: - Unlock Account Overlay
    
    @ViewBuilder
    private var unlockAccountOverlay: some View {
        if flow.showingUnlockAccountSheet {
            ZStack {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) {
                            flow.showingUnlockAccountSheet = false
                            flow.unlockUsername = ""
                        }
                    }
                
                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.15))
                                .frame(width: 56, height: 56)
                            
                            Image(systemName: "person.badge.key")
                                .font(.system(size: 24))
                                .foregroundColor(.blue)
                        }
                        
                        Text("Unlock User Account")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                    
                    Text("Enter the username of the account to unlock on \(computer.displayName).")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                    
                    // Username field
                    TextField("Username", text: $flow.unlockUsername)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                    
                    // Buttons
                    HStack(spacing: 0) {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                flow.showingUnlockAccountSheet = false
                                flow.unlockUsername = ""
                            }
                        } label: {
                            Text("Cancel")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                        .buttonStyle(.plain)
                        
                        Divider()
                            .background(Color.white.opacity(0.1))
                            .frame(height: 50)
                        
                        Button {
                            let username = flow.unlockUsername
                            withAnimation(.easeOut(duration: 0.2)) {
                                flow.showingUnlockAccountSheet = false
                                flow.unlockUsername = ""
                            }
                            Task { await executor.sendUnlockAccountCommand(username: username) }
                        } label: {
                            Text("Unlock")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(flow.unlockUsername.isEmpty ? .gray : .blue)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                        .buttonStyle(.plain)
                        .disabled(flow.unlockUsername.isEmpty)
                    }
                }
                .frame(width: 340)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(white: 0.12))
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 30)
            }
        }
    }
}
