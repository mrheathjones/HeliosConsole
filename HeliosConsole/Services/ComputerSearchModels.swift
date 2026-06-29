//
//
//  ComputerSearchResponse.swift
//  test
//
//  Created by heath on 1/20/26.
//

import Foundation

// MARK: - Computer Search Response

/// Response from the computers-inventory search endpoint
struct ComputerSearchResponse: Codable, Sendable {
    let totalCount: Int?
    let results: [ComputerSearchResult]?
}

/// Individual computer result from search
/// This model handles the full inventory response structure
struct ComputerSearchResult: Codable, Identifiable, Hashable, Sendable {
    let id: String?
    let udid: String?
    let general: ComputerSearchGeneral?
    let hardware: ComputerSearchHardware?
    let operatingSystem: ComputerSearchOS?
    let userAndLocation: ComputerSearchUserLocation?
    let diskEncryption: ComputerSearchDiskEncryption?
    let security: ComputerSearchSecurity?
    let applications: [ComputerSearchApplication]?
    let storage: ComputerSearchStorage?
    let configurationProfiles: [ComputerSearchProfile]?
    let printers: [ComputerSearchPrinter]?
    let localUserAccounts: [ComputerSearchLocalUser]?
    let certificates: [ComputerSearchCertificate]?
    let softwareUpdates: [ComputerSearchSoftwareUpdate]?
    let groupMemberships: [ComputerSearchGroupMembership]?
    let extensionAttributes: [ComputerSearchExtensionAttribute]?
    let contentCaching: ComputerSearchContentCaching?
    
    // Computed ID for Identifiable conformance
    var computerId: String {
        id ?? UUID().uuidString
    }
}

struct ComputerSearchGeneral: Codable, Hashable, Sendable {
    let name: String?
    let lastIpAddress: String?
    let lastReportedIp: String?
    let lastReportedIpV4: String?
    let lastReportedIpV6: String?
    let lastContactTime: String?
    let reportDate: String?
    let remoteManagement: ComputerSearchRemoteManagement?
    let supervised: Bool?
    let mdmCapable: ComputerSearchMDMCapable?
    let managementId: String?
    let platform: String?
    let jamfBinaryVersion: String?
    let barcode1: String?
    let barcode2: String?
    let assetTag: String?
    let site: ComputerSearchSite?
    let enrolledViaAutomatedDeviceEnrollment: Bool?
    let userApprovedMdm: Bool?
    let declarativeDeviceManagementEnabled: Bool?
    let extensionAttributes: [ComputerSearchExtensionAttribute]?
}

struct ComputerSearchRemoteManagement: Codable, Hashable, Sendable {
    let managed: Bool?
    let managementUsername: String?
}

struct ComputerSearchMDMCapable: Codable, Hashable, Sendable {
    let capable: Bool?
    let capableUsers: [String]?
}

struct ComputerSearchSite: Codable, Hashable, Sendable {
    let id: String?
    let name: String?
}

struct ComputerSearchHardware: Codable, Hashable, Sendable {
    let make: String?
    let model: String?
    let modelIdentifier: String?
    let serialNumber: String?
    let processorType: String?
    let processorArchitecture: String?
    let processorSpeedMhz: Int?
    let processorCount: Int?
    let coreCount: Int?
    let totalRamMegabytes: Int?
    let appleSilicon: Bool?
    let macAddress: String?
    let altMacAddress: String?
    let networkAdapterType: String?
    let bootRom: String?
    let batteryCapacityPercent: Int?
    let batteryHealth: String?
}

struct ComputerSearchOS: Codable, Hashable, Sendable {
    let name: String?
    let version: String?
    let build: String?
    let supplementalBuildVersion: String?
    let rapidSecurityResponse: String?
    let activeDirectoryStatus: String?
    let fileVault2Status: String?
}

struct ComputerSearchUserLocation: Codable, Hashable, Sendable {
    let username: String?
    let realname: String?
    let email: String?
    let position: String?
    let phone: String?
    let department: String?
    let departmentId: String?
    let building: String?
    let buildingId: String?
    let room: String?
}

struct ComputerSearchDiskEncryption: Codable, Hashable, Sendable {
    let fileVault2Enabled: Bool?
    let individualRecoveryKeyValidityStatus: String?
    let institutionalRecoveryKeyPresent: Bool?
    let bootPartitionEncryptionDetails: ComputerSearchBootPartition?
}

struct ComputerSearchBootPartition: Codable, Hashable, Sendable {
    let partitionName: String?
    let partitionFileVault2State: String?
    let partitionFileVault2Percent: Int?
}

struct ComputerSearchSecurity: Codable, Hashable, Sendable {
    let sipStatus: String?
    let gatekeeperStatus: String?
    let xprotectVersion: String?
    let autoLoginDisabled: Bool?
    let firewallEnabled: Bool?
    let activationLockEnabled: Bool?
    let secureBootLevel: String?
    let bootstrapTokenEscrowedStatus: String?
    let recoveryLockEnabled: Bool?
}

struct ComputerSearchExtensionAttribute: Codable, Hashable, Sendable {
    let definitionId: String?
    let name: String?
    let description: String?
    let values: [String]?
    let dataType: String?
}

// MARK: - Applications

struct ComputerSearchApplication: Codable, Hashable, Sendable {
    let name: String?
    let path: String?
    let version: String?
    let macAppStore: Bool?
    let sizeMegabytes: Int?
    let bundleId: String?
    let updateAvailable: Bool?
    let externalVersionId: String?
}

// MARK: - Storage

struct ComputerSearchStorage: Codable, Hashable, Sendable {
    let bootDriveAvailableSpaceMegabytes: Int?
    let disks: [ComputerSearchDisk]?
}

struct ComputerSearchDisk: Codable, Hashable, Sendable {
    let id: String?
    let device: String?
    let model: String?
    let sizeMegabytes: Int?
    let smartStatus: String?
    let type: String?
    let partitions: [ComputerSearchPartition]?
}

struct ComputerSearchPartition: Codable, Hashable, Sendable {
    let name: String?
    let sizeMegabytes: Int?
    let availableMegabytes: Int?
    let partitionType: String?
    let percentUsed: Int?
    let fileVault2State: String?
}

// MARK: - Configuration Profiles

struct ComputerSearchProfile: Codable, Hashable, Sendable {
    let id: String?
    let username: String?
    let lastInstalled: String?
    let removable: Bool?
    let displayName: String?
    let profileIdentifier: String?
}

// MARK: - Printers

struct ComputerSearchPrinter: Codable, Hashable, Sendable {
    let name: String?
    let type: String?
    let uri: String?
    let location: String?
}

// MARK: - Local User Accounts

struct ComputerSearchLocalUser: Codable, Hashable, Sendable {
    let uid: String?
    let username: String?
    let fullName: String?
    let admin: Bool?
    let homeDirectory: String?
    let homeDirectorySizeMb: Int?
    let fileVault2Enabled: Bool?
    let userAccountType: String?
}

// MARK: - Certificates

struct ComputerSearchCertificate: Codable, Hashable, Sendable {
    let commonName: String?
    let identity: Bool?
    let expirationDate: String?
    let username: String?
    let lifecycleStatus: String?
    let certificateStatus: String?
    let subjectName: String?
    let serialNumber: String?
    let sha1Fingerprint: String?
    let issuedDate: String?
}

// MARK: - Software Updates

struct ComputerSearchSoftwareUpdate: Codable, Hashable, Sendable {
    let name: String?
    let version: String?
    let packageName: String?
}

// MARK: - Group Memberships

struct ComputerSearchGroupMembership: Codable, Hashable, Sendable {
    let groupId: String?
    let groupName: String?
    let smartGroup: Bool?
}

// MARK: - Content Caching

struct ComputerSearchContentCaching: Codable, Hashable, Sendable {
    let computerContentCachingInformationId: String?
    let activated: Bool?
    let active: Bool?
    let cacheBytesFree: Int?
    let cacheBytesUsed: Int?
    let cacheStatus: String?
}

// MARK: - Preview Helpers

#if DEBUG
extension ComputerSearchResult {
    static var sampleMacStudio: ComputerSearchResult {
        ComputerSearchResult(
            id: "958",
            udid: "B5B94226-E80F-5CD4-9A7C-B8BE6067741D",
            general: ComputerSearchGeneral(
                name: "Mac Studio",
                lastIpAddress: "167.73.110.88",
                lastReportedIp: "10.0.20.201",
                lastReportedIpV4: "10.0.20.201",
                lastReportedIpV6: nil,
                lastContactTime: "2026-01-19T23:55:32.937Z",
                reportDate: "2026-01-19T23:57:00.659Z",
                remoteManagement: ComputerSearchRemoteManagement(managed: true, managementUsername: nil),
                supervised: true,
                mdmCapable: ComputerSearchMDMCapable(capable: true, capableUsers: ["user"]),
                managementId: "bc156e0b-5b6e-47f1-b943-b5bda0f0b1dc",
                platform: "Mac",
                jamfBinaryVersion: "11.23.2",
                barcode1: nil,
                barcode2: nil,
                assetTag: nil,
                site: ComputerSearchSite(id: "2", name: "Enterprise"),
                enrolledViaAutomatedDeviceEnrollment: false,
                userApprovedMdm: true,
                declarativeDeviceManagementEnabled: true,
                extensionAttributes: nil
            ),
            hardware: ComputerSearchHardware(
                make: "Apple",
                model: "Mac Studio",
                modelIdentifier: "Mac13,2",
                serialNumber: "LYFGQ7J7JQ",
                processorType: "Apple M1 Ultra",
                processorArchitecture: "arm64",
                processorSpeedMhz: 0,
                processorCount: 1,
                coreCount: 20,
                totalRamMegabytes: 131072,
                appleSilicon: true,
                macAddress: "9C:76:0E:7D:F8:18",
                altMacAddress: "9C:76:0E:7B:F2:59",
                networkAdapterType: "Ethernet",
                bootRom: "13822.61.10",
                batteryCapacityPercent: nil,
                batteryHealth: nil
            ),
            operatingSystem: ComputerSearchOS(
                name: "macOS",
                version: "15.2.0",
                build: "24C101",
                supplementalBuildVersion: nil,
                rapidSecurityResponse: nil,
                activeDirectoryStatus: nil,
                fileVault2Status: "BOOT_ENCRYPTED"
            ),
            userAndLocation: ComputerSearchUserLocation(
                username: "jsmith",
                realname: "John Smith",
                email: "jsmith@example.com",
                position: "Engineer",
                phone: "+1 (555) 123-4567",
                department: "IT",
                departmentId: nil,
                building: "HQ",
                buildingId: nil,
                room: nil
            ),
            diskEncryption: ComputerSearchDiskEncryption(
                fileVault2Enabled: true,
                individualRecoveryKeyValidityStatus: "VALID",
                institutionalRecoveryKeyPresent: false,
                bootPartitionEncryptionDetails: ComputerSearchBootPartition(
                    partitionName: "Macintosh HD",
                    partitionFileVault2State: "ENCRYPTED",
                    partitionFileVault2Percent: 100
                )
            ),
            security: ComputerSearchSecurity(
                sipStatus: "ENABLED",
                gatekeeperStatus: "APP_STORE_AND_IDENTIFIED_DEVELOPERS",
                xprotectVersion: "5325",
                autoLoginDisabled: true,
                firewallEnabled: true,
                activationLockEnabled: false,
                secureBootLevel: "FULL_SECURITY",
                bootstrapTokenEscrowedStatus: "ESCROWED",
                recoveryLockEnabled: false
            ),
            applications: nil,
            storage: nil,
            configurationProfiles: nil,
            printers: nil,
            localUserAccounts: nil,
            certificates: nil,
            softwareUpdates: nil,
            groupMemberships: nil,
            extensionAttributes: nil,
            contentCaching: nil
        )
    }
    
    static var sampleMacBook: ComputerSearchResult {
        ComputerSearchResult(
            id: "1024",
            udid: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
            general: ComputerSearchGeneral(
                name: "MacBook-Pro-JDoe",
                lastIpAddress: "10.0.20.105",
                lastReportedIp: "10.0.20.105",
                lastReportedIpV4: "10.0.20.105",
                lastReportedIpV6: nil,
                lastContactTime: "2026-01-20T10:30:00.000Z",
                reportDate: nil,
                remoteManagement: ComputerSearchRemoteManagement(managed: true, managementUsername: nil),
                supervised: false,
                mdmCapable: ComputerSearchMDMCapable(capable: true, capableUsers: nil),
                managementId: "abc123-def456",
                platform: "Mac",
                jamfBinaryVersion: nil,
                barcode1: nil,
                barcode2: nil,
                assetTag: nil,
                site: nil,
                enrolledViaAutomatedDeviceEnrollment: nil,
                userApprovedMdm: nil,
                declarativeDeviceManagementEnabled: nil,
                extensionAttributes: nil
            ),
            hardware: ComputerSearchHardware(
                make: "Apple",
                model: "MacBook Pro (16-inch, 2023)",
                modelIdentifier: "Mac15,7",
                serialNumber: "C02XL1234567",
                processorType: "Apple M3 Pro",
                processorArchitecture: "arm64",
                processorSpeedMhz: nil,
                processorCount: nil,
                coreCount: nil,
                totalRamMegabytes: 36864,
                appleSilicon: true,
                macAddress: nil,
                altMacAddress: nil,
                networkAdapterType: nil,
                bootRom: nil,
                batteryCapacityPercent: 95,
                batteryHealth: "NORMAL"
            ),
            operatingSystem: ComputerSearchOS(
                name: "macOS",
                version: "14.3.1",
                build: "23D60",
                supplementalBuildVersion: nil,
                rapidSecurityResponse: nil,
                activeDirectoryStatus: nil,
                fileVault2Status: nil
            ),
            userAndLocation: ComputerSearchUserLocation(
                username: "jdoe",
                realname: "Jane Doe",
                email: "jdoe@example.com",
                position: "Designer",
                phone: nil,
                department: "Creative",
                departmentId: nil,
                building: "West Campus",
                buildingId: nil,
                room: nil
            ),
            diskEncryption: nil,
            security: nil,
            applications: nil,
            storage: nil,
            configurationProfiles: nil,
            printers: nil,
            localUserAccounts: nil,
            certificates: nil,
            softwareUpdates: nil,
            groupMemberships: nil,
            extensionAttributes: nil,
            contentCaching: nil
        )
    }
}
#endif
