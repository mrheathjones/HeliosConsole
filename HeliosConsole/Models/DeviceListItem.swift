//
//  DeviceListItem.swift
//  HeliosConsole
//
//  Lightweight device model used for list display and navigation.
//  Extracted from DeviceListView so it can be shared across targets.
//

import SwiftUI

// MARK: - Device List Item Model

struct DeviceListItem: Identifiable, Hashable {
    let id: String           // Unique ID for SwiftUI (includes prefix)
    let originalId: String   // Original API ID (no prefix)
    let name: String
    let serialNumber: String
    let model: String
    let modelIdentifier: String?
    let osVersion: String
    let assignedUser: String?
    let lastCheckIn: Date?
    let isManaged: Bool
    let isSupervised: Bool
    let platform: PlatformType

    init(
        id: String,
        originalId: String? = nil,
        name: String,
        serialNumber: String,
        model: String,
        modelIdentifier: String? = nil,
        osVersion: String,
        assignedUser: String?,
        lastCheckIn: Date?,
        isManaged: Bool,
        isSupervised: Bool,
        platform: PlatformType
    ) {
        self.id = id
        self.originalId = originalId ?? id
        self.name = name
        self.serialNumber = serialNumber
        self.model = model
        self.modelIdentifier = modelIdentifier
        self.osVersion = osVersion
        self.assignedUser = assignedUser
        self.lastCheckIn = lastCheckIn
        self.isManaged = isManaged
        self.isSupervised = isSupervised
        self.platform = platform
    }

    var lastCheckInFormatted: String {
        guard let date = lastCheckIn else { return "Never" }
        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}

// MARK: - Sort Order

enum DeviceSortOrder: String, CaseIterable, Identifiable {
    case nameAscending = "name_asc"
    case nameDescending = "name_desc"
    case lastCheckIn = "last_checkin"
    case serialNumber = "serial"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nameAscending: return "Name (A-Z)"
        case .nameDescending: return "Name (Z-A)"
        case .lastCheckIn: return "Last Check-in"
        case .serialNumber: return "Serial Number"
        }
    }
}
