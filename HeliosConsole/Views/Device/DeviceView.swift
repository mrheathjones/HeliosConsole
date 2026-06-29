//
//  DeviceView.swift
//  Helios
//
//  Comprehensive device detail view for computer inventory
//

import SwiftUI
// AppKit removed - using pure SwiftUI

struct DeviceView: View {
    let computer: Computer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject private var actionLogService = ActionLogService.shared
    @State private var selectedSection: DeviceSection = .overview
    @State private var searchText: String = ""
    
    // State for loading full details
    @State private var fullComputer: Computer?
    @State private var isLoadingDetails: Bool = false
    @State private var loadError: String?
    
    // MARK: - Search State for Each Section
    @State private var profilesSearchText: String = ""
    @State private var localAccountsSearchText: String = ""
    @State private var certificatesSearchText: String = ""
    @State private var printersSearchText: String = ""
    @State private var groupsSearchText: String = ""
    @State private var extensionAttributesSearchText: String = ""
    
    // MARK: - Filter State
    // Local Accounts filters (default ON to show only Admin/FileVault users)
    @State private var filterAdminAccounts: Bool = true
    @State private var filterFileVaultAccounts: Bool = true
    
    // Groups filters
    @State private var filterSmartGroups: Bool = true
    @State private var filterStaticGroups: Bool = true
    
    // Certificates filter
    enum CertificateFilter: String, CaseIterable {
        case all = "All"
        case valid = "Valid"
        case expiring = "Expiring"
        case expired = "Expired"
    }
    @State private var certificateFilter: CertificateFilter = .all
    
    // MARK: - Pagination State
    @State private var applicationsPage: Int = 1
    @State private var profilesPage: Int = 1
    @State private var localAccountsPage: Int = 1
    @State private var certificatesPage: Int = 1
    @State private var printersPage: Int = 1
    @State private var groupsPage: Int = 1
    @State private var extensionAttributesPage: Int = 1
    
    // MARK: - Popover State
    @State private var showingUpdatesPopover: Bool = false
    
    // MARK: - MDM Command State
    @State private var isExecutingCommand: Bool = false
    @State private var commandResult: CommandResult?
    @State private var showingCommandAlert: Bool = false
    @State private var showingActionConfirmation: Bool = false
    @State private var pendingAction: DeviceAction?
    @State private var showingUnlockAccountSheet: Bool = false
    @State private var unlockUsername: String = ""
    @State private var showingLocalAdminPassword: Bool = false
    @State private var localAdminPassword: String = ""
    @State private var localAdminUsername: String = ""
    @State private var showingFileVaultKey: Bool = false
    @State private var fileVaultKey: String = ""
    @State private var fileVaultKeyStatus: String = ""
    @State private var fileVaultEncryptionState: String = ""
    
    enum DeviceAction {
        case enableBluetooth
        case disableBluetooth
        case enableRemoteDesktop
        case disableRemoteDesktop
        case restart
        case restartSilent
        case shutdown
        case returnToService
        case viewLocalAdminPassword
        case viewFileVaultKey
        case sendBlankPush
        case screenShare
        
        var title: String {
            switch self {
            case .enableBluetooth: return "Enable Bluetooth?"
            case .disableBluetooth: return "Disable Bluetooth?"
            case .enableRemoteDesktop: return "Enable Remote Desktop?"
            case .disableRemoteDesktop: return "Disable Remote Desktop?"
            case .restart: return "Restart Device?"
            case .restartSilent: return "Restart Device (Silent)?"
            case .shutdown: return "Shutdown Device?"
            case .returnToService: return "Return to Service?"
            case .viewLocalAdminPassword: return "View Local Admin Password?"
            case .viewFileVaultKey: return "View FileVault Recovery Key?"
            case .sendBlankPush: return "Send Blank Push?"
            case .screenShare: return "Screen Share?"
            }
        }
        
        var message: String {
            switch self {
            case .enableBluetooth: return "This will enable Bluetooth on the device."
            case .disableBluetooth: return "This will disable Bluetooth on the device. Any connected Bluetooth devices (keyboards, mice, trackpads, headsets) will be disconnected."
            case .enableRemoteDesktop: return "This will enable Remote Desktop (Screen Sharing) on the device, allowing remote connections."
            case .disableRemoteDesktop: return "This will disable Remote Desktop (Screen Sharing) on the device. Any active remote sessions will be disconnected."
            case .restart: return "This will restart the device and notify the user. Any unsaved work may be lost."
            case .restartSilent: return "This will restart the device without notifying the user. Any unsaved work may be lost."
            case .shutdown: return "This will shut down the device. The user will need physical access to turn it back on."
            case .returnToService: return "This will erase all data on the device and prepare it for reassignment. This action cannot be undone."
            case .viewLocalAdminPassword: return "This will retrieve and display the local administrator password for this device. This action is logged for security auditing."
            case .viewFileVaultKey: return "This will retrieve and display the FileVault personal recovery key for this device. This key can be used to unlock the encrypted disk. This action is logged for security auditing."
            case .sendBlankPush: return "This will send an APNs (Apple Push Notification) to the device, prompting it to check in with Jamf Pro. Use this to verify device connectivity or to trigger pending MDM commands."
            case .screenShare: return "This will open a screen sharing session to the device using Apple's built-in Screen Sharing app. If the device is on VPN, the VPN IP address will be used."
            }
        }
        
        var icon: String {
            switch self {
            case .enableBluetooth: return "antenna.radiowaves.left.and.right"
            case .disableBluetooth: return "antenna.radiowaves.left.and.right.slash"
            case .enableRemoteDesktop: return "desktopcomputer.and.arrow.down"
            case .disableRemoteDesktop: return "desktopcomputer.trianglebadge.exclamationmark"
            case .restart, .restartSilent: return "arrow.clockwise.circle"
            case .shutdown: return "power"
            case .returnToService: return "arrow.counterclockwise.circle"
            case .viewLocalAdminPassword: return "key.fill"
            case .viewFileVaultKey: return "lock.shield"
            case .sendBlankPush: return "bell.badge"
            case .screenShare: return "shared.with.you"
            }
        }
        
        var iconColor: Color {
            switch self {
            case .enableBluetooth, .enableRemoteDesktop: return .blue
            case .disableBluetooth, .disableRemoteDesktop: return .orange
            case .restart, .restartSilent: return .orange
            case .shutdown: return .orange
            case .returnToService: return .red
            case .viewLocalAdminPassword: return .purple
            case .viewFileVaultKey: return .green
            case .sendBlankPush: return .blue
            case .screenShare: return .cyan
            }
        }
        
        var confirmButtonTitle: String {
            switch self {
            case .enableBluetooth: return "Enable"
            case .disableBluetooth: return "Disable"
            case .enableRemoteDesktop: return "Enable"
            case .disableRemoteDesktop: return "Disable"
            case .restart, .restartSilent: return "Restart"
            case .shutdown: return "Shutdown"
            case .returnToService: return "Erase & Return"
            case .viewLocalAdminPassword: return "View Password"
            case .viewFileVaultKey: return "View Key"
            case .sendBlankPush: return "Send Push"
            case .screenShare: return "Connect"
            }
        }
        
        var isDestructive: Bool {
            switch self {
            case .returnToService: return true
            default: return false
            }
        }
        
        var isWarning: Bool {
            switch self {
            case .disableBluetooth, .disableRemoteDesktop, .restart, .restartSilent, .shutdown, .viewLocalAdminPassword, .viewFileVaultKey: return true
            default: return false
            }
        }
        
        var logName: String {
            switch self {
            case .enableBluetooth: return "Enable Bluetooth"
            case .disableBluetooth: return "Disable Bluetooth"
            case .enableRemoteDesktop: return "Enable Remote Desktop"
            case .disableRemoteDesktop: return "Disable Remote Desktop"
            case .restart: return "Restart Device"
            case .restartSilent: return "Restart Device (Silent)"
            case .shutdown: return "Shutdown Device"
            case .returnToService: return "Return to Service"
            case .viewLocalAdminPassword: return "View Local Admin Password"
            case .viewFileVaultKey: return "View FileVault Key"
            case .sendBlankPush: return "Send Blank Push"
            case .screenShare: return "Screen Share"
            }
        }
        
        var logCategory: String {
            switch self {
            case .enableBluetooth, .disableBluetooth, .enableRemoteDesktop, .disableRemoteDesktop:
                return "Device Settings"
            case .restart, .restartSilent, .shutdown, .returnToService, .screenShare:
                return "Device Actions"
            case .viewLocalAdminPassword, .viewFileVaultKey:
                return "Security"
            case .sendBlankPush:
                return "Inventory"
            }
        }
    }
    
    struct CommandResult {
        let success: Bool
        let title: String
        let message: String
    }
    
    private let itemsPerPage: Int = 25
    
    // The computer to display - use full details if loaded, otherwise initial
    private var displayComputer: Computer {
        fullComputer ?? computer
    }
    
    var body: some View {
        ZStack {
            // Background
            AnimatedBackgroundView(animate: .constant(true))
            
            if isLoadingDetails {
                // Loading state
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text("Loading device details...")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                // Error state with fallback to show partial data
                VStack(spacing: 0) {
                    // Header
                    deviceHeader
                    
                    // Show error banner but still show content
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Some details may be incomplete: \(error)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
                    
                    // Content
                    HStack(spacing: 0) {
                        sectionSidebar
                        Rectangle()
                            .fill(Color.white.opacity(0.05))
                            .frame(width: 1)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                sectionContent
                            }
                            .padding(32)
                        }
                    }
                }
            } else {
                VStack(spacing: 0) {
                    // Header
                    deviceHeader
                    
                    // Content
                    HStack(spacing: 0) {
                        // Section Navigation
                        sectionSidebar
                        
                        // Divider
                        Rectangle()
                            .fill(Color.white.opacity(0.05))
                            .frame(width: 1)
                        
                        // Detail Content
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                sectionContent
                            }
                            .padding(32)
                        }
                    }
                }
            }
            
            // Command result overlay
            commandResultOverlay
            
            // Action confirmation overlay
            actionConfirmationOverlay
            
            // Unlock account sheet overlay
            unlockAccountOverlay
            
            // Local admin password overlay
            localAdminPasswordOverlay
            
            // FileVault key overlay
            fileVaultKeyOverlay
        }
        .navigationBarBackButtonHidden(true)
        .task {
            await loadFullDetails()
        }
    }
    
    // MARK: - FileVault Key Overlay
    
    @ViewBuilder
    private var fileVaultKeyOverlay: some View {
        if showingFileVaultKey {
            ZStack {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showingFileVaultKey = false
                            fileVaultKey = ""
                            fileVaultKeyStatus = ""
                            fileVaultEncryptionState = ""
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
                        
                        Text(displayComputer.displayName)
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
                            
                            Text(fileVaultKey)
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(fileVaultKey, forType: .string)
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
                                    .fill(fileVaultKeyStatus == "VALID" ? Color.green : Color.orange)
                                    .frame(width: 8, height: 8)
                                Text(fileVaultKeyStatus.capitalized)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(fileVaultKeyStatus == "VALID" ? .green : .orange)
                            }
                            
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(8)
                        
                        // Encryption State row
                        if !fileVaultEncryptionState.isEmpty {
                            HStack {
                                Text("Encryption")
                                    .font(.system(size: 13))
                                    .foregroundColor(.gray)
                                    .frame(width: 100, alignment: .leading)
                                
                                Text(formatEncryptionState(fileVaultEncryptionState))
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
                            showingFileVaultKey = false
                            fileVaultKey = ""
                            fileVaultKeyStatus = ""
                            fileVaultEncryptionState = ""
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
        if showingLocalAdminPassword {
            ZStack {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showingLocalAdminPassword = false
                            localAdminPassword = ""
                            localAdminUsername = ""
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
                        
                        Text(displayComputer.displayName)
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
                            
                            Text(localAdminUsername)
                                .font(.system(size: 15, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(localAdminUsername, forType: .string)
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
                            
                            Text(localAdminPassword)
                                .font(.system(size: 15, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(localAdminPassword, forType: .string)
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
                            showingLocalAdminPassword = false
                            localAdminPassword = ""
                            localAdminUsername = ""
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
    
    // MARK: - Action Confirmation Overlay
    
    @ViewBuilder
    private var actionConfirmationOverlay: some View {
        if showingActionConfirmation, let action = pendingAction {
            ZStack {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showingActionConfirmation = false
                            pendingAction = nil
                        }
                    }
                
                VStack(spacing: 0) {
                    // Warning header
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(action.iconColor.opacity(0.15))
                                .frame(width: 56, height: 56)
                            
                            Image(systemName: (action.isDestructive || action.isWarning) ? "exclamationmark.triangle.fill" : action.icon)
                                .font(.system(size: 28))
                                .foregroundColor(action.iconColor)
                        }
                        
                        Text(action.title)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                    
                    Text(action.message)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                    
                    Text(displayComputer.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.bottom, 24)
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                    
                    // Buttons
                    HStack(spacing: 0) {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                showingActionConfirmation = false
                                pendingAction = nil
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
                                showingActionConfirmation = false
                                pendingAction = nil
                            }
                            Task { await executeAction(actionToExecute) }
                        } label: {
                            Text(action.confirmButtonTitle)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(action.isDestructive ? .red : (action.isWarning ? .orange : .blue))
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                        .buttonStyle(.plain)
                    }
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
    
    private func executeAction(_ action: DeviceAction) async {
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
        case .returnToService:
            await sendEraseCommand()
        case .viewLocalAdminPassword:
            await fetchLocalAdminPassword()
        case .viewFileVaultKey:
            await fetchFileVaultKey()
        case .sendBlankPush:
            await sendBlankPushCommand()
        case .screenShare:
            await launchScreenShare()
            return // Screen Share handles its own logging
        }
        
        // Centralized logging for all MDM commands (except Screen Share which logs internally)
        if let result = commandResult {
            ActionLogService.shared.logAction(
                actionName: action.logName,
                actionCategory: action.logCategory,
                deviceName: displayComputer.displayName,
                deviceSerialNumber: displayComputer.serialNumber ?? "Unknown",
                deviceId: displayComputer.id,
                success: result.success,
                errorMessage: result.success ? nil : result.message
            )
        }
    }
    
    // MARK: - Screen Share
    
    private func launchScreenShare() async {
        // Prefer VPN IP if available (EA_VPN_IP_ADDRESS is hardcoded — future: config profile)
        let vpnIP = getExtensionAttributeValue("EA_VPN_IP_ADDRESS")
        let hasVPN = vpnIP != nil && !vpnIP!.isEmpty && vpnIP!.uppercased() != "N/A"
        let targetIP = hasVPN ? vpnIP! : (displayComputer.ipAddress ?? "")
        
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
                deviceName: displayComputer.displayName,
                deviceSerialNumber: displayComputer.serialNumber ?? "Unknown",
                deviceId: displayComputer.id,
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
                deviceName: displayComputer.displayName,
                deviceSerialNumber: displayComputer.serialNumber ?? "Unknown",
                deviceId: displayComputer.id,
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
            deviceName: displayComputer.displayName,
            deviceSerialNumber: displayComputer.serialNumber ?? "Unknown",
            deviceId: displayComputer.id,
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
    
    // MARK: - Unlock Account Overlay
    
    @ViewBuilder
    private var unlockAccountOverlay: some View {
        if showingUnlockAccountSheet {
            ZStack {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showingUnlockAccountSheet = false
                            unlockUsername = ""
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
                    
                    Text("Enter the username of the account to unlock on \(displayComputer.displayName).")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                    
                    // Username field
                    TextField("Username", text: $unlockUsername)
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
                                showingUnlockAccountSheet = false
                                unlockUsername = ""
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
                            let username = unlockUsername
                            withAnimation(.easeOut(duration: 0.2)) {
                                showingUnlockAccountSheet = false
                                unlockUsername = ""
                            }
                            Task { await sendUnlockAccountCommand(username: username) }
                        } label: {
                            Text("Unlock")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(unlockUsername.isEmpty ? .gray : .blue)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                        .buttonStyle(.plain)
                        .disabled(unlockUsername.isEmpty)
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
    
    // MARK: - Load Full Details
    
    @MainActor
    private func loadFullDetails() async {
        // Check if we already have full details (applications is a good indicator)
        if computer.applications != nil && !(computer.applications?.isEmpty ?? true) {
            NSLog("📱 DeviceView: Already have full details for %@", computer.displayName)
            return
        }
        
        NSLog("📱 DeviceView: Loading full details for %@ (id: %@)", computer.displayName, computer.id)
        isLoadingDetails = true
        
        do {
            let searchService = ComputerSearchService()
            let fullDetails = try await searchService.fetchComputerDetails(id: computer.id)
            
            self.fullComputer = fullDetails
            self.isLoadingDetails = false
            NSLog("✅ DeviceView: Loaded full details - %d apps, %d profiles",
                  fullDetails.applications?.count ?? 0,
                  fullDetails.configurationProfiles?.count ?? 0)
        } catch {
            self.loadError = error.localizedDescription
            self.isLoadingDetails = false
            NSLog("❌ DeviceView: Failed to load details: %@", error.localizedDescription)
        }
    }
    
    // MARK: - Device Header
    
    private var deviceHeader: some View {
        HStack(spacing: 20) {
            // Circle back button
            Button {
                dismiss()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            
            // Device icon - larger and more prominent
            DeviceIconView(
                modelIdentifier: displayComputer.hardware?.modelIdentifier,
                modelName: displayComputer.modelName,
                size: 96
            )
            
            // Device info
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Text(displayComputer.displayName)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    
                    if displayComputer.isSupervised {
                        statusBadge("Supervised", color: .blue)
                    }
                    
                    if displayComputer.isManaged {
                        statusBadge("Managed", color: .green)
                    }
                    
                    if displayComputer.isFileVaultEnabled {
                        statusBadge("Encrypted", color: .purple)
                    }
                }
                
                HStack(spacing: 20) {
                    if let serial = displayComputer.serialNumber {
                        headerInfoItem(icon: nil, text: serial)
                    }
                    if let model = displayComputer.modelName {
                        headerInfoItem(icon: "desktopcomputer", text: model)
                    }
                    if let os = displayComputer.osVersion {
                        headerInfoItem(icon: "gear", text: "macOS \(os)")
                    }
                }
                
                // User info row
                if let username = displayComputer.assignedUserRealName ?? displayComputer.assignedUser {
                    HStack(spacing: 8) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 12))
                        Text(username)
                            .font(.system(size: 14))
                        
                        if let email = displayComputer.userAndLocation?.email {
                            Text("•")
                            Text(email)
                                .font(.system(size: 14))
                        }
                    }
                    .foregroundColor(.gray)
                    .padding(.top, 4)
                }
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 12) {
                // Refresh button
                Button {
                    Task {
                        await loadFullDetails()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isLoadingDetails {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .medium))
                        }
                        Text("Refresh")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isLoadingDetails)
                
                // Actions menu with MDM commands
                actionsMenu
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .background(Color.black.opacity(0.3))
    }
    
    // MARK: - Actions Menu
    
    private var actionsMenu: some View {
        Menu {
            // Device Settings section
            Section("Device Settings") {
                Button {
                    pendingAction = .enableBluetooth
                    showingActionConfirmation = true
                } label: {
                    Label("Enable Bluetooth", systemImage: "antenna.radiowaves.left.and.right")
                }
                
                Button {
                    pendingAction = .disableBluetooth
                    showingActionConfirmation = true
                } label: {
                    Label("Disable Bluetooth", systemImage: "antenna.radiowaves.left.and.right.slash")
                }
                
                Button {
                    pendingAction = .enableRemoteDesktop
                    showingActionConfirmation = true
                } label: {
                    Label("Enable Remote Desktop", systemImage: "desktopcomputer.and.arrow.down")
                }
                
                Button {
                    pendingAction = .disableRemoteDesktop
                    showingActionConfirmation = true
                } label: {
                    Label("Disable Remote Desktop", systemImage: "desktopcomputer.trianglebadge.exclamationmark")
                }
            }
            
            Divider()
            
            // Device Actions section
            Section("Device Actions") {
                if MDMConfigurationManager.shared.configuration.screenShareEnabled {
                    Button {
                        pendingAction = .screenShare
                        showingActionConfirmation = true
                    } label: {
                        Label("Screen Share", systemImage: "shared.with.you")
                    }
                }
                
                Button {
                    pendingAction = .restart
                    showingActionConfirmation = true
                } label: {
                    Label("Restart Device", systemImage: "arrow.clockwise.circle")
                }
                
                Button {
                    pendingAction = .restartSilent
                    showingActionConfirmation = true
                } label: {
                    Label("Restart Device (Silent)", systemImage: "arrow.clockwise.circle.fill")
                }
                
                Button {
                    pendingAction = .shutdown
                    showingActionConfirmation = true
                } label: {
                    Label("Shutdown Device", systemImage: "power")
                }
                
                Button(role: .destructive) {
                    pendingAction = .returnToService
                    showingActionConfirmation = true
                } label: {
                    Label("Return to Service", systemImage: "arrow.counterclockwise.circle")
                }
            }
            
            Divider()
            
            // Security section
            Section("Security") {
                Button {
                    pendingAction = .viewLocalAdminPassword
                    showingActionConfirmation = true
                } label: {
                    Label("Local Admin Password", systemImage: "key.fill")
                }
                
                Button {
                    pendingAction = .viewFileVaultKey
                    showingActionConfirmation = true
                } label: {
                    Label("FileVault Key", systemImage: "lock.shield")
                }
            }
            
            Divider()
            
            // User Management section
            Section("User Management") {
                Button {
                    showingUnlockAccountSheet = true
                } label: {
                    Label("Unlock User Account", systemImage: "person.badge.key")
                }
            }
            
            Divider()
            
            // Inventory section
            Section("Inventory") {
                Button {
                    // TODO: Implement
                } label: {
                    Label("Update Inventory", systemImage: "arrow.triangle.2.circlepath")
                }
                
                Button {
                    pendingAction = .sendBlankPush
                    showingActionConfirmation = true
                } label: {
                    Label("Send Blank Push", systemImage: "bell.badge")
                }
            }
            
        } label: {
            HStack(spacing: 6) {
                if isExecutingCommand {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 12, weight: .medium))
                }
                Text("Actions")
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .disabled(isExecutingCommand)
    }
    
    // MARK: - Command Result Alert Overlay
    
    @ViewBuilder
    private var commandResultOverlay: some View {
        if showingCommandAlert, let result = commandResult {
            ZStack {
                // Dimmed background
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showingCommandAlert = false
                            commandResult = nil
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
                            showingCommandAlert = false
                            commandResult = nil
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
    
    // MARK: - MDM Commands
    
    private func sendBluetoothCommand(enable: Bool) async {
        guard let managementId = displayComputer.general?.managementId else {
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
            request.timeoutInterval = 30
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = postData
            
            NSLog("📤 Sending Bluetooth command (enable: \(enable)) to device: \(displayComputer.displayName)")
            
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
                        message: "Bluetooth \(enable ? "enable" : "disable") command has been sent to \(displayComputer.displayName). The device will process this command shortly."
                    )
                    showingCommandAlert = true
                }
            } else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                NSLog("❌ Bluetooth command failed: \(errorMessage)")
                throw NSError(domain: "DeviceView", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned status \(httpResponse.statusCode): \(errorMessage)"])
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
    
    private func getBearerToken() async throws -> String {
        let config = MDMConfigurationManager.shared.configuration
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
            successMessage: "Remote Desktop \(enable ? "enable" : "disable") command has been sent to \(displayComputer.displayName)."
        )
    }
    
    // MARK: - Restart Command
    
    private func sendRestartCommand(notifyUser: Bool) async {
        guard let managementId = displayComputer.general?.managementId else {
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
                    message: "Restart command has been sent to \(displayComputer.displayName).\(notifyUser ? " The user will be notified." : "")"
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
            successMessage: "Shutdown command has been sent to \(displayComputer.displayName)."
        )
    }
    
    // MARK: - Erase Device Command
    
    private func sendEraseCommand() async {
        await MainActor.run { isExecutingCommand = true }
        
        do {
            let token = try await getBearerToken()
            let config = MDMConfigurationManager.shared.configuration
            
            // Use the dedicated erase endpoint for computers
            guard let url = URL(string: "\(config.jamfURL)/api/v1/computer-inventory/\(displayComputer.id)/erase") else {
                throw NSError(domain: "DeviceView", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            // Empty body or optional PIN - we'll send empty for now
            request.httpBody = "{}".data(using: .utf8)
            
            NSLog("📤 Sending Erase command to device: \(displayComputer.displayName) (id: \(displayComputer.id))")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "DeviceView", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }
            
            NSLog("📥 Erase command response status: \(httpResponse.statusCode)")
            
            if (200...299).contains(httpResponse.statusCode) {
                await MainActor.run {
                    isExecutingCommand = false
                    commandResult = CommandResult(
                        success: true,
                        title: "Erase Command Sent",
                        message: "Erase command has been queued for \(displayComputer.displayName). The device will be wiped."
                    )
                    showingCommandAlert = true
                }
            } else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                NSLog("❌ Erase command failed: \(errorMessage)")
                throw NSError(domain: "DeviceView", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned status \(httpResponse.statusCode): \(errorMessage)"])
            }
            
        } catch {
            NSLog("❌ Erase command error: \(error.localizedDescription)")
            await showError(error.localizedDescription)
        }
    }
    
    // MARK: - Unlock User Account Command
    
    private func sendUnlockAccountCommand(username: String) async {
        guard let managementId = displayComputer.general?.managementId else {
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
                    message: "Unlock account command for user '\(username)' has been sent to \(displayComputer.displayName)."
                )
                showingCommandAlert = true
            }
        } catch {
            await showError(error.localizedDescription)
        }
    }
    
    // MARK: - Helper Functions
    
    private func sendSimpleCommand(commandType: String, successMessage: String) async {
        guard let managementId = displayComputer.general?.managementId else {
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
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = postData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "DeviceView", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "DeviceView", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned status \(httpResponse.statusCode): \(errorMessage)"])
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
        guard let managementId = displayComputer.general?.managementId else {
            await showError("Device management ID not available")
            return
        }
        
        let config = MDMConfigurationManager.shared.configuration
        let username = config.localAdminUsername
        
        await MainActor.run { isExecutingCommand = true }
        
        do {
            let token = try await getBearerToken()
            let jamfURL = config.jamfURL
            
            // Build the LAPS API URL
            guard let url = URL(string: "\(jamfURL)/api/v2/local-admin-password/\(managementId)/account/\(username)/password") else {
                throw NSError(domain: "DeviceView", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 30
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            NSLog("📤 Fetching local admin password for device: \(displayComputer.displayName) (managementId: \(managementId), user: \(username))")
            
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
        let deviceId = displayComputer.id
        
        await MainActor.run { isExecutingCommand = true }
        
        do {
            let token = try await getBearerToken()
            let config = MDMConfigurationManager.shared.configuration
            let jamfURL = config.jamfURL
            
            // Build the FileVault API URL
            guard let url = URL(string: "\(jamfURL)/api/v3/computers-inventory/\(deviceId)/filevault") else {
                throw NSError(domain: "DeviceView", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 30
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            NSLog("📤 Fetching FileVault key for device: \(displayComputer.displayName) (id: \(deviceId))")
            
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
        guard let managementId = displayComputer.general?.managementId else {
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
            request.timeoutInterval = 30
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = postData
            
            NSLog("📤 Sending Blank Push to device: \(displayComputer.displayName) (managementId: \(managementId))")
            
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
                        message: "An APNs notification has been sent to \(displayComputer.displayName). The device should check in shortly if it's online and reachable."
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
    
    private func statusBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(color))
    }
    
    private func headerInfoItem(icon: String?, text: String) -> some View {
        HStack(spacing: 6) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 12))
            }
            Text(text)
                .font(.system(size: 14))
        }
        .foregroundColor(.gray)
    }
    
    private func actionButton(icon: String, title: String) -> some View {
        Button {
            // Action
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(title)
                    .font(.system(size: 11))
            }
            .foregroundColor(.gray)
            .frame(width: 60, height: 50)
            .background(Color.white.opacity(0.05))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Section Sidebar
    
    private var sectionSidebar: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(DeviceSection.allCases, id: \.self) { section in
                    sectionButton(section)
                }
            }
            .padding(16)
        }
        .frame(width: 270)
        .background(Color.black.opacity(0.2))
    }
    
    private func sectionButton(_ section: DeviceSection) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedSection = section
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: section.icon)
                    .font(.system(size: 14))
                    .foregroundColor(selectedSection == section ? .blue : .gray)
                    .frame(width: 20)
                
                Text(section.title)
                    .font(.system(size: 14, weight: selectedSection == section ? .medium : .regular))
                
                Spacer()
                
                if let count = sectionItemCount(section) {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(10)
                }
                
                // Blue dot indicator for selected section
                if selectedSection == section {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                }
            }
            .foregroundColor(selectedSection == section ? .white : .gray)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedSection == section ? Color.blue.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func sectionItemCount(_ section: DeviceSection) -> Int? {
        switch section {
        case .applications:
            return displayComputer.applications?.count
        case .profiles:
            return displayComputer.configurationProfiles?.count
        case .localAccounts:
            return displayComputer.localUserAccounts?.count
        case .certificates:
            return displayComputer.certificates?.count
        case .printers:
            return displayComputer.printers?.count
        case .groupMemberships:
            return displayComputer.groupMemberships?.count
        case .extensionAttributes:
            return displayComputer.extensionAttributes?.count
        case .logs:
            let count = actionLogService.logs(forDeviceId: displayComputer.id).count
            return count > 0 ? count : nil
        default:
            return nil
        }
    }
    
    // MARK: - Section Content
    
    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .overview:
            overviewSection
        case .hardware:
            hardwareSection
        case .storage:
            storageSection
        case .security:
            securitySection
        case .operatingSystem:
            operatingSystemSection
        case .userAndLocation:
            userAndLocationSection
        case .applications:
            applicationsSection
        case .profiles:
            profilesSection
        case .localAccounts:
            localAccountsSection
        case .diskEncryption:
            diskEncryptionSection
        case .certificates:
            certificatesSection
        case .printers:
            printersSection
        case .purchasing:
            purchasingSection
        case .groupMemberships:
            groupMembershipsSection
        case .extensionAttributes:
            extensionAttributesSection
        case .management:
            managementSection
        case .logs:
            deviceLogsSection
        }
    }
    
    // MARK: - Overview Section
    
    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("Overview", icon: "square.grid.2x2")
            
            // Quick Stats - Row 1
            HStack(spacing: 16) {
                overviewStatCard(
                    title: "Last Check-in",
                    value: formatDate(displayComputer.general?.reportDate) ?? "N/A",
                    icon: "clock.fill",
                    color: .blue
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Battery Health card
                batteryHealthCard
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Storage card with bar graph
                storageCard
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // IP Address card
                ipAddressCard
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Available Updates card
                availableUpdatesCard
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 170)
            
            // Device Health Section
            DeviceHealthSection(computer: displayComputer)
            
            // General Info
            detailCard(title: "General Information", icon: "info.circle") {
                detailRow("Device Name", displayComputer.general?.name)
                detailRow("Serial Number", displayComputer.serialNumber)
                detailRow("UDID", displayComputer.udid)
                detailRow("Management ID", displayComputer.general?.managementId)
                detailRow("Asset Tag", displayComputer.general?.assetTag)
                detailRow("Site", displayComputer.general?.site?.name)
                detailRow("Platform", displayComputer.general?.platform)
                detailRow("Jamf Binary", displayComputer.general?.jamfBinaryVersion)
            }
            
            // Hardware Summary
            detailCard(title: "Hardware Summary", icon: "cpu") {
                detailRow("Model", displayComputer.modelName)
                detailRow("Model Identifier", displayComputer.hardware?.modelIdentifier)
                detailRow("Processor", displayComputer.processorDescription)
                detailRow("Architecture", displayComputer.hardware?.processorArchitecture)
                detailRow("Apple Silicon", displayComputer.isAppleSilicon ? "Yes" : "No")
                detailRow("Memory", displayComputer.totalRAMGB.map { "\(Int($0)) GB" })
            }
            
            // Security Summary
            detailCard(title: "Security Summary", icon: "shield.checkered") {
                detailRow("FileVault", displayComputer.isFileVaultEnabled ? "Enabled" : "Disabled")
                detailRow("SIP Status", displayComputer.security?.sipStatus)
                detailRow("Gatekeeper", formatGatekeeperStatus(displayComputer.security?.gatekeeperStatus))
                detailRow("Firewall", displayComputer.security?.firewallEnabled == true ? "Enabled" : "Disabled")
                detailRow("Secure Boot", displayComputer.security?.secureBootLevel)
            }
        }
    }
    
    // MARK: - Battery Health Card
    
    private var batteryHealthCard: some View {
        let batteryHealth = displayComputer.hardware?.batteryHealth
        let batteryCapacity = displayComputer.hardware?.batteryCapacityPercent
        
        // Determine if battery info is available (not unsupported/N/A and has valid capacity)
        let hasBattery = batteryHealth != nil &&
                         batteryHealth?.uppercased() != "UNSUPPORTED" &&
                         batteryCapacity != nil &&
                         batteryCapacity != -1
        
        let displayValue: String
        let healthColor: Color
        
        if hasBattery, let health = batteryHealth, let capacity = batteryCapacity {
            displayValue = "\(capacity)%"
            // Color based on health status
            switch health.uppercased() {
            case "NORMAL", "GOOD":
                healthColor = .green
            case "SERVICE_RECOMMENDED", "SERVICE RECOMMENDED":
                healthColor = .orange
            case "REPLACE_SOON", "REPLACE SOON":
                healthColor = .orange
            case "REPLACE_NOW", "REPLACE NOW", "SERVICE_BATTERY", "SERVICE BATTERY":
                healthColor = .red
            default:
                healthColor = .purple
            }
        } else {
            displayValue = "N/A"
            healthColor = .purple
        }
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: hasBattery ? "battery.100" : "battery.0")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(healthColor)
                Spacer()
            }
            
            Spacer()
            
            Text(displayValue)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            if hasBattery, let health = displayComputer.hardware?.batteryHealth {
                Text(formatBatteryHealth(health))
                    .font(.system(size: 10))
                    .foregroundColor(healthColor.opacity(0.8))
            }
            
            Spacer()
            
            Text("Battery Health")
                .font(.system(size: 12))
                .foregroundColor(.gray)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
                .background(.ultraThinMaterial.opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
    
    private func formatBatteryHealth(_ health: String) -> String {
        switch health.uppercased() {
        case "NORMAL", "GOOD": return "Normal"
        case "SERVICE_RECOMMENDED", "SERVICE RECOMMENDED": return "Service Recommended"
        case "REPLACE_SOON", "REPLACE SOON": return "Replace Soon"
        case "REPLACE_NOW", "REPLACE NOW": return "Replace Now"
        case "SERVICE_BATTERY", "SERVICE BATTERY": return "Service Battery"
        case "UNSUPPORTED": return "No Battery"
        default: return health
        }
    }
    
    // MARK: - Storage Card with Bar Graph
    
    private var storageCard: some View {
        // Get storage info - try to find boot drive partition or use disk info
        let availableMB = displayComputer.storage?.bootDriveAvailableSpaceMegabytes
        let totalMB = getBootDriveTotalSize()
        
        let availableGB = availableMB.map { Double($0) / 1024.0 }
        let totalGB = totalMB.map { Double($0) / 1024.0 }
        
        let usedPercentage: Double
        if let available = availableMB, let total = totalMB, total > 0 {
            usedPercentage = Double(total - available) / Double(total)
        } else {
            usedPercentage = 0
        }
        
        let usedPercentageInt = Int(usedPercentage * 100)
        
        // Color based on usage
        let barColor: Color = {
            if usedPercentage > 0.9 { return .red }
            if usedPercentage > 0.75 { return .orange }
            return .orange
        }()
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "internaldrive")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.orange)
                Spacer()
                
                // Percentage used badge
                if availableMB != nil && totalMB != nil {
                    Text("\(usedPercentageInt)% Used")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(barColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(barColor.opacity(0.2))
                        )
                }
            }
            
            Spacer()
            
            if let available = availableGB {
                Text(String(format: "%.1f GB", available))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text("N/A")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            // Storage bar graph
            if let _ = availableMB, let total = totalGB {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background bar
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 6)
                        
                        // Used space bar
                        RoundedRectangle(cornerRadius: 3)
                            .fill(barColor)
                            .frame(width: geometry.size.width * usedPercentage, height: 6)
                    }
                }
                .frame(height: 6)
                
                // Show total size
                Text(String(format: "of %.0f GB", total))
                    .font(.system(size: 10))
                    .foregroundColor(.gray.opacity(0.8))
            }
            
            Spacer()
            
            Text("Available Storage")
                .font(.system(size: 12))
                .foregroundColor(.gray)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
                .background(.ultraThinMaterial.opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
    
    private func getBootDriveTotalSize() -> Int? {
        // Try to get total size from the boot partition or first disk
        if let disks = displayComputer.storage?.disks {
            // Look for the boot partition in any disk
            for disk in disks {
                if let partitions = disk.partitions {
                    // Find partition named "Macintosh HD" or similar boot partition
                    if let bootPartition = partitions.first(where: {
                        $0.name?.lowercased().contains("macintosh") == true ||
                        $0.partitionType?.uppercased() == "BOOT"
                    }) {
                        return bootPartition.sizeMegabytes
                    }
                }
                // Fallback to disk size
                if let diskSize = disk.sizeMegabytes {
                    return diskSize
                }
            }
        }
        return nil
    }
    
    // MARK: - IP Address Card (VPN or Regular)
    
    private var ipAddressCard: some View {
        // Check for VPN IP extension attribute first
        let vpnIP = getExtensionAttributeValue("EA_VPN_IP_ADDRESS")
        // Only consider VPN valid if it has a value that's not empty or "N/A"
        let hasVPN = vpnIP != nil && !vpnIP!.isEmpty && vpnIP!.uppercased() != "N/A"
        
        let ipAddress = hasVPN ? vpnIP : displayComputer.ipAddress
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: hasVPN ? "lock.shield" : "network")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.green)
                Spacer()
                
                if hasVPN {
                    // VPN indicator badge
                    Text("VPN")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.green.opacity(0.2))
                        )
                }
            }
            
            Spacer()
            
            Text(ipAddress ?? "N/A")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Spacer()
            
            Text("IP Address")
                .font(.system(size: 12))
                .foregroundColor(.gray)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
                .background(.ultraThinMaterial.opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
    
    private func getExtensionAttributeValue(_ name: String) -> String? {
        // Check general extension attributes
        if let eas = displayComputer.general?.extensionAttributes {
            if let ea = eas.first(where: { $0.name == name }) {
                return ea.values?.first
            }
        }
        
        // Check top-level extension attributes
        if let eas = displayComputer.extensionAttributes {
            if let ea = eas.first(where: { $0.name == name }) {
                return ea.values?.first
            }
        }
        
        return nil
    }
    
    // MARK: - Available Updates Card
    
    private var availableUpdatesCard: some View {
        let updates = displayComputer.softwareUpdates ?? []
        let updateCount = updates.count
        
        let color: Color = updateCount > 0 ? .cyan : .green
        let icon = updateCount > 0 ? "arrow.down.circle" : "checkmark.circle"
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(color)
                Spacer()
                
                if updateCount > 0 {
                    // Updates available badge
                    Text("\(updateCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 18, height: 18)
                        .background(
                            Circle()
                                .fill(color)
                        )
                }
            }
            
            Spacer()
            
            Text(updateCount > 0 ? "\(updateCount) Available" : "Up to Date")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Spacer()
            
            Text("Updates")
                .font(.system(size: 12))
                .foregroundColor(.gray)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
                .background(.ultraThinMaterial.opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
        .onTapGesture {
            if updateCount > 0 {
                showingUpdatesPopover.toggle()
            }
        }
        .popover(isPresented: $showingUpdatesPopover, arrowEdge: .bottom) {
            updatesPopoverContent(updates: updates)
        }
    }
    
    private func updatesPopoverContent(updates: [SoftwareUpdate]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.cyan)
                Text("Available Updates")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
            }
            .padding(.bottom, 4)
            
            Divider()
            
            ForEach(updates) { update in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(update.name ?? "Unknown Update")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                        Spacer()
                        if let version = update.version {
                            Text(version)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let packageName = update.packageName {
                        Text(packageName)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
                
                if update.id != updates.last?.id {
                    Divider()
                }
            }
        }
        .padding(16)
        .frame(width: 350)
    }
    
    private func overviewStatCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(color)
                Spacer()
            }
            
            Spacer()
            
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Spacer()
            
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.gray)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
                .background(.ultraThinMaterial.opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
    
    // MARK: - Hardware Section
    
    private var hardwareSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("Hardware", icon: "cpu")
            
            detailCard(title: "System Information", icon: "desktopcomputer") {
                detailRow("Make", displayComputer.hardware?.make)
                detailRow("Model", displayComputer.hardware?.model)
                detailRow("Model Identifier", displayComputer.hardware?.modelIdentifier)
                detailRow("Serial Number", displayComputer.hardware?.serialNumber)
                detailRow("Provisioning UDID", displayComputer.hardware?.provisioningUdid)
            }
            
            detailCard(title: "Processor", icon: "cpu") {
                detailRow("Processor Type", displayComputer.hardware?.processorType)
                detailRow("Architecture", displayComputer.hardware?.processorArchitecture)
                detailRow("Processor Count", displayComputer.hardware?.processorCount.map { "\($0)" })
                detailRow("Core Count", displayComputer.hardware?.coreCount.map { "\($0)" })
                detailRow("Speed", displayComputer.hardware?.processorSpeedMhz.map { $0 > 0 ? "\($0) MHz" : "N/A" })
                detailRow("Apple Silicon", displayComputer.hardware?.appleSilicon == true ? "Yes" : "No")
            }
            
            detailCard(title: "Memory", icon: "memorychip") {
                detailRow("Total RAM", displayComputer.hardware?.totalRamMegabytes.map { "\($0 / 1024) GB" })
                detailRow("Open RAM Slots", displayComputer.hardware?.openRamSlots.map { "\($0)" })
                detailRow("Cache Size", displayComputer.hardware?.cacheSizeKilobytes.map { $0 > 0 ? "\($0) KB" : "N/A" })
            }
            
            detailCard(title: "Network", icon: "network") {
                detailRow("Ethernet Adapter", displayComputer.hardware?.networkAdapterType)
                detailRow("Ethernet MAC", displayComputer.hardware?.macAddress)
                detailRow("Ethernet Speed", displayComputer.hardware?.nicSpeed)
                detailRow("Wi-Fi Adapter", displayComputer.hardware?.altNetworkAdapterType)
                detailRow("Wi-Fi MAC", displayComputer.hardware?.altMacAddress)
            }
            
            detailCard(title: "System", icon: "gearshape") {
                detailRow("Boot ROM", displayComputer.hardware?.bootRom)
                detailRow("SMC Version", displayComputer.hardware?.smcVersion)
                detailRow("BLE Capable", displayComputer.hardware?.bleCapable == true ? "Yes" : "No")
                detailRow("Supports iOS Apps", displayComputer.hardware?.supportsIosAppInstalls == true ? "Yes" : "No")
            }
            
            if displayComputer.hardware?.batteryCapacityPercent ?? -1 >= 0 {
                detailCard(title: "Battery", icon: "battery.100") {
                    detailRow("Capacity", displayComputer.hardware?.batteryCapacityPercent.map { "\($0)%" })
                    detailRow("Health", displayComputer.hardware?.batteryHealth)
                }
            }
        }
    }
    
    // MARK: - Storage Section
    
    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("Storage", icon: "internaldrive")
            
            detailCard(title: "Boot Drive", icon: "internaldrive.fill") {
                detailRow("Available Space", displayComputer.storage?.bootDriveAvailableSpaceMegabytes.map { formatStorage($0) })
            }
            
            if let disks = displayComputer.storage?.disks {
                ForEach(disks, id: \.id) { disk in
                    detailCard(title: disk.device ?? "Disk", icon: "cylinder") {
                        detailRow("Model", disk.model)
                        detailRow("Serial Number", disk.serialNumber)
                        detailRow("Size", disk.sizeMegabytes.map { formatStorage($0) })
                        detailRow("Type", disk.type)
                        detailRow("SMART Status", disk.smartStatus)
                        detailRow("Revision", disk.revision)
                    }
                    
                    if let partitions = disk.partitions {
                        ForEach(partitions, id: \.id) { partition in
                            detailCard(title: partition.name ?? "Partition", icon: "square.split.bottomrightquarter") {
                                detailRow("Size", partition.sizeMegabytes.map { formatStorage($0) })
                                detailRow("Available", partition.availableMegabytes.map { formatStorage($0) })
                                detailRow("Used", partition.percentUsed.map { "\($0)%" })
                                detailRow("Type", partition.partitionType)
                                detailRow("FileVault State", partition.fileVault2State)
                                detailRow("LVM Managed", partition.lvmManaged == true ? "Yes" : "No")
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Security Section
    
    private var securitySection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("Security", icon: "shield.checkered")
            
            detailCard(title: "System Security", icon: "lock.shield") {
                detailRow("SIP Status", displayComputer.security?.sipStatus)
                detailRow("Gatekeeper", formatGatekeeperStatus(displayComputer.security?.gatekeeperStatus))
                detailRow("XProtect Version", displayComputer.security?.xprotectVersion)
                detailRow("Firewall", displayComputer.security?.firewallEnabled == true ? "Enabled" : "Disabled")
                detailRow("Auto Login", displayComputer.security?.autoLoginDisabled == true ? "Disabled" : "Enabled")
                detailRow("Remote Desktop", displayComputer.security?.remoteDesktopEnabled == true ? "Enabled" : "Disabled")
            }
            
            detailCard(title: "Boot Security", icon: "lock.rectangle") {
                detailRow("Secure Boot Level", displayComputer.security?.secureBootLevel)
                detailRow("External Boot Level", displayComputer.security?.externalBootLevel)
                detailRow("Activation Lock", displayComputer.security?.activationLockEnabled == true ? "Enabled" : "Disabled")
                detailRow("Recovery Lock", displayComputer.security?.recoveryLockEnabled == true ? "Enabled" : "Disabled")
            }
            
            detailCard(title: "Bootstrap Token", icon: "key") {
                detailRow("Allowed", displayComputer.security?.bootstrapTokenAllowed == true ? "Yes" : "No")
                detailRow("Escrow Status", displayComputer.security?.bootstrapTokenEscrowedStatus)
            }
            
            detailCard(title: "Attestation", icon: "checkmark.shield") {
                detailRow("Status", displayComputer.security?.attestationStatus)
                detailRow("Last Attempt", formatDate(displayComputer.security?.lastAttestationAttempt))
                detailRow("Last Success", formatDate(displayComputer.security?.lastSuccessfulAttestation))
            }
        }
    }
    
    // MARK: - Operating System Section
    
    private var operatingSystemSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("Operating System", icon: "apple.logo")
            
            detailCard(title: "macOS", icon: "apple.logo") {
                detailRow("Name", displayComputer.operatingSystem?.name)
                detailRow("Version", displayComputer.operatingSystem?.version)
                detailRow("Build", displayComputer.operatingSystem?.build)
                detailRow("Supplemental Build", displayComputer.operatingSystem?.supplementalBuildVersion)
                detailRow("Rapid Security Response", displayComputer.operatingSystem?.rapidSecurityResponse)
                detailRow("Software Update Device ID", displayComputer.operatingSystem?.softwareUpdateDeviceId)
            }
            
            detailCard(title: "Directory Services", icon: "person.2") {
                detailRow("Active Directory", displayComputer.operatingSystem?.activeDirectoryStatus)
                detailRow("FileVault 2 Status", displayComputer.operatingSystem?.fileVault2Status)
            }
            
            if let updates = displayComputer.softwareUpdates, !updates.isEmpty {
                detailCard(title: "Available Updates", icon: "arrow.down.circle") {
                    ForEach(updates, id: \.id) { update in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(update.name ?? "Unknown Update")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                if let packageName = update.packageName {
                                    Text(packageName)
                                        .font(.system(size: 11))
                                        .foregroundColor(.gray)
                                }
                            }
                            Spacer()
                            Text(update.version ?? "")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }
    
    // MARK: - User and Location Section
    
    private var userAndLocationSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("User & Location", icon: "person.fill")
            
            detailCard(title: "Assigned User", icon: "person") {
                detailRow("Username", displayComputer.userAndLocation?.username)
                detailRow("Full Name", displayComputer.userAndLocation?.realname)
                detailRow("Email", displayComputer.userAndLocation?.email)
                detailRow("Phone", displayComputer.userAndLocation?.phone)
                detailRow("Position", displayComputer.userAndLocation?.position)
            }
            
            detailCard(title: "Location", icon: "building.2") {
                detailRow("Department ID", displayComputer.userAndLocation?.departmentId)
                detailRow("Building ID", displayComputer.userAndLocation?.buildingId)
                detailRow("Room", displayComputer.userAndLocation?.room)
            }
            
            detailCard(title: "Last Login", icon: "clock") {
                detailRow("Self Service User", displayComputer.general?.lastLoggedInUsernameSelfService)
                detailRow("Self Service Time", formatDate(displayComputer.general?.lastLoggedInUsernameSelfServiceTimestamp))
                detailRow("Binary User", displayComputer.general?.lastLoggedInUsernameBinary)
                detailRow("Binary Time", formatDate(displayComputer.general?.lastLoggedInUsernameBinaryTimestamp))
            }
        }
    }
    
    // MARK: - Applications Section
    
    private var applicationsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("Applications (\(displayComputer.applications?.count ?? 0))", icon: "square.grid.2x2")
            
            if let apps = displayComputer.applications, !apps.isEmpty {
                // Search/filter bar
                searchBar(text: $searchText, placeholder: "Filter applications...")
                
                let filteredApps = searchText.isEmpty ? apps : apps.filter {
                    ($0.name ?? "").localizedCaseInsensitiveContains(searchText) ||
                    ($0.bundleId ?? "").localizedCaseInsensitiveContains(searchText)
                }
                
                // Pagination
                let totalPages = max(1, Int(ceil(Double(filteredApps.count) / Double(itemsPerPage))))
                let startIndex = (applicationsPage - 1) * itemsPerPage
                let endIndex = min(startIndex + itemsPerPage, filteredApps.count)
                let paginatedApps = Array(filteredApps[startIndex..<endIndex])
                
                LazyVStack(spacing: 8) {
                    ForEach(paginatedApps, id: \.id) { app in
                        applicationRow(app)
                    }
                }
                
                // Pagination controls
                if filteredApps.count > itemsPerPage {
                    paginationControls(
                        currentPage: $applicationsPage,
                        totalPages: totalPages,
                        totalItems: filteredApps.count,
                        startIndex: startIndex,
                        endIndex: endIndex
                    )
                }
            } else {
                emptyStateView("No applications found", icon: "app.badge")
            }
        }
        .onChange(of: searchText) { _, _ in
            applicationsPage = 1
        }
    }
    
    private func applicationRow(_ app: Application) -> some View {
        HStack(spacing: 16) {
            // App icon placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 44, height: 44)
                
                Image(systemName: app.macAppStore == true ? "apple.logo" : "app")
                    .font(.system(size: 18))
                    .foregroundColor(.gray)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(app.name ?? "Unknown")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    
                    if app.updateAvailable == true {
                        Text("Update Available")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                Text(app.version ?? app.cfBundleShortVersionString ?? "")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                
                if let bundleId = app.bundleId {
                    Text(bundleId)
                        .font(.system(size: 11))
                        .foregroundColor(.gray.opacity(0.7))
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                if let size = app.sizeMegabytes {
                    Text(formatStorage(size))
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                
                if app.macAppStore == true {
                    Text("App Store")
                        .font(.system(size: 10))
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
    
    // MARK: - Configuration Profiles Section
    
    private var profilesSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("Configuration Profiles (\(displayComputer.configurationProfiles?.count ?? 0))", icon: "doc.badge.gearshape")
            
            if let profiles = displayComputer.configurationProfiles, !profiles.isEmpty {
                // Search bar
                searchBar(text: $profilesSearchText, placeholder: "Filter profiles...")
                
                let filteredProfiles = profilesSearchText.isEmpty ? profiles : profiles.filter {
                    ($0.displayName ?? "").localizedCaseInsensitiveContains(profilesSearchText) ||
                    ($0.profileIdentifier ?? "").localizedCaseInsensitiveContains(profilesSearchText)
                }
                
                // Pagination
                let totalPages = max(1, Int(ceil(Double(filteredProfiles.count) / Double(itemsPerPage))))
                let startIndex = (profilesPage - 1) * itemsPerPage
                let endIndex = min(startIndex + itemsPerPage, filteredProfiles.count)
                let paginatedProfiles = Array(filteredProfiles[startIndex..<endIndex])
                
                LazyVStack(spacing: 8) {
                    ForEach(paginatedProfiles) { profile in
                        profileRow(profile)
                    }
                }
                
                // Pagination controls
                if filteredProfiles.count > itemsPerPage {
                    paginationControls(
                        currentPage: $profilesPage,
                        totalPages: totalPages,
                        totalItems: filteredProfiles.count,
                        startIndex: startIndex,
                        endIndex: endIndex
                    )
                }
            } else {
                emptyStateView("No configuration profiles", icon: "doc.badge.gearshape")
            }
        }
        .onChange(of: profilesSearchText) { _, _ in
            profilesPage = 1
        }
    }
    
    private func profileRow(_ profile: ConfigurationProfile) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: "doc.badge.gearshape.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayName ?? "Unknown Profile")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                if let identifier = profile.profileIdentifier {
                    Text(identifier)
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                if profile.removable == true {
                    Text("Removable")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                }
                
                if let installed = profile.lastInstalled {
                    Text(formatDate(installed) ?? "")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
    
    // MARK: - Local Accounts Section
    
    private var localAccountsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("Local User Accounts (\(displayComputer.localUserAccounts?.count ?? 0))", icon: "person.2")
            
            if let accounts = displayComputer.localUserAccounts, !accounts.isEmpty {
                // Search bar
                searchBar(text: $localAccountsSearchText, placeholder: "Filter accounts...")
                
                // Filter toggles
                HStack(spacing: 12) {
                    filterToggle(label: "Admin", isOn: $filterAdminAccounts, color: .orange)
                    filterToggle(label: "FileVault", isOn: $filterFileVaultAccounts, color: .purple)
                    
                    Spacer()
                    
                    // Show count of filtered vs total
                    let filteredCount = filteredLocalAccounts(from: accounts).count
                    if filteredCount != accounts.count {
                        Text("\(filteredCount) of \(accounts.count)")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                }
                
                let filteredAccounts = filteredLocalAccounts(from: accounts)
                
                if filteredAccounts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 32))
                            .foregroundColor(.gray.opacity(0.5))
                        Text("No accounts match filters")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                        Button("Clear Filters") {
                            filterAdminAccounts = false
                            filterFileVaultAccounts = false
                        }
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    // Pagination
                    let totalPages = max(1, Int(ceil(Double(filteredAccounts.count) / Double(itemsPerPage))))
                    let startIndex = (localAccountsPage - 1) * itemsPerPage
                    let endIndex = min(startIndex + itemsPerPage, filteredAccounts.count)
                    let paginatedAccounts = Array(filteredAccounts[startIndex..<endIndex])
                    
                    LazyVStack(spacing: 8) {
                        ForEach(paginatedAccounts) { account in
                            localAccountRow(account)
                        }
                    }
                    
                    // Pagination controls
                    if filteredAccounts.count > itemsPerPage {
                        paginationControls(
                            currentPage: $localAccountsPage,
                            totalPages: totalPages,
                            totalItems: filteredAccounts.count,
                            startIndex: startIndex,
                            endIndex: endIndex
                        )
                    }
                }
            } else {
                emptyStateView("No local user accounts", icon: "person.2")
            }
        }
        .onChange(of: localAccountsSearchText) { _, _ in
            localAccountsPage = 1
        }
        .onChange(of: filterAdminAccounts) { _, _ in
            localAccountsPage = 1
        }
        .onChange(of: filterFileVaultAccounts) { _, _ in
            localAccountsPage = 1
        }
    }
    
    private func filteredLocalAccounts(from accounts: [LocalUserAccount]) -> [LocalUserAccount] {
        var result = accounts
        
        // Apply search filter
        if !localAccountsSearchText.isEmpty {
            result = result.filter {
                ($0.fullName ?? "").localizedCaseInsensitiveContains(localAccountsSearchText) ||
                ($0.username ?? "").localizedCaseInsensitiveContains(localAccountsSearchText)
            }
        }
        
        // Apply Admin/FileVault filters (if any filter is active)
        if filterAdminAccounts || filterFileVaultAccounts {
            result = result.filter { account in
                let isAdmin = account.admin == true
                let hasFileVault = account.fileVault2Enabled == true
                
                if filterAdminAccounts && filterFileVaultAccounts {
                    return isAdmin || hasFileVault
                } else if filterAdminAccounts {
                    return isAdmin
                } else if filterFileVaultAccounts {
                    return hasFileVault
                }
                return true
            }
        }
        
        return result
    }
    
    private func localAccountRow(_ account: LocalUserAccount) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(account.admin == true ? Color.orange.opacity(0.1) : Color.blue.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: account.admin == true ? "person.badge.key.fill" : "person.fill")
                    .font(.system(size: 18))
                    .foregroundColor(account.admin == true ? .orange : .blue)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(account.fullName ?? account.username ?? "Unknown")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    
                    if account.admin == true {
                        Text("Admin")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(4)
                    }
                    
                    if account.fileVault2Enabled == true {
                        Text("FileVault")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.purple)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                Text(account.username ?? "")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                
                if let home = account.homeDirectory {
                    Text(home)
                        .font(.system(size: 11))
                        .foregroundColor(.gray.opacity(0.7))
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("UID: \(account.uid ?? "N/A")")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                
                if let size = account.homeDirectorySizeMb, size > 0 {
                    Text(formatStorage(size))
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
    
    // MARK: - Disk Encryption Section
    
    private var diskEncryptionSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("Disk Encryption", icon: "lock.doc")
            
            detailCard(title: "FileVault 2", icon: "lock.shield") {
                detailRow("Status", displayComputer.diskEncryption?.fileVault2Enabled == true ? "Enabled" : "Disabled")
                detailRow("Eligibility", displayComputer.diskEncryption?.fileVault2EligibilityMessage)
                detailRow("Recovery Key Status", displayComputer.diskEncryption?.individualRecoveryKeyValidityStatus)
                detailRow("Institutional Key", displayComputer.diskEncryption?.institutionalRecoveryKeyPresent == true ? "Present" : "Not Present")
                detailRow("Configuration", displayComputer.diskEncryption?.diskEncryptionConfigurationName)
            }
            
            if let users = displayComputer.diskEncryption?.fileVault2EnabledUserNames, !users.isEmpty {
                detailCard(title: "FileVault Enabled Users", icon: "person.badge.key") {
                    ForEach(users, id: \.self) { user in
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundColor(.blue)
                            Text(user)
                                .font(.system(size: 13))
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            
            if let boot = displayComputer.diskEncryption?.bootPartitionEncryptionDetails {
                detailCard(title: "Boot Partition", icon: "internaldrive") {
                    detailRow("Partition", boot.partitionName)
                    detailRow("State", boot.partitionFileVault2State)
                    detailRow("Encryption Progress", boot.partitionFileVault2Percent.map { "\($0)%" })
                }
            }
        }
    }
    
    // MARK: - Certificates Section
    
    private var certificatesSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("Certificates (\(displayComputer.certificates?.count ?? 0))", icon: "checkmark.seal")
            
            if let certs = displayComputer.certificates, !certs.isEmpty {
                // Search bar
                searchBar(text: $certificatesSearchText, placeholder: "Filter certificates...")
                
                // Status filter
                HStack(spacing: 12) {
                    ForEach(CertificateFilter.allCases, id: \.self) { filter in
                        Button {
                            certificateFilter = filter
                        } label: {
                            Text(filter.rawValue)
                                .font(.system(size: 12, weight: certificateFilter == filter ? .semibold : .regular))
                                .foregroundColor(certificateFilter == filter ? .white : .gray)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(certificateFilter == filter ? certificateFilterColor(filter).opacity(0.3) : Color.white.opacity(0.05))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer()
                }
                
                let filteredCerts = filteredCertificates(from: certs)
                
                if filteredCerts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 32))
                            .foregroundColor(.gray.opacity(0.5))
                        Text("No certificates match filters")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                        Button("Show All") {
                            certificateFilter = .all
                            certificatesSearchText = ""
                        }
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    // Pagination
                    let totalPages = max(1, Int(ceil(Double(filteredCerts.count) / Double(itemsPerPage))))
                    let startIndex = (certificatesPage - 1) * itemsPerPage
                    let endIndex = min(startIndex + itemsPerPage, filteredCerts.count)
                    let paginatedCerts = Array(filteredCerts[startIndex..<endIndex])
                    
                    LazyVStack(spacing: 8) {
                        ForEach(paginatedCerts) { cert in
                            certificateRow(cert)
                        }
                    }
                    
                    // Pagination controls
                    if filteredCerts.count > itemsPerPage {
                        paginationControls(
                            currentPage: $certificatesPage,
                            totalPages: totalPages,
                            totalItems: filteredCerts.count,
                            startIndex: startIndex,
                            endIndex: endIndex
                        )
                    }
                }
            } else {
                emptyStateView("No certificates found", icon: "checkmark.seal")
            }
        }
        .onChange(of: certificatesSearchText) { _, _ in
            certificatesPage = 1
        }
        .onChange(of: certificateFilter) { _, _ in
            certificatesPage = 1
        }
    }
    
    private func certificateFilterColor(_ filter: CertificateFilter) -> Color {
        switch filter {
        case .all: return .blue
        case .valid: return .green
        case .expiring: return .yellow
        case .expired: return .red
        }
    }
    
    private func filteredCertificates(from certs: [Certificate]) -> [Certificate] {
        var result = certs
        
        // Apply search filter
        if !certificatesSearchText.isEmpty {
            result = result.filter {
                ($0.commonName ?? "").localizedCaseInsensitiveContains(certificatesSearchText) ||
                ($0.subjectName ?? "").localizedCaseInsensitiveContains(certificatesSearchText)
            }
        }
        
        // Apply status filter
        switch certificateFilter {
        case .all:
            break
        case .valid:
            result = result.filter { $0.certificateStatus == "ISSUED" || $0.lifecycleStatus == "ACTIVE" }
        case .expiring:
            result = result.filter { cert in
                guard let expiryString = cert.expirationDate,
                      let expiryDate = ISO8601DateFormatter().date(from: expiryString) else {
                    return false
                }
                let thirtyDaysFromNow = Date().addingTimeInterval(30 * 24 * 60 * 60)
                return expiryDate > Date() && expiryDate <= thirtyDaysFromNow
            }
        case .expired:
            result = result.filter { cert in
                if cert.certificateStatus == "EXPIRED" {
                    return true
                }
                guard let expiryString = cert.expirationDate,
                      let expiryDate = ISO8601DateFormatter().date(from: expiryString) else {
                    return false
                }
                return expiryDate < Date()
            }
        }
        
        return result
    }
    
    private func certificateRow(_ cert: Certificate) -> some View {
        // Determine certificate status and color
        let (statusText, statusColor) = certificateStatusInfo(cert)
        
        return HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(statusColor.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: statusIcon(for: statusText))
                    .font(.system(size: 18))
                    .foregroundColor(statusColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(cert.commonName ?? "Unknown Certificate")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                if let subject = cert.subjectName {
                    Text(subject)
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                if let expiry = cert.expirationDate {
                    Text("Expires: \(formatDate(expiry) ?? expiry)")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
                
                Text(statusText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(statusColor)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
    
    private func certificateStatusInfo(_ cert: Certificate) -> (String, Color) {
        // Check if expired first
        if cert.certificateStatus?.uppercased() == "EXPIRED" {
            return ("EXPIRED", .red)
        }
        
        // Check expiration date
        if let expiryString = cert.expirationDate {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var expiryDate = formatter.date(from: expiryString)
            if expiryDate == nil {
                formatter.formatOptions = [.withInternetDateTime]
                expiryDate = formatter.date(from: expiryString)
            }
            
            if let expiry = expiryDate {
                // Check if expired
                if expiry < Date() {
                    return ("EXPIRED", .red)
                }
                
                // Check if expiring within 30 days
                let thirtyDaysFromNow = Date().addingTimeInterval(30 * 24 * 60 * 60)
                if expiry <= thirtyDaysFromNow {
                    return ("EXPIRING", .yellow)
                }
            }
        }
        
        // Valid certificate
        return ("VALID", .green)
    }
    
    private func statusIcon(for status: String) -> String {
        switch status {
        case "EXPIRED": return "xmark.seal.fill"
        case "EXPIRING": return "exclamationmark.triangle.fill"
        default: return "checkmark.seal.fill"
        }
    }
    
    // MARK: - Printers Section
    
    private var printersSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("Printers (\(displayComputer.printers?.count ?? 0))", icon: "printer")
            
            if let printers = displayComputer.printers, !printers.isEmpty {
                // Search bar
                searchBar(text: $printersSearchText, placeholder: "Filter printers...")
                
                let filteredPrinters = printersSearchText.isEmpty ? printers : printers.filter {
                    ($0.name ?? "").localizedCaseInsensitiveContains(printersSearchText) ||
                    ($0.location ?? "").localizedCaseInsensitiveContains(printersSearchText) ||
                    ($0.type ?? "").localizedCaseInsensitiveContains(printersSearchText)
                }
                
                if filteredPrinters.isEmpty {
                    emptyStateView("No printers match search", icon: "printer")
                } else {
                    // Pagination
                    let totalPages = max(1, Int(ceil(Double(filteredPrinters.count) / Double(itemsPerPage))))
                    let startIndex = (printersPage - 1) * itemsPerPage
                    let endIndex = min(startIndex + itemsPerPage, filteredPrinters.count)
                    let paginatedPrinters = Array(filteredPrinters[startIndex..<endIndex])
                    
                    LazyVStack(spacing: 8) {
                        ForEach(paginatedPrinters) { printer in
                            printerRow(printer)
                        }
                    }
                    
                    // Pagination controls
                    if filteredPrinters.count > itemsPerPage {
                        paginationControls(
                            currentPage: $printersPage,
                            totalPages: totalPages,
                            totalItems: filteredPrinters.count,
                            startIndex: startIndex,
                            endIndex: endIndex
                        )
                    }
                }
            } else {
                emptyStateView("No printers configured", icon: "printer")
            }
        }
        .onChange(of: printersSearchText) { _, _ in
            printersPage = 1
        }
    }
    
    private func printerRow(_ printer: Printer) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.cyan.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: "printer.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.cyan)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(printer.name ?? "Unknown Printer")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                if let type = printer.type {
                    Text(type)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                
                if let uri = printer.uri {
                    Text(uri)
                        .font(.system(size: 11))
                        .foregroundColor(.gray.opacity(0.7))
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            if let location = printer.location, !location.isEmpty {
                Text(location)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
    
    // MARK: - Purchasing Section
    
    private var purchasingSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("Purchasing", icon: "dollarsign.circle")
            
            detailCard(title: "Purchase Information", icon: "cart") {
                detailRow("Purchased", displayComputer.purchasing?.purchased == true ? "Yes" : "No")
                detailRow("Leased", displayComputer.purchasing?.leased == true ? "Yes" : "No")
                detailRow("PO Number", displayComputer.purchasing?.poNumber)
                detailRow("PO Date", displayComputer.purchasing?.poDate)
                detailRow("Purchase Price", displayComputer.purchasing?.purchasePrice)
                detailRow("Vendor", displayComputer.purchasing?.vendor)
            }
            
            detailCard(title: "Warranty & Support", icon: "shield") {
                detailRow("AppleCare ID", displayComputer.purchasing?.appleCareId)
                detailRow("Warranty Date", displayComputer.purchasing?.warrantyDate)
                detailRow("Lease Date", displayComputer.purchasing?.leaseDate)
                detailRow("Life Expectancy", displayComputer.purchasing?.lifeExpectancy.map { "\($0) months" })
            }
            
            detailCard(title: "Contacts", icon: "person.2") {
                detailRow("Purchasing Account", displayComputer.purchasing?.purchasingAccount)
                detailRow("Purchasing Contact", displayComputer.purchasing?.purchasingContact)
            }
        }
    }
    
    // MARK: - Group Memberships Section
    
    private var groupMembershipsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("Group Memberships (\(displayComputer.groupMemberships?.count ?? 0))", icon: "person.3")
            
            if let groups = displayComputer.groupMemberships, !groups.isEmpty {
                // Search bar
                searchBar(text: $groupsSearchText, placeholder: "Filter groups...")
                
                // Filter toggles
                HStack(spacing: 12) {
                    filterToggle(label: "Smart Groups", isOn: $filterSmartGroups, color: .purple)
                    filterToggle(label: "Static Groups", isOn: $filterStaticGroups, color: .blue)
                    
                    Spacer()
                    
                    let filteredCount = filteredGroups(from: groups).count
                    if filteredCount != groups.count {
                        Text("\(filteredCount) of \(groups.count)")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                }
                
                let filteredGroupsList = filteredGroups(from: groups)
                
                if filteredGroupsList.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 32))
                            .foregroundColor(.gray.opacity(0.5))
                        Text("No groups match filters")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                        Button("Show All") {
                            filterSmartGroups = true
                            filterStaticGroups = true
                            groupsSearchText = ""
                        }
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    // Pagination
                    let totalPages = max(1, Int(ceil(Double(filteredGroupsList.count) / Double(itemsPerPage))))
                    let startIndex = (groupsPage - 1) * itemsPerPage
                    let endIndex = min(startIndex + itemsPerPage, filteredGroupsList.count)
                    let paginatedGroups = Array(filteredGroupsList[startIndex..<endIndex])
                    
                    LazyVStack(spacing: 8) {
                        ForEach(paginatedGroups) { group in
                            groupRow(group)
                        }
                    }
                    
                    // Pagination controls
                    if filteredGroupsList.count > itemsPerPage {
                        paginationControls(
                            currentPage: $groupsPage,
                            totalPages: totalPages,
                            totalItems: filteredGroupsList.count,
                            startIndex: startIndex,
                            endIndex: endIndex
                        )
                    }
                }
            } else {
                emptyStateView("No group memberships", icon: "person.3")
            }
        }
        .onChange(of: groupsSearchText) { _, _ in
            groupsPage = 1
        }
        .onChange(of: filterSmartGroups) { _, _ in
            groupsPage = 1
        }
        .onChange(of: filterStaticGroups) { _, _ in
            groupsPage = 1
        }
    }
    
    private func filteredGroups(from groups: [GroupMembership]) -> [GroupMembership] {
        var result = groups
        
        // Apply search filter
        if !groupsSearchText.isEmpty {
            result = result.filter {
                ($0.groupName ?? "").localizedCaseInsensitiveContains(groupsSearchText)
            }
        }
        
        // Apply type filters
        if !filterSmartGroups || !filterStaticGroups {
            result = result.filter { group in
                let isSmart = group.smartGroup == true
                if filterSmartGroups && isSmart { return true }
                if filterStaticGroups && !isSmart { return true }
                return false
            }
        }
        
        return result
    }
    
    private func groupRow(_ group: GroupMembership) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(group.smartGroup == true ? Color.purple.opacity(0.1) : Color.blue.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: group.smartGroup == true ? "gearshape.2.fill" : "person.3.fill")
                    .font(.system(size: 18))
                    .foregroundColor(group.smartGroup == true ? .purple : .blue)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(group.groupName ?? "Unknown Group")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                Text("ID: \(group.groupId ?? "N/A")")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Text(group.smartGroup == true ? "Smart Group" : "Static Group")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(group.smartGroup == true ? .purple : .blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((group.smartGroup == true ? Color.purple : Color.blue).opacity(0.1))
                .cornerRadius(6)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
    
    // MARK: - Extension Attributes Section
    
    private var extensionAttributesSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("Extension Attributes (\(displayComputer.extensionAttributes?.count ?? 0))", icon: "list.bullet.rectangle")
            
            if let attrs = displayComputer.extensionAttributes, !attrs.isEmpty {
                // Search bar
                searchBar(text: $extensionAttributesSearchText, placeholder: "Filter extension attributes...")
                
                let filteredAttrs = extensionAttributesSearchText.isEmpty ? attrs : attrs.filter {
                    ($0.name ?? "").localizedCaseInsensitiveContains(extensionAttributesSearchText) ||
                    ($0.values?.joined(separator: " ") ?? "").localizedCaseInsensitiveContains(extensionAttributesSearchText)
                }
                
                if filteredAttrs.isEmpty {
                    emptyStateView("No attributes match search", icon: "list.bullet.rectangle")
                } else {
                    // Pagination
                    let totalPages = max(1, Int(ceil(Double(filteredAttrs.count) / Double(itemsPerPage))))
                    let startIndex = (extensionAttributesPage - 1) * itemsPerPage
                    let endIndex = min(startIndex + itemsPerPage, filteredAttrs.count)
                    let paginatedAttrs = Array(filteredAttrs[startIndex..<endIndex])
                    
                    LazyVStack(spacing: 8) {
                        ForEach(paginatedAttrs) { attr in
                            extensionAttributeRow(attr)
                        }
                    }
                    
                    // Pagination controls
                    if filteredAttrs.count > itemsPerPage {
                        paginationControls(
                            currentPage: $extensionAttributesPage,
                            totalPages: totalPages,
                            totalItems: filteredAttrs.count,
                            startIndex: startIndex,
                            endIndex: endIndex
                        )
                    }
                }
            } else {
                emptyStateView("No extension attributes", icon: "list.bullet.rectangle")
            }
        }
        .onChange(of: extensionAttributesSearchText) { _, _ in
            extensionAttributesPage = 1
        }
    }
    
    private func extensionAttributeRow(_ attr: ExtensionAttribute) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.indigo.opacity(0.1))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "tag.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.indigo)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(attr.name ?? "Unknown Attribute")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    
                    if let id = attr.definitionId {
                        Text("ID: \(id)")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                if let dataType = attr.dataType {
                    Text(dataType)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.indigo)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.indigo.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            
            // Value display
            if let values = attr.values, !values.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Value")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.gray)
                    
                    Text(values.joined(separator: ", "))
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(3)
                }
                .padding(.leading, 48)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
    
    // MARK: - Management Section
    
    private var managementSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeader("Management", icon: "gearshape.2")
            
            detailCard(title: "MDM Status", icon: "checkmark.circle") {
                detailRow("Managed", displayComputer.general?.remoteManagement?.managed == true ? "Yes" : "No")
                detailRow("Supervised", displayComputer.general?.supervised == true ? "Yes" : "No")
                detailRow("MDM Capable", displayComputer.general?.mdmCapable?.capable == true ? "Yes" : "No")
                detailRow("User Approved MDM", displayComputer.general?.userApprovedMdm == true ? "Yes" : "No")
                detailRow("DDM Enabled", displayComputer.general?.declarativeDeviceManagementEnabled == true ? "Yes" : "No")
            }
            
            detailCard(title: "Enrollment", icon: "arrow.down.circle") {
                detailRow("Method", displayComputer.general?.enrollmentMethod?.objectType)
                detailRow("ADE Enrolled", displayComputer.general?.enrolledViaAutomatedDeviceEnrollment == true ? "Yes" : "No")
                detailRow("Initial Entry", displayComputer.general?.initialEntryDate)
                detailRow("Last Enrolled", formatDate(displayComputer.general?.lastEnrolledDate))
                detailRow("MDM Profile Expiration", formatDate(displayComputer.general?.mdmProfileExpiration))
            }
            
            detailCard(title: "Check-in", icon: "clock") {
                detailRow("Last Contact", formatDate(displayComputer.general?.lastContactTime))
                detailRow("Last Report", formatDate(displayComputer.general?.reportDate))
                detailRow("Last Cloud Backup", formatDate(displayComputer.general?.lastCloudBackupDate))
            }
            
            if let capableUsers = displayComputer.general?.mdmCapable?.capableUsers, !capableUsers.isEmpty {
                detailCard(title: "MDM Capable Users", icon: "person.badge.shield.checkmark") {
                    ForEach(capableUsers, id: \.self) { user in
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundColor(.blue)
                            Text(user)
                                .font(.system(size: 13))
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Views
    
    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.blue, Color.cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
        }
    }
    
    private func detailCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.blue)
                
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray)
            }
            
            VStack(spacing: 12) {
                content()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
                .background(.ultraThinMaterial.opacity(0.3))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
    
    private func detailRow(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.gray)
                .frame(width: 180, alignment: .leading)
            
            Text(value ?? "N/A")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .textSelection(.enabled)
            
            Spacer()
        }
    }
    
    private func emptyStateView(_ message: String, icon: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.gray.opacity(0.4))
            
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
    
    // MARK: - Search & Filter Components
    
    private func searchBar(text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .foregroundColor(.white)
            
            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }
    
    private func filterToggle(label: String, isOn: Binding<Bool>, color: Color) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundColor(isOn.wrappedValue ? color : .gray)
                
                Text(label)
                    .font(.system(size: 12, weight: isOn.wrappedValue ? .medium : .regular))
                    .foregroundColor(isOn.wrappedValue ? .white : .gray)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isOn.wrappedValue ? color.opacity(0.2) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isOn.wrappedValue ? color.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func paginationControls(
        currentPage: Binding<Int>,
        totalPages: Int,
        totalItems: Int,
        startIndex: Int,
        endIndex: Int
    ) -> some View {
        HStack(spacing: 16) {
            // Items per page info
            Text("Showing \(startIndex + 1)-\(endIndex) of \(totalItems)")
                .font(.system(size: 12))
                .foregroundColor(.gray)
            
            Spacer()
            
            // Page navigation
            HStack(spacing: 8) {
                // First page
                Button {
                    currentPage.wrappedValue = 1
                } label: {
                    Image(systemName: "chevron.left.2")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(currentPage.wrappedValue > 1 ? .white : .gray.opacity(0.5))
                }
                .buttonStyle(.plain)
                .disabled(currentPage.wrappedValue <= 1)
                
                // Previous page
                Button {
                    currentPage.wrappedValue = max(1, currentPage.wrappedValue - 1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(currentPage.wrappedValue > 1 ? .white : .gray.opacity(0.5))
                }
                .buttonStyle(.plain)
                .disabled(currentPage.wrappedValue <= 1)
                
                // Page indicator
                Text("Page \(currentPage.wrappedValue) of \(totalPages)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(6)
                
                // Next page
                Button {
                    currentPage.wrappedValue = min(totalPages, currentPage.wrappedValue + 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(currentPage.wrappedValue < totalPages ? .white : .gray.opacity(0.5))
                }
                .buttonStyle(.plain)
                .disabled(currentPage.wrappedValue >= totalPages)
                
                // Last page
                Button {
                    currentPage.wrappedValue = totalPages
                } label: {
                    Image(systemName: "chevron.right.2")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(currentPage.wrappedValue < totalPages ? .white : .gray.opacity(0.5))
                }
                .buttonStyle(.plain)
                .disabled(currentPage.wrappedValue >= totalPages)
            }
        }
        .padding(.top, 16)
    }
    
    // MARK: - Formatting Helpers
    
    private func formatStorage(_ megabytes: Int) -> String {
        if megabytes >= 1024 * 1024 {
            return String(format: "%.2f TB", Double(megabytes) / (1024 * 1024))
        } else if megabytes >= 1024 {
            return String(format: "%.1f GB", Double(megabytes) / 1024)
        } else {
            return "\(megabytes) MB"
        }
    }
    
    private func formatDate(_ dateString: String?) -> String? {
        guard let dateString = dateString else { return nil }
        
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        var date = isoFormatter.date(from: dateString)
        if date == nil {
            isoFormatter.formatOptions = [.withInternetDateTime]
            date = isoFormatter.date(from: dateString)
        }
        
        // Try simple date format
        if date == nil {
            let simpleFormatter = DateFormatter()
            simpleFormatter.dateFormat = "yyyy-MM-dd"
            date = simpleFormatter.date(from: dateString)
        }
        
        guard let parsedDate = date else { return dateString }
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .short
        
        return displayFormatter.string(from: parsedDate)
    }
    
    private func formatGatekeeperStatus(_ status: String?) -> String? {
        guard let status = status else { return nil }
        switch status {
        case "APP_STORE_AND_IDENTIFIED_DEVELOPERS":
            return "App Store & Identified Developers"
        case "APP_STORE":
            return "App Store Only"
        case "ANYWHERE":
            return "Anywhere"
        case "DISABLED":
            return "Disabled"
        default:
            return status
        }
    }
    
    // MARK: - Device Action Logs Section
    
    private var deviceLogsSection: some View {
        let deviceLogs = actionLogService.logs(forDeviceId: displayComputer.id)
        
        return VStack(alignment: .leading, spacing: 24) {
            sectionHeader("Action Logs", icon: "doc.text.magnifyingglass")
            
            if deviceLogs.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.gray.opacity(0.4))
                    Text("No actions logged yet")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.gray)
                    Text("Actions performed on this device will appear here for auditing.")
                        .font(.system(size: 13))
                        .foregroundColor(.gray.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            } else {
                VStack(spacing: 8) {
                    ForEach(deviceLogs) { entry in
                        HStack(spacing: 12) {
                            // Status indicator
                            Circle()
                                .fill(entry.success ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            
                            // Action info
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(entry.actionName)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white)
                                    
                                    Text(entry.source.rawValue)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.blue)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.15))
                                        .cornerRadius(4)
                                }
                                
                                HStack(spacing: 8) {
                                    Text(entry.timestamp, style: .date)
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                    Text(entry.timestamp, style: .time)
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                    if let ip = entry.ipAddressUsed {
                                        Text(ip)
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundColor(.gray)
                                    }
                                }
                                
                                if let error = entry.errorMessage, !entry.success {
                                    Text(error)
                                        .font(.system(size: 11))
                                        .foregroundColor(.red.opacity(0.8))
                                        .lineLimit(2)
                                }
                            }
                            
                            Spacer()
                            
                            // Result badge
                            Text(entry.success ? "Success" : "Failed")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(entry.success ? .green : .red)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background((entry.success ? Color.green : Color.red).opacity(0.15))
                                .cornerRadius(6)
                            
                            // Performed by
                            Text(entry.performedBy)
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                                .frame(width: 120, alignment: .trailing)
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(8)
                    }
                }
            }
        }
    }
}

// MARK: - Device Section Enum

enum DeviceSection: String, CaseIterable {
    case overview
    case hardware
    case storage
    case security
    case operatingSystem
    case userAndLocation
    case applications
    case profiles
    case localAccounts
    case diskEncryption
    case certificates
    case printers
    case purchasing
    case groupMemberships
    case extensionAttributes
    case management
    case logs
    
    var title: String {
        switch self {
        case .overview: return "Overview"
        case .hardware: return "Hardware"
        case .storage: return "Storage"
        case .security: return "Security"
        case .operatingSystem: return "Operating System"
        case .userAndLocation: return "User & Location"
        case .applications: return "Applications"
        case .profiles: return "Profiles"
        case .localAccounts: return "Local Accounts"
        case .diskEncryption: return "Disk Encryption"
        case .certificates: return "Certificates"
        case .printers: return "Printers"
        case .purchasing: return "Purchasing"
        case .groupMemberships: return "Groups"
        case .extensionAttributes: return "Extension Attributes"
        case .management: return "Management"
        case .logs: return "Action Logs"
        }
    }
    
    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .hardware: return "cpu"
        case .storage: return "internaldrive"
        case .security: return "shield.checkered"
        case .operatingSystem: return "apple.logo"
        case .userAndLocation: return "person.fill"
        case .applications: return "app.badge"
        case .profiles: return "doc.badge.gearshape"
        case .localAccounts: return "person.2"
        case .diskEncryption: return "lock.doc"
        case .certificates: return "checkmark.seal"
        case .printers: return "printer"
        case .purchasing: return "dollarsign.circle"
        case .groupMemberships: return "person.3"
        case .extensionAttributes: return "list.bullet.rectangle"
        case .management: return "gearshape.2"
        case .logs: return "doc.text.magnifyingglass"
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Device View") {
    DeviceView(computer: MockData.testComputer)
        .frame(width: 1200, height: 800)
}
#endif
