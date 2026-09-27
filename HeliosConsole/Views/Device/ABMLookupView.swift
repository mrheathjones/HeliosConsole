//
//  ABMLookupView.swift
//  HeliosConsole
//
//  Apple Business Manager org-inventory lookup. Renders the full ABM device
//  sweep from ABMDeviceCache (populated on demand via ABMAPIService: MDM
//  server list → org device sweep → deviceId→serverId assignment map), with
//  search over serial / model / asset tag, Assigned/Unassigned filter chips,
//  a per-MDM-server filter menu, and a detail sheet that lazily fetches
//  AppleCare coverage per device. Asset tags come from a serial→assetTag
//  join against the Jamf computer inventory cache — ABM itself carries no
//  asset tags. If the core domain's appleBusinessManager block is not
//  delivered by profile, the whole tab is a not-configured notice.
//

import SwiftUI

// MARK: - Assignment Filter

private enum ABMAssignmentFilter: String, CaseIterable, Identifiable {
    case all
    case assigned
    case unassigned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .assigned: return "Assigned"
        case .unassigned: return "Unassigned"
        }
    }

    var color: Color {
        switch self {
        case .all: return .gray
        case .assigned: return .green
        case .unassigned: return .orange
        }
    }
}

// MARK: - ABM Lookup View

struct ABMLookupView: View {
    @ObservedObject private var abmService = ABMAPIService.shared
    @ObservedObject private var cache = ABMDeviceCache.shared
    /// Observed so assign/unassign gates re-evaluate on role change.
    @ObservedObject private var session = UserSession.shared

    @State private var searchText = ""
    @State private var assignmentFilter: ABMAssignmentFilter = .all
    @State private var selectedServerId: String?
    @State private var selectedDeviceType: ABMDeviceType = .all
    @State private var selectedDevice: ABMOrgDevice?
    @State private var isLoading = false
    @State private var loadError: String?

    /// Config-profile default filters (defaultMdmServerName / defaultDeviceType)
    /// are a STARTING POINT applied once — after that the operator's choices
    /// stand, so we never re-override a filter they cleared. Tracked
    /// INDEPENDENTLY: device type has no dependency and applies immediately,
    /// while the server default must wait for the server list to resolve its
    /// name→id. A shared flag made a configured server default (with a slow or
    /// failed server-list load) also swallow the device-type default.
    @State private var didApplyDefaultDeviceType = false
    @State private var didApplyDefaultServer = false

    // Assign / unassign flow state (PR D)
    @State private var assignSheetDevice: ABMOrgDevice?
    @State private var unassignConfirmDevice: ABMOrgDevice?
    @State private var isUnassigning = false
    @State private var actionResultTitle: String?
    @State private var actionResultMessage = ""
    @State private var actionResultSuccess = false

    /// serial (uppercased) → asset tag, joined from the Jamf computer
    /// inventory cache. Rebuilt on load/refresh — never inside `body`,
    /// where an O(n) sweep per evaluation would be far too hot.
    @State private var assetTagsBySerial: [String: String] = [:]

    @FocusState private var isSearchFocused: Bool

    // MARK: - Derived Data

    private var filteredDevices: [ABMOrgDevice] {
        let query = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return cache.devices.filter { device in
            switch assignmentFilter {
            case .all:
                break
            case .assigned:
                if !device.isAssigned { return false }
            case .unassigned:
                if device.isAssigned { return false }
            }

            if let serverId = selectedServerId,
               cache.assignmentMap[device.id] != serverId {
                return false
            }

            if !selectedDeviceType.matches(productFamily: device.productFamily) {
                return false
            }

            if !query.isEmpty {
                let assetTag = assetTagsBySerial[device.serialNumber.uppercased()] ?? ""
                let matches = device.serialNumber.lowercased().contains(query)
                    || (device.deviceModel ?? "").lowercased().contains(query)
                    || assetTag.lowercased().contains(query)
                if !matches { return false }
            }

            return true
        }
    }

    private var assignedCount: Int {
        cache.devices.filter { $0.isAssigned }.count
    }

    private var unassignedCount: Int {
        cache.devices.count - assignedCount
    }

    private func count(for filter: ABMAssignmentFilter) -> Int {
        switch filter {
        case .all: return cache.devices.count
        case .assigned: return assignedCount
        case .unassigned: return unassignedCount
        }
    }

    private var selectedServerName: String? {
        guard let id = selectedServerId else { return nil }
        return cache.mdmServers.first { $0.id == id }?.serverName
    }

    private var hasActiveFilters: Bool {
        !searchText.isEmpty || assignmentFilter != .all || selectedServerId != nil || selectedDeviceType != .all
    }

    /// Device types actually present in the inventory, in enum order, always
    /// including .all. Keeps the menu honest — no "iPad" option for a Mac-only
    /// org — while a configured default that no longer matches still resolves
    /// harmlessly to showing everything.
    private var availableDeviceTypes: [ABMDeviceType] {
        ABMDeviceType.allCases.filter { type in
            type == .all || cache.devices.contains { type.matches(productFamily: $0.productFamily) }
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Animated background matching app design
            AnimatedBackgroundView(animate: .constant(true))

            if !abmService.isConfigured {
                notConfiguredView
            } else {
                VStack(spacing: 0) {
                    headerSection
                    toolbarSection

                    if isLoading && cache.devices.isEmpty {
                        loadingView
                    } else if let error = loadError, cache.devices.isEmpty {
                        errorView(error: error)
                    } else if cache.devices.isEmpty {
                        emptyStateView
                    } else if filteredDevices.isEmpty {
                        emptySearchView
                    } else {
                        contentView
                    }
                }
            }
        }
        .task {
            rebuildAssetTagMap()
            applyConfigDefaultsIfNeeded()
            // Gate on isCacheValid, not hasCachedData: a tenant whose ABM
            // org is genuinely empty would otherwise re-sweep on every
            // tab entry (hasCachedData requires a non-empty device list).
            if abmService.isConfigured && !cache.isCacheValid && !isLoading {
                await loadInventory()
            }
            // Servers may have just landed via loadInventory — resolve a
            // configured default-server name now that the list exists.
            applyConfigDefaultsIfNeeded()
        }
        // The preload can populate the server list after this view's first
        // .task ran; re-attempt default resolution when it arrives.
        .onChange(of: cache.mdmServers.count) { _, _ in
            applyConfigDefaultsIfNeeded()
        }
        .sheet(item: $selectedDevice) { device in
            ABMDeviceDetailSheet(
                device: device,
                assignedServer: cache.assignedServer(forDeviceId: device.id),
                assetTag: assetTagsBySerial[device.serialNumber.uppercased()],
                canAssign: canAssign(device),
                canUnassign: canUnassign(device),
                // The detail sheet must close before the assign sheet /
                // confirmation can present — only one sheet may be up at a
                // time, so hand off on the next runloop pass.
                onAssign: {
                    selectedDevice = nil
                    Task { @MainActor in assignSheetDevice = device }
                },
                onUnassign: {
                    selectedDevice = nil
                    Task { @MainActor in unassignConfirmDevice = device }
                }
            )
        }
        .sheet(item: $assignSheetDevice) { device in
            ABMAssignmentSheet(
                serialNumber: device.serialNumber,
                deviceName: device.deviceModel ?? device.serialNumber,
                title: ActionBranding.label(for: .abmAssign),
                policyProvider: { policy(for: device) },
                onFinished: { success, _, error in
                    logAction(.abmAssign, device: device, success: success, error: error)
                }
            )
        }
        .confirmationDialog(
            DeviceAction.abmUnassign.title,
            isPresented: Binding(
                get: { unassignConfirmDevice != nil },
                set: { if !$0 { unassignConfirmDevice = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Unassign", role: .destructive) {
                if let device = unassignConfirmDevice {
                    unassignConfirmDevice = nil
                    Task { await executeUnassign(device) }
                }
            }
            Button("Cancel", role: .cancel) { unassignConfirmDevice = nil }
        } message: {
            Text(DeviceAction.abmUnassign.message)
        }
        .alert(
            actionResultTitle ?? "",
            isPresented: Binding(
                get: { actionResultTitle != nil },
                set: { if !$0 { actionResultTitle = nil } }
            )
        ) {
            Button("OK") { actionResultTitle = nil }
        } message: {
            Text(actionResultMessage)
        }
    }

    // MARK: - Data Loading

    /// Full inventory load: server list → device sweep → assignment map,
    /// then one atomic cache update. @MainActor because ABMDeviceCache is
    /// main-actor isolated; the service calls themselves hop off to await.
    @MainActor
    private func loadInventory() async {
        guard abmService.isConfigured else { return }
        // Reentrancy guard: Try Again / empty-state Refresh can be clicked
        // while a sweep is already running — never stack a second sweep.
        guard !isLoading else { return }

        isLoading = true
        loadError = nil

        do {
            try await cache.loadFromNetwork()
            rebuildAssetTagMap()
        } catch {
            loadError = error.localizedDescription
        }

        isLoading = false
    }

    /// Rebuilds the serial→assetTag join from the Jamf computer inventory
    /// cache. O(n) over the computer list, run only on load/refresh.
    @MainActor
    private func rebuildAssetTagMap() {
        var map: [String: String] = [:]
        let computers = ComputerInventoryCache.shared.computers
        map.reserveCapacity(computers.count)

        for computer in computers {
            if let serial = computer.hardware?.serialNumber,
               let assetTag = computer.general?.assetTag,
               !assetTag.isEmpty {
                map[serial.uppercased()] = assetTag
            }
        }

        assetTagsBySerial = map
    }

    /// Applies the config-profile default filters ONCE each, independently.
    /// Device type applies immediately (no dependency). The server default is
    /// named and needs the server list to resolve name→id, so it applies as
    /// soon as the list is present (re-attempted via the onChange below); a
    /// configured name that matches nothing settles on "Any Server". Called on
    /// appear, after a load, and whenever the server count changes.
    @MainActor
    private func applyConfigDefaultsIfNeeded() {
        let config = MDMConfigurationManager.shared.configuration

        if !didApplyDefaultDeviceType {
            selectedDeviceType = ABMDeviceType.from(config.abmDefaultDeviceType)
            didApplyDefaultDeviceType = true
            NSLog("ABM: Applied default device-type filter '%@' (config: %@)",
                  selectedDeviceType.rawValue, config.abmDefaultDeviceType ?? "nil")
        }

        if !didApplyDefaultServer {
            guard let name = config.abmDefaultMdmServerName else {
                didApplyDefaultServer = true  // none configured — nothing to do
                return
            }
            // Need the server list to resolve the name; retry when it arrives.
            guard !cache.mdmServers.isEmpty else { return }

            if let match = cache.mdmServers.first(where: {
                $0.serverName.caseInsensitiveCompare(name) == .orderedSame
            }) {
                selectedServerId = match.id
                NSLog("ABM: Applied default MDM server filter '%@' → id %@", name, match.id)
            } else {
                NSLog("ABM: Default MDM server '%@' matched no server in the %d loaded — leaving 'Any Server'",
                      name, cache.mdmServers.count)
            }
            didApplyDefaultServer = true
        }
    }

    @MainActor
    private func refresh() async {
        // Deliberately NOT cache.clearCache() first: loadInventory commits
        // atomically on success, so fetching before swapping keeps the
        // last-known-good inventory on screen through a failed refresh.
        // Only the AppleCare coverage cache is dropped up front (stale
        // coverage is the one thing a refresh must not preserve).
        ABMAPIService.shared.clearCache()
        cache.invalidateCache()
        await loadInventory()
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 20) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.2), Color.cyan.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)

                    Image(systemName: "apple.logo")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("ABM Lookup")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)

                    HStack(spacing: 8) {
                        Text("\(cache.devices.count) devices in Apple Business Manager")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)

                        if let lastFetch = cache.lastFetchDate {
                            Text("•")
                                .foregroundColor(.gray)
                            // Date + time: this inventory can be served from a
                            // persisted cache written on an earlier launch, so
                            // show how old it actually is, not just the time.
                            Text("Updated \(lastFetch.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                    }
                }
            }

            Spacer()

            // Refresh button — clears the cache and reloads
            RefreshButton(isLoading: isLoading) {
                Task { await refresh() }
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .background(Color.black.opacity(0.3))
    }

    // MARK: - Toolbar Section

    /// The toolbar never compresses its controls: `ViewThatFits` picks the
    /// widest arrangement that fits intact, then progressively stacks rows as
    /// the window narrows. Every leaf is `.fixedSize()`d so SwiftUI can't
    /// "solve" a tight layout by squeezing chip labels into vertical text.
    private var toolbarSection: some View {
        ViewThatFits(in: .horizontal) {
            // Widest: one row — chips, menus, count, search.
            HStack(spacing: 16) {
                filterChipsRow
                serverFilterMenu
                deviceTypeFilterMenu
                Spacer(minLength: 12)
                resultsCountLabel
                searchField.frame(width: 280)
            }

            // Medium: filters on one row, full-width search below.
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 16) {
                    filterChipsRow
                    serverFilterMenu
                    deviceTypeFilterMenu
                    Spacer(minLength: 12)
                    resultsCountLabel
                }
                searchField
            }

            // Narrow: chips, then menus + count, then search.
            VStack(alignment: .leading, spacing: 10) {
                filterChipsRow
                HStack(spacing: 10) {
                    serverFilterMenu
                    deviceTypeFilterMenu
                    Spacer(minLength: 12)
                    resultsCountLabel
                }
                searchField
            }

            // Narrowest: one control per row.
            VStack(alignment: .leading, spacing: 10) {
                filterChipsRow
                serverFilterMenu
                deviceTypeFilterMenu
                resultsCountLabel
                searchField
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.15))
    }

    private var filterChipsRow: some View {
        HStack(spacing: 8) {
            ForEach(ABMAssignmentFilter.allCases) { filter in
                filterChip(
                    title: filter.title,
                    count: count(for: filter),
                    isSelected: assignmentFilter == filter,
                    color: filter.color
                ) {
                    assignmentFilter = filter
                }
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private var resultsCountLabel: some View {
        if hasActiveFilters {
            Text("\(filteredDevices.count) of \(cache.devices.count) shown")
                .font(.system(size: 13))
                .foregroundColor(.gray)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.gray)

            TextField("", text: $searchText, prompt: Text("Search serial, model, asset tag...")
                .foregroundColor(.gray.opacity(0.6)))
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .focused($isSearchFocused)
                .frame(minWidth: 140)

            if !searchText.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        searchText = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSearchFocused ? Color.blue.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var serverFilterMenu: some View {
        Menu {
            Button("Any Server") {
                selectedServerId = nil
            }

            if !cache.mdmServers.isEmpty {
                Divider()

                ForEach(cache.mdmServers) { server in
                    Button {
                        selectedServerId = server.id
                    } label: {
                        if selectedServerId == server.id {
                            Label(server.serverName, systemImage: "checkmark")
                        } else {
                            Text(server.serverName)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "server.rack")
                    .font(.system(size: 11, weight: .medium))
                Text(selectedServerName ?? "Any Server")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundColor(selectedServerId != nil ? .white : .white.opacity(0.8))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(selectedServerId != nil ? Color.blue : Color.white.opacity(0.05))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selectedServerId != nil ? Color.blue : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var deviceTypeFilterMenu: some View {
        let isActive = selectedDeviceType != .all
        return Menu {
            ForEach(availableDeviceTypes) { type in
                Button {
                    selectedDeviceType = type
                } label: {
                    if selectedDeviceType == type {
                        Label(type.title, systemImage: "checkmark")
                    } else {
                        Text(type.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selectedDeviceType.icon)
                    .font(.system(size: 11, weight: .medium))
                Text(selectedDeviceType.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundColor(isActive ? .white : .white.opacity(0.8))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isActive ? Color.blue : Color.white.opacity(0.05))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? Color.blue : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func filterChip(title: String, count: Int, isSelected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()

                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? Color.white.opacity(0.3) : color.opacity(0.2))
                    .cornerRadius(4)
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.8))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? color : Color.white.opacity(0.05))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? color : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content

    /// Below this list width the row's device metadata and two labelled
    /// action buttons start fighting for the same space, so the buttons
    /// collapse to icon-only (tooltip + accessibility label keep the meaning).
    private static let iconOnlyActionsWidthThreshold: CGFloat = 720

    private var contentView: some View {
        GeometryReader { proxy in
            let iconOnlyActions = proxy.size.width < Self.iconOnlyActionsWidthThreshold

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filteredDevices) { device in
                        ABMDeviceRow(
                            device: device,
                            serverName: cache.assignedServer(forDeviceId: device.id)?.serverName,
                            assetTag: assetTagsBySerial[device.serialNumber.uppercased()],
                            canAssign: canAssign(device),
                            canUnassign: canUnassign(device),
                            iconOnlyActions: iconOnlyActions,
                            onAssign: { assignSheetDevice = device },
                            onUnassign: { unassignConfirmDevice = device },
                            onTap: { selectedDevice = device }
                        )
                        .contextMenu { actionMenuItems(for: device) }
                    }
                }
                .padding(32)
            }
        }
    }

    // MARK: - Assign / Unassign Actions

    /// Policy for THIS device's platform: Macs consult the computer action
    /// grants, known non-Mac families the mobile-device grants. A device
    /// whose family is missing entirely gets .denyAll — when the platform
    /// cannot be determined, no policy branch may be assumed (fail-closed).
    private func policy(for device: ABMOrgDevice) -> DeviceActionPolicy {
        guard let family = device.productFamily,
              !family.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .denyAll
        }
        let config = MDMConfigurationManager.shared.configuration
        if family.caseInsensitiveCompare("Mac") == .orderedSame {
            return config.computerActionPolicy(capabilities: session.capabilities)
        }
        return config.mobileDeviceActionPolicy(capabilities: session.capabilities)
    }

    /// Single source of truth for whether the assign affordance is offered —
    /// shared by the inline row buttons, the detail sheet, and the context
    /// menu so the three can never drift apart.
    private func canAssign(_ device: ABMOrgDevice) -> Bool {
        policy(for: device).isAllowed(.abmAssign)
    }

    private func canUnassign(_ device: ABMOrgDevice) -> Bool {
        policy(for: device).isAllowed(.abmUnassign) && cache.assignmentMap[device.id] != nil
    }

    @ViewBuilder
    private func actionMenuItems(for device: ABMOrgDevice) -> some View {
        let devicePolicy = policy(for: device)
        if devicePolicy.isAllowed(.abmAssign) {
            Button {
                assignSheetDevice = device
            } label: {
                Label(ActionBranding.label(for: .abmAssign), systemImage: ActionBranding.icon(for: .abmAssign))
            }
        }
        if devicePolicy.isAllowed(.abmUnassign), cache.assignmentMap[device.id] != nil {
            Button(role: .destructive) {
                unassignConfirmDevice = device
            } label: {
                Label(ActionBranding.label(for: .abmUnassign), systemImage: ActionBranding.icon(for: .abmUnassign))
            }
        }
    }

    /// Unassigns `device` from its current server — the same rules as the
    /// Device Details flow: the grant's allowedMdmServers governs which
    /// servers the operator may unassign FROM, and the policy is re-checked
    /// here (defense in depth), never trusted from the menu.
    @MainActor
    private func executeUnassign(_ device: ABMOrgDevice) async {
        guard !isUnassigning else { return }
        let devicePolicy = policy(for: device)
        if devicePolicy.denialReason(for: .abmUnassign) != nil {
            // Defense-in-depth denial: surface AND audit-log it — never a
            // silent drop. Gating is role-only now, so the reason is always
            // the role capability.
            showResult(false, "Action Not Permitted",
                       "Unassigning from an MDM server is not available for your role.")
            logAction(.abmUnassign, device: device, success: false,
                      error: "Blocked by role capability (no held role grants 'abmUnassign' on computers)")
            return
        }

        isUnassigning = true
        defer { isUnassigning = false }

        do {
            let servers = try await ABMAssignmentExecutor.loadServers()
            guard let current = try await ABMAssignmentExecutor.currentServer(for: device, servers: servers) else {
                showResult(false, "Unassign from MDM Server",
                           "The device is not assigned to any MDM server — there is nothing to unassign.")
                return
            }

            guard devicePolicy.canAssignToMdmServer(named: current.serverName) else {
                showResult(false, "Not Permitted",
                           "Your role's grant does not permit unassigning devices from \(current.serverName).")
                logAction(.abmUnassign, device: device, success: false,
                          error: "Denied by allowedMdmServers for server \(current.serverName)")
                return
            }

            let outcome = try await ABMAPIService.shared.performAssignment(
                .unassignDevices, deviceId: device.id, mdmServerId: current.id
            )
            switch outcome {
            case .succeeded:
                cache.applyAssignment(deviceId: device.id, serverId: nil)
                showResult(true, "Unassigned from \(current.serverName)",
                           "Until the device is reassigned, it cannot enroll via Automated Device Enrollment.")
                logAction(.abmUnassign, device: device, success: true, error: nil)
            case .completedWithErrors(let detail):
                showResult(false, "Completed With Errors", detail)
                logAction(.abmUnassign, device: device, success: false, error: "COMPLETED_WITH_ERROR")
            case .failed(let status):
                showResult(false, "Unassign Failed", "Apple Business Manager reported the activity as \(status).")
                logAction(.abmUnassign, device: device, success: false, error: status)
            case .stillRunning(let activityId):
                showResult(false, "Still Processing",
                           "Apple accepted the request but it had not completed when polling stopped (activity \(activityId)). Refresh shortly to confirm.")
                logAction(.abmUnassign, device: device, success: false, error: "Timed out polling \(activityId)")
            }
        } catch {
            showResult(false, "Unassign Failed", error.localizedDescription)
            logAction(.abmUnassign, device: device, success: false, error: error.localizedDescription)
        }
    }

    @MainActor
    private func showResult(_ success: Bool, _ title: String, _ message: String) {
        actionResultSuccess = success
        actionResultTitle = title
        actionResultMessage = message
    }

    private func logAction(_ action: DeviceAction, device: ABMOrgDevice, success: Bool, error: String?) {
        ActionLogService.shared.logAction(
            actionName: action.logName,
            actionCategory: action.logCategory,
            deviceName: device.deviceModel ?? device.serialNumber,
            deviceSerialNumber: device.serialNumber,
            deviceId: device.id,
            devicePlatform: device.productFamily?.caseInsensitiveCompare("Mac") == .orderedSame ? "macOS" : (device.productFamily ?? "Unknown"),
            success: success,
            errorMessage: error
        )
    }

    // MARK: - Not Configured

    private var notConfiguredView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "apple.logo")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundColor(.blue.opacity(0.6))
            }

            VStack(spacing: 12) {
                Text("Apple Business Manager Is Not Configured")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)

                Text("ABM lookups require the core domain's appleBusinessManager block and its credentials private key, delivered by configuration profile. Contact your administrator to enable the integration.")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }

            Spacer()
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading Apple Business Manager inventory...")
                .font(.system(size: 14))
                .foregroundColor(.gray)
            Spacer()
        }
    }

    // MARK: - Error View

    private func errorView(error: String) -> some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.red)
            }

            VStack(spacing: 8) {
                Text("Unable to Load ABM Inventory")
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
                    await loadInventory()
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
                .background(Color.blue)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    // MARK: - Empty States

    /// Empty ORG INVENTORY — ABM answered but returned no devices.
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "apple.logo")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundColor(.blue.opacity(0.6))
            }

            VStack(spacing: 12) {
                Text("No Devices in Apple Business Manager")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)

                Text("The organization's ABM inventory is empty.\nDevices will appear here once added to Apple Business Manager.")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            Button {
                Task {
                    await refresh()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.blue)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    /// Empty SEARCH RESULT — inventory exists, filters matched nothing.
    private var emptySearchView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "magnifyingglass")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundColor(.gray.opacity(0.6))
            }

            VStack(spacing: 12) {
                Text("No Matching Devices")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)

                Text("None of the \(cache.devices.count) devices in Apple Business Manager match the current search and filters.")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    searchText = ""
                    assignmentFilter = .all
                    selectedServerId = nil
                    selectedDeviceType = .all
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle")
                    Text("Clear Filters")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }
}

// MARK: - Product Family Icon

/// SF Symbol for an ABM productFamily string. Shared by the row and the
/// detail sheet.
private func abmFamilyIcon(for productFamily: String?) -> String {
    let family = (productFamily ?? "").lowercased()
    if family.contains("iphone") { return "iphone" }
    if family.contains("ipad") { return "ipad" }
    if family.contains("tv") { return "appletv" }
    if family.contains("watch") { return "applewatch" }
    if family.contains("vision") { return "visionpro" }
    if family.contains("mac") { return "laptopcomputer" }
    return "questionmark.square"
}

// MARK: - ABM Device Row

struct ABMDeviceRow: View {
    let device: ABMOrgDevice
    let serverName: String?
    let assetTag: String?
    /// Role-gated: mirrors the same policy check that governs the context menu.
    let canAssign: Bool
    let canUnassign: Bool
    /// Collapses the action buttons to their glyphs when the list is too
    /// narrow to carry the labels alongside the device metadata.
    let iconOnlyActions: Bool
    let onAssign: () -> Void
    let onUnassign: () -> Void
    let onTap: () -> Void

    @State private var isHovered = false

    private var statusColor: Color {
        device.isAssigned ? .green : .orange
    }

    private var statusTitle: String {
        device.isAssigned ? "ASSIGNED" : "UNASSIGNED"
    }

    var body: some View {
        // NOTE: this is a tap-gesture container, not a Button — the row holds
        // real Buttons (Assign / Unassign) and nested buttons inside a Button
        // label do not reliably receive their own clicks on macOS.
        HStack(spacing: 16) {
                // Product family icon tile
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 48, height: 48)

                    Image(systemName: abmFamilyIcon(for: device.productFamily))
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }

                // Device info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(device.serialNumber)
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)

                        // Assignment status capsule
                        Text(statusTitle)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(statusColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(statusColor.opacity(0.15)))

                        if device.isAssigned, let serverName {
                            HStack(spacing: 4) {
                                Image(systemName: "server.rack")
                                    .font(.system(size: 9))
                                Text(serverName)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.gray)
                            .lineLimit(1)
                        }
                    }

                    HStack(spacing: 12) {
                        if let model = device.deviceModel {
                            Text(model)
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                        }

                        if let color = device.color, !color.isEmpty {
                            Text("•")
                                .foregroundColor(.gray.opacity(0.5))
                            Text(color.capitalized)
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                        }
                    }

                    HStack(spacing: 12) {
                        if let assetTag {
                            HStack(spacing: 4) {
                                Image(systemName: "tag.fill")
                                    .font(.system(size: 10))
                                Text(assetTag)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.blue)
                        }

                        if let added = device.addedToOrgDate {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar.badge.plus")
                                    .font(.system(size: 10))
                                Text("Added \(added.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(.gray.opacity(0.7))
                        }
                    }
                }

                Spacer()

                // Role-gated actions — visible affordances, not hidden behind
                // the right-click menu (which stays as a secondary path).
                HStack(spacing: 8) {
                    if canAssign {
                        ABMActionButton(
                            title: ActionBranding.label(for: .abmAssign),
                            systemImage: ActionBranding.icon(for: .abmAssign),
                            tint: .blue,
                            compact: true,
                            iconOnly: iconOnlyActions,
                            action: onAssign
                        )
                    }
                    if canUnassign {
                        ABMActionButton(
                            title: ActionBranding.label(for: .abmUnassign),
                            systemImage: ActionBranding.icon(for: .abmUnassign),
                            tint: .red,
                            compact: true,
                            iconOnly: iconOnlyActions,
                            action: onUnassign
                        )
                    }
                }

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray.opacity(0.5))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(isHovered ? 0.06 : 0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(isHovered ? 0.1 : 0.05), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { isHovered = $0 }
    }
}

// MARK: - ABM Action Button

/// A real, obviously-clickable button for the ABM assign/unassign actions.
/// Filled tint + border so it never reads as a plain clickable label.
struct ABMActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    var compact: Bool = false
    /// Glyph only — the label moves to the tooltip and the accessibility
    /// label, so the control stays legible to VoiceOver when it collapses.
    var iconOnly: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: compact ? 11 : 13, weight: .semibold))
                if !iconOnly {
                    Text(title)
                        .font(.system(size: compact ? 12 : 13, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .foregroundColor(tint)
            .padding(.horizontal, iconOnly ? 9 : (compact ? 12 : 16))
            .padding(.vertical, compact ? 7 : 10)
            .frame(maxWidth: compact ? nil : .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint.opacity(isHovered ? 0.28 : 0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(tint.opacity(isHovered ? 0.8 : 0.45), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(title)
        .accessibilityLabel(title)
    }
}

// MARK: - ABM Device Detail Sheet

struct ABMDeviceDetailSheet: View {
    let device: ABMOrgDevice
    let assignedServer: ABMMdmServer?
    let assetTag: String?
    /// Role-gated by the caller with the same policy the row and menu use.
    let canAssign: Bool
    let canUnassign: Bool
    let onAssign: () -> Void
    let onUnassign: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var coverages: [AppleCareCoverage] = []
    @State private var isLoadingCoverage = true
    @State private var coverageUnavailable = false

    private var statusColor: Color {
        device.isAssigned ? .green : .orange
    }

    private var statusTitle: String {
        device.isAssigned ? "ASSIGNED" : "UNASSIGNED"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with gradient accent
            VStack(spacing: 16) {
                HStack(alignment: .top) {
                    // Product family icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 96, height: 96)

                        Image(systemName: abmFamilyIcon(for: device.productFamily))
                            .font(.system(size: 40, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(device.serialNumber)
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)

                        if let model = device.deviceModel {
                            Text(model)
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }

                        // Status badge
                        HStack(spacing: 6) {
                            Image(systemName: device.isAssigned ? "checkmark.circle.fill" : "circle.dashed")
                                .font(.system(size: 11, weight: .semibold))
                            Text(statusTitle)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(statusColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(statusColor.opacity(0.2))
                        .cornerRadius(6)
                    }
                    .padding(.leading, 8)

                    Spacer()

                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.gray)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.white.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .background(Color.white.opacity(0.03))

            Divider()
                .background(Color.white.opacity(0.1))

            // Content
            ScrollView {
                VStack(spacing: 16) {
                    deviceCard
                    identifiersCard
                    assignmentCard
                    datesCard
                    appleCareCard
                }
                .padding(20)
            }

            if canAssign || canUnassign {
                Divider()
                    .background(Color.white.opacity(0.1))

                HStack(spacing: 12) {
                    if canAssign {
                        ABMActionButton(
                            title: ActionBranding.label(for: .abmAssign),
                            systemImage: ActionBranding.icon(for: .abmAssign),
                            tint: .blue,
                            action: onAssign
                        )
                    }
                    if canUnassign {
                        ABMActionButton(
                            title: ActionBranding.label(for: .abmUnassign),
                            systemImage: ActionBranding.icon(for: .abmUnassign),
                            tint: .red,
                            action: onUnassign
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.03))
            }
        }
        .frame(width: 520, height: 640)
        .background(.ultraThinMaterial.opacity(0.8))
        .background(Color(white: 0.06).opacity(0.7))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .task {
            await loadCoverage()
        }
    }

    // MARK: - Cards

    private var deviceCard: some View {
        DetailCard(title: "Device", icon: abmFamilyIcon(for: device.productFamily)) {
            VStack(spacing: 12) {
                if let model = device.deviceModel {
                    DetailRow("Model", model)
                }

                if let family = device.productFamily {
                    DetailRow("Product Family", family)
                }

                if let productType = device.productType {
                    DetailRow("Product Type", productType, monospaced: true)
                }

                if let capacity = device.deviceCapacity {
                    DetailRow("Capacity", capacity)
                }

                if let color = device.color, !color.isEmpty {
                    DetailRow("Color", color.capitalized)
                }
            }
        }
    }

    private var identifiersCard: some View {
        DetailCard(title: "Identifiers", icon: "number") {
            VStack(spacing: 12) {
                DetailRow("Serial Number", device.serialNumber, monospaced: true)

                if let assetTag {
                    DetailRow("Asset Tag", assetTag)
                }
            }
        }
    }

    private var assignmentCard: some View {
        DetailCard(title: "Assignment", icon: "server.rack") {
            VStack(spacing: 12) {
                HStack {
                    // Same label column as DetailRow so the badge lines up
                    // with the values below it.
                    Text("Status")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                        .frame(width: 180, alignment: .leading)

                    Text(statusTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(statusColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(statusColor.opacity(0.15)))

                    Spacer()
                }

                if let server = assignedServer {
                    DetailRow("MDM Server", server.serverName)

                    if let serverType = server.serverType {
                        DetailRow("Server Type", serverType)
                    }
                }
            }
        }
    }

    private var datesCard: some View {
        DetailCard(title: "Dates", icon: "calendar") {
            VStack(spacing: 12) {
                if let added = formatISODate(device.addedToOrgDateTime) {
                    DetailRow("Added to Org", added)
                }

                if let updated = formatISODate(device.updatedDateTime) {
                    DetailRow("Last Updated", updated)
                }

                if let ordered = formatISODate(device.orderDateTime) {
                    DetailRow("Order Date", ordered)
                }

                if let orderNumber = device.orderNumber, !orderNumber.isEmpty {
                    DetailRow("Order Number", orderNumber, monospaced: true)
                }
            }
        }
    }

    private var appleCareCard: some View {
        DetailCard(title: "AppleCare", icon: "cross.case") {
            VStack(spacing: 12) {
                if isLoadingCoverage {
                    HStack(spacing: 10) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Checking coverage...")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                        Spacer()
                    }
                } else if coverageUnavailable {
                    HStack {
                        Text("AppleCare information unavailable")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                        Spacer()
                    }
                } else if coverages.isEmpty {
                    HStack {
                        Text("No coverage records for this device")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                        Spacer()
                    }
                } else {
                    ForEach(coverages) { coverage in
                        coverageRow(coverage)

                        if coverage.id != coverages.last?.id {
                            Divider()
                                .background(Color.white.opacity(0.06))
                        }
                    }
                }
            }
        }
    }

    private func coverageRow(_ coverage: AppleCareCoverage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(coverage.description)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)

                Text(coverage.isActive ? "ACTIVE" : "INACTIVE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(coverage.isActive ? .green : .gray)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill((coverage.isActive ? Color.green : Color.gray).opacity(0.15)))

                Spacer()
            }

            if let end = coverage.endDate {
                HStack(spacing: 6) {
                    Text("Ends \(end.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)

                    if let days = coverage.daysRemaining {
                        Text("•")
                            .foregroundColor(.gray.opacity(0.5))

                        if coverage.isExpired {
                            Text("Expired \(-days) day\(days == -1 ? "" : "s") ago")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.red)
                        } else {
                            Text("\(days) day\(days == 1 ? "" : "s") remaining")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(coverage.isExpiringSoon ? .orange : .gray)
                        }
                    }
                }
            }
        }
    }

    // MARK: - AppleCare Loading

    /// Fail-soft: coverage is a nice-to-have on top of the org record, so
    /// any error collapses to a plain "unavailable" line, never an alert.
    @MainActor
    private func loadCoverage() async {
        isLoadingCoverage = true
        coverageUnavailable = false

        do {
            coverages = try await ABMAPIService.shared.getAppleCareCoverage(forSerialNumber: device.serialNumber)
        } catch {
            coverageUnavailable = true
        }

        isLoadingCoverage = false
    }

    // MARK: - Card Helpers

    private func formatISODate(_ isoString: String?) -> String? {
        guard let date = ABMDateParser.date(from: isoString) else { return nil }
        return Self.displayFormatter.string(from: date)
    }

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - Preview

#if DEBUG
#Preview("ABM Lookup") {
    ABMLookupView()
        .frame(width: 1200, height: 800)
}
#endif
