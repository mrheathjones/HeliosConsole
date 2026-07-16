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
//    • modules              → sidebar/route ids (NavigationDestination raw values)
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

    /// Sidebar/route ids the user may open.
    let modules: Set<String>

    /// DeviceAction raw values the user may run on computers.
    let computerActions: Set<String>

    /// DeviceAction raw values the user may run on mobile devices.
    let mobileDeviceActions: Set<String>

    /// CleanupAction configIDs the user may run.
    let cleanupActions: Set<String>

    /// Whether the user may export data out of the app.
    let allowExport: Bool

    /// The fail-closed value: grants nothing at all. Used before
    /// configuration loads, before sign-in, after sign-out, and whenever a
    /// user's role names match no definition in the profile.
    static let none = UserCapabilities(
        modules: [],
        computerActions: [],
        mobileDeviceActions: [],
        cleanupActions: [],
        allowExport: false
    )

    /// Unions a set of role definitions — a user holding multiple roles gets
    /// the SUM of their capabilities, and `allowExport` is OR'd (any role
    /// granting export grants it). `union([])` is `.none` by construction,
    /// so "no matching roles" needs no special case.
    static func union(_ definitions: [AccessConfiguration.RoleDefinition]) -> UserCapabilities {
        var modules: Set<String> = []
        var computerActions: Set<String> = []
        var mobileDeviceActions: Set<String> = []
        var cleanupActions: Set<String> = []
        var allowExport = false

        for definition in definitions {
            modules.formUnion(definition.effectiveModules)
            computerActions.formUnion(definition.effectiveComputerActions)
            mobileDeviceActions.formUnion(definition.effectiveMobileDeviceActions)
            cleanupActions.formUnion(definition.effectiveCleanupActions)
            allowExport = allowExport || definition.effectiveAllowExport
        }

        return UserCapabilities(
            modules: modules,
            computerActions: computerActions,
            mobileDeviceActions: mobileDeviceActions,
            cleanupActions: cleanupActions,
            allowExport: allowExport
        )
    }

    /// Whether the user may open a sidebar/route id. Exact, case-sensitive.
    func canAccess(module: String) -> Bool {
        modules.contains(module)
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
}
