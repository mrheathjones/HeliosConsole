//
//  DeviceFormatting.swift
//  Helios
//
//  Display formatting shared by the computer detail views.
//

import Foundation

enum DeviceFormatting {
    static func storage(_ megabytes: Int) -> String {
        if megabytes >= 1024 * 1024 {
            return String(format: "%.2f TB", Double(megabytes) / (1024 * 1024))
        } else if megabytes >= 1024 {
            return String(format: "%.1f GB", Double(megabytes) / 1024)
        } else {
            return "\(megabytes) MB"
        }
    }
    
    static func date(_ dateString: String?) -> String? {
        guard let dateString = dateString else { return nil }
        
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        var date = isoFormatter.date(from: dateString)
        if date == nil {
            isoFormatter.formatOptions = [.withInternetDateTime]
            date = isoFormatter.date(from: dateString)
        }
        
        // Try simple date format
        if date == nil {
            let simpleFormatter = DateFormatter()
            simpleFormatter.dateFormat = "yyyy-MM-dd"
            date = simpleFormatter.date(from: dateString)
        }
        
        guard let parsedDate = date else { return dateString }
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .short
        
        return displayFormatter.string(from: parsedDate)
    }
    
    static func gatekeeperStatus(_ status: String?) -> String? {
        guard let status = status else { return nil }
        switch status {
        case "APP_STORE_AND_IDENTIFIED_DEVELOPERS":
            return "App Store & Identified Developers"
        case "APP_STORE":
            return "App Store Only"
        case "ANYWHERE":
            return "Anywhere"
        case "DISABLED":
            return "Disabled"
        default:
            return status
        }
    }
}

// MARK: - Extension Attribute Lookup

extension Computer {
    /// First value of the extension attribute `ref` identifies, checking the
    /// general section before the top-level list.
    func extensionAttributeValue(_ ref: VPNIPExtensionAttributeRef) -> String? {
        // Check general extension attributes
        if let eas = general?.extensionAttributes {
            if let ea = eas.first(where: { ref.matches($0) }) {
                return ea.values?.first
            }
        }

        // Check top-level extension attributes
        if let eas = extensionAttributes {
            if let ea = eas.first(where: { ref.matches($0) }) {
                return ea.values?.first
            }
        }

        return nil
    }
}
