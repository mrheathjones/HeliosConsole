//
//  DeviceAction.swift
//  HeliosConsole
//
//  Every operator-triggerable device action, promoted out of DeviceView so
//  the access domain's `deviceActions` allow-list can gate it by id.
//
//  Raw values are the action ids used in the managed config profile
//  (schemas/Helios_Access_SCHEMA.json → deviceActions.computer.actions[].id).
//  Renaming a case or raw value is a breaking profile change — don't.
//
//  Case order = menu display order within each section. Section grouping and
//  ordering stay app-defined by design: the profile controls only which
//  actions are visible (DeviceActionPolicy) and their menu label.
//

import SwiftUI

enum DeviceAction: String, CaseIterable, Identifiable {
    // Device Settings
    case enableBluetooth
    case disableBluetooth
    case enableRemoteDesktop
    case disableRemoteDesktop
    // Device Actions
    case screenShare
    case restart
    case restartSilent
    case shutdown
    case wipe
    case returnToService
    // Security
    case viewLocalAdminPassword
    case viewFileVaultKey
    // User Management
    case unlockUserAccount
    // Inventory
    case sendBlankPush

    var id: String { rawValue }

    // MARK: - Menu placement

    enum MenuSection: String, CaseIterable {
        case deviceSettings = "Device Settings"
        case deviceActions = "Device Actions"
        case security = "Security"
        case userManagement = "User Management"
        case inventory = "Inventory"

        var title: String { rawValue }
    }

    var menuSection: MenuSection {
        switch self {
        case .enableBluetooth, .disableBluetooth, .enableRemoteDesktop, .disableRemoteDesktop:
            return .deviceSettings
        case .screenShare, .restart, .restartSilent, .shutdown, .wipe, .returnToService:
            return .deviceActions
        case .viewLocalAdminPassword, .viewFileVaultKey:
            return .security
        case .unlockUserAccount:
            return .userManagement
        case .sendBlankPush:
            return .inventory
        }
    }

    /// Built-in menu label, overridable per-action via the profile's
    /// `displayName` (see DeviceActionPolicy.menuLabel(for:)).
    var menuLabel: String {
        switch self {
        case .enableBluetooth: return "Enable Bluetooth"
        case .disableBluetooth: return "Disable Bluetooth"
        case .enableRemoteDesktop: return "Enable Remote Desktop"
        case .disableRemoteDesktop: return "Disable Remote Desktop"
        case .screenShare: return "Screen Share"
        case .restart: return "Restart Device"
        case .restartSilent: return "Restart Device (Silent)"
        case .shutdown: return "Shutdown Device"
        case .wipe: return "Erase Device"
        case .returnToService: return "Return to Service"
        case .viewLocalAdminPassword: return "Local Admin Password"
        case .viewFileVaultKey: return "FileVault Key"
        case .unlockUserAccount: return "Unlock User Account"
        case .sendBlankPush: return "Send Blank Push"
        }
    }

    var menuIcon: String {
        switch self {
        case .restartSilent: return "arrow.clockwise.circle.fill"
        case .unlockUserAccount: return "person.badge.key"
        default: return icon
        }
    }

    /// True for actions that call the Jamf Pro API (everything except
    /// Screen Share, which opens Apple's local Screen Sharing app). The
    /// features domain's `computers.enableAPIActions` kill switch applies
    /// only to these.
    var isJamfAPICommand: Bool {
        self != .screenShare
    }

    // MARK: - Confirmation dialog copy
    // Deliberately NOT profile-overridable: a menu-label rename must never
    // be able to soften the safety copy on a destructive action.

    var title: String {
        switch self {
        case .enableBluetooth: return "Enable Bluetooth?"
        case .disableBluetooth: return "Disable Bluetooth?"
        case .enableRemoteDesktop: return "Enable Remote Desktop?"
        case .disableRemoteDesktop: return "Disable Remote Desktop?"
        case .restart: return "Restart Device?"
        case .restartSilent: return "Restart Device (Silent)?"
        case .shutdown: return "Shutdown Device?"
        case .wipe: return "Erase Device?"
        case .returnToService: return "Return to Service?"
        case .viewLocalAdminPassword: return "View Local Admin Password?"
        case .viewFileVaultKey: return "View FileVault Recovery Key?"
        case .sendBlankPush: return "Send Blank Push?"
        case .screenShare: return "Screen Share?"
        case .unlockUserAccount: return "Unlock User Account?"
        }
    }

    var message: String {
        switch self {
        case .enableBluetooth: return "This will enable Bluetooth on the device."
        case .disableBluetooth: return "This will disable Bluetooth on the device. Any connected Bluetooth devices (keyboards, mice, trackpads, headsets) will be disconnected."
        case .enableRemoteDesktop: return "This will enable Remote Desktop (Screen Sharing) on the device, allowing remote connections."
        case .disableRemoteDesktop: return "This will disable Remote Desktop (Screen Sharing) on the device. Any active remote sessions will be disconnected."
        case .restart: return "This will restart the device and notify the user. Any unsaved work may be lost."
        case .restartSilent: return "This will restart the device without notifying the user. Any unsaved work may be lost."
        case .shutdown: return "This will shut down the device. The user will need physical access to turn it back on."
        case .wipe: return "This will send an erase command that permanently erases all data on the device, then wait for the device to acknowledge the command. The device's Jamf Pro record and Entra device object are left in place. This action cannot be undone."
        case .returnToService: return "This will (1) erase all data on the device, (2) remove its record from Jamf Pro once the erase is confirmed as issued, and (3) delete its device object from Microsoft Entra so the device can re-enroll cleanly. This action cannot be undone."
        case .viewLocalAdminPassword: return "This will retrieve and display the local administrator password for this device. This action is logged for security auditing."
        case .viewFileVaultKey: return "This will retrieve and display the FileVault personal recovery key for this device. This key can be used to unlock the encrypted disk. This action is logged for security auditing."
        case .sendBlankPush: return "This will send an APNs (Apple Push Notification) to the device, prompting it to check in with Jamf Pro. Use this to verify device connectivity or to trigger pending MDM commands."
        case .screenShare: return "This will open a screen sharing session to the device using Apple's built-in Screen Sharing app. If the device is on VPN, the VPN IP address will be used."
        case .unlockUserAccount: return "This will unlock a local user account on the device. This action is logged for security auditing."
        }
    }

    var icon: String {
        switch self {
        case .enableBluetooth: return "antenna.radiowaves.left.and.right"
        case .disableBluetooth: return "antenna.radiowaves.left.and.right.slash"
        case .enableRemoteDesktop: return "desktopcomputer.and.arrow.down"
        case .disableRemoteDesktop: return "desktopcomputer.trianglebadge.exclamationmark"
        case .restart, .restartSilent: return "arrow.clockwise.circle"
        case .shutdown: return "power"
        case .wipe: return "externaldrive.badge.xmark"
        case .returnToService: return "arrow.counterclockwise.circle"
        case .viewLocalAdminPassword: return "key.fill"
        case .viewFileVaultKey: return "lock.shield"
        case .sendBlankPush: return "bell.badge"
        case .screenShare: return "shared.with.you"
        case .unlockUserAccount: return "person.badge.key"
        }
    }

    var iconColor: Color {
        switch self {
        case .enableBluetooth, .enableRemoteDesktop: return .blue
        case .disableBluetooth, .disableRemoteDesktop: return .orange
        case .restart, .restartSilent: return .orange
        case .shutdown: return .orange
        case .wipe: return .red
        case .returnToService: return .red
        case .viewLocalAdminPassword: return .purple
        case .viewFileVaultKey: return .green
        case .sendBlankPush: return .blue
        case .screenShare: return .cyan
        case .unlockUserAccount: return .blue
        }
    }

    var confirmButtonTitle: String {
        switch self {
        case .enableBluetooth: return "Enable"
        case .disableBluetooth: return "Disable"
        case .enableRemoteDesktop: return "Enable"
        case .disableRemoteDesktop: return "Disable"
        case .restart, .restartSilent: return "Restart"
        case .shutdown: return "Shutdown"
        case .wipe: return "Erase"
        case .returnToService: return "Erase & Return"
        case .viewLocalAdminPassword: return "View Password"
        case .viewFileVaultKey: return "View Key"
        case .sendBlankPush: return "Send Push"
        case .screenShare: return "Connect"
        case .unlockUserAccount: return "Unlock"
        }
    }

    var isDestructive: Bool {
        switch self {
        case .wipe, .returnToService: return true
        default: return false
        }
    }

    var isWarning: Bool {
        switch self {
        case .disableBluetooth, .disableRemoteDesktop, .restart, .restartSilent, .shutdown, .viewLocalAdminPassword, .viewFileVaultKey: return true
        default: return false
        }
    }

    var logName: String {
        switch self {
        case .enableBluetooth: return "Enable Bluetooth"
        case .disableBluetooth: return "Disable Bluetooth"
        case .enableRemoteDesktop: return "Enable Remote Desktop"
        case .disableRemoteDesktop: return "Disable Remote Desktop"
        case .restart: return "Restart Device"
        case .restartSilent: return "Restart Device (Silent)"
        case .shutdown: return "Shutdown Device"
        case .wipe: return "Erase Device"
        case .returnToService: return "Return to Service"
        case .viewLocalAdminPassword: return "View Local Admin Password"
        case .viewFileVaultKey: return "View FileVault Key"
        case .sendBlankPush: return "Send Blank Push"
        case .screenShare: return "Screen Share"
        case .unlockUserAccount: return "Unlock User Account"
        }
    }

    var logCategory: String {
        switch self {
        case .enableBluetooth, .disableBluetooth, .enableRemoteDesktop, .disableRemoteDesktop:
            return "Device Settings"
        case .restart, .restartSilent, .shutdown, .wipe, .returnToService, .screenShare:
            return "Device Actions"
        case .viewLocalAdminPassword, .viewFileVaultKey:
            return "Security"
        case .unlockUserAccount:
            return "User Management"
        case .sendBlankPush:
            return "Inventory"
        }
    }
}
