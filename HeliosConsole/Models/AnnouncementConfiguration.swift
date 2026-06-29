//
//  AnnouncementConfiguration.swift
//  HeliosConsole
//
//  Configuration models for announcements deployed via separate MDM profile
//  Preference Domain: com.helios.console.announcements
//

import Foundation

// MARK: - Announcement Configuration

struct AnnouncementConfiguration: Codable {
    var configurationVersion: String = "1.0"
    var announcementsEnabled: Bool = true
    var refreshInterval: Int = 60
    var allowLocalFile: Bool = false
    var allowUserDismiss: Bool = true
    var showUnreadBadge: Bool = true
    var notificationSettings: NotificationSettings?
    var announcements: [AnnouncementItem]?
    var scheduledMaintenanceWindows: [MaintenanceWindow]?
    var templates: [AnnouncementTemplate]?
    
    var effectiveNotificationSettings: NotificationSettings {
        notificationSettings ?? NotificationSettings()
    }
    
    var activeAnnouncements: [AnnouncementItem] {
        let now = Date()
        return (announcements ?? []).filter { announcement in
            // Check if expired
            if let expiresAt = announcement.expiresAtDate, expiresAt < now {
                return false
            }
            // Check if not yet started
            if let startsAt = announcement.startsAtDate, startsAt > now {
                return false
            }
            return true
        }
    }
}

// MARK: - Notification Settings

struct NotificationSettings: Codable {
    var enabled: Bool = false
    var criticalOnly: Bool = true
    var sound: Bool = false
}

// MARK: - Announcement Item

struct AnnouncementItem: Codable, Identifiable {
    var id: String
    var title: String
    var message: String
    var type: String = "info"
    var priority: String = "normal"
    var createdAt: String?
    var expiresAt: String?
    var startsAt: String?
    var dismissible: Bool = true
    var requiredReading: Bool = false
    var requiresAcknowledgment: Bool = false
    var actionURL: String?
    var actionLabel: String?
    var actionType: String?
    var targetAudience: TargetAudience?
    var displayOptions: DisplayOptions?
    var attachments: [Attachment]?
    var metadata: [String: AnyCodableValue]?
    
    // MARK: - Computed Properties
    
    var announcementType: AnnouncementType {
        AnnouncementType(rawValue: type) ?? .info
    }
    
    var announcementPriority: AnnouncementPriority {
        AnnouncementPriority(rawValue: priority) ?? .normal
    }
    
    var createdAtDate: Date? {
        guard let createdAt = createdAt else { return nil }
        return ISO8601DateFormatter().date(from: createdAt)
    }
    
    var expiresAtDate: Date? {
        guard let expiresAt = expiresAt else { return nil }
        return ISO8601DateFormatter().date(from: expiresAt)
    }
    
    var startsAtDate: Date? {
        guard let startsAt = startsAt else { return nil }
        return ISO8601DateFormatter().date(from: startsAt)
    }
    
    var effectiveActionLabel: String {
        actionLabel ?? "Learn More"
    }
    
    var effectiveDisplayOptions: DisplayOptions {
        displayOptions ?? DisplayOptions()
    }
    
    /// Convert to the Announcement model used by AnnouncementService
    func toAnnouncement() -> Announcement {
        Announcement(
            id: id,
            title: title,
            message: message,
            type: announcementType,
            priority: announcementPriority,
            createdAt: createdAtDate ?? Date(),
            expiresAt: expiresAtDate,
            dismissible: dismissible,
            requiredReading: requiredReading,
            actionURL: actionURL,
            actionLabel: actionLabel
        )
    }
}

// MARK: - Target Audience

struct TargetAudience: Codable {
    var departments: [String]?
    var buildings: [String]?
    var userGroups: [String]?
    var deviceGroups: [String]?
    var platforms: [String]?
    
    func matches(department: String?, building: String?, platform: String?) -> Bool {
        // If no filters are set, show to everyone
        let hasFilters = (departments != nil && !departments!.isEmpty) ||
                         (buildings != nil && !buildings!.isEmpty) ||
                         (platforms != nil && !platforms!.isEmpty)
        
        guard hasFilters else { return true }
        
        // Check platform filter
        if let platforms = platforms, !platforms.isEmpty {
            guard let platform = platform, platforms.contains(platform) else {
                return false
            }
        }
        
        // Check department filter
        if let departments = departments, !departments.isEmpty {
            guard let department = department, departments.contains(department) else {
                return false
            }
        }
        
        // Check building filter
        if let buildings = buildings, !buildings.isEmpty {
            guard let building = building, buildings.contains(building) else {
                return false
            }
        }
        
        return true
    }
}

// MARK: - Display Options

struct DisplayOptions: Codable {
    var showOnDashboard: Bool = false
    var modalOnStartup: Bool = false
    var pinToTop: Bool = false
    var backgroundColor: String?
    var iconName: String?
}

// MARK: - Attachment

struct Attachment: Codable, Identifiable {
    var id: String { name + (url ?? "") }
    var name: String
    var url: String?
    var type: String?
    var size: String?
    
    var attachmentURL: URL? {
        guard let url = url else { return nil }
        return URL(string: url)
    }
}

// MARK: - Maintenance Window

struct MaintenanceWindow: Codable, Identifiable {
    var id: String
    var title: String
    var description: String?
    var startTime: String
    var endTime: String
    var affectedServices: [String]?
    var notifyBefore: Int = 60
    var recurring: RecurringSchedule?
    
    var startDate: Date? {
        ISO8601DateFormatter().date(from: startTime)
    }
    
    var endDate: Date? {
        ISO8601DateFormatter().date(from: endTime)
    }
    
    var isActive: Bool {
        guard let start = startDate, let end = endDate else { return false }
        let now = Date()
        return now >= start && now <= end
    }
    
    var isUpcoming: Bool {
        guard let start = startDate else { return false }
        let now = Date()
        let notifyDate = start.addingTimeInterval(TimeInterval(-notifyBefore * 60))
        return now >= notifyDate && now < start
    }
    
    /// Generate an announcement for this maintenance window
    func toAnnouncement() -> AnnouncementItem {
        let servicesText = affectedServices?.joined(separator: ", ") ?? "Various services"
        let message = """
        \(description ?? "Scheduled maintenance window")
        
        **Affected Services:** \(servicesText)
        
        **Start:** \(startTime)
        **End:** \(endTime)
        """
        
        return AnnouncementItem(
            id: "maintenance-\(id)",
            title: title,
            message: message,
            type: "maintenance",
            priority: "high",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            expiresAt: endTime,
            dismissible: true
        )
    }
}

struct RecurringSchedule: Codable {
    var frequency: String? // daily, weekly, monthly
    var daysOfWeek: [Int]? // 0 = Sunday
    var dayOfMonth: Int?
}

// MARK: - Announcement Template

struct AnnouncementTemplate: Codable, Identifiable {
    var id: String
    var name: String
    var type: String?
    var titleTemplate: String
    var messageTemplate: String
    var defaultPriority: String?
    var defaultDuration: Int? // hours
    
    /// Apply template with given values
    func apply(values: [String: String]) -> AnnouncementItem {
        var title = titleTemplate
        var message = messageTemplate
        
        for (key, value) in values {
            title = title.replacingOccurrences(of: "{{\(key)}}", with: value)
            message = message.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        
        var expiresAt: String? = nil
        if let duration = defaultDuration {
            let expiry = Date().addingTimeInterval(TimeInterval(duration * 3600))
            expiresAt = ISO8601DateFormatter().string(from: expiry)
        }
        
        return AnnouncementItem(
            id: "template-\(id)-\(UUID().uuidString)",
            title: title,
            message: message,
            type: type ?? "info",
            priority: defaultPriority ?? "normal",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            expiresAt: expiresAt
        )
    }
}

// MARK: - AnyCodableValue for metadata

enum AnyCodableValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])
    case null
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([AnyCodableValue].self) {
            self = .array(array)
        } else if let dict = try? container.decode([String: AnyCodableValue].self) {
            self = .dictionary(dict)
        } else {
            throw DecodingError.typeMismatch(
                AnyCodableValue.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported type")
            )
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .dictionary(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
