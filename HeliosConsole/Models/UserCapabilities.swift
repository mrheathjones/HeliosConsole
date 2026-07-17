//
//  UserCapabilities.swift
//  HeliosConsole
//
//  The resolved set of things the signed-in user may do, produced by
//  unioning the profile-defined role definitions the user holds
//  (MDMConfiguration.capabilities(forRoleNames:)).
//
//  NOTHING HERE IS HARDCODED. There is no built-in module list, no built-in
//  action classification, and no default role. Every id in these sets came
//  out of the access domain's `roles` block, which the admin authors. An
//  empty set grants nothing — which is why `.none` (all sets empty) is the
//  fail-closed value used before sign-in, on sign-out, and whenever role
//  resolution finds no match.
//
//  Ids are matched EXACTLY (case-sensitive):
//    • modules              → sidebar/route ids (NavigationDestination raw values),
//                             ORDERED — the position of an id in a role's
//                             `modules` array IS its sidebar row order
//    • deviceTabs           → Devices-view tab ids (e.g. abmLookup, prestage),
//                             ORDERED like modules — array position is tab order
//    • computerActions      → DeviceAction raw values
//    • mobileDeviceActions  → DeviceAction raw values
//    • cleanupActions       → CleanupAction.configID values
//
//  Capabilities are the USER-scoped layer only. They never widen the
//  machine-scoped layers (the access domain's deviceActions allow-list, the
//  features domain's kill switches) — DeviceActionPolicy intersects the two.
//
//  NOTE: `canRunCleanupAction(_:)` lives in Cleanup/Models/CleanupModels.swift,
//  not here — CleanupAction is only compiled into the HeliosConsole target,
//  and this file is in both targets.
//

import Foundation

struct UserCapabilities: Equatable {

    /// Sidebar/route ids the user may open, IN SIDEBAR ORDER — first element
    /// is the topmost row. THE ONLY ORDERED capability: the admin sets a
    /// role's order by arranging its `modules` array, so enabling a module and
    /// placing it are one edit in one place. There is no `order` key anywhere;
    /// the ui domain's sidebarItems carries presence/label/icon only.
    ///
    /// Deduplicated on first appearance by `init` — so `union(_:)` can simply
    /// concatenate and the "first appearance wins" rule holds for every
    /// construction path, not just the union one.
    let modules: [String]

    /// `modules` as a set, so `canAccess(module:)` stays O(1) while `modules`
    /// itself stays ordered. Derived — excluded from `==` (see below).
    private let moduleSet: Set<String>

    /// Devices-view tab ids the user may open (e.g. `abmLookup`,
    /// `prestage`), ordered like `modules`: array position is tab position
    /// after the app-defined base tab, first appearance wins on union. The
    /// base device list is gated by the `devices` module, not listed here.
    let deviceTabs: [String]

    /// `deviceTabs` as a set for the O(1) gate. Derived — excluded from `==`.
    private let deviceTabSet: Set<String>

    /// DeviceAction raw values the user may run on computers.
    let computerActions: Set<String>

    /// DeviceAction raw values the user may run on mobile devices.
    let mobileDeviceActions: Set<String>

    /// CleanupAction configIDs the user may run.
    let cleanupActions: Set<String>

    /// Jamf Computer PreStage displayNames selectable in the Pre-Stage tab.
    /// Exact names, plus the reserved literal `all` (case-insensitive)
    /// meaning every PreStage — interpreted by `canUsePrestage(named:)`.
    let allowedPrestages: Set<String>

    /// Whether the user may export data out of the app.
    let allowExport: Bool

    /// Order is significant for `modules` and preserved verbatim apart from
    /// de-duplication: the FIRST occurrence of an id keeps its position and
    /// later repeats are dropped (never moved).
    init(
        modules: [String],
        deviceTabs: [String],
        computerActions: Set<String>,
        mobileDeviceActions: Set<String>,
        cleanupActions: Set<String>,
        allowedPrestages: Set<String> = [],
        allowExport: Bool
    ) {
        var seen: Set<String> = []
        var ordered: [String] = []
        ordered.reserveCapacity(modules.count)
        for module in modules where seen.insert(module).inserted {
            ordered.append(module)
        }
        self.modules = ordered
        self.moduleSet = seen

        var seenTabs: Set<String> = []
        var orderedTabs: [String] = []
        orderedTabs.reserveCapacity(deviceTabs.count)
        for tab in deviceTabs where seenTabs.insert(tab).inserted {
            orderedTabs.append(tab)
        }
        self.deviceTabs = orderedTabs
        self.deviceTabSet = seenTabs

        self.computerActions = computerActions
        self.mobileDeviceActions = mobileDeviceActions
        self.cleanupActions = cleanupActions
        self.allowedPrestages = allowedPrestages
        self.allowExport = allowExport
    }

    /// The fail-closed value: grants nothing at all. Used before
    /// configuration loads, before sign-in, after sign-out, and whenever a
    /// user's role names match no definition in the profile.
    static let none = UserCapabilities(
        modules: [],
        deviceTabs: [],
        computerActions: [],
        mobileDeviceActions: [],
        cleanupActions: [],
        allowExport: false
    )

    /// Hand-written because `moduleSet` is derived from `modules` — comparing
    /// it too would be redundant work on every `.onChange(of: capabilities)`.
    /// `modules` compares as an ARRAY: a different ORDER is a different value,
    /// which is what makes the sidebar re-resolve when a reordered profile
    /// lands.
    static func == (lhs: UserCapabilities, rhs: UserCapabilities) -> Bool {
        lhs.modules == rhs.modules
            && lhs.deviceTabs == rhs.deviceTabs
            && lhs.computerActions == rhs.computerActions
            && lhs.mobileDeviceActions == rhs.mobileDeviceActions
            && lhs.cleanupActions == rhs.cleanupActions
            && lhs.allowedPrestages == rhs.allowedPrestages
            && lhs.allowExport == rhs.allowExport
    }

    /// Unions role definitions — a user holding multiple roles gets the SUM of
    /// their capabilities, and `allowExport` is OR'd (any role granting export
    /// grants it). `union([])` is `.none` by construction, so "no matching
    /// roles" needs no special case.
    ///
    /// MODULE ORDER RULE (the sidebar's row order, so it is defined here once):
    ///
    ///   1. Role definitions are walked in the order the caller supplies them,
    ///      and `MDMConfiguration.capabilities(forRoleNames:)` — the only
    ///      caller — supplies them in the order they appear in the PROFILE's
    ///      `roles` array. Deliberately NOT the order the token's roles claim
    ///      lists them: the claim's order is Entra's to decide and can change
    ///      between sign-ins, whereas the profile is the admin's deterministic,
    ///      version-controlled statement of intent.
    ///   2. Within a role, its `modules` are appended in listed order.
    ///   3. FIRST APPEARANCE WINS. A module already contributed by an earlier
    ///      role keeps its earlier position — a later role listing it again is
    ///      ignored, never a re-order. (Enforced by `init`'s dedup.)
    ///
    /// Every other list is an unordered Set: only modules drive a layout.
    static func union(_ definitions: [AccessConfiguration.RoleDefinition]) -> UserCapabilities {
        var modules: [String] = []
        var deviceTabs: [String] = []
        var computerActions: Set<String> = []
        var mobileDeviceActions: Set<String> = []
        var cleanupActions: Set<String> = []
        var allowExport = false

        var allowedPrestages: Set<String> = []
        for definition in definitions {
            modules.append(contentsOf: definition.effectiveModules)
            deviceTabs.append(contentsOf: definition.effectiveDeviceTabs)
            computerActions.formUnion(definition.effectiveComputerActions)
            mobileDeviceActions.formUnion(definition.effectiveMobileDeviceActions)
            cleanupActions.formUnion(definition.effectiveCleanupActions)
            allowedPrestages.formUnion(definition.effectiveAllowedPrestages)
            allowExport = allowExport || definition.effectiveAllowExport
        }

        return UserCapabilities(
            modules: modules,
            deviceTabs: deviceTabs,
            computerActions: computerActions,
            mobileDeviceActions: mobileDeviceActions,
            cleanupActions: cleanupActions,
            allowedPrestages: allowedPrestages,
            allowExport: allowExport
        )
    }

    /// Whether the user may open a sidebar/route id. Exact, case-sensitive.
    /// O(1) via `moduleSet` — the ordered `modules` array is for LAYOUT, this
    /// is for the gate, and they can never disagree (both come from `init`).
    func canAccess(module: String) -> Bool {
        moduleSet.contains(module)
    }

    /// Whether the user may open a Devices-view tab id. Exact,
    /// case-sensitive; same array-for-layout / set-for-gate split as
    /// `canAccess(module:)`.
    func canAccess(deviceTab: String) -> Bool {
        deviceTabSet.contains(deviceTab)
    }

    /// Whether the user's roles grant a computer action. This is the
    /// user-scoped layer ONLY — go through DeviceActionPolicy for the real
    /// decision, which also applies the machine allow-list.
    func canRunComputerAction(_ action: DeviceAction) -> Bool {
        computerActions.contains(action.rawValue)
    }

    /// Whether the user's roles grant a mobile-device action. Same caveat as
    /// `canRunComputerAction(_:)` — user layer only.
    func canRunMobileDeviceAction(_ action: DeviceAction) -> Bool {
        mobileDeviceActions.contains(action.rawValue)
    }

    /// Whether any held role's `allowedPrestages` carries the reserved
    /// `all` literal (case-insensitive).
    var allowsAllPrestages: Bool {
        allowedPrestages.contains { $0.caseInsensitiveCompare("all") == .orderedSame }
    }

    /// Whether the user may select the named PreStage in the Pre-Stage
    /// tab. The sentinel is interpreted BEFORE name matching, so a
    /// PreStage literally named "all" can never be matched by name; real
    /// names compare exactly after trimming (entries were trimmed at
    /// decode).
    func canUsePrestage(named name: String) -> Bool {
        if allowsAllPrestages { return true }
        let candidate = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return allowedPrestages.contains(candidate)
    }
}
