//
//  AnnouncementService.swift
//  Helios
//
//  Service for managing announcements pushed via MDM configuration profiles
//  or loaded from local JSON file
//

import Foundation
import Combine

// MARK: - Announcement Model

struct Announcement: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let message: String
    let type: AnnouncementType
    let priority: AnnouncementPriority
    let createdAt: Date
    let expiresAt: Date?
    let actionURL: String?
    let actionLabel: String?
    let dismissible: Bool
    let targetPlatforms: [String]? // nil = all platforms
    let requiredReading: Bool
    
    init(
        id: String = UUID().uuidString,
        title: String,
        message: String,
        type: AnnouncementType = .info,
        priority: AnnouncementPriority = .normal,
        createdAt: Date = Date(),
        expiresAt: Date? = nil,
        actionURL: String? = nil,
        actionLabel: String? = nil,
        dismissible: Bool = true,
        targetPlatforms: [String]? = nil,
        requiredReading: Bool = false
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.type = type
        self.priority = priority
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.actionURL = actionURL
        self.actionLabel = actionLabel
        self.dismissible = dismissible
        self.targetPlatforms = targetPlatforms
        self.requiredReading = requiredReading
    }
    
    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() > expiresAt
    }
    
    var isActive: Bool {
        !isExpired
    }
    
    // Custom decoding to handle ISO8601 dates
    enum CodingKeys: String, CodingKey {
        case id, title, message, type, priority, createdAt, expiresAt
        case actionURL, actionLabel, dismissible, targetPlatforms, requiredReading
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        message = try container.decode(String.self, forKey: .message)
        type = try container.decodeIfPresent(AnnouncementType.self, forKey: .type) ?? .info
        priority = try container.decodeIfPresent(AnnouncementPriority.self, forKey: .priority) ?? .normal
        
        // Handle date decoding - try ISO8601 string first, then Date
        if let dateString = try? container.decode(String.self, forKey: .createdAt) {
            createdAt = ISO8601DateFormatter().date(from: dateString) ?? Date()
        } else if let date = try? container.decode(Date.self, forKey: .createdAt) {
            createdAt = date
        } else {
            createdAt = Date()
        }
        
        if let dateString = try? container.decodeIfPresent(String.self, forKey: .expiresAt) {
            expiresAt = ISO8601DateFormatter().date(from: dateString)
        } else {
            expiresAt = try? container.decodeIfPresent(Date.self, forKey: .expiresAt)
        }
        
        actionURL = try container.decodeIfPresent(String.self, forKey: .actionURL)
        actionLabel = try container.decodeIfPresent(String.self, forKey: .actionLabel)
        dismissible = try container.decodeIfPresent(Bool.self, forKey: .dismissible) ?? true
        targetPlatforms = try container.decodeIfPresent([String].self, forKey: .targetPlatforms)
        requiredReading = try container.decodeIfPresent(Bool.self, forKey: .requiredReading) ?? false
    }
}

// MARK: - Announcement Type

enum AnnouncementType: String, Codable, CaseIterable, Identifiable {
    case info = "info"
    case warning = "warning"
    case critical = "critical"
    case success = "success"
    case maintenance = "maintenance"
    case update = "update"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        case .success: return "checkmark.circle.fill"
        case .maintenance: return "wrench.and.screwdriver.fill"
        case .update: return "arrow.down.circle.fill"
        }
    }
    
    var color: String {
        switch self {
        case .info: return "blue"
        case .warning: return "orange"
        case .critical: return "red"
        case .success: return "green"
        case .maintenance: return "purple"
        case .update: return "cyan"
        }
    }
    
    var displayName: String {
        switch self {
        case .info: return "Information"
        case .warning: return "Warning"
        case .critical: return "Critical"
        case .success: return "Success"
        case .maintenance: return "Maintenance"
        case .update: return "Update"
        }
    }
}

// MARK: - Announcement Priority

enum AnnouncementPriority: String, Codable, CaseIterable, Comparable {
    case low = "low"
    case normal = "normal"
    case high = "high"
    case urgent = "urgent"
    
    var sortOrder: Int {
        switch self {
        case .urgent: return 0
        case .high: return 1
        case .normal: return 2
        case .low: return 3
        }
    }
    
    static func < (lhs: AnnouncementPriority, rhs: AnnouncementPriority) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

// MARK: - Announcements File Structure

struct AnnouncementsFile: Codable {
    let announcements: [Announcement]
    let version: String?
    let lastUpdated: String?
    
    enum CodingKeys: String, CodingKey {
        case announcements = "Announcements"
        case version = "Version"
        case lastUpdated = "LastUpdated"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        announcements = try container.decode([Announcement].self, forKey: .announcements)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        lastUpdated = try container.decodeIfPresent(String.self, forKey: .lastUpdated)
    }
}

// MARK: - Announcement Source

enum AnnouncementSource: String {
    case mdm = "MDM Configuration Profile"
    case localFile = "Local File"
    case userDefaults = "User Defaults (Testing)"
    case none = "None"
}

// MARK: - Announcement Service

@MainActor
class AnnouncementService: ObservableObject {
    static let shared = AnnouncementService()
    
    // MARK: - Published Properties
    
    @Published private(set) var announcements: [Announcement] = []
    @Published private(set) var unreadCount: Int = 0
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: String?
    @Published private(set) var activeSource: AnnouncementSource = .none
    
    // MARK: - Configuration
    
    /// The managed preference domain for MDM-pushed announcements.
    /// Matches the announcements schema ($id) and ConfigurationManager.
    private let managedPreferenceDomain = "com.helios.console.announcements"
    
    /// Local file path for announcements JSON
    /// /Library/Application Support/Helios/Announcements/announcements.json
    static let localAnnouncementsDirectory = "/Library/Application Support/Helios/Announcements"
    static let localAnnouncementsFilePath = "/Library/Application Support/Helios/Announcements/announcements.json"
    
    /// Key in UserDefaults for dismissed announcement IDs
    private let dismissedKey = "helios_dismissed_announcements"
    
    /// Key in UserDefaults for read announcement IDs
    private let readKey = "helios_read_announcements"
    
    // MARK: - Private Properties
    
    private var dismissedIDs: Set<String> = []
    private var readIDs: Set<String> = []
    private var refreshTimer: Timer?
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    private init() {
        loadDismissedIDs()
        loadReadIDs()
        loadAnnouncements()
        startAutoRefresh()
        startFileMonitoring()
        
        // Listen for managed configuration changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(managedConfigurationDidChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }
    
    deinit {
        refreshTimer?.invalidate()
        fileMonitor?.cancel()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Methods
    
    /// Manually refresh announcements from all sources
    func refresh() {
        loadAnnouncements()
    }
    
    /// Mark an announcement as read
    func markAsRead(_ announcement: Announcement) {
        readIDs.insert(announcement.id)
        saveReadIDs()
        updateUnreadCount()
    }
    
    /// Mark all announcements as read
    func markAllAsRead() {
        for announcement in announcements {
            readIDs.insert(announcement.id)
        }
        saveReadIDs()
        updateUnreadCount()
    }
    
    /// Dismiss an announcement (only if dismissible)
    func dismiss(_ announcement: Announcement) {
        guard announcement.dismissible else { return }
        dismissedIDs.insert(announcement.id)
        saveDismissedIDs()
        loadAnnouncements() // Reload to filter out dismissed
    }
    
    /// Check if an announcement has been read
    func isRead(_ announcement: Announcement) -> Bool {
        readIDs.contains(announcement.id)
    }
    
    /// Get active (non-expired, non-dismissed) announcements
    var activeAnnouncements: [Announcement] {
        announcements
            .filter { $0.isActive && !dismissedIDs.contains($0.id) }
            .sorted { $0.priority < $1.priority }
    }
    
    /// Get unread active announcements
    var unreadAnnouncements: [Announcement] {
        activeAnnouncements.filter { !readIDs.contains($0.id) }
    }
    
    /// Get urgent/critical announcements that require attention
    var urgentAnnouncements: [Announcement] {
        activeAnnouncements.filter {
            $0.priority == .urgent || $0.type == .critical || $0.requiredReading && !isRead($0)
        }
    }
    
    /// Get the local announcements file URL
    var localFileURL: URL {
        URL(fileURLWithPath: Self.localAnnouncementsFilePath)
    }
    
    /// Check if local announcements file exists
    var localFileExists: Bool {
        FileManager.default.fileExists(atPath: Self.localAnnouncementsFilePath)
    }
    
    /// Create the local announcements directory and sample file
    func createLocalAnnouncementsFile() {
        let fileManager = FileManager.default
        let directoryPath = Self.localAnnouncementsDirectory
        let filePath = Self.localAnnouncementsFilePath
        
        // Create directory if needed
        if !fileManager.fileExists(atPath: directoryPath) {
            do {
                try fileManager.createDirectory(atPath: directoryPath, withIntermediateDirectories: true)
            } catch {
                self.error = "Failed to create directory: \(error.localizedDescription)"
                return
            }
        }
        
        // Create sample file
        let sampleAnnouncements = AnnouncementsSampleFile(
            announcements: [
                AnnouncementFileEntry(
                    id: "sample-1",
                    title: "Welcome to Helios Console",
                    message: "This is a sample announcement loaded from the local file. You can edit announcements.json to add your own.",
                    type: "info",
                    priority: "normal",
                    createdAt: ISO8601DateFormatter().string(from: Date()),
                    dismissible: true,
                    requiredReading: false
                )
            ],
            version: "1.0",
            lastUpdated: ISO8601DateFormatter().string(from: Date())
        )
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(sampleAnnouncements)
            try data.write(to: URL(fileURLWithPath: filePath))
            loadAnnouncements()
        } catch {
            self.error = "Failed to create sample file: \(error.localizedDescription)"
        }
    }
    
    /// Open the local announcements directory in Finder
    func openLocalDirectory() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [Self.localAnnouncementsDirectory]
        
        do {
            try process.run()
        } catch {
            self.error = "Failed to open directory: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Private Methods
    
    private func loadAnnouncements() {
        isLoading = true
        error = nil
        
        var loadedAnnouncements: [Announcement] = []
        var source: AnnouncementSource = .none
        
        // 1. Try to load from managed preferences (MDM) - highest priority
        if let managedAnnouncements = loadFromManagedPreferences(), !managedAnnouncements.isEmpty {
            loadedAnnouncements.append(contentsOf: managedAnnouncements)
            source = .mdm
        }
        
        // 2. Try to load from local file - second priority (if MDM didn't provide any)
        if loadedAnnouncements.isEmpty, let fileAnnouncements = loadFromLocalFile(), !fileAnnouncements.isEmpty {
            loadedAnnouncements.append(contentsOf: fileAnnouncements)
            source = .localFile
        }
        
        // 3. Load any testing announcements from UserDefaults
        if let localAnnouncements = loadFromUserDefaults() {
            loadedAnnouncements.append(contentsOf: localAnnouncements)
            if source == .none && !localAnnouncements.isEmpty {
                source = .userDefaults
            }
        }
        
        // 4. Filter out dismissed and expired
        loadedAnnouncements = loadedAnnouncements.filter { announcement in
            !dismissedIDs.contains(announcement.id) && announcement.isActive
        }
        
        // 5. Sort by priority, then by date
        loadedAnnouncements.sort { a, b in
            if a.priority != b.priority {
                return a.priority < b.priority
            }
            return a.createdAt > b.createdAt
        }
        
        // 6. Remove duplicates by ID (keep first occurrence)
        var seenIDs = Set<String>()
        loadedAnnouncements = loadedAnnouncements.filter { announcement in
            if seenIDs.contains(announcement.id) {
                return false
            }
            seenIDs.insert(announcement.id)
            return true
        }
        
        self.announcements = loadedAnnouncements
        self.activeSource = source
        self.lastRefresh = Date()
        self.isLoading = false
        updateUnreadCount()
    }
    
    /// Load announcements from MDM managed preferences
    private func loadFromManagedPreferences() -> [Announcement]? {
        // Read from managed app configuration
        // This reads preferences set by MDM configuration profiles
        guard let managedPrefs = UserDefaults.standard.persistentDomain(forName: managedPreferenceDomain) else {
            return nil
        }
        
        guard let announcementsData = managedPrefs["Announcements"] as? [[String: Any]] else {
            return nil
        }
        
        return announcementsData.compactMap { dict -> Announcement? in
            parseAnnouncementDictionary(dict)
        }
    }
    
    /// Load announcements from local JSON file
    private func loadFromLocalFile() -> [Announcement]? {
        let filePath = Self.localAnnouncementsFilePath
        
        guard FileManager.default.fileExists(atPath: filePath) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            let decoder = JSONDecoder()
            let file = try decoder.decode(AnnouncementsFile.self, from: data)
            return file.announcements
        } catch {
            self.error = "Failed to load local file: \(error.localizedDescription)"
            return nil
        }
    }
    
    /// Load local announcements from UserDefaults (for testing)
    private func loadFromUserDefaults() -> [Announcement]? {
        guard let data = UserDefaults.standard.data(forKey: "helios_local_announcements"),
              let announcements = try? JSONDecoder().decode([Announcement].self, from: data) else {
            return nil
        }
        return announcements
    }
    
    /// Parse announcement from dictionary (for MDM plist)
    private func parseAnnouncementDictionary(_ dict: [String: Any]) -> Announcement? {
        guard let id = dict["id"] as? String,
              let title = dict["title"] as? String,
              let message = dict["message"] as? String else {
            return nil
        }
        
        let typeString = dict["type"] as? String ?? "info"
        let type = AnnouncementType(rawValue: typeString) ?? .info
        
        let priorityString = dict["priority"] as? String ?? "normal"
        let priority = AnnouncementPriority(rawValue: priorityString) ?? .normal
        
        var createdAt = Date()
        if let createdAtString = dict["createdAt"] as? String {
            createdAt = ISO8601DateFormatter().date(from: createdAtString) ?? Date()
        }
        
        var expiresAt: Date? = nil
        if let expiresAtString = dict["expiresAt"] as? String {
            expiresAt = ISO8601DateFormatter().date(from: expiresAtString)
        }
        
        let actionURL = dict["actionURL"] as? String
        let actionLabel = dict["actionLabel"] as? String
        let dismissible = dict["dismissible"] as? Bool ?? true
        let targetPlatforms = dict["targetPlatforms"] as? [String]
        let requiredReading = dict["requiredReading"] as? Bool ?? false
        
        return Announcement(
            id: id,
            title: title,
            message: message,
            type: type,
            priority: priority,
            createdAt: createdAt,
            expiresAt: expiresAt,
            actionURL: actionURL,
            actionLabel: actionLabel,
            dismissible: dismissible,
            targetPlatforms: targetPlatforms,
            requiredReading: requiredReading
        )
    }
    
    /// Save local announcements (for testing)
    func saveLocalAnnouncement(_ announcement: Announcement) {
        var local = loadFromUserDefaults() ?? []
        local.removeAll { $0.id == announcement.id }
        local.append(announcement)
        
        if let data = try? JSONEncoder().encode(local) {
            UserDefaults.standard.set(data, forKey: "helios_local_announcements")
        }
        loadAnnouncements()
    }
    
    /// Remove a local announcement (for testing)
    func removeLocalAnnouncement(_ id: String) {
        var local = loadFromUserDefaults() ?? []
        local.removeAll { $0.id == id }
        
        if let data = try? JSONEncoder().encode(local) {
            UserDefaults.standard.set(data, forKey: "helios_local_announcements")
        }
        loadAnnouncements()
    }
    
    private func loadDismissedIDs() {
        if let ids = UserDefaults.standard.stringArray(forKey: dismissedKey) {
            dismissedIDs = Set(ids)
        }
    }
    
    private func saveDismissedIDs() {
        UserDefaults.standard.set(Array(dismissedIDs), forKey: dismissedKey)
    }
    
    private func loadReadIDs() {
        if let ids = UserDefaults.standard.stringArray(forKey: readKey) {
            readIDs = Set(ids)
        }
    }
    
    private func saveReadIDs() {
        UserDefaults.standard.set(Array(readIDs), forKey: readKey)
    }
    
    private func updateUnreadCount() {
        unreadCount = unreadAnnouncements.count
    }
    
    private func startAutoRefresh() {
        // Refresh every 5 minutes
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.loadAnnouncements()
            }
        }
    }
    
    private func startFileMonitoring() {
        let filePath = Self.localAnnouncementsFilePath
        let directoryPath = Self.localAnnouncementsDirectory
        
        // Monitor the directory for changes
        let fd = open(directoryPath, O_EVTONLY)
        guard fd >= 0 else { return }
        
        fileMonitor = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        
        fileMonitor?.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.loadAnnouncements()
            }
        }
        
        fileMonitor?.setCancelHandler {
            close(fd)
        }
        
        fileMonitor?.resume()
    }
    
    @objc private func managedConfigurationDidChange(_ notification: Notification) {
        // Reload when managed configuration changes
        Task { @MainActor in
            loadAnnouncements()
        }
    }
}

// MARK: - Sample File Structure (for encoding)

private struct AnnouncementsSampleFile: Codable {
    let announcements: [AnnouncementFileEntry]
    let version: String
    let lastUpdated: String
    
    enum CodingKeys: String, CodingKey {
        case announcements = "Announcements"
        case version = "Version"
        case lastUpdated = "LastUpdated"
    }
}

private struct AnnouncementFileEntry: Codable {
    let id: String
    let title: String
    let message: String
    let type: String
    let priority: String
    let createdAt: String
    let expiresAt: String?
    let actionURL: String?
    let actionLabel: String?
    let dismissible: Bool
    let requiredReading: Bool
    
    init(
        id: String,
        title: String,
        message: String,
        type: String = "info",
        priority: String = "normal",
        createdAt: String,
        expiresAt: String? = nil,
        actionURL: String? = nil,
        actionLabel: String? = nil,
        dismissible: Bool = true,
        requiredReading: Bool = false
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.type = type
        self.priority = priority
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.actionURL = actionURL
        self.actionLabel = actionLabel
        self.dismissible = dismissible
        self.requiredReading = requiredReading
    }
}

// MARK: - Mock Data for Testing

extension AnnouncementService {
    /// Add sample announcements for testing (to UserDefaults)
    func addSampleAnnouncements() {
        let samples: [Announcement] = [
            Announcement(
                id: "sample-1",
                title: "System Maintenance Scheduled",
                message: "Our servers will be undergoing maintenance on Saturday, February 1st from 2:00 AM to 4:00 AM EST. During this time, device check-ins may be delayed.",
                type: .maintenance,
                priority: .high,
                expiresAt: Calendar.current.date(byAdding: .day, value: 7, to: Date()),
                actionURL: "https://status.example.com",
                actionLabel: "View Status Page"
            ),
            Announcement(
                id: "sample-2",
                title: "New macOS Update Available",
                message: "macOS 15.3 is now available. Please ensure all managed devices are updated within the next 14 days to maintain compliance.",
                type: .update,
                priority: .normal,
                expiresAt: Calendar.current.date(byAdding: .day, value: 14, to: Date()),
                actionURL: "https://support.apple.com/macos",
                actionLabel: "Learn More"
            ),
            Announcement(
                id: "sample-3",
                title: "Security Advisory",
                message: "A critical security vulnerability has been identified. Devices running macOS 14.0 or earlier should be updated immediately.",
                type: .critical,
                priority: .urgent,
                requiredReading: true
            ),
            Announcement(
                id: "sample-4",
                title: "Welcome to Helios Console",
                message: "Thank you for using Helios Console for your device management needs. Check out our documentation to get started.",
                type: .info,
                priority: .low,
                actionURL: "https://docs.example.com",
                actionLabel: "View Documentation",
                dismissible: true
            ),
            Announcement(
                id: "sample-5",
                title: "Enrollment Complete",
                message: "Your organization has successfully enrolled 500+ devices. All compliance policies are now active.",
                type: .success,
                priority: .normal
            )
        ]
        
        for sample in samples {
            saveLocalAnnouncement(sample)
        }
    }
    
    /// Clear all sample/local announcements from UserDefaults
    func clearLocalAnnouncements() {
        UserDefaults.standard.removeObject(forKey: "helios_local_announcements")
        loadAnnouncements()
    }
}
