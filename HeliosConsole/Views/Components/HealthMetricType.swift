//
//  HealthMetricType.swift
//  test
//
//  Created by heath on 1/21/26.
//


//
//  HealthMetricTypes.swift
//  Helios Console
//
//  Core types for the Environment Health Scorecard system
//

import SwiftUI

// MARK: - Health Metric Type

enum HealthMetricType: String, CaseIterable, Identifiable, Hashable {
    case checkedIn = "Checked-In"
    case protected = "Protected"
    case encrypted = "Encrypted"
    case secured = "Secured"
    case upToDate = "Up to Date"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .checkedIn: return "clock.badge.checkmark"
        case .protected: return "shield.checkered"
        case .encrypted: return "checkmark.seal"
        case .secured: return "checkmark.shield"
        case .upToDate: return "arrow.triangle.2.circlepath"
        }
    }
    
    var description: String {
        switch self {
        case .checkedIn: return "Devices that have checked in recently"
        case .protected: return "Devices with active protection"
        case .encrypted: return "Devices with AppleCare coverage"
        case .secured: return "Devices meeting security requirements"
        case .upToDate: return "Devices running latest OS version"
        }
    }
    
    // Labels for each compliance status
    var compliantLabel: String {
        switch self {
        case .checkedIn: return "Recently Checked-In"
        case .protected: return "Protected"
        case .encrypted: return "Encrypted"
        case .secured: return "Secured"
        case .upToDate: return "Up to Date"
        }
    }
    
    var nonCompliantLabel: String {
        switch self {
        case .checkedIn: return "Not Checked-In"
        case .protected: return "Not Protected"
        case .encrypted: return "Not Encrypted"
        case .secured: return "Not Secured"
        case .upToDate: return "Outdated"
        }
    }
    
    var unknownLabel: String {
        return "Unknown Status"
    }
    
    // Gradient colors for each metric
    var gradientColors: [Color] {
        switch self {
        case .checkedIn: return [.blue, .cyan]
        case .protected: return [.purple, .pink]
        case .encrypted: return [.orange, .yellow]
        case .secured: return [.green, .mint]
        case .upToDate: return [.indigo, .blue]
        }
    }
}

// MARK: - Health Thresholds (config-driven banding)

/// Percentage → color banding for health scores, driven by the features
/// domain's healthScorecard.metrics[].thresholds (defaults: warning 80,
/// critical 50 — green at/above warning, orange at/above critical, red
/// below). Every scorecard/health surface must band through this helper so
/// they never disagree again (Dashboard previously used 90/70 while the
/// device health section used 80/50).
enum HealthThresholds {
    static func color(forPercentage percentage: Double, metricID: String? = nil) -> Color {
        let scorecard = MDMConfigurationManager.shared.configuration
            .features?.effectiveHealthScorecard
        let thresholds = metricID.flatMap { scorecard?.effectiveMetric(id: $0)?.effectiveThresholds }
            ?? FeaturesConfiguration.HealthMetricSetting.Thresholds.empty
        if percentage >= Double(thresholds.effectiveWarning) { return .green }
        if percentage >= Double(thresholds.effectiveCritical) { return .orange }
        return .red
    }
}

// MARK: - Health Segment Type

enum HealthSegmentType: String, Hashable, CaseIterable {
    case compliant
    case nonCompliant
    case unknown
    
    var color: Color {
        switch self {
        case .compliant: return .green
        case .nonCompliant: return .red
        case .unknown: return .yellow
        }
    }
    
    var label: String {
        switch self {
        case .compliant: return "Compliant"
        case .nonCompliant: return "Non-Compliant"
        case .unknown: return "Unknown"
        }
    }
    
    var icon: String {
        switch self {
        case .compliant: return "checkmark.circle.fill"
        case .nonCompliant: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}

// MARK: - Health Metric Data

struct HealthMetricData: Identifiable, Hashable {
    let id = UUID()
    let type: HealthMetricType
    let compliantCount: Int
    let nonCompliantCount: Int
    let unknownCount: Int
    
    // Encryption-specific breakdown (only used when type == .encrypted)
    var encryptedCount: Int = 0      // Boot partition state = ENCRYPTED
    var encryptingCount: Int = 0     // Boot partition state = ENCRYPTING
    var decryptingCount: Int = 0     // Boot partition state = DECRYPTING
    var unencryptedCount: Int = 0    // Boot partition state = UNENCRYPTED or other non-compliant
    
    var totalCount: Int {
        compliantCount + nonCompliantCount + unknownCount
    }
    
    var percentage: Double {
        guard totalCount > 0 else { return 0 }
        return Double(compliantCount) / Double(totalCount) * 100
    }
    
    var compliantPercentage: Double {
        guard totalCount > 0 else { return 0 }
        return Double(compliantCount) / Double(totalCount)
    }
    
    var nonCompliantPercentage: Double {
        guard totalCount > 0 else { return 0 }
        return Double(nonCompliantCount) / Double(totalCount)
    }
    
    var unknownPercentage: Double {
        guard totalCount > 0 else { return 0 }
        return Double(unknownCount) / Double(totalCount)
    }
    
    // Encryption-specific percentages
    var encryptedPercentage: Double {
        guard totalCount > 0 else { return 0 }
        return Double(encryptedCount) / Double(totalCount)
    }
    
    var encryptingPercentage: Double {
        guard totalCount > 0 else { return 0 }
        return Double(encryptingCount) / Double(totalCount)
    }
    
    var decryptingPercentage: Double {
        guard totalCount > 0 else { return 0 }
        return Double(decryptingCount) / Double(totalCount)
    }
    
    var unencryptedPercentage: Double {
        guard totalCount > 0 else { return 0 }
        return Double(unencryptedCount) / Double(totalCount)
    }
    
    // Integer percentage displays (for badges)
    var compliantPercentageDisplay: Int {
        Int(compliantPercentage * 100)
    }
    
    var nonCompliantPercentageDisplay: Int {
        Int(nonCompliantPercentage * 100)
    }
    
    var unknownPercentageDisplay: Int {
        Int(unknownPercentage * 100)
    }
    
    var encryptedPercentageDisplay: Int {
        Int(encryptedPercentage * 100)
    }
    
    var encryptingPercentageDisplay: Int {
        Int(encryptingPercentage * 100)
    }
    
    var decryptingPercentageDisplay: Int {
        Int(decryptingPercentage * 100)
    }
    
    var unencryptedPercentageDisplay: Int {
        Int(unencryptedPercentage * 100)
    }
    
    // Get count for a specific segment type
    func count(for segment: HealthSegmentType) -> Int {
        switch segment {
        case .compliant: return compliantCount
        case .nonCompliant: return nonCompliantCount
        case .unknown: return unknownCount
        }
    }
    
    // Get percentage for a specific segment type
    func percentage(for segment: HealthSegmentType) -> Double {
        switch segment {
        case .compliant: return compliantPercentage
        case .nonCompliant: return nonCompliantPercentage
        case .unknown: return unknownPercentage
        }
    }
    
    func percentageDisplay(for segment: HealthSegmentType) -> Int {
        switch segment {
        case .compliant: return compliantPercentageDisplay
        case .nonCompliant: return nonCompliantPercentageDisplay
        case .unknown: return unknownPercentageDisplay
        }
    }
}

// MARK: - Mock Health Data Generator

extension HealthMetricData {
    /// Generates mock health data for testing purposes
    static func generateMockData() -> [HealthMetricData] {
        return [
            HealthMetricData(
                type: .checkedIn,
                compliantCount: 5420,
                nonCompliantCount: 489,
                unknownCount: 98
            ),
            HealthMetricData(
                type: .protected,
                compliantCount: 5780,
                nonCompliantCount: 185,
                unknownCount: 42
            ),
            HealthMetricData(
                type: .encrypted,
                compliantCount: 5650,
                nonCompliantCount: 287,
                unknownCount: 70
            ),
            HealthMetricData(
                type: .secured,
                compliantCount: 5512,
                nonCompliantCount: 398,
                unknownCount: 97
            ),
            HealthMetricData(
                type: .upToDate,
                compliantCount: 4870,
                nonCompliantCount: 1039,
                unknownCount: 98
            )
        ]
    }
}
