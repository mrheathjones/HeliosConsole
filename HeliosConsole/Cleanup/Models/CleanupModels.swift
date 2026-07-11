//
//  CleanupModels.swift
//  HeliosConsole
//
//  Data types for the Cleanup feature (Jamf Pro stale-device cleanup),
//  ported from the Clean Slate app. These are feature-local view/transport
//  models — they intentionally do not replace Helios's canonical Computer /
//  ComputerInventoryItem models.
//

import Foundation

// MARK: - Computers inventory (Jamf Pro API v3)

struct ComputerInventoryList: Decodable, Sendable {
    let totalCount: Int
    let results: [ComputerInventoryRecord]
}

struct ComputerInventoryRecord: Decodable, Sendable {
    let id: String
    let udid: String?
    let general: General?
    let hardware: Hardware?
    let userAndLocation: UserAndLocation?

    struct General: Decodable, Sendable {
        let name: String?
        let lastContactTime: Date?
        let managementId: String?
        let remoteManagement: RemoteManagement?
        let site: Site?
        let supervised: Bool?

        struct RemoteManagement: Decodable, Sendable {
            let managed: Bool?
        }

        struct Site: Decodable, Sendable {
            let id: String?
            let name: String?
        }
    }

    struct Hardware: Decodable, Sendable {
        let serialNumber: String?
        let model: String?
    }

    struct UserAndLocation: Decodable, Sendable {
        let username: String?
        let realname: String?
        let email: String?
    }
}

// MARK: - Display model

struct StaleDevice: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let serialNumber: String
    let model: String
    let userEmail: String
    let username: String
    let lastContactTime: Date?
    let isManaged: Bool
    let managementId: String?
    let siteName: String

    var daysSinceContact: Int? {
        guard let lastContactTime else { return nil }
        return Calendar.current.dateComponents([.day], from: lastContactTime, to: Date()).day
    }

    /// Never-contacted devices count as stale forever.
    var isStaleOverOneYear: Bool {
        daysSinceContact.map { $0 >= 365 } ?? true
    }

    init?(record: ComputerInventoryRecord) {
        guard let intID = Int(record.id) else { return nil }
        id = intID
        name = record.general?.name ?? "Unknown"
        serialNumber = record.hardware?.serialNumber ?? "—"
        model = record.hardware?.model ?? ""
        userEmail = record.userAndLocation?.email ?? ""
        username = record.userAndLocation?.username ?? ""
        lastContactTime = record.general?.lastContactTime
        isManaged = record.general?.remoteManagement?.managed ?? false
        managementId = record.general?.managementId
        let site = record.general?.site
        siteName = (site?.name?.isEmpty == false) ? site!.name! : "None"
    }
}

// MARK: - Lookup objects

struct JamfSite: Identifiable, Hashable, Decodable, Sendable {
    let id: String
    let name: String

    var intID: Int { Int(id) ?? -1 }
}

struct StaticGroup: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
}

// MARK: - Jamf Protect

struct ProtectDevice: Identifiable, Hashable, Sendable {
    let uuid: String
    let hostName: String
    let serial: String
    let checkin: Date?

    var id: String { uuid }

    var daysSinceCheckin: Int? {
        guard let checkin else { return nil }
        return Calendar.current.dateComponents([.day], from: checkin, to: Date()).day
    }
}

/// Slices of the Jamf Protect computer list.
enum ProtectFilter: Hashable, Sendable {
    case all
    case stale

    var title: String {
        switch self {
        case .all: "Protect Computers"
        case .stale: "Protect Stale"
        }
    }
}

// MARK: - Filters

/// What slice of the stale-device set a device list shows.
/// The stale filters only count devices still marked managed; records
/// that are already unmanaged live under the `.unmanaged` filter.
enum DeviceFilter: Hashable, Sendable {
    case allStale
    case overOneYear
    case unmanaged
    case site(String)

    var title: String {
        switch self {
        case .allStale: "Stale Devices"
        case .overOneYear: "Stale Over 1 Year"
        case .unmanaged: "Unmanaged"
        case .site(let name): name
        }
    }

    func matches(_ device: StaleDevice) -> Bool {
        switch self {
        case .allStale: device.isManaged
        case .overOneYear: device.isManaged && device.isStaleOverOneYear
        case .unmanaged: !device.isManaged
        case .site(let name): device.isManaged && device.siteName == name
        }
    }
}

// MARK: - Actions

struct ActionPlan: Sendable {
    var unmanage = false
    var addToGroupID: Int?
    var addToGroupName: String?
    var moveToSiteID: Int?
    var moveToSiteName: String?
    var deleteFromProtect = false
    var deleteRecord = false

    var isEmpty: Bool {
        !unmanage && addToGroupID == nil && moveToSiteID == nil && !deleteFromProtect && !deleteRecord
    }

    var isDestructive: Bool { deleteRecord || deleteFromProtect || unmanage }

    var summary: [String] {
        var parts: [String] = []
        if unmanage { parts.append("Send Unmanage command") }
        if let name = addToGroupName { parts.append("Add to static group “\(name)”") }
        if let name = moveToSiteName { parts.append("Move to site “\(name)”") }
        if deleteFromProtect { parts.append("Delete from Jamf Protect") }
        if deleteRecord { parts.append("Delete Jamf Pro record") }
        return parts
    }
}

enum CleanupAction: String, Sendable {
    case unmanage = "Unmanage"
    case addToGroup = "Add to Group"
    case moveToSite = "Move to Site"
    case deleteFromProtect = "Delete from Protect"
    case deleteRecord = "Delete Record"
}

struct ActionResult: Identifiable, Sendable {
    let id = UUID()
    let deviceName: String
    let action: CleanupAction
    let success: Bool
    let message: String
}

// MARK: - Errors

enum JamfCleanupError: LocalizedError, Sendable {
    case notConfigured
    case badURL
    case http(Int, String)
    case authenticationFailed(String)
    case decoding(String)
    case protectNotConfigured
    case protectGraphQL(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Cleanup isn't configured yet. Helios needs a Jamf Pro URL and master API client."
        case .badURL:
            "The Jamf Pro server URL is not a valid URL."
        case .http(let code, let body):
            "Jamf returned HTTP \(code). \(body)"
        case .authenticationFailed(let detail):
            "Authentication failed: \(detail)"
        case .decoding(let detail):
            "Couldn't read the server response: \(detail)"
        case .protectNotConfigured:
            "Jamf Protect isn't configured. Add the tenant URL and API client in Settings."
        case .protectGraphQL(let detail):
            "Jamf Protect error: \(detail)"
        }
    }
}
