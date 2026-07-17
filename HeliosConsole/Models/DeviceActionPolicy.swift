//
//  DeviceActionPolicy.swift
//  HeliosConsole
//
//  The single decision point for whether a device action is available to
//  this operator. Gating is ROLE-ONLY (single layer): the signed-in user's
//  UserCapabilities must list the action id for THIS platform. Capabilities
//  are the union of the profile-defined roles the user holds (Entra roles
//  claim, or the access domain's `role` key). Nothing is hardcoded — an
//  action the profile's roles never name is denied to everyone, and `.none`
//  (no matching role) denies everything.
//
//  There is NO machine-scoped second layer: the former access-domain
//  deviceActions allow-list and the features-domain enableAPIActions kill
//  switch were removed. Each action's label/icon is cosmetic and lives in
//  the ui domain (deviceActionLabels), resolved via ActionBranding, not
//  here. Per-action options (Return-to-Service cleanup, ABM server/PreStage
//  scoping) are role-scoped and exposed as pass-throughs below.
//
//  Views use this for visibility; executeAction() re-checks it as defense
//  in depth so enforcement never lives only in the UI.
//

import Foundation

struct DeviceActionPolicy {

    /// Which platform's capability set this policy consults.
    enum Platform {
        case computer
        case mobileDevice
    }

    /// The signed-in user's resolved capabilities — the SINGLE gating
    /// layer. `.none` denies everything.
    let capabilities: UserCapabilities

    /// Which capability set to consult for this policy.
    let platform: Platform

    /// Policy that denies everything (default before configuration loads).
    static let denyAll = DeviceActionPolicy(capabilities: .none, platform: .computer)

    /// Kept for call-site compatibility with the defense-in-depth guards.
    /// There is now only one layer, so the sole reason is `roleCapability`.
    enum DenialReason {
        case roleCapability
    }

    /// Whether the user's roles grant `action` on this policy's platform.
    private func capabilityGrants(_ action: DeviceAction) -> Bool {
        switch platform {
        case .computer: return capabilities.canRunComputerAction(action)
        case .mobileDevice: return capabilities.canRunMobileDeviceAction(action)
        }
    }

    func denialReason(for action: DeviceAction) -> DenialReason? {
        capabilityGrants(action) ? nil : .roleCapability
    }

    /// The single allow check: the signed-in user's role grants the action.
    func isAllowed(_ action: DeviceAction) -> Bool {
        capabilityGrants(action)
    }

    // MARK: - Role-scoped action options (thin pass-through to capabilities)

    /// Return to Service post-erase cleanup, resolved from the role.
    func returnToServiceOptions() -> AccessConfiguration.ReturnToServiceOptions {
        capabilities.returnToServiceOptions
    }

    /// Whether the role permits assigning to / unassigning from the named
    /// MDM server (the `all` sentinel is handled inside).
    func canAssignToMdmServer(named name: String) -> Bool {
        capabilities.canAssignToMdmServer(named: name)
    }

    var allowsAllMdmServers: Bool { capabilities.allowsAllMdmServers }

    /// Whether abmAssign offers the optional PreStage step.
    var allowsPrestageOnAssign: Bool { capabilities.allowPrestageOnAssign }

    /// Whether the role permits the named PreStage. NOTE: does not itself
    /// gate on allowsPrestageOnAssign — the offer flow checks that first.
    func canUsePrestage(named name: String) -> Bool {
        capabilities.canUsePrestage(named: name)
    }

    var allowsAllPrestages: Bool { capabilities.allowsAllPrestages }

    /// False → the Actions button is not rendered at all.
    func hasAnyVisibleAction() -> Bool {
        DeviceAction.allCases.contains { isAllowed($0) }
    }
}
