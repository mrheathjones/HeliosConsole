//
//  ActionLogEntry.swift
//  HeliosConsole
//
//  Data model for auditing MDM actions performed from Helios Console
//

import Foundation

struct ActionLogEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let actionName: String
    let actionCategory: String
    let deviceName: String
    let deviceSerialNumber: String
    let deviceId: String
    let devicePlatform: String
    let performedBy: String
    let ipAddressUsed: String?
    let success: Bool
    let errorMessage: String?
    let source: LogSource
    
    enum LogSource: String, Codable, CaseIterable {
        case heliosConsole = "Helios Console"
        case jamfPolicy = "Jamf Policy"
        
        var icon: String {
            switch self {
            case .heliosConsole: return "sun.max.fill"
            case .jamfPolicy: return "server.rack"
            }
        }
    }
    
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        actionName: String,
        actionCategory: String,
        deviceName: String,
        deviceSerialNumber: String,
        deviceId: String,
        devicePlatform: String = "macOS",
        performedBy: String,
        ipAddressUsed: String? = nil,
        success: Bool,
        errorMessage: String? = nil,
        source: LogSource = .heliosConsole
    ) {
        self.id = id
        self.timestamp = timestamp
        self.actionName = actionName
        self.actionCategory = actionCategory
        self.deviceName = deviceName
        self.deviceSerialNumber = deviceSerialNumber
        self.deviceId = deviceId
        self.devicePlatform = devicePlatform
        self.performedBy = performedBy
        self.ipAddressUsed = ipAddressUsed
        self.success = success
        self.errorMessage = errorMessage
        self.source = source
    }
}
