//
//  CleanupViewModel.swift
//  HeliosConsole
//
//  Drives the Cleanup feature: loads stale Jamf Pro computers, holds the
//  multi-selection, and runs bulk actions with bounded concurrency.
//  Ported from Clean Slate's AppModel; credentials now come from Helios's
//  MDM configuration via CleanupSettings.
//

import Foundation
import Observation

@MainActor
@Observable
final class CleanupViewModel {
    let settings = CleanupSettings()

    // Device list state
    var devices: [StaleDevice] = []
    var selection: Set<Int> = []
    var isLoading = false
    var lastRefresh: Date?
    var loadError: String?

    // Dashboard metrics
    var totalComputers: Int?

    // Jamf Protect state
    var protectDevices: [ProtectDevice] = []
    var protectLoaded = false
    var protectError: String?

    /// Protect records whose last check-in is older than the stale
    /// threshold (never-checked-in counts as stale).
    var protectStaleDevices: [ProtectDevice] {
        let cutoff = Date().addingTimeInterval(-TimeInterval(settings.staleDays) * 86_400)
        return protectDevices.filter { ($0.checkin ?? .distantPast) < cutoff }
    }

    func protectDevices(for filter: ProtectFilter) -> [ProtectDevice] {
        switch filter {
        case .all: protectDevices
        case .stale: protectStaleDevices
        }
    }

    struct SiteCount: Identifiable {
        let name: String
        let count: Int
        var id: String { name }
    }

    /// Stale devices still marked managed — the population every stale
    /// metric is computed over.
    var managedStale: [StaleDevice] {
        devices.filter(\.isManaged)
    }

    /// Stale devices whose record is already unmanaged.
    var unmanagedStaleCount: Int {
        devices.count(where: { !$0.isManaged })
    }

    var staleOverYearCount: Int {
        managedStale.count(where: \.isStaleOverOneYear)
    }

    /// Managed stale device counts grouped by site, most stale first.
    var staleBySite: [SiteCount] {
        Dictionary(grouping: managedStale, by: \.siteName)
            .map { SiteCount(name: $0.key, count: $0.value.count) }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
    }

    var topStaleSite: SiteCount? { staleBySite.first }

    // Lookup data for pickers
    var sites: [JamfSite] = []
    var staticGroups: [StaticGroup] = []

    // Action run state
    var isRunningActions = false
    var actionProgress: Double = 0
    var actionResults: [ActionResult] = []

    private var jamfClient: JamfCleanupClient?
    private var protectClient: JamfProtectClient?

    var selectedDevices: [StaleDevice] {
        devices.filter { selection.contains($0.id) }
    }

    // MARK: - Client management

    private func client() throws -> JamfCleanupClient {
        if let jamfClient { return jamfClient }
        guard settings.isConfigured, let url = settings.normalizedJamfURL else {
            throw JamfCleanupError.notConfigured
        }
        let client = JamfCleanupClient(
            baseURL: url,
            clientID: settings.jamfClientID,
            clientSecret: settings.jamfClientSecret,
            pageSize: settings.pageSize
        )
        jamfClient = client
        return client
    }

    private func protect() throws -> JamfProtectClient {
        if let protectClient { return protectClient }
        guard settings.isProtectConfigured, let url = settings.normalizedProtectURL else {
            throw JamfCleanupError.protectNotConfigured
        }
        let client = JamfProtectClient(
            baseURL: url,
            clientID: settings.protectClientID,
            password: settings.protectClientPassword
        )
        protectClient = client
        return client
    }

    /// Call after credentials/URLs change so new values take effect.
    func resetClients() async {
        await invalidateSessions()
        jamfClient = nil
        protectClient = nil
    }

    /// Release server-side tokens (called when the app backgrounds).
    func invalidateSessions() async {
        if let jamfClient {
            await jamfClient.invalidateToken()
        }
        if let protectClient {
            await protectClient.invalidate()
        }
    }

    // MARK: - Loading

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let client = try client()
            let days = settings.staleDays
            async let totalTask = client.fetchTotalComputerCount()
            devices = try await client.fetchStaleComputers(olderThanDays: days)
            totalComputers = try await totalTask
            selection.formIntersection(devices.map(\.id))
            lastRefresh = Date()
        } catch {
            loadError = error.localizedDescription
        }

        // Jamf Protect is independent: its failure never blocks the
        // Jamf Pro view, it just surfaces on the dashboard.
        if settings.isProtectConfigured {
            do {
                let protect = try protect()
                protectDevices = try await protect.fetchAllComputers()
                protectLoaded = true
                protectError = nil
            } catch {
                protectError = error.localizedDescription
            }
        } else {
            protectDevices = []
            protectLoaded = false
            protectError = nil
        }
    }

    /// Deletes records from Jamf Protect only — Jamf Pro is untouched.
    /// Returns per-device results and prunes successes from local state.
    func deleteProtectDevices(_ targets: [ProtectDevice]) async -> [ActionResult] {
        var results: [ActionResult] = []
        var deletedUUIDs: Set<String> = []
        do {
            let protect = try protect()
            await withTaskGroup(of: (String, ActionResult).self) { group in
                var iterator = targets.makeIterator()
                var inFlight = 0

                func addNext() {
                    guard let device = iterator.next() else { return }
                    inFlight += 1
                    group.addTask {
                        do {
                            try await protect.deleteComputer(uuid: device.uuid)
                            return (device.uuid, ActionResult(
                                deviceName: device.hostName, action: .deleteFromProtect,
                                success: true, message: "OK"
                            ))
                        } catch {
                            return ("", ActionResult(
                                deviceName: device.hostName, action: .deleteFromProtect,
                                success: false, message: error.localizedDescription
                            ))
                        }
                    }
                }

                for _ in 0..<min(4, targets.count) { addNext() }
                while inFlight > 0 {
                    guard let (uuid, result) = await group.next() else { break }
                    inFlight -= 1
                    if !uuid.isEmpty { deletedUUIDs.insert(uuid) }
                    results.append(result)
                    addNext()
                }
            }
            protectDevices.removeAll { deletedUUIDs.contains($0.uuid) }
        } catch {
            results = targets.map {
                ActionResult(
                    deviceName: $0.hostName, action: .deleteFromProtect,
                    success: false, message: error.localizedDescription
                )
            }
        }
        return results
    }

    func loadLookups() async {
        do {
            let client = try client()
            async let sitesTask = client.fetchSites()
            async let groupsTask = client.fetchStaticGroups()
            sites = try await sitesTask
            staticGroups = try await groupsTask
        } catch {
            // Pickers degrade gracefully; the action sheet shows the error.
            loadError = error.localizedDescription
        }
    }

    func toggleSelection(_ id: Int) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    /// Tri-state select-all over whatever subset is currently visible:
    /// if every visible device is selected, deselect them; otherwise
    /// select them all (leaving selections outside the subset alone).
    func toggleSelectAll(in visible: [StaleDevice]) {
        let ids = Set(visible.map(\.id))
        if ids.isSubset(of: selection) {
            selection.subtract(ids)
        } else {
            selection.formUnion(ids)
        }
    }

    func clearSelection() {
        selection.removeAll()
    }

    // MARK: - Action engine

    /// Runs the chosen actions against every selected device.
    ///
    /// Order matters: unmanage and organize first, Protect cleanup next,
    /// and the Jamf Pro record deletion strictly last — once the record
    /// is gone no other Jamf Pro action can target the device.
    func runActions(_ plan: ActionPlan) async {
        let targets = selectedDevices
        guard !targets.isEmpty, !plan.isEmpty else { return }

        isRunningActions = true
        actionResults = []
        actionProgress = 0

        var completedSteps = 0.0
        var totalSteps = 0.0
        if plan.unmanage { totalSteps += Double(targets.count) }
        if plan.addToGroupID != nil { totalSteps += 1 }
        if plan.moveToSiteID != nil { totalSteps += Double(targets.count) }
        if plan.deleteFromProtect { totalSteps += Double(targets.count) }
        if plan.deleteRecord { totalSteps += Double(targets.count) }

        func bump() {
            completedSteps += 1
            actionProgress = totalSteps > 0 ? completedSteps / totalSteps : 1
        }

        do {
            let client = try client()

            // 1. Unmanage
            if plan.unmanage {
                await forEachDevice(targets, action: .unmanage) { device in
                    try await client.unmanage(computerID: device.id)
                } onResult: { result in
                    self.actionResults.append(result)
                    bump()
                }
            }

            // 2. Static group — one bulk call
            if let groupID = plan.addToGroupID {
                do {
                    try await client.addComputers(targets.map(\.id), toStaticGroup: groupID)
                    actionResults.append(ActionResult(
                        deviceName: "\(targets.count) devices",
                        action: .addToGroup, success: true,
                        message: "Added to “\(plan.addToGroupName ?? "group")”"
                    ))
                } catch {
                    actionResults.append(ActionResult(
                        deviceName: "\(targets.count) devices",
                        action: .addToGroup, success: false,
                        message: error.localizedDescription
                    ))
                }
                bump()
            }

            // 3. Site
            if let siteID = plan.moveToSiteID {
                await forEachDevice(targets, action: .moveToSite) { device in
                    try await client.moveComputer(device.id, toSite: siteID)
                } onResult: { result in
                    self.actionResults.append(result)
                    bump()
                }
            }

            // 4. Jamf Protect
            if plan.deleteFromProtect {
                do {
                    let protect = try protect()
                    await forEachDevice(targets, action: .deleteFromProtect) { device in
                        guard device.serialNumber != "—" else {
                            throw JamfCleanupError.protectGraphQL("No serial number on record.")
                        }
                        if let uuid = try await protect.findComputerUUID(serial: device.serialNumber) {
                            try await protect.deleteComputer(uuid: uuid)
                        }
                        // No Protect record is a success: nothing to clean up.
                    } onResult: { result in
                        self.actionResults.append(result)
                        bump()
                    }
                } catch {
                    for device in targets {
                        actionResults.append(ActionResult(
                            deviceName: device.name, action: .deleteFromProtect,
                            success: false, message: error.localizedDescription
                        ))
                        bump()
                    }
                }
            }

            // 5. Delete record — always last
            if plan.deleteRecord {
                await forEachDevice(targets, action: .deleteRecord) { device in
                    try await client.deleteComputer(device.id)
                } onResult: { result in
                    self.actionResults.append(result)
                    bump()
                }
            }
        } catch {
            actionResults.append(ActionResult(
                deviceName: "—", action: .deleteRecord, success: false,
                message: error.localizedDescription
            ))
        }

        isRunningActions = false
        actionProgress = 1

        // Refresh the list so completed work is reflected.
        await refresh()
    }

    /// Runs `work` for each device with bounded concurrency (Jamf Cloud
    /// rate limits punish bursts — cap at 4 in flight).
    private func forEachDevice(
        _ devices: [StaleDevice],
        action: DeviceAction,
        work: @escaping @Sendable (StaleDevice) async throws -> Void,
        onResult: @MainActor (ActionResult) -> Void
    ) async {
        await withTaskGroup(of: ActionResult.self) { group in
            var iterator = devices.makeIterator()
            var inFlight = 0

            func addNext() {
                guard let device = iterator.next() else { return }
                inFlight += 1
                group.addTask {
                    do {
                        try await work(device)
                        return ActionResult(
                            deviceName: device.name, action: action,
                            success: true, message: "OK"
                        )
                    } catch {
                        return ActionResult(
                            deviceName: device.name, action: action,
                            success: false, message: error.localizedDescription
                        )
                    }
                }
            }

            for _ in 0..<min(4, devices.count) { addNext() }
            while inFlight > 0 {
                guard let result = await group.next() else { break }
                inFlight -= 1
                onResult(result)
                addNext()
            }
        }
    }

    // MARK: - Connection tests (Settings)

    func testJamfConnection() async -> Result<String, Error> {
        await resetClients()
        return await CleanupConnectionTester.testJamf(settings)
    }

    func testProtectConnection() async -> Result<String, Error> {
        await resetClients()
        return await CleanupConnectionTester.testProtect(settings)
    }
}
