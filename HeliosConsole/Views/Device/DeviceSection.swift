//
//  DeviceSection.swift
//  Helios
//
//  Sidebar sections of the computer detail view.
//

import Foundation

enum DeviceSection: String, CaseIterable {
    case overview
    case hardware
    case storage
    case security
    case operatingSystem
    case userAndLocation
    case applications
    case profiles
    case localAccounts
    case diskEncryption
    case certificates
    case printers
    case purchasing
    case groupMemberships
    case extensionAttributes
    case management
    case logs
    case history

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .hardware: return "Hardware"
        case .storage: return "Storage"
        case .security: return "Security"
        case .operatingSystem: return "Operating System"
        case .userAndLocation: return "User & Location"
        case .applications: return "Applications"
        case .profiles: return "Profiles"
        case .localAccounts: return "Local Accounts"
        case .diskEncryption: return "Disk Encryption"
        case .certificates: return "Certificates"
        case .printers: return "Printers"
        case .purchasing: return "Purchasing"
        case .groupMemberships: return "Groups"
        case .extensionAttributes: return "Extension Attributes"
        case .management: return "Management"
        case .logs: return "Action Logs"
        case .history: return "History"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .hardware: return "cpu"
        case .storage: return "internaldrive"
        case .security: return "shield.checkered"
        case .operatingSystem: return "apple.logo"
        case .userAndLocation: return "person.fill"
        case .applications: return "app.badge"
        case .profiles: return "doc.badge.gearshape"
        case .localAccounts: return "person.2"
        case .diskEncryption: return "lock.doc"
        case .certificates: return "checkmark.seal"
        case .printers: return "printer"
        case .purchasing: return "dollarsign.circle"
        case .groupMemberships: return "person.3"
        case .extensionAttributes: return "list.bullet.rectangle"
        case .management: return "gearshape.2"
        case .logs: return "doc.text.magnifyingglass"
        case .history: return "clock.arrow.circlepath"
        }
    }
}
