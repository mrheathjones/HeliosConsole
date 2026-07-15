//
//  DeviceActionPolicy.swift
//  HeliosConsole
//
//  The single decision point for whether a device action is available to
//  this operator, composed from TWO INDEPENDENT LAYERS — both must allow
//  (fail-closed intersection):
//
//  Layer 1 — machine-scoped:
//    1. access domain  → deviceActions.<platform>.actions allow-list
//       (STRICT FAIL-CLOSED: no allow-list delivered → nothing is allowed
//       and the Actions menu is hidden entirely; an id that is not listed,
//       or listed with enabled=false, is hidden AND blocked at execution).
//    2. features domain → computers.enableAPIActions kill switch (denies
//       every Jamf API command; Screen Share is exempt because it opens
//       Apple's local Screen Sharing app, not a Jamf endpoint).
//
//  Layer 2 — user-scoped (`tierGatingEnabled`, active ONLY when core
//  signIn.method=entra): the signed-in user's UserAccessTier must be at
//  least the action's required tier (profile `requiredTier` override, or
//  the action's built-in `defaultMinimumTier`). In email mode this layer
//  is inert — every tier check passes and behavior is identical to
//  pre-tier builds.
//
//  Views use this for visibility; executeAction() re-checks it as defense
//  in depth so enforcement never lives only in the UI.
//

import Foundation

struct DeviceActionPolicy {

    /// Grants keyed by action id, from the access domain's allow-list.
    /// `nil` means no allow-list was delivered for this platform — strict
    /// fail-closed, everything is denied. (Distinct from an empty
    /// dictionary, which is an explicit empty allow-list — same outcome.)
    /// Each grant also carries the optional per-action `requiredTier`
    /// override consumed by `requiredTier(for:)`.
    let grants: [String: AccessConfiguration.DeviceActionSetting]?

    /// features.<platform>.enableAPIActions (default true when the
    /// features domain is absent — that domain is fail-open by design).
    let apiActionsEnabled: Bool

    /// Whether the user-tier layer is active — true only when the core
    /// domain selects Entra sign-in (signIn.method=entra). False (email
    /// mode) makes every tier check pass, so deployments that never adopt
    /// Entra sign-in are unaffected.
    let tierGatingEnabled: Bool

    /// Policy that denies everything (default before configuration loads).
    /// `grants: nil` already denies every action at layer 1; the tier
    /// layer can only restrict further, never expand.
    static let denyAll = DeviceActionPolicy(grants: nil, apiActionsEnabled: true, tierGatingEnabled: false)

    /// Which layer denied an action (nil = allowed). Callers gate on
    /// `isAllowed(_:tier:)`; this exists so the defense-in-depth guards
    /// can audit-log tier denials distinctly from allow-list denials.
    enum DenialReason {
        /// Layer 1: allow-list / enableAPIActions kill switch.
        case machinePolicy
        /// Layer 2: signed-in user's tier below the action's required tier.
        case userTier
    }

    func denialReason(for action: DeviceAction, tier: UserAccessTier) -> DenialReason? {
        if action.isJamfAPICommand && !apiActionsEnabled { return .machinePolicy }
        guard let grant = grants?[action.rawValue], grant.effectiveEnabled else { return .machinePolicy }
        if tierGatingEnabled && tier < requiredTier(for: action) { return .userTier }
        return nil
    }

    /// Minimum tier for an action: the profile's per-entry `requiredTier`
    /// override wins over the action's built-in classification.
    func requiredTier(for action: DeviceAction) -> UserAccessTier {
        grants?[action.rawValue]?.effectiveRequiredTier ?? action.defaultMinimumTier
    }

    /// The single allow check: machine allow-list (layer 1) AND the
    /// signed-in user's tier (layer 2, inert in email mode).
    func isAllowed(_ action: DeviceAction, tier: UserAccessTier) -> Bool {
        denialReason(for: action, tier: tier) == nil
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

    /// False → the Actions button is not rendered at all. Tier-aware: in
    /// entra mode a user whose tier grants nothing sees no Actions button.
    func hasAnyVisibleAction(tier: UserAccessTier) -> Bool {
        DeviceAction.allCases.contains { isAllowed($0, tier: tier) }
    }
}
