//
//  DeviceView.swift
//  Helios
//
//  Comprehensive device detail view for computer inventory. A thin shell:
//  header + section sidebar + the selected section, with device actions
//  executed by DeviceCommandExecutor and presented by DeviceActionOverlays.
//

import SwiftUI

struct DeviceView: View {
    let computer: Computer
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var actionLogService = ActionLogService.shared
    @ObservedObject private var configManager = MDMConfigurationManager.shared
    /// Observed so every policy gate re-evaluates when the user's
    /// capabilities land after sign-in (they are resolved post-login).
    @ObservedObject private var session = UserSession.shared
    @State private var selectedSection: DeviceSection = .overview

    // State for loading full details
    @State private var fullComputer: Computer?
    @State private var isLoadingDetails: Bool = false
    @State private var loadError: String?

    // Device history (Jamf Policy Logs + MDM command history). Lazy-loaded the
    // first time the History section is opened.
    @State private var history: ComputerHistory?
    @State private var isLoadingHistory: Bool = false
    @State private var historyError: String?

    /// Search / filter / page state for the inventory sections. Held here so
    /// it survives switching between sections.
    @State private var inventory = DeviceInventoryState()

    /// Runs MDM commands and the erase-acknowledgment flow for this device.
    @State private var executor: DeviceCommandExecutor
    /// Which confirmation stage or action sheet is showing.
    @State private var actionFlow = DeviceActionFlow()

    init(computer: Computer) {
        self.computer = computer
        _executor = State(initialValue: DeviceCommandExecutor(computer: computer))
    }

    /// Policy for this device's Actions menu (strict fail-closed — see
    /// DeviceActionPolicy). Recomputed on configuration reload via
    /// `configManager` and on capability change via `session`; the policy is
    /// a value type, so it must be rebuilt from the CURRENT capabilities.
    private var actionPolicy: DeviceActionPolicy {
        configManager.configuration.computerActionPolicy(capabilities: session.capabilities)
    }

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
            
            // Command result, confirmation, progress, and secret overlays
            DeviceActionOverlays(computer: displayComputer, executor: executor, flow: actionFlow)
        }
        .navigationBarBackButtonHidden(true)
        .task {
            await loadFullDetails()
        }
        .sheet(isPresented: $actionFlow.showingABMAssignSheet) {
            ABMAssignmentSheet(
                serialNumber: displayComputer.serialNumber ?? "",
                deviceName: displayComputer.displayName,
                title: ActionBranding.label(for: .abmAssign),
                policyProvider: { actionPolicy },
                onFinished: { success, _, error in
                    executor.logABMAction(.abmAssign, serial: displayComputer.serialNumber ?? "Unknown",
                                 success: success, error: error)
                }
            )
        }
        .sheet(isPresented: $actionFlow.showingPreStageAssignSheet) {
            PreStageAssignmentSheet(
                serialNumber: displayComputer.serialNumber ?? "",
                deviceName: displayComputer.displayName,
                title: ActionBranding.label(for: .assignPreStage),
                policyProvider: { actionPolicy },
                onFinished: { success, _, detail in
                    executor.logABMAction(.assignPreStage, serial: displayComputer.serialNumber ?? "Unknown",
                                 success: success, error: detail)
                }
            )
        }
        .sheet(isPresented: $actionFlow.showingSiteMoveSheet) {
            SiteMoveSheet(
                deviceID: displayComputer.id,
                deviceName: displayComputer.displayName,
                serialNumber: displayComputer.serialNumber ?? "",
                currentSiteID: displayComputer.general?.site?.id,
                currentSiteName: displayComputer.general?.site?.name,
                title: ActionBranding.label(for: .moveToSite),
                policyProvider: { actionPolicy },
                performMove: { siteID in
                    try await JamfSiteService.shared.moveComputer(computerID: displayComputer.id, toSiteID: siteID)
                },
                onFinished: { success, _, detail in
                    executor.logABMAction(.moveToSite, serial: displayComputer.serialNumber ?? "Unknown",
                                 success: success, error: detail)
                }
            )
        }
    }

    // MARK: - Load Full Details
    
    @MainActor
    private func loadFullDetails() async {
        // Skip the fetch only when this computer clearly came from the detail
        // endpoint. APPLICATIONS alone is NOT proof: the bulk inventory fetch
        // uses features.computers.inventorySections, which commonly includes
        // APPLICATIONS but not the detail-only sections below — skipping on
        // apps alone leaves those sections permanently empty in this view.
        let hasDetailOnlySections = computer.localUserAccounts != nil
            && computer.certificates != nil
            && computer.printers != nil
        if hasDetailOnlySections, !(computer.applications?.isEmpty ?? true) {
            NSLog("📱 DeviceView: Already have full details for %@", computer.displayName)
            return
        }
        
        NSLog("📱 DeviceView: Loading full details for %@ (id: %@)", computer.displayName, computer.id)
        isLoadingDetails = true
        
        do {
            let searchService = ComputerSearchService()
            let fullDetails = try await searchService.fetchComputerDetails(id: computer.id)
            
            self.fullComputer = fullDetails
            executor.computer = fullDetails
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
    
    /// Lazy-load Policy Logs + MDM command history for this device. Skips work
    /// if already loaded (unless `force`, used by the Retry button).
    @MainActor
    private func loadHistory(force: Bool = false) async {
        if !force, history != nil { return }

        isLoadingHistory = true
        historyError = nil
        do {
            let service = ComputerHistoryService()
            history = try await service.fetchHistory(id: computer.id)
        } catch {
            historyError = error.localizedDescription
            NSLog("❌ DeviceView: Failed to load history: %@", error.localizedDescription)
        }
        isLoadingHistory = false
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
                        StatusBadge("Supervised", color: .blue)
                    }
                    
                    if displayComputer.isManaged {
                        StatusBadge("Managed", color: .green)
                    }
                    
                    if displayComputer.isFileVaultEnabled {
                        StatusBadge("Encrypted", color: .purple)
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
                RefreshButton(isLoading: isLoadingDetails) {
                    Task { await loadFullDetails() }
                }
                
                // Actions menu with MDM commands. Strict fail-closed: when
                // the access profile grants no device actions — or the
                // user's roles grant none — the button itself is not
                // rendered. Bound once per render: the computed policy
                // rebuilds its grants dictionary on every access, and one
                // menu render consults it dozens of times.
                let policy = actionPolicy
                if policy.hasAnyVisibleAction() {
                    DeviceActionsMenu(policy: policy, isExecuting: executor.isExecutingCommand) { action in
                        // Act on exactly the device the header shows.
                        executor.computer = displayComputer
                        actionFlow.trigger(action, executor: executor)
                    }
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .background(Color.black.opacity(0.3))
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

    // MARK: - Section Sidebar
    
    private var sectionSidebar: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(visibleSections, id: \.self) { section in
                    sectionButton(section)
                }
            }
            .padding(16)
        }
        .frame(width: 270)
        .background(Color.black.opacity(0.2))
    }

    /// Sections shown in the sidebar. History is gated behind the
    /// `features.computers.showDeviceHistory` flag (default off); everything
    /// else is always visible.
    private var visibleSections: [DeviceSection] {
        DeviceSection.allCases.filter { section in
            switch section {
            case .history:
                return configManager.configuration.features?.effectiveComputers.effectiveShowDeviceHistory ?? false
            default:
                return true
            }
        }
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
            DeviceOverviewView(computer: displayComputer)
        case .hardware, .storage, .security, .operatingSystem, .userAndLocation,
             .diskEncryption, .purchasing, .management:
            DeviceDetailSectionsView(section: selectedSection, computer: displayComputer)
        case .applications, .profiles, .localAccounts, .certificates, .printers,
             .groupMemberships, .extensionAttributes:
            DeviceInventoryTabsView(section: selectedSection, computer: displayComputer, state: inventory)
        case .logs:
            DeviceLogsSectionView(computer: displayComputer)
        case .history:
            DeviceHistorySectionView(
                history: history,
                isLoading: isLoadingHistory,
                errorMessage: historyError,
                pageSize: configManager.configuration.features?.effectiveComputers.effectiveHistoryPageSize ?? 25,
                onRetry: { Task { await loadHistory(force: true) } }
            )
            .task { await loadHistory() }
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
