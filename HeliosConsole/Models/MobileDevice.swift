//
//  MobileDevice.swift
//  test
//
//  Created by heath on 1/21/26.
//


//
//  MobileDevice.swift
//  Helios
//
//  Model for mobile device detail from Jamf Pro API v2
//  Supports iOS, iPadOS, tvOS, watchOS, and visionOS devices
//

import Foundation

// MARK: - Mobile Device (Top-Level Model)

/// Represents a mobile device from the Jamf Pro mobile-devices/detail API
struct MobileDevice: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let enforceName: Bool?
    let assetTag: String?
    let lastInventoryUpdateTimestamp: String?
    let osVersion: String?
    let osBuild: String?
    let osSupplementalBuildVersion: String?
    let osRapidSecurityResponse: String?
    let softwareUpdateDeviceId: String?
    let serialNumber: String?
    let udid: String?
    let initialEntryTimestamp: String?
    let ipAddress: String?
    let wifiMacAddress: String?
    let bluetoothMacAddress: String?
    let deviceOwnershipLevel: String?
    let enrollmentMethod: String?
    let enrollmentSessionTokenValid: Bool?
    let lastEnrollmentTimestamp: String?
    let mdmProfileExpirationTimestamp: String?
    let managed: Bool?
    let timeZone: String?
    let site: MobileDeviceSite?
    let location: MobileDeviceLocation?
    let type: String?  // "ios", "tvos", "visionos", etc.
    let ios: MobileDeviceiOS?
    let tvos: MobileDeviceTvOS?
    let watchos: MobileDeviceWatchOS?
    let visionos: MobileDeviceVisionOS?
    let declarativeDeviceManagementEnabled: Bool?
    let extensionAttributes: [MobileDeviceExtensionAttribute]?
    let managementId: String?
    let groups: [MobileDeviceGroup]?
    
    // MARK: - Hashable
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: MobileDevice, rhs: MobileDevice) -> Bool {
        lhs.id == rhs.id
    }
    
    // MARK: - Computed Properties
    
    var displayName: String {
        name ?? "Unknown Device"
    }
    
    var platformType: PlatformType {
        guard let type = type?.lowercased() else { return .iOS }
        
        switch type {
        case "ios":
            // Check if it's an iPad based on model identifier
            if let modelId = ios?.modelIdentifier?.lowercased(), modelId.contains("ipad") {
                return .iPadOS
            }
            if let model = ios?.model?.lowercased(), model.contains("ipad") {
                return .iPadOS
            }
            return .iOS
        case "ipados":
            return .iPadOS
        case "visionos":
            return .visionOS
        case "tvos":
            return .iOS // Group tvOS with iOS for now
        default:
            return .iOS
        }
    }
    
    var model: String {
        ios?.model ?? tvos?.model ?? visionos?.model ?? "Unknown"
    }
    
    var modelIdentifier: String? {
        ios?.modelIdentifier ?? tvos?.modelIdentifier ?? visionos?.modelIdentifier
    }
    
    var isSupervised: Bool {
        ios?.supervised ?? tvos?.supervised ?? visionos?.supervised ?? false
    }
    
    var batteryLevel: Int? {
        ios?.batteryLevel ?? visionos?.batteryLevel
    }
    
    var capacityMb: Int? {
        ios?.capacityMb ?? tvos?.capacityMb ?? visionos?.capacityMb
    }
    
    var availableMb: Int? {
        ios?.availableMb ?? tvos?.availableMb ?? visionos?.availableMb
    }
    
    var percentageUsed: Int? {
        ios?.percentageUsed ?? tvos?.percentageUsed ?? visionos?.percentageUsed
    }
    
    var applications: [MobileDeviceApplication]? {
        ios?.applications ?? tvos?.applications ?? visionos?.applications
    }
    
    var certificates: [MobileDeviceCertificate]? {
        ios?.certificates ?? tvos?.certificates ?? visionos?.certificates
    }
    
    var configurationProfiles: [MobileDeviceConfigurationProfile]? {
        ios?.configurationProfiles ?? tvos?.configurationProfiles ?? visionos?.configurationProfiles
    }
    
    var security: MobileDeviceSecurity? {
        ios?.security ?? tvos?.security ?? visionos?.security
    }
    
    var purchasing: MobileDevicePurchasing? {
        ios?.purchasing ?? tvos?.purchasing ?? visionos?.purchasing
    }
    
    var network: MobileDeviceNetwork? {
        ios?.network ?? tvos?.network ?? visionos?.network
    }
}

// MARK: - Site

struct MobileDeviceSite: Codable, Hashable {
    let id: String?
    let name: String?
}

// MARK: - Location

struct MobileDeviceLocation: Codable, Hashable {
    let username: String?
    let realName: String?
    let emailAddress: String?
    let position: String?
    let phoneNumber: String?
    let departmentId: String?
    let buildingId: String?
    let room: String?
}

// MARK: - iOS Device Details

struct MobileDeviceiOS: Codable, Hashable {
    let capacityMb: Int?
    let availableMb: Int?
    let percentageUsed: Int?
    let model: String?
    let modelIdentifier: String?
    let modelNumber: String?
    let shared: Bool?
    let supervised: Bool?
    let batteryLevel: Int?
    let batteryHealth: String?
    let lastBackupTimestamp: String?
    let deviceLocatorServiceEnabled: Bool?
    let doNotDisturbEnabled: Bool?
    let cloudBackupEnabled: Bool?
    let lastCloudBackupTimestamp: String?
    let locationServicesEnabled: Bool?
    let computer: String?
    let bleCapable: Bool?
    let security: MobileDeviceSecurity?
    let purchasing: MobileDevicePurchasing?
    let network: MobileDeviceNetwork?
    let configurationProfiles: [MobileDeviceConfigurationProfile]?
    let attachments: [MobileDeviceAttachment]?
    let applications: [MobileDeviceApplication]?
    let certificates: [MobileDeviceCertificate]?
    let provisioningProfiles: [MobileDeviceProvisioningProfile]?
    let ebooks: [MobileDeviceEbook]?
    let serviceSubscriptions: [MobileDeviceServiceSubscription]?
    let mdmCapableUsers: [MobileDeviceMdmCapableUser]?
    let iTunesStoreAccountActive: Bool?
    let unlockToken: String?
}

// MARK: - tvOS Device Details

struct MobileDeviceTvOS: Codable, Hashable {
    let capacityMb: Int?
    let availableMb: Int?
    let percentageUsed: Int?
    let model: String?
    let modelIdentifier: String?
    let modelNumber: String?
    let supervised: Bool?
    let security: MobileDeviceSecurity?
    let purchasing: MobileDevicePurchasing?
    let network: MobileDeviceNetwork?
    let configurationProfiles: [MobileDeviceConfigurationProfile]?
    let applications: [MobileDeviceApplication]?
    let certificates: [MobileDeviceCertificate]?
}

// MARK: - watchOS Device Details

struct MobileDeviceWatchOS: Codable, Hashable {
    let model: String?
    let modelIdentifier: String?
    let supervised: Bool?
}

// MARK: - visionOS Device Details

struct MobileDeviceVisionOS: Codable, Hashable {
    let capacityMb: Int?
    let availableMb: Int?
    let percentageUsed: Int?
    let model: String?
    let modelIdentifier: String?
    let modelNumber: String?
    let supervised: Bool?
    let batteryLevel: Int?
    let batteryHealth: String?
    let security: MobileDeviceSecurity?
    let purchasing: MobileDevicePurchasing?
    let network: MobileDeviceNetwork?
    let configurationProfiles: [MobileDeviceConfigurationProfile]?
    let applications: [MobileDeviceApplication]?
    let certificates: [MobileDeviceCertificate]?
}

// MARK: - Security, Purchasing, Network
// (Defined in MobileDeviceModels.swift)

// MARK: - Configuration Profile

struct MobileDeviceConfigurationProfile: Codable, Hashable, Identifiable {
    let displayName: String?
    let version: String?
    let uuid: String?
    let identifier: String?
    
    var id: String { uuid ?? identifier ?? UUID().uuidString }
}

// MARK: - Application, Certificate, Provisioning Profile, Ebook, Service Subscription
// (Defined in MobileDeviceModels.swift)

// MARK: - MDM Capable User

struct MobileDeviceMdmCapableUser: Codable, Hashable {
    let id: String?
    let name: String?
}

// MARK: - Attachment

struct MobileDeviceAttachment: Codable, Hashable, Identifiable {
    let id: String
    let name: String?
    let fileType: String?
    let sizeBytes: Int?
}

// MARK: - Extension Attribute, Group
// (Defined in MobileDeviceModels.swift)

// MARK: - Search Response

/// Response from /api/v2/mobile-devices/detail search
struct MobileDeviceSearchResponse: Codable {
    let totalCount: Int
    let results: [MobileDevice]
}
