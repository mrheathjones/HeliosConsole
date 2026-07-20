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
    // Site
    case moveToSite
    // Apple Business Manager
    case abmAssign
    case abmUnassign
    // Pre-Stage
    case assignPreStage

    var id: String { rawValue }

    // MARK: - Menu placement

    enum MenuSection: String, CaseIterable {
        case deviceSettings = "Device Settings"
        case deviceActions = "Device Actions"
        case security = "Security"
        case userManagement = "User Management"
        case inventory = "Inventory"
        case site = "Site"
        case appleBusinessManager = "Apple Business Manager"
        case preStage = "Pre-Stage"

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
        case .moveToSite:
            return .site
        case .abmAssign, .abmUnassign:
            return .appleBusinessManager
        case .assignPreStage:
            return .preStage
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
        case .moveToSite: return "Move to Site"
        case .abmAssign: return "Assign to MDM Server"
        case .abmUnassign: return "Unassign from MDM Server"
        case .assignPreStage: return "Assign to PreStage"
        }
    }

    var menuIcon: String {
        switch self {
        case .restartSilent: return "arrow.clockwise.circle.fill"
        case .unlockUserAccount: return "person.badge.key"
        default: return icon
        }
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
        case .moveToSite: return "Move to Site?"
        case .screenShare: return "Screen Share?"
        case .unlockUserAccount: return "Unlock User Account?"
        case .abmAssign: return "Assign to MDM Server?"
        case .abmUnassign: return "Unassign from MDM Server?"
        case .assignPreStage: return "Assign to PreStage?"
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
        case .returnToService: return "This will (1) erase all data on the device (the device must acknowledge the erase before any cleanup step runs), (2) remove its record from Jamf Pro, and (3) delete its device object from Microsoft Entra so the device can re-enroll cleanly. This action cannot be undone." // Fallback only — DeviceView.confirmationMessage(for:) composes the real dialog copy from the profile-enabled steps.
        case .viewLocalAdminPassword: return "This will retrieve and display the local administrator password for this device. This action is logged for security auditing."
        case .viewFileVaultKey: return "This will retrieve and display the FileVault personal recovery key for this device. This key can be used to unlock the encrypted disk. This action is logged for security auditing."
        case .sendBlankPush: return "This will send an APNs (Apple Push Notification) to the device, prompting it to check in with Jamf Pro. Use this to verify device connectivity or to trigger pending MDM commands."
        case .moveToSite: return "This will change the Jamf Pro site the device's record belongs to. Nothing changes on the device itself, but site membership drives scoping — policies, profiles and group memberships targeted by site will start or stop applying at the device's next check-in." // Fallback only — the picker sheet composes its own copy from the chosen site.
        case .screenShare: return "This will open a screen sharing session to the device using Apple's built-in Screen Sharing app. If the device is on VPN, the VPN IP address will be used."
        case .unlockUserAccount: return "This will unlock a local user account on the device. This action is logged for security auditing."
        case .abmAssign: return "This will assign the device's serial number to the selected MDM server in Apple Business Manager. Nothing changes on the device now — the assignment determines which MDM the device enrolls with at its next Automated Device Enrollment. If the device is currently assigned to a different MDM server, it will be reassigned."
        case .abmUnassign: return "This will remove the device's MDM server assignment in Apple Business Manager. Nothing changes on the device now — but until it is reassigned, the device cannot enroll via Automated Device Enrollment."
        case .assignPreStage: return "This will register the device's serial number to the selected Jamf Pro PreStage Enrollment. If you enter an asset tag, an Inventory Preload record is saved first. Nothing changes on the device now — the PreStage applies at the device's next Automated Device Enrollment."
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
        case .moveToSite: return "building.2"
        case .screenShare: return "shared.with.you"
        case .unlockUserAccount: return "person.badge.key"
        case .abmAssign: return "externaldrive.badge.plus"
        case .abmUnassign: return "externaldrive.badge.minus"
        case .assignPreStage: return "shippingbox"
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
        case .moveToSite: return .indigo
        case .screenShare: return .cyan
        case .unlockUserAccount: return .blue
        case .abmAssign: return .blue
        case .abmUnassign: return .orange
        case .assignPreStage: return .purple
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
        case .moveToSite: return "Move"
        case .screenShare: return "Connect"
        case .unlockUserAccount: return "Unlock"
        case .abmAssign: return "Assign"
        case .abmUnassign: return "Unassign"
        case .assignPreStage: return "Assign"
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
        case .disableBluetooth, .disableRemoteDesktop, .restart, .restartSilent, .shutdown, .viewLocalAdminPassword, .viewFileVaultKey, .abmAssign, .abmUnassign: return true
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
        case .moveToSite: return "Move to Site"
        case .screenShare: return "Screen Share"
        case .unlockUserAccount: return "Unlock User Account"
        case .abmAssign: return "ABM Assign to MDM"
        case .abmUnassign: return "ABM Unassign from MDM"
        case .assignPreStage: return "Assign to PreStage"
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
        case .moveToSite:
            return "Site"
        case .abmAssign, .abmUnassign:
            return "Apple Business Manager"
        case .assignPreStage:
            return "Pre-Stage"
        }
    }
}
