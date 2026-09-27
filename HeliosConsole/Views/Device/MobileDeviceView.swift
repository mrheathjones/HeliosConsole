//
//  MobileDeviceView.swift
//  Helios
//
//  Comprehensive detail view for mobile devices (iOS, iPadOS, visionOS)
//  Matches the design language of DeviceView for computers
//

import SwiftUI

struct MobileDeviceView: View {
    let device: MobileDevice
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var configManager = MDMConfigurationManager.shared
    @ObservedObject private var session = UserSession.shared

    @State private var selectedSection: MobileDeviceSection = .overview

    // MARK: - Action State
    @State private var showingSiteMoveSheet: Bool = false

    /// The mobile-device action policy — the SAME role-capability gating as
    /// computers, but consulting the user's `mobileDeviceActions` grant
    /// (DeviceActionPolicy.Platform.mobileDevice). Recomputed on config or
    /// capability change via the observed managers. `.moveToSite` also gates
    /// on a non-empty `allowedSites` (shared with computers) — see
    /// DeviceActionPolicy.hasUsableScope.
    private var actionPolicy: DeviceActionPolicy {
        configManager.configuration.mobileDeviceActionPolicy(capabilities: session.capabilities)
    }

    /// Mobile actions that actually have a UI/execution path today. The
    /// `mobileDeviceActions` schema enum lists more (sendBlankPush, restart,
    /// shutdown, wipe) as forward-looking, but nothing renders them yet — so
    /// the menu is filtered to this set to avoid offering dead buttons. Add a
    /// case here when its mobile flow lands.
    private let implementedMobileActions: [DeviceAction] = [.moveToSite]
    
    // MARK: - Search State for Each Section
    @State private var applicationsSearchText: String = ""
    @State private var profilesSearchText: String = ""
    @State private var certificatesSearchText: String = ""
    @State private var groupsSearchText: String = ""
    @State private var extensionAttributesSearchText: String = ""
    
    // MARK: - Filter State
    // Groups filters
    @State private var filterSmartGroups: Bool = true
    @State private var filterStaticGroups: Bool = true
    
    // Certificates filter
    enum CertificateFilter: String, CaseIterable {
        case all = "All"
        case issued = "Issued"
        case expiring = "Expiring"
        case expired = "Expired"
    }
    @State private var certificateFilter: CertificateFilter = .all
    
    // MARK: - Pagination State
    @State private var applicationsPage: Int = 1
    @State private var profilesPage: Int = 1
    @State private var certificatesPage: Int = 1
    @State private var groupsPage: Int = 1
    @State private var extensionAttributesPage: Int = 1
    
    private let itemsPerPage: Int = 25
    
    var body: some View {
        ZStack {
            AnimatedBackgroundView(animate: .constant(true))
            
            VStack(spacing: 0) {
                // Header
                deviceHeader
                
                // Content
                HStack(spacing: 0) {
                    // Sidebar
                    sectionSidebar
                    
                    // Divider
                    Rectangle()
                        .fill(Color.white.opacity(0.05))
                        .frame(width: 1)
                    
                    // Main Content
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            sectionContent
                        }
                        .padding(32)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showingSiteMoveSheet) {
            SiteMoveSheet(
                deviceID: device.id,
                deviceName: device.displayName,
                serialNumber: device.serialNumber ?? "",
                currentSiteID: device.site?.id,
                currentSiteName: device.site?.name,
                title: ActionBranding.label(for: .moveToSite),
                policyProvider: { actionPolicy },
                performMove: { siteID in
                    try await JamfSiteService.shared.moveMobileDevice(mobileDeviceID: device.id, toSiteID: siteID)
                },
                onFinished: { success, _, detail in
                    logMobileAction(.moveToSite, success: success, detail: detail)
                }
            )
        }
    }

    // MARK: - Device Header
    
    private var deviceHeader: some View {
        HStack(spacing: 24) {
            // Back button
            Button {
                dismiss()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            
            // Device icon
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(device.platformType.color.opacity(0.15))
                    .frame(width: 64, height: 64)
                
                Image(systemName: device.platformType.icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(device.platformType.color)
            }
            
            // Device info
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Text(device.displayName)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    
                    if device.isSupervised {
                        StatusBadge("Supervised", color: .blue)
                    }
                    
                    if device.managed ?? false {
                        StatusBadge("Managed", color: .green)
                    }
                    
                    // Platform badge
                    StatusBadge(device.platformType.rawValue, color: device.platformType.color)
                }
                
                HStack(spacing: 20) {
                    if let serial = device.serialNumber {
                        headerInfoItem(icon: "number", text: serial)
                    }
                    headerInfoItem(icon: device.platformType.icon, text: device.model)
                    if let os = device.osVersion {
                        headerInfoItem(icon: "gear", text: "\(device.platformType == .visionOS ? "visionOS" : "iOS") \(os)")
                    }
                }
                
                // User info row
                if let username = device.location?.realName ?? device.location?.username {
                    HStack(spacing: 8) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 12))
                        Text(username)
                            .font(.system(size: 14))
                        
                        if let email = device.location?.emailAddress {
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
                // (No Refresh control here: this view is handed a fully-loaded
                // immutable `device`, so there is nothing to reload in place —
                // a dead placeholder button would be worse than none.)

                // Fail-closed like the computer view: the menu renders only
                // when the user's role grants at least one IMPLEMENTED mobile
                // action (today just Move to Site, and only with a non-empty
                // allowedSites). No grant → no button, rather than a dead
                // placeholder. Bound once per render — the computed policy
                // rebuilds its grants on every access.
                let policy = actionPolicy
                let visible = implementedMobileActions.filter { policy.isAllowed($0) }
                if !visible.isEmpty {
                    actionsMenu(visible: visible)
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .background(Color.black.opacity(0.3))
    }

    // MARK: - Actions Menu

    /// Header actions menu for mobile devices. Mirrors the computer view's
    /// menu (sectioned, policy-gated, ActionBranding label/icon overrides)
    /// but is filtered to `implementedMobileActions` so nothing dead is ever
    /// offered. Styled to match the header's other `actionButton`s rather
    /// than the computer view's pill.
    private func actionsMenu(visible: [DeviceAction]) -> some View {
        Menu {
            ForEach(DeviceAction.MenuSection.allCases, id: \.self) { section in
                let sectionActions = visible.filter { $0.menuSection == section }
                if !sectionActions.isEmpty {
                    Section(section.title) {
                        ForEach(sectionActions) { action in
                            Button(role: action.isDestructive ? .destructive : nil) {
                                trigger(action)
                            } label: {
                                Label(ActionBranding.label(for: action), systemImage: ActionBranding.icon(for: action))
                            }
                        }
                    }
                }
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16))
                Text("More")
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
        .menuStyle(.borderlessButton)
    }

    // MARK: - Action Routing

    /// Routes a granted mobile action. Own-sheet actions (moveToSite) open
    /// their sheet after a defense-in-depth policy re-check; the menu already
    /// filters by policy, but never trust the UI filter alone. As more mobile
    /// actions gain flows, add their routing here.
    private func trigger(_ action: DeviceAction) {
        switch action {
        case .moveToSite:
            if actionPolicy.denialReason(for: .moveToSite) != nil {
                logMobileAction(.moveToSite, success: false, detail: "Denied by policy at trigger (menu filter bypassed)")
            } else {
                showingSiteMoveSheet = true
            }
        default:
            // Not reachable: the menu only offers implementedMobileActions.
            logMobileAction(action, success: false, detail: "No mobile flow implemented for '\(action.rawValue)'")
        }
    }

    /// Audit-logs a mobile action end state, mirroring the computer view's
    /// logABMAction. deviceId uses the mobile inventory id.
    private func logMobileAction(_ action: DeviceAction, success: Bool, detail: String?) {
        ActionLogService.shared.logAction(
            actionName: action.logName,
            actionCategory: action.logCategory,
            deviceName: device.displayName,
            deviceSerialNumber: device.serialNumber ?? "Unknown",
            deviceId: device.id,
            success: success,
            errorMessage: detail
        )
    }
    
    private func headerInfoItem(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
            Text(text)
                .font(.system(size: 14))
        }
        .foregroundColor(.gray)
    }
    
    // MARK: - Section Sidebar
    
    private var sectionSidebar: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(MobileDeviceSection.allCases, id: \.self) { section in
                    sectionButton(section)
                }
            }
            .padding(16)
        }
        .frame(width: 270)
        .background(Color.black.opacity(0.2))
    }
    
    private func sectionButton(_ section: MobileDeviceSection) -> some View {
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
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selectedSection == section ? Color.blue.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func sectionItemCount(_ section: MobileDeviceSection) -> Int? {
        switch section {
        case .applications:
            return device.applications?.count
        case .profiles:
            return device.configurationProfiles?.count
        case .certificates:
            return device.certificates?.count
        case .groups:
            return device.groups?.count
        case .extensionAttributes:
            return device.extensionAttributes?.count
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
        case .security:
            securitySection
        case .userAndLocation:
            userAndLocationSection
        case .applications:
            applicationsSection
        case .profiles:
            profilesSection
        case .certificates:
            certificatesSection
        case .network:
            networkSection
        case .groups:
            groupsSection
        case .extensionAttributes:
            extensionAttributesSection
        case .purchasing:
            purchasingSection
        case .management:
            managementSection
        }
    }
    
    // MARK: - Overview Section
    
    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader("Device Overview", icon: "square.grid.2x2")
            
            // Quick stats grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                overviewStatCard(
                    title: "Applications",
                    value: "\(device.applications?.count ?? 0)",
                    icon: "app.badge",
                    color: .blue
                )
                overviewStatCard(
                    title: "Profiles",
                    value: "\(device.configurationProfiles?.count ?? 0)",
                    icon: "doc.badge.gearshape",
                    color: .orange
                )
                overviewStatCard(
                    title: "Certificates",
                    value: "\(device.certificates?.count ?? 0)",
                    icon: "checkmark.seal",
                    color: .green
                )
                overviewStatCard(
                    title: "Groups",
                    value: "\(device.groups?.count ?? 0)",
                    icon: "person.3",
                    color: .purple
                )
            }
            
            // Device details cards
            HStack(alignment: .top, spacing: 20) {
                // Left column
                VStack(spacing: 20) {
                    DetailCard(title: "Device Information") {
                        DetailRow("Name", device.name ?? "N/A")
                        DetailRow("Serial Number", device.serialNumber ?? "N/A")
                        DetailRow("Model", device.model)
                        DetailRow("Model Identifier", device.modelIdentifier ?? "N/A")
                        DetailRow("Platform", device.platformType.rawValue)
                    }
                    
                    DetailCard(title: "Operating System") {
                        DetailRow("Version", device.osVersion ?? "N/A")
                        DetailRow("Build", device.osBuild ?? "N/A")
                        if let supplemental = device.osSupplementalBuildVersion {
                            DetailRow("Supplemental", supplemental)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                
                // Right column
                VStack(spacing: 20) {
                    DetailCard(title: "Management Status") {
                        DetailRow("Managed", device.managed ?? false ? "Yes" : "No")
                        DetailRow("Supervised", device.isSupervised ? "Yes" : "No")
                        DetailRow("Site", device.site?.name ?? "None")
                        if let enrollmentMethod = device.enrollmentMethod {
                            DetailRow("Enrollment", enrollmentMethod)
                        }
                    }
                    
                    DetailCard(title: "Last Activity") {
                        DetailRow("Last Inventory", formatDate(device.lastInventoryUpdateTimestamp))
                        DetailRow("Initial Enrollment", formatDate(device.initialEntryTimestamp))
                        DetailRow("Last Enrollment", formatDate(device.lastEnrollmentTimestamp))
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    private func overviewStatCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)
                Spacer()
            }
            
            HStack {
                Text(value)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
            }
            
            HStack {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                Spacer()
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.03))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
    
    // MARK: - Hardware Section
    
    private var hardwareSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader("Hardware", icon: "cpu")
            
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 20) {
                    DetailCard(title: "Storage") {
                        if let capacity = device.capacityMb {
                            DetailRow("Total Capacity", formatStorage(capacity))
                        }
                        if let available = device.availableMb {
                            DetailRow("Available", formatStorage(available))
                        }
                        if let used = device.percentageUsed {
                            DetailRow("Used", "\(used)%")
                            
                            // Storage bar
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.white.opacity(0.1))
                                        .frame(height: 8)
                                    
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(used > 90 ? Color.red : used > 75 ? Color.orange : Color.blue)
                                        .frame(width: geometry.size.width * CGFloat(used) / 100, height: 8)
                                }
                            }
                            .frame(height: 8)
                            .padding(.top, 4)
                        }
                    }
                    
                    if device.batteryLevel != nil {
                        DetailCard(title: "Battery") {
                            if let level = device.batteryLevel {
                                DetailRow("Level", "\(level)%")
                                
                                // Battery bar
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.white.opacity(0.1))
                                            .frame(height: 8)
                                        
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(level < 20 ? Color.red : level < 50 ? Color.orange : Color.green)
                                            .frame(width: geometry.size.width * CGFloat(level) / 100, height: 8)
                                    }
                                }
                                .frame(height: 8)
                                .padding(.top, 4)
                            }
                            if let health = device.ios?.batteryHealth ?? device.visionos?.batteryHealth {
                                DetailRow("Health", health)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                
                VStack(spacing: 20) {
                    DetailCard(title: "Network") {
                        DetailRow("IP Address", device.ipAddress ?? "N/A")
                        DetailRow("Wi-Fi MAC", device.wifiMacAddress ?? "N/A")
                        DetailRow("Bluetooth MAC", device.bluetoothMacAddress ?? "N/A")
                    }
                    
                    DetailCard(title: "Identifiers") {
                        DetailRow("UDID", device.udid ?? "N/A")
                        DetailRow("Management ID", device.managementId ?? "N/A")
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    // MARK: - Security Section
    
    private var securitySection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader("Security", icon: "shield.checkered")
            
            if let security = device.security {
                HStack(alignment: .top, spacing: 20) {
                    VStack(spacing: 20) {
                        DetailCard(title: "Passcode & Protection") {
                            securityRow("Passcode Present", security.passcodePresent ?? false)
                            securityRow("Passcode Compliant", security.passcodeCompliant ?? false)
                            securityRow("Passcode Compliant with Profile", security.passcodeCompliantWithProfile ?? false)
                            securityRow("Data Protected", security.dataProtected ?? false)
                        }
                        
                        DetailCard(title: "Device Security") {
                            securityRow("Activation Lock", security.activationLockEnabled ?? false)
                            securityRow("Jailbreak Detected", security.jailBreakDetected ?? false, invertColors: true)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    VStack(spacing: 20) {
                        DetailCard(title: "Encryption") {
                            securityRow("Block Level Encryption Capable", security.blockLevelEncryptionCapable ?? false)
                            securityRow("File Level Encryption Capable", security.fileLevelEncryptionCapable ?? false)
                            if let hw = security.hardwareEncryption {
                                DetailRow("Hardware Encryption", "\(hw)")
                            }
                        }
                        
                        if security.attestationStatus != nil {
                            DetailCard(title: "Attestation") {
                                DetailRow("Status", security.attestationStatus ?? "N/A")
                                DetailRow("Last Attempt", formatDate(security.lastAttestationAttemptDate))
                                DetailRow("Last Success", formatDate(security.lastSuccessfulAttestationDate))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                EmptyStateView("No security information available", icon: "shield.checkered")
            }
        }
    }
    
    private func securityRow(_ label: String, _ value: Bool, invertColors: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.gray)
            
            Spacer()
            
            HStack(spacing: 6) {
                Image(systemName: value ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 12))
                Text(value ? "Yes" : "No")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(invertColors ? (value ? .red : .green) : (value ? .green : .red.opacity(0.7)))
        }
    }
    
    // MARK: - User & Location Section
    
    private var userAndLocationSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader("User & Location", icon: "person.fill")
            
            if let location = device.location,
               (location.username != nil || location.realName != nil || location.emailAddress != nil) {
                HStack(alignment: .top, spacing: 20) {
                    DetailCard(title: "Assigned User") {
                        DetailRow("Username", location.username ?? "N/A")
                        DetailRow("Real Name", location.realName ?? "N/A")
                        DetailRow("Email", location.emailAddress ?? "N/A")
                        DetailRow("Position", location.position ?? "N/A")
                        DetailRow("Phone", location.phoneNumber ?? "N/A")
                    }
                    .frame(maxWidth: .infinity)
                    
                    DetailCard(title: "Location") {
                        DetailRow("Room", location.room ?? "N/A")
                        DetailRow("Building ID", location.buildingId ?? "N/A")
                        DetailRow("Department ID", location.departmentId ?? "N/A")
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                EmptyStateView("No user assigned to this device", icon: "person.crop.circle.badge.questionmark")
            }
        }
    }
    
    // MARK: - Applications Section
    
    private var applicationsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader("Applications (\(device.applications?.count ?? 0))", icon: "app.badge")
            
            if let apps = device.applications, !apps.isEmpty {
                // Search bar
                SearchBar(text: $applicationsSearchText, placeholder: "Filter applications...")
                
                let filteredApps = applicationsSearchText.isEmpty ? apps : apps.filter {
                    ($0.name ?? "").localizedCaseInsensitiveContains(applicationsSearchText) ||
                    ($0.identifier ?? "").localizedCaseInsensitiveContains(applicationsSearchText)
                }
                
                if filteredApps.isEmpty {
                    EmptyStateView("No applications match search", icon: "app.badge")
                } else {
                    // Pagination
                    let totalPages = max(1, Int(ceil(Double(filteredApps.count) / Double(itemsPerPage))))
                    let startIndex = (applicationsPage - 1) * itemsPerPage
                    let endIndex = min(startIndex + itemsPerPage, filteredApps.count)
                    let paginatedApps = Array(filteredApps[startIndex..<endIndex])
                    
                    LazyVStack(spacing: 8) {
                        ForEach(paginatedApps) { app in
                            applicationRow(app)
                        }
                    }
                    
                    // Pagination controls
                    if filteredApps.count > itemsPerPage {
                        PaginationControls(
                            currentPage: $applicationsPage,
                            totalPages: totalPages,
                            totalItems: filteredApps.count,
                            startIndex: startIndex,
                            endIndex: endIndex
                        )
                    }
                }
            } else {
                EmptyStateView("No applications installed", icon: "app.badge")
            }
        }
        .onChange(of: applicationsSearchText) { _, _ in
            applicationsPage = 1
        }
    }
    
    private func applicationRow(_ app: MobileDeviceApplication) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: "app.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name ?? "Unknown")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                Text(app.identifier ?? "N/A")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                if let version = app.shortVersion ?? app.version {
                    Text("v\(version)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray)
                }
                if let build = app.version, app.shortVersion != nil {
                    Text("Build \(build)")
                        .font(.system(size: 10))
                        .foregroundColor(.gray.opacity(0.7))
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
    
    // MARK: - Profiles Section
    
    private var profilesSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader("Configuration Profiles (\(device.configurationProfiles?.count ?? 0))", icon: "doc.badge.gearshape")
            
            if let profiles = device.configurationProfiles, !profiles.isEmpty {
                // Search bar
                SearchBar(text: $profilesSearchText, placeholder: "Filter profiles...")
                
                let filteredProfiles = profilesSearchText.isEmpty ? profiles : profiles.filter {
                    ($0.displayName ?? "").localizedCaseInsensitiveContains(profilesSearchText) ||
                    ($0.identifier ?? "").localizedCaseInsensitiveContains(profilesSearchText)
                }
                
                if filteredProfiles.isEmpty {
                    EmptyStateView("No profiles match search", icon: "doc.badge.gearshape")
                } else {
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
                        PaginationControls(
                            currentPage: $profilesPage,
                            totalPages: totalPages,
                            totalItems: filteredProfiles.count,
                            startIndex: startIndex,
                            endIndex: endIndex
                        )
                    }
                }
            } else {
                EmptyStateView("No configuration profiles", icon: "doc.badge.gearshape")
            }
        }
        .onChange(of: profilesSearchText) { _, _ in
            profilesPage = 1
        }
    }
    
    private func profileRow(_ profile: MobileDeviceConfigurationProfile) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.orange)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayName ?? "Unknown Profile")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                Text(profile.identifier ?? "N/A")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if let version = profile.version {
                Text("v\(version)")
                    .font(.system(size: 12, weight: .medium))
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
    
    // MARK: - Certificates Section
    
    private var certificatesSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader("Certificates (\(device.certificates?.count ?? 0))", icon: "checkmark.seal")
            
            if let certs = device.certificates, !certs.isEmpty {
                // Search bar and filters
                HStack(spacing: 16) {
                    SearchBar(text: $certificatesSearchText, placeholder: "Filter certificates...")
                    
                    // Certificate status filter
                    HStack(spacing: 8) {
                        ForEach(CertificateFilter.allCases, id: \.self) { filter in
                            Button {
                                certificateFilter = filter
                            } label: {
                                Text(filter.rawValue)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(certificateFilter == filter ? .white : .gray)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(certificateFilter == filter ? certificateFilterColor(filter) : Color.white.opacity(0.05))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                let filteredCerts = filteredCertificates(from: certs)
                
                if filteredCerts.isEmpty {
                    EmptyStateView("No certificates match filters", icon: "checkmark.seal")
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
                        PaginationControls(
                            currentPage: $certificatesPage,
                            totalPages: totalPages,
                            totalItems: filteredCerts.count,
                            startIndex: startIndex,
                            endIndex: endIndex
                        )
                    }
                }
            } else {
                EmptyStateView("No certificates", icon: "checkmark.seal")
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
        case .issued: return .green
        case .expiring: return .orange
        case .expired: return .red
        }
    }
    
    private func filteredCertificates(from certs: [MobileDeviceCertificate]) -> [MobileDeviceCertificate] {
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
        case .issued:
            result = result.filter { $0.certificateStatus == "ISSUED" || $0.lifecycleStatus == "ACTIVE" }
        case .expiring:
            result = result.filter { cert in
                guard let expiryString = cert.expirationDateEpoch,
                      let expiryDate = parseDate(expiryString) else {
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
                guard let expiryString = cert.expirationDateEpoch,
                      let expiryDate = parseDate(expiryString) else {
                    return false
                }
                return expiryDate < Date()
            }
        }
        
        return result
    }
    
    private func certificateRow(_ cert: MobileDeviceCertificate) -> some View {
        let isExpired = isCertificateExpired(cert)
        let isExpiring = isCertificateExpiring(cert)
        let statusColor: Color = isExpired ? .red : (isExpiring ? .orange : .green)
        
        return HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(statusColor.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: isExpired ? "xmark.seal.fill" : "checkmark.seal.fill")
                    .font(.system(size: 18))
                    .foregroundColor(statusColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(cert.commonName ?? "Unknown Certificate")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    
                    if cert.identity == true {
                        Text("Identity")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.purple)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                if let subject = cert.subjectName {
                    Text(subject)
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                if let expiry = cert.expirationDateEpoch {
                    Text("Expires: \(formatDate(expiry))")
                        .font(.system(size: 10))
                        .foregroundColor(statusColor)
                }
                
                if let status = cert.certificateStatus {
                    Text(status)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(statusColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(statusColor.opacity(0.1))
                        .cornerRadius(4)
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
    
    private func isCertificateExpired(_ cert: MobileDeviceCertificate) -> Bool {
        if cert.certificateStatus == "EXPIRED" { return true }
        guard let expiryString = cert.expirationDateEpoch,
              let expiryDate = parseDate(expiryString) else { return false }
        return expiryDate < Date()
    }
    
    private func isCertificateExpiring(_ cert: MobileDeviceCertificate) -> Bool {
        guard let expiryString = cert.expirationDateEpoch,
              let expiryDate = parseDate(expiryString) else { return false }
        let thirtyDaysFromNow = Date().addingTimeInterval(30 * 24 * 60 * 60)
        return expiryDate > Date() && expiryDate <= thirtyDaysFromNow
    }
    
    // MARK: - Network Section
    
    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader("Network", icon: "antenna.radiowaves.left.and.right")
            
            if let network = device.network {
                HStack(alignment: .top, spacing: 20) {
                    VStack(spacing: 20) {
                        DetailCard(title: "Carrier Information") {
                            DetailRow("Current Carrier", network.currentCarrierNetwork ?? "N/A")
                            DetailRow("Home Carrier", network.homeCarrierNetwork ?? "N/A")
                            DetailRow("Carrier Settings", network.carrierSettingsVersion ?? "N/A")
                            DetailRow("Phone Number", network.phoneNumber ?? "N/A")
                        }
                        
                        DetailCard(title: "Cellular Identifiers") {
                            DetailRow("IMEI", network.imei ?? "N/A")
                            DetailRow("ICCID", network.iccid ?? "N/A")
                            DetailRow("MEID", network.meid ?? "N/A")
                            DetailRow("EID", network.eid ?? "N/A")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    VStack(spacing: 20) {
                        DetailCard(title: "Network Status") {
                            securityRow("Roaming", network.roaming ?? false)
                            securityRow("Data Roaming Enabled", network.dataRoamingEnabled ?? false)
                            securityRow("Voice Roaming Enabled", network.voiceRoamingEnabled ?? false)
                            securityRow("Personal Hotspot", network.personalHotspotEnabled ?? false)
                        }
                        
                        DetailCard(title: "Mobile Network Codes") {
                            DetailRow("Current MCC", network.currentMobileCountryCode ?? "N/A")
                            DetailRow("Current MNC", network.currentMobileNetworkCode ?? "N/A")
                            DetailRow("Home MCC", network.homeMobileCountryCode ?? "N/A")
                            DetailRow("Home MNC", network.homeMobileNetworkCode ?? "N/A")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                EmptyStateView("No network information available", icon: "antenna.radiowaves.left.and.right")
            }
        }
    }
    
    // MARK: - Groups Section
    
    private var groupsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader("Group Memberships (\(device.groups?.count ?? 0))", icon: "person.3")
            
            if let groups = device.groups, !groups.isEmpty {
                // Search bar and filters
                HStack(spacing: 16) {
                    SearchBar(text: $groupsSearchText, placeholder: "Filter groups...")
                    
                    // Group type toggles
                    HStack(spacing: 8) {
                        FilterToggle("Smart", isOn: $filterSmartGroups, color: .purple)
                        FilterToggle("Static", isOn: $filterStaticGroups, color: .blue)
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
                        Button("Clear Filters") {
                            filterSmartGroups = true
                            filterStaticGroups = true
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
                        PaginationControls(
                            currentPage: $groupsPage,
                            totalPages: totalPages,
                            totalItems: filteredGroupsList.count,
                            startIndex: startIndex,
                            endIndex: endIndex
                        )
                    }
                }
            } else {
                EmptyStateView("No group memberships", icon: "person.3")
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
    
    private func filteredGroups(from groups: [MobileDeviceGroup]) -> [MobileDeviceGroup] {
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
                let isSmart = group.smart == true
                if filterSmartGroups && isSmart { return true }
                if filterStaticGroups && !isSmart { return true }
                return false
            }
        }
        
        return result
    }
    
    private func groupRow(_ group: MobileDeviceGroup) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(group.smart == true ? Color.purple.opacity(0.1) : Color.blue.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: group.smart == true ? "gearshape.2.fill" : "person.3.fill")
                    .font(.system(size: 18))
                    .foregroundColor(group.smart == true ? .purple : .blue)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(group.groupName ?? "Unknown Group")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                if let description = group.groupDescription {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                } else {
                    Text("ID: \(group.groupId ?? "N/A")")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            Text(group.smart == true ? "Smart Group" : "Static Group")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(group.smart == true ? .purple : .blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((group.smart == true ? Color.purple : Color.blue).opacity(0.1))
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
            SectionHeader("Extension Attributes (\(device.extensionAttributes?.count ?? 0))", icon: "list.bullet.rectangle")
            
            if let attrs = device.extensionAttributes, !attrs.isEmpty {
                // Search bar
                SearchBar(text: $extensionAttributesSearchText, placeholder: "Filter extension attributes...")
                
                let filteredAttrs = extensionAttributesSearchText.isEmpty ? attrs : attrs.filter {
                    ($0.name ?? "").localizedCaseInsensitiveContains(extensionAttributesSearchText) ||
                    ($0.value?.joined(separator: " ") ?? "").localizedCaseInsensitiveContains(extensionAttributesSearchText)
                }
                
                if filteredAttrs.isEmpty {
                    EmptyStateView("No attributes match search", icon: "list.bullet.rectangle")
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
                        PaginationControls(
                            currentPage: $extensionAttributesPage,
                            totalPages: totalPages,
                            totalItems: filteredAttrs.count,
                            startIndex: startIndex,
                            endIndex: endIndex
                        )
                    }
                }
            } else {
                EmptyStateView("No extension attributes", icon: "list.bullet.rectangle")
            }
        }
        .onChange(of: extensionAttributesSearchText) { _, _ in
            extensionAttributesPage = 1
        }
    }
    
    private func extensionAttributeRow(_ attr: MobileDeviceExtensionAttribute) -> some View {
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
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                    
                    if let type = attr.type {
                        Text(type)
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
            }
            
            // Value
            if let values = attr.value, !values.isEmpty {
                let valueText = values.joined(separator: ", ")
                if !valueText.isEmpty {
                    Text(valueText)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(6)
                } else {
                    Text("(empty)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray.opacity(0.5))
                        .italic()
                }
            } else {
                Text("(no value)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray.opacity(0.5))
                    .italic()
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
            SectionHeader("Purchasing", icon: "dollarsign.circle")
            
            if let purchasing = device.purchasing {
                HStack(alignment: .top, spacing: 20) {
                    DetailCard(title: "Purchase Information") {
                        DetailRow("Purchased", purchasing.purchased ?? false ? "Yes" : "No")
                        DetailRow("Leased", purchasing.leased ?? false ? "Yes" : "No")
                        DetailRow("PO Number", purchasing.poNumber ?? "N/A")
                        DetailRow("Vendor", purchasing.vendor ?? "N/A")
                        DetailRow("Purchase Price", purchasing.purchasePrice ?? "N/A")
                        DetailRow("Purchasing Account", purchasing.purchasingAccount ?? "N/A")
                        DetailRow("Purchasing Contact", purchasing.purchasingContact ?? "N/A")
                    }
                    .frame(maxWidth: .infinity)
                    
                    DetailCard(title: "Dates & Warranty") {
                        DetailRow("PO Date", formatDate(purchasing.poDate))
                        DetailRow("Warranty Expires", formatDate(purchasing.warrantyExpiresDate))
                        DetailRow("Lease Expires", formatDate(purchasing.leaseExpiresDate))
                        if let lifeExpectancy = purchasing.lifeExpectancy, lifeExpectancy > 0 {
                            DetailRow("Life Expectancy", "\(lifeExpectancy) years")
                        }
                        DetailRow("AppleCare ID", purchasing.appleCareId ?? "N/A")
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                EmptyStateView("No purchasing information", icon: "dollarsign.circle")
            }
        }
    }
    
    // MARK: - Management Section
    
    private var managementSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader("Management", icon: "gearshape.2")
            
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 20) {
                    DetailCard(title: "MDM Status") {
                        DetailRow("Managed", device.managed ?? false ? "Yes" : "No")
                        DetailRow("Supervised", device.isSupervised ? "Yes" : "No")
                        DetailRow("DDM Enabled", device.declarativeDeviceManagementEnabled ?? false ? "Yes" : "No")
                        DetailRow("Enrollment Valid", device.enrollmentSessionTokenValid ?? false ? "Yes" : "No")
                    }
                    
                    DetailCard(title: "Enrollment") {
                        DetailRow("Method", device.enrollmentMethod ?? "N/A")
                        DetailRow("Device Ownership", device.deviceOwnershipLevel ?? "N/A")
                        DetailRow("Last Enrollment", formatDate(device.lastEnrollmentTimestamp))
                        DetailRow("MDM Profile Expires", formatDate(device.mdmProfileExpirationTimestamp))
                    }
                }
                .frame(maxWidth: .infinity)
                
                VStack(spacing: 20) {
                    DetailCard(title: "Site & Location") {
                        DetailRow("Site", device.site?.name ?? "None")
                        DetailRow("Site ID", device.site?.id ?? "N/A")
                        DetailRow("Time Zone", device.timeZone ?? "N/A")
                    }
                    
                    DetailCard(title: "Identifiers") {
                        DetailRow("Jamf ID", device.id)
                        DetailRow("Management ID", device.managementId ?? "N/A")
                        DetailRow("Asset Tag", device.assetTag ?? "N/A")
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func formatDate(_ dateString: String?) -> String {
        guard let dateString = dateString else { return "N/A" }
        guard let date = parseDate(dateString) else { return dateString }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func parseDate(_ dateString: String) -> Date? {
        // Try ISO8601 with fractional seconds
        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso8601Formatter.date(from: dateString) {
            return date
        }
        
        // Try ISO8601 without fractional seconds
        iso8601Formatter.formatOptions = [.withInternetDateTime]
        if let date = iso8601Formatter.date(from: dateString) {
            return date
        }
        
        // Try epoch date format "1970-01-01T00:00:00Z"
        if dateString == "1970-01-01T00:00:00Z" {
            return nil
        }
        
        return nil
    }
    
    private func formatStorage(_ mb: Int) -> String {
        if mb >= 1024 {
            return String(format: "%.1f GB", Double(mb) / 1024.0)
        }
        return "\(mb) MB"
    }
}

// MARK: - Mobile Device Section Enum

enum MobileDeviceSection: String, CaseIterable {
    case overview
    case hardware
    case security
    case userAndLocation
    case applications
    case profiles
    case certificates
    case network
    case groups
    case extensionAttributes
    case purchasing
    case management
    
    var title: String {
        switch self {
        case .overview: return "Overview"
        case .hardware: return "Hardware"
        case .security: return "Security"
        case .userAndLocation: return "User & Location"
        case .applications: return "Applications"
        case .profiles: return "Profiles"
        case .certificates: return "Certificates"
        case .network: return "Network"
        case .groups: return "Groups"
        case .extensionAttributes: return "Extension Attributes"
        case .purchasing: return "Purchasing"
        case .management: return "Management"
        }
    }
    
    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .hardware: return "cpu"
        case .security: return "shield.checkered"
        case .userAndLocation: return "person.fill"
        case .applications: return "app.badge"
        case .profiles: return "doc.badge.gearshape"
        case .certificates: return "checkmark.seal"
        case .network: return "antenna.radiowaves.left.and.right"
        case .groups: return "person.3"
        case .extensionAttributes: return "list.bullet.rectangle"
        case .purchasing: return "dollarsign.circle"
        case .management: return "gearshape.2"
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Mobile Device View") {
    MobileDeviceView(device: MobileDevice(
        id: "4",
        name: "iPhone-MRYG6Q09RY",
        enforceName: false,
        assetTag: nil,
        lastInventoryUpdateTimestamp: "2026-01-22T02:23:30.149Z",
        osVersion: "18.5",
        osBuild: "22F76",
        osSupplementalBuildVersion: "22F76",
        osRapidSecurityResponse: nil,
        softwareUpdateDeviceId: "iPhone17,5",
        serialNumber: "MRYG6Q09RY",
        udid: "00008140-00024C1E1E0A801C",
        initialEntryTimestamp: "2025-10-30T19:25:58.28Z",
        ipAddress: "167.73.213.46",
        wifiMacAddress: "90:5F:7A:28:68:AF",
        bluetoothMacAddress: "90:5F:7A:27:AC:84",
        deviceOwnershipLevel: "Institutional",
        enrollmentMethod: "PreStage enrollment: iOS POC (2)",
        enrollmentSessionTokenValid: false,
        lastEnrollmentTimestamp: "2025-10-30T19:33:39.591Z",
        mdmProfileExpirationTimestamp: "2027-10-30T19:33:38Z",
        managed: true,
        timeZone: "America/Detroit",
        site: MobileDeviceSite(id: "1", name: "Staging"),
        location: MobileDeviceLocation(
            username: "testuser",
            realName: "Test User",
            emailAddress: "testuser@example.com",
            position: "IT Admin",
            phoneNumber: nil,
            departmentId: nil,
            buildingId: nil,
            room: nil
        ),
        type: "ios",
        ios: MobileDeviceiOS(
            capacityMb: 131072,
            availableMb: 101673,
            percentageUsed: 22,
            model: "iPhone 16e",
            modelIdentifier: "iPhone17,5",
            modelNumber: "MD0D4LL",
            shared: false,
            supervised: true,
            batteryLevel: 85,
            batteryHealth: "NORMAL",
            lastBackupTimestamp: nil,
            deviceLocatorServiceEnabled: false,
            doNotDisturbEnabled: false,
            cloudBackupEnabled: false,
            lastCloudBackupTimestamp: nil,
            locationServicesEnabled: false,
            computer: nil,
            bleCapable: false,
            security: MobileDeviceSecurity(
                dataProtected: true,
                blockLevelEncryptionCapable: true,
                fileLevelEncryptionCapable: true,
                passcodePresent: true,
                passcodeCompliant: true,
                passcodeCompliantWithProfile: true,
                hardwareEncryption: 3,
                activationLockEnabled: false,
                jailBreakDetected: false,
                bootstrapToken: nil,
                bootstrapTokenEscrowed: nil,
                attestationStatus: "SUCCESS",
                lastAttestationAttemptDate: "2026-01-20T02:14:48.854Z",
                lastSuccessfulAttestationDate: "2026-01-20T02:14:50.435Z",
                passcodeLockGracePeriodEnforcedSeconds: nil,
                personalDeviceProfileCurrent: nil,
                lostModeEnabled: false,
                lostModePersistent: false,
                lostModeMessage: nil,
                lostModePhoneNumber: nil,
                lostModeFootnote: nil,
                lostModeLocation: nil,
                lostModeEnabledDate: nil
            ),
            purchasing: nil,
            network: nil,
            configurationProfiles: [
                MobileDeviceConfigurationProfile(displayName: "System Config - Staging", version: "1", uuid: "F4333763-ADCB-4BF9-9F84-6C9D177050B6", identifier: "F4333763-ADCB-4BF9-9F84-6C9D177050B6"),
                MobileDeviceConfigurationProfile(displayName: "MDM Profile", version: "1", uuid: "00000000-0000-0000-A000-4A414D460003", identifier: "00000000-0000-0000-A000-4A414D460003")
            ],
            attachments: nil,
            applications: [
                MobileDeviceApplication(name: "Self Service", identifier: "com.jamfsoftware.selfservice", version: "1080", shortVersion: "11.3.4", managementStatus: "Managed", validationStatus: true, bundleSize: "45.2 MB", dynamicSize: "50.1 MB"),
                MobileDeviceApplication(name: "Reset", identifier: "com.jamf.reset", version: "138", shortVersion: "3.3.2", managementStatus: "Managed", validationStatus: true, bundleSize: "12.5 MB", dynamicSize: "15.0 MB")
            ],
            certificates: [
                MobileDeviceCertificate(commonName: "Test Certificate", identity: true, expirationDate: "2027-10-30T19:33:38Z", expirationDateEpoch: "2027-10-30T19:33:38Z", subjectName: "CN=Test,O=Test Org", serialNumber: "123456", sha1Fingerprint: "abc123", issuedDateEpoch: "2025-10-29T19:33:38Z", certificateStatus: "ISSUED", lifecycleStatus: "ACTIVE")
            ],
            provisioningProfiles: nil,
            ebooks: nil,
            serviceSubscriptions: nil,
            mdmCapableUsers: nil,
            iTunesStoreAccountActive: false,
            unlockToken: nil
        ),
        tvos: nil,
        watchos: nil,
        visionos: nil,
        declarativeDeviceManagementEnabled: true,
        extensionAttributes: [
            MobileDeviceExtensionAttribute(id: "1", name: "Custom Attribute", type: "STRING", value: ["Test Value"], inventoryDisplay: "General", extensionAttributeCollectionAllowed: true)
        ],
        managementId: "f7d9b4c5-eb25-4c0e-aab1-d62c72b98b3e",
        groups: [
            MobileDeviceGroup(groupId: "5", groupName: "iOS POC Staging", groupDescription: "Staging Group for iOS POC", smart: true),
            MobileDeviceGroup(groupId: "2", groupName: "All Managed iPhones", groupDescription: nil, smart: true)
        ]
    ))
    .frame(width: 1400, height: 900)
}
#endif
