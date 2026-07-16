//
//  DeviceActionPolicy.swift
//  HeliosConsole
//
//  The single decision point for whether a device action is available to
//  this operator, composed from TWO INDEPENDENT LAYERS — both must allow
//  (fail-closed intersection):
//
//  Layer 1 — machine-scoped (which actions exist on THIS Mac):
//    1. access domain  → deviceActions.<platform>.actions allow-list
//       (STRICT FAIL-CLOSED: no allow-list delivered → nothing is allowed
//       and the Actions menu is hidden entirely; an id that is not listed,
//       or listed with enabled=false, is hidden AND blocked at execution).
//       This layer also carries each action's label and options.
//    2. features domain → computers.enableAPIActions kill switch (denies
//       every Jamf API command; Screen Share is exempt because it opens
//       Apple's local Screen Sharing app, not a Jamf endpoint).
//
//  Layer 2 — user-scoped: the signed-in user's UserCapabilities must list
//    the action id for THIS platform. Capabilities are the union of the
//    profile-defined roles the user holds (Entra roles claim, or the access
//    domain's `role` key). Nothing is hardcoded — an action the profile's
//    roles never name is denied to everyone, and `.none` (no matching role)
//    denies everything.
//
//  The layers never widen each other: an action must be BOTH present in the
//  machine allow-list AND granted by a role.
//
//  Views use this for visibility; executeAction() re-checks it as defense
//  in depth so enforcement never lives only in the UI.
//

import Foundation

struct DeviceActionPolicy {

    /// Which platform's capability set this policy consults. The machine
    /// allow-list is already per-platform (grants come from
    /// deviceActions.computer / .mobileDevice); this makes the user layer
    /// agree with it.
    enum Platform {
        case computer
        case mobileDevice
    }

    /// Grants keyed by action id, from the access domain's allow-list.
    /// `nil` means no allow-list was delivered for this platform — strict
    /// fail-closed, everything is denied. (Distinct from an empty
    /// dictionary, which is an explicit empty allow-list — same outcome.)
    /// Each grant also carries the action's label and options.
    let grants: [String: AccessConfiguration.DeviceActionSetting]?

    /// features.<platform>.enableAPIActions (default true when the
    /// features domain is absent — that domain is fail-open by design).
    let apiActionsEnabled: Bool

    /// The signed-in user's resolved capabilities (layer 2). `.none` denies
    /// every action regardless of the allow-list.
    let capabilities: UserCapabilities

    /// Which capability set to consult for this policy.
    let platform: Platform

    /// Policy that denies everything (default before configuration loads).
    /// `grants: nil` already denies every action at layer 1, and `.none`
    /// denies it again at layer 2.
    static let denyAll = DeviceActionPolicy(
        grants: nil,
        apiActionsEnabled: true,
        capabilities: .none,
        platform: .computer
    )

    /// Which layer denied an action (nil = allowed). Callers gate on
    /// `isAllowed(_:)`; this exists so the defense-in-depth guards can
    /// audit-log role denials distinctly from allow-list denials.
    enum DenialReason {
        /// Layer 1: allow-list / enableAPIActions kill switch — the action
        /// is not available on this Mac at all.
        case machinePolicy
        /// Layer 2: no role held by the signed-in user grants this action.
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
        if action.isJamfAPICommand && !apiActionsEnabled { return .machinePolicy }
        guard let grant = grants?[action.rawValue], grant.effectiveEnabled else { return .machinePolicy }
        guard capabilityGrants(action) else { return .roleCapability }
        return nil
    }

    /// The single allow check: machine allow-list (layer 1) AND the
    /// signed-in user's role capabilities (layer 2).
    func isAllowed(_ action: DeviceAction) -> Bool {
        denialReason(for: action) == nil
    }

    /// Per-action `options` object from the allow-list entry. Absent grant
    /// or absent options → `.empty`, whose toggles all resolve to their
    /// defaults — deliberately preserving the original full-decommission
    /// behavior for profiles that never deliver an options object.
    func options(for action: DeviceAction) -> AccessConfiguration.DeviceActionOptions {
        grants?[action.rawValue]?.effectiveOptions ?? .empty
    }

    /// Menu label: the profile's non-empty `displayName` override wins,
    /// otherwise the built-in label. Confirmation-dialog copy is never
    /// overridable (see DeviceAction).
    func menuLabel(for action: DeviceAction) -> String {
        if let override = grants?[action.rawValue]?.effectiveDisplayName,
           !override.trimmingCharacters(in: .whitespaces).isEmpty {
            return override
        }
        return action.menuLabel
    }

    /// False → the Actions button is not rendered at all. Capability-aware:
    /// a user whose roles grant no action on this platform sees no Actions
    /// button, even where the Mac's allow-list offers some.
    func hasAnyVisibleAction() -> Bool {
        DeviceAction.allCases.contains { isAllowed($0) }
    }
}
