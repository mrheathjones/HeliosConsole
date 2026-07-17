//
//  ActionBranding.swift
//  HeliosConsole
//
//  Resolves the DISPLAY label and icon for a device action, applying the ui
//  domain's cosmetic `deviceActionLabels` overrides on top of the action's
//  built-ins. Presentation ONLY — an action's AVAILABILITY is gated
//  role-only by the access domain (DeviceActionPolicy), never here. An id
//  absent from the override list, or an override field left blank, falls back
//  to the action's built-in label/icon.
//
//  Overrides are read live from MDMConfigurationManager.shared.configuration
//  so a profile push takes effect without rebuilding a policy value.
//

import Foundation

enum ActionBranding {

    /// The menu label for `action`: the ui-domain `deviceActionLabels`
    /// displayName override when a non-empty one is delivered, otherwise the
    /// action's built-in `menuLabel`.
    static func label(for action: DeviceAction) -> String {
        let override = MDMConfigurationManager.shared.configuration
            .deviceActionLabelOverride(id: action.id)
        if let displayName = override?.displayName, !displayName.isEmpty {
            return displayName
        }
        return action.menuLabel
    }

    /// The SF Symbol name for `action`: the ui-domain `deviceActionLabels`
    /// icon override (free-form symbol string) when a non-empty one is
    /// delivered, otherwise the action's built-in `menuIcon`.
    static func icon(for action: DeviceAction) -> String {
        let override = MDMConfigurationManager.shared.configuration
            .deviceActionLabelOverride(id: action.id)
        if let icon = override?.icon, !icon.isEmpty {
            return icon
        }
        return action.menuIcon
    }
}
