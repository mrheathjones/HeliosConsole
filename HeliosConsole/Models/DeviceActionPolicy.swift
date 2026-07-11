//
//  DeviceActionPolicy.swift
//  HeliosConsole
//
//  The single decision point for whether a device action is available to
//  this operator, composed from two managed inputs:
//
//    1. access domain  → deviceActions.<platform>.actions allow-list
//       (STRICT FAIL-CLOSED: no allow-list delivered → nothing is allowed
//       and the Actions menu is hidden entirely; an id that is not listed,
//       or listed with enabled=false, is hidden AND blocked at execution).
//    2. features domain → computers.enableAPIActions kill switch (denies
//       every Jamf API command; Screen Share is exempt because it opens
//       Apple's local Screen Sharing app, not a Jamf endpoint).
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
    let grants: [String: AccessConfiguration.DeviceActionSetting]?

    /// features.<platform>.enableAPIActions (default true when the
    /// features domain is absent — that domain is fail-open by design).
    let apiActionsEnabled: Bool

    /// Policy that denies everything (default before configuration loads).
    static let denyAll = DeviceActionPolicy(grants: nil, apiActionsEnabled: true)

    func isAllowed(_ action: DeviceAction) -> Bool {
        if action.isJamfAPICommand && !apiActionsEnabled { return false }
        guard let grant = grants?[action.rawValue] else { return false }
        return grant.effectiveEnabled
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

    /// False → the Actions button is not rendered at all.
    var hasAnyVisibleAction: Bool {
        DeviceAction.allCases.contains { isAllowed($0) }
    }
}
