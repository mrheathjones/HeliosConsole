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

/// The column a device list is sorted by. Direction is tracked separately
/// so every field supports both ascending and descending order.
enum DeviceSortField: String, CaseIterable, Identifiable {
    case name
    case lastCheckIn = "last_checkin"
    case serialNumber = "serial"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "Name"
        case .lastCheckIn: return "Last Check-in"
        case .serialNumber: return "Serial Number"
        }
    }

    /// Jamf inventory API sort key for this field.
    var apiField: String {
        switch self {
        case .name: return "general.name"
        case .lastCheckIn: return "general.lastContactTime"
        case .serialNumber: return "hardware.serialNumber"
        }
    }

    /// Direction the field defaults to when it is newly selected.
    var defaultDirection: DeviceSortDirection {
        switch self {
        case .name, .serialNumber: return .ascending
        case .lastCheckIn: return .descending
        }
    }
}

enum DeviceSortDirection: String, CaseIterable, Identifiable {
    case ascending = "asc"
    case descending = "desc"

    var id: String { rawValue }

    /// Field-specific wording, e.g. "A-Z" reads better than "Ascending" for names.
    func title(for field: DeviceSortField) -> String {
        switch field {
        case .name, .serialNumber:
            return self == .ascending ? "A-Z" : "Z-A"
        case .lastCheckIn:
            return self == .ascending ? "Oldest first" : "Newest first"
        }
    }

    var symbolName: String {
        self == .ascending ? "arrow.up" : "arrow.down"
    }
}

struct DeviceSortOrder: Equatable, Hashable {
    var field: DeviceSortField
    var direction: DeviceSortDirection

    static let nameAscending = DeviceSortOrder(field: .name, direction: .ascending)

    var title: String {
        "\(field.title) (\(direction.title(for: field)))"
    }

    /// Jamf inventory API `(field, direction)` pair.
    var apiParameters: (String, String) {
        (field.apiField, direction.rawValue)
    }

    /// Selecting a field keeps the current direction only if the field is unchanged;
    /// otherwise it resets to that field's natural default.
    func selecting(_ newField: DeviceSortField) -> DeviceSortOrder {
        field == newField ? self : DeviceSortOrder(field: newField, direction: newField.defaultDirection)
    }

    /// `sorted(by:)` predicate. Comparison is tri-state so equal elements never
    /// report "less than" in both directions, which would break the sort's ordering.
    func comparator(_ first: DeviceListItem, _ second: DeviceListItem) -> Bool {
        let result: ComparisonResult
        switch field {
        case .name:
            result = first.name.localizedCompare(second.name)
        case .serialNumber:
            result = first.serialNumber.localizedCompare(second.serialNumber)
        case .lastCheckIn:
            let firstDate = first.lastCheckIn ?? .distantPast
            let secondDate = second.lastCheckIn ?? .distantPast
            result = firstDate == secondDate ? .orderedSame
                : (firstDate < secondDate ? .orderedAscending : .orderedDescending)
        }
        guard result != .orderedSame else { return false }
        return direction == .ascending ? result == .orderedAscending : result == .orderedDescending
    }
}
