//
//  MobileDeviceModels.swift
//  Helios
//
//  Shared models for mobile device data from Jamf Pro API v2
//  Used by both MobileDevice and MobileDeviceInventoryService
//

import Foundation

// MARK: - Security

struct MobileDeviceSecurity: Codable, Hashable {
    let dataProtected: Bool?
    let blockLevelEncryptionCapable: Bool?
    let fileLevelEncryptionCapable: Bool?
    let passcodePresent: Bool?
    let passcodeCompliant: Bool?
    let passcodeCompliantWithProfile: Bool?
    let hardwareEncryption: Int?
    let activationLockEnabled: Bool?
    let jailBreakDetected: Bool?
    let bootstrapToken: String?
    let bootstrapTokenEscrowed: String?
    let attestationStatus: String?
    let lastAttestationAttemptDate: String?
    let lastSuccessfulAttestationDate: String?
    let passcodeLockGracePeriodEnforcedSeconds: Int?
    let personalDeviceProfileCurrent: Bool?
    let lostModeEnabled: Bool?
    let lostModePersistent: Bool?
    let lostModeMessage: String?
    let lostModePhoneNumber: String?
    let lostModeFootnote: String?
    let lostModeLocation: MobileDeviceLostModeLocation?
    let lostModeEnabledDate: String?
}

struct MobileDeviceLostModeLocation: Codable, Hashable {
    let latitude: Double?
    let longitude: Double?
    let altitude: Double?
    let horizontalAccuracy: Double?
    let verticalAccuracy: Double?
    let course: Double?
    let speed: Double?
    let timestamp: String?
}

// MARK: - Purchasing

struct MobileDevicePurchasing: Codable, Hashable {
    let purchased: Bool?
    let leased: Bool?
    let poNumber: String?
    let vendor: String?
    let appleCareId: String?
    let purchasePrice: String?
    let purchasingAccount: String?
    let poDate: String?
    let warrantyExpiresDate: String?
    let leaseExpiresDate: String?
    let lifeExpectancy: Int?
    let purchasingContact: String?
    let extensionAttributes: [MobileDeviceExtensionAttribute]?
}

// MARK: - Network

struct MobileDeviceNetwork: Codable, Hashable {
    let cellularTechnology: String?
    let voiceRoamingEnabled: Bool?
    let imei: String?
    let iccid: String?
    let meid: String?
    let eid: String?
    let carrierSettingsVersion: String?
    let currentCarrierNetwork: String?
    let currentMobileCountryCode: String?
    let currentMobileNetworkCode: String?
    let homeCarrierNetwork: String?
    let homeMobileCountryCode: String?
    let homeMobileNetworkCode: String?
    let dataRoamingEnabled: Bool?
    let roaming: Bool?
    let personalHotspotEnabled: Bool?
    let phoneNumber: String?
    let preferredVoiceNumber: String?
}

// MARK: - Application

struct MobileDeviceApplication: Codable, Hashable, Identifiable {
    let name: String?
    let identifier: String?
    let version: String?
    let shortVersion: String?
    let managementStatus: String?
    let validationStatus: Bool?
    let bundleSize: String?
    let dynamicSize: String?
    
    var id: String {
        identifier ?? UUID().uuidString
    }
}

// MARK: - Certificate

struct MobileDeviceCertificate: Codable, Hashable, Identifiable {
    let commonName: String?
    let identity: Bool?
    let expirationDate: String?
    let expirationDateEpoch: String?
    let subjectName: String?
    let serialNumber: String?
    let sha1Fingerprint: String?
    let issuedDateEpoch: String?
    let certificateStatus: String?
    let lifecycleStatus: String?
    
    var id: String {
        sha1Fingerprint ?? serialNumber ?? "\(commonName ?? "unknown")_\(expirationDate ?? "noexp")"
    }
}

// MARK: - Provisioning Profile

struct MobileDeviceProvisioningProfile: Codable, Hashable, Identifiable {
    let displayName: String?
    let uuid: String?
    let expirationDate: String?
    
    var id: String {
        uuid ?? UUID().uuidString
    }
}

// MARK: - Ebook

struct MobileDeviceEbook: Codable, Hashable, Identifiable {
    let title: String?
    let name: String?
    let author: String?
    let version: String?
    let kind: String?
    
    var id: String {
        name ?? title ?? "\(title ?? "unknown")_\(author ?? "unknown")_\(version ?? "1.0")"
    }
}

// MARK: - Service Subscription

struct MobileDeviceServiceSubscription: Codable, Hashable, Identifiable {
    let label: String?
    let carrierId: String?
    let carrierName: String?
    let phoneNumber: String?
    let slot: String?
    let labelId: String?
    let eid: String?
    let imei: String?
    let iccid: String?
    let meid: String?
    let carrierSettingsVersion: String?
    let currentCarrierNetwork: String?
    let currentMobileCountryCode: String?
    let currentMobileNetworkCode: String?
    let subscriberCarrierNetwork: String?
    let roaming: Bool?
    let voicePreferred: Bool?
    let dataPreferred: Bool?
    
    var id: String {
        iccid ?? imei ?? eid ?? UUID().uuidString
    }
}

// MARK: - Extension Attribute

struct MobileDeviceExtensionAttribute: Codable, Hashable, Identifiable {
    let id: String?
    let name: String?
    let type: String?
    let value: [String]?
    let inventoryDisplay: String?
    let extensionAttributeCollectionAllowed: Bool?
}

// MARK: - Group

struct MobileDeviceGroup: Codable, Hashable, Identifiable {
    let groupId: String?
    let groupName: String?
    let groupDescription: String?
    let smart: Bool?
    
    var id: String {
        groupId ?? UUID().uuidString
    }
}
