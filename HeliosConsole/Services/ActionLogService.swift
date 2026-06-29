//
//  ActionLogService.swift
//  HeliosConsole
//
//  Singleton service for auditing MDM actions with disk persistence
//

import Foundation

@MainActor
class ActionLogService: ObservableObject {
    static let shared = ActionLogService()
    
    // MARK: - Published Properties
    
    @Published private(set) var logs: [ActionLogEntry] = []
    @Published private(set) var isLoading: Bool = false
    
    // MARK: - File Paths
    
    private static let logsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Helios/Logs", isDirectory: true)
    }()
    
    private static let logsFileURL: URL = {
        logsDirectory.appendingPathComponent("action_logs.json")
    }()
    
    // MARK: - Init
    
    private init() {
        ensureDirectoryExists()
        loadFromDisk()
    }
    
    // MARK: - Public Methods
    
    /// Log a new action entry. Auto-saves to disk.
    func logAction(
        actionName: String,
        actionCategory: String,
        deviceName: String,
        deviceSerialNumber: String,
        deviceId: String,
        devicePlatform: String = "macOS",
        performedBy: String? = nil,
        ipAddressUsed: String? = nil,
        success: Bool,
        errorMessage: String? = nil,
        source: ActionLogEntry.LogSource = .heliosConsole
    ) {
        let userEmail = performedBy ?? KeychainManager.shared.loadUserEmail() ?? "Unknown"
        
        let entry = ActionLogEntry(
            actionName: actionName,
            actionCategory: actionCategory,
            deviceName: deviceName,
            deviceSerialNumber: deviceSerialNumber,
            deviceId: deviceId,
            devicePlatform: devicePlatform,
            performedBy: userEmail,
            ipAddressUsed: ipAddressUsed,
            success: success,
            errorMessage: errorMessage,
            source: source
        )
        
        logs.insert(entry, at: 0) // Newest first
        saveToDisk()
        NSLog("📋 ActionLogService: Logged '%@' on '%@' — %@", actionName, deviceName, success ? "Success" : "Failed")
    }
    
    /// Get logs filtered to a specific device by ID
    func logs(forDeviceId deviceId: String) -> [ActionLogEntry] {
        logs.filter { $0.deviceId == deviceId }
    }
    
    /// Get logs with multiple filter criteria
    func filteredLogs(
        searchText: String = "",
        source: ActionLogEntry.LogSource? = nil,
        category: String? = nil,
        successOnly: Bool? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) -> [ActionLogEntry] {
        var result = logs
        
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.deviceName.lowercased().contains(query) ||
                $0.deviceSerialNumber.lowercased().contains(query) ||
                $0.actionName.lowercased().contains(query) ||
                $0.performedBy.lowercased().contains(query)
            }
        }
        if let source = source {
            result = result.filter { $0.source == source }
        }
        if let category = category {
            result = result.filter { $0.actionCategory == category }
        }
        if let successOnly = successOnly {
            result = result.filter { $0.success == successOnly }
        }
        if let startDate = startDate {
            result = result.filter { $0.timestamp >= startDate }
        }
        if let endDate = endDate {
            result = result.filter { $0.timestamp <= endDate }
        }
        
        return result
    }
    
    /// Get unique action categories from all logs
    var availableCategories: [String] {
        Array(Set(logs.map { $0.actionCategory })).sorted()
    }
    
    /// Clear all logs
    func clearLogs() {
        logs.removeAll()
        saveToDisk()
        NSLog("🗑️ ActionLogService: All logs cleared")
    }
    
    /// Export logs as CSV string
    func exportAsCSV() -> String {
        var csv = "Timestamp,Action,Category,Device,Serial Number,Platform,Performed By,IP Address,Success,Error,Source\n"
        let formatter = ISO8601DateFormatter()
        
        for log in logs {
            let row = [
                formatter.string(from: log.timestamp),
                log.actionName,
                log.actionCategory,
                log.deviceName,
                log.deviceSerialNumber,
                log.devicePlatform,
                log.performedBy,
                log.ipAddressUsed ?? "",
                log.success ? "Yes" : "No",
                log.errorMessage ?? "",
                log.source.rawValue
            ].map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
            .joined(separator: ",")
            
            csv += row + "\n"
        }
        return csv
    }
    
    // MARK: - Private Persistence
    
    private func ensureDirectoryExists() {
        try? FileManager.default.createDirectory(
            at: Self.logsDirectory,
            withIntermediateDirectories: true
        )
    }
    
    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: Self.logsFileURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: Self.logsFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            logs = try decoder.decode([ActionLogEntry].self, from: data)
            NSLog("✅ ActionLogService: Loaded %d log entries from disk", logs.count)
        } catch {
            NSLog("❌ ActionLogService: Failed to load logs: %@", error.localizedDescription)
        }
    }
    
    private func saveToDisk() {
        let currentLogs = logs
        Task.detached(priority: .background) {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(currentLogs)
                try data.write(to: Self.logsFileURL, options: .atomic)
            } catch {
                NSLog("❌ ActionLogService: Failed to save logs: %@", error.localizedDescription)
            }
        }
    }
}
