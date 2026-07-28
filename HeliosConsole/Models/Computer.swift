//
//  Computer.swift
//  test
//
//  Created by heath on 1/20/26.
//


//
//  Computer.swift
//  Overkast
//
//  Created for Jamf Pro API integration
//  Model for computers-inventory-detail endpoint
//

import Foundation

// MARK: - Computer (Top-Level Model)

/// Represents a Mac computer from the Jamf Pro computers-inventory-detail API
struct Computer: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let udid: String
    let general: ComputerGeneral?
    let diskEncryption: DiskEncryption?
    let localUserAccounts: [LocalUserAccount]?
    let purchasing: Purchasing?
    let printers: [Printer]?
    let storage: Storage?
    let applications: [Application]?
    let userAndLocation: UserAndLocation?
    let configurationProfiles: [ConfigurationProfile]?
    let services: [Service]?
    let hardware: Hardware?
    let certificates: [Certificate]?
    let attachments: [Attachment]?
    let packageReceipts: PackageReceipts?
    let security: Security?
    let operatingSystem: OperatingSystem?
    let licensedSoftware: [LicensedSoftware]?
    let softwareUpdates: [SoftwareUpdate]?
    let groupMemberships: [GroupMembership]?
    let extensionAttributes: [ExtensionAttribute]?
    let contentCaching: ContentCaching?
    let ibeacons: [IBeacon]?
    
    // MARK: - Hashable
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Computer, rhs: Computer) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - General

struct ComputerGeneral: Codable, Hashable, Sendable {
    let name: String?
    let lastIpAddress: String?
    let lastReportedIpV4: String?
    let lastReportedIpV6: String?
    let jamfBinaryVersion: String?
    let platform: String?
    let barcode1: String?
    let barcode2: String?
    let assetTag: String?
    let remoteManagement: RemoteManagement?
    let supervised: Bool?
    let mdmCapable: MDMCapable?
    let reportDate: String?
    let lastContactTime: String?
    let lastCloudBackupDate: String?
    let lastEnrolledDate: String?
    let mdmProfileExpiration: String?
    let initialEntryDate: String?
    let distributionPoint: String?
    let site: Site?
    let itunesStoreAccountActive: Bool?
    let enrolledViaAutomatedDeviceEnrollment: Bool?
    let userApprovedMdm: Bool?
    let enrollmentMethod: EnrollmentMethod?
    let declarativeDeviceManagementEnabled: Bool?
    let managementId: String?
    let lastLoggedInUsernameSelfService: String?
    let lastLoggedInUsernameSelfServiceTimestamp: String?
    let lastLoggedInUsernameBinary: String?
    let lastLoggedInUsernameBinaryTimestamp: String?
    let extensionAttributes: [ExtensionAttribute]?
    let lastReportedIp: String?
}

struct RemoteManagement: Codable, Hashable, Sendable {
    let managed: Bool?
    let managementUsername: String?
}

struct MDMCapable: Codable, Hashable, Sendable {
    let capable: Bool?
    let capableUsers: [String]?
    let userManagementInfo: [UserManagementInfo]?
}

struct UserManagementInfo: Codable, Hashable, Sendable {
    let capableUser: String?
    let managementId: String?
}

struct Site: Codable, Hashable, Sendable {
    let id: String?
    let name: String?
}

struct EnrollmentMethod: Codable, Hashable, Sendable {
    let id: String?
    let objectName: String?
    let objectType: String?
}

// MARK: - Disk Encryption

struct DiskEncryption: Codable, Hashable, Sendable {
    let individualRecoveryKeyValidityStatus: String?
    let institutionalRecoveryKeyPresent: Bool?
    let diskEncryptionConfigurationName: String?
    let fileVault2Enabled: Bool?
    let fileVault2EligibilityMessage: String?
    let fileVault2EnabledUserNames: [String]?
    let bootPartitionEncryptionDetails: BootPartitionEncryptionDetails?
}

struct BootPartitionEncryptionDetails: Codable, Hashable, Sendable {
    let partitionName: String?
    let partitionFileVault2State: String?
    let partitionFileVault2Percent: Int?
}

// MARK: - Local User Accounts

struct LocalUserAccount: Codable, Hashable, Sendable, Identifiable {
    var id: String { uid ?? UUID().uuidString }
    
    let uid: String?
    let userGuid: String?
    let username: String?
    let fullName: String?
    let admin: Bool?
    let userAccountType: String?
    let homeDirectory: String?
    let homeDirectorySizeMb: Int?
    let fileVault2Enabled: Bool?
    let passwordMinLength: Int?
    let passwordMaxAge: Int?
    let passwordMinComplexCharacters: Int?
    let passwordRequireAlphanumeric: Bool?
    let passwordHistoryDepth: Int?
    let computerAzureActiveDirectoryId: String?
    let userAzureActiveDirectoryId: String?
    let azureActiveDirectoryId: String?
}

extension LocalUserAccount {
    /// Home directories macOS assigns to accounts that never log in interactively.
    private static let systemHomeDirectories: Set<String> = ["/var/empty", "/dev/null", "/var/root"]

    /// True for macOS service/system accounts (root, daemon, `_`-prefixed service users, Guest).
    ///
    /// macOS reserves UIDs below 500 for the system; human accounts start at 501. Jamf reports
    /// the UID as a string, and accounts with negative UIDs (`nobody` = -2) come back either
    /// signed or as their unsigned 32-bit form.
    var isSystemAccount: Bool {
        if let username, username.hasPrefix("_") { return true }

        if let raw = uid?.trimmingCharacters(in: .whitespaces), let numeric = Int(raw) {
            if numeric < 500 { return true }
            if numeric > Int(Int32.max) { return true }  // -1 / -2 wrapped to unsigned
        }

        if let home = homeDirectory, Self.systemHomeDirectories.contains(home) { return true }

        return false
    }

    /// The account's primary type. Every account is exactly one of these, so the
    /// Local Accounts tags form a complete, non-overlapping set: selecting all of
    /// them shows every account, selecting none shows nothing.
    ///
    /// System classification wins over admin — `root` is admin-flagged but is a
    /// system account, and surfacing it under the Admin tag would defeat the
    /// point of being able to hide service accounts.
    enum AccountType {
        case system
        case admin
        case standard
    }

    /// Jamf leaves `admin` nil on some records, so anything not positively
    /// flagged as admin counts as standard.
    var accountType: AccountType {
        if isSystemAccount { return .system }
        return admin == true ? .admin : .standard
    }
}

// MARK: - Purchasing

struct Purchasing: Codable, Hashable, Sendable {
    let purchased: Bool?
    let leased: Bool?
    let poNumber: String?
    let lifeExpectancy: Int?
    let purchasePrice: String?
    let purchasingAccount: String?
    let purchasingContact: String?
    let appleCareId: String?
    let vendor: String?
    let leaseDate: String?
    let poDate: String?
    let warrantyDate: String?
    let extensionAttributes: [ExtensionAttribute]?
}

// MARK: - Printers

struct Printer: Codable, Hashable, Sendable, Identifiable {
    var id: String { name ?? UUID().uuidString }
    
    let name: String?
    let type: String?
    let uri: String?
    let location: String?
}

// MARK: - Storage

struct Storage: Codable, Hashable, Sendable {
    let bootDriveAvailableSpaceMegabytes: Int?
    let disks: [Disk]?
}

struct Disk: Codable, Hashable, Sendable, Identifiable {
    let id: String?
    let device: String?
    let model: String?
    let revision: String?
    let serialNumber: String?
    let sizeMegabytes: Int?
    let smartStatus: String?
    let type: String?
    let partitions: [Partition]?
}

struct Partition: Codable, Hashable, Sendable, Identifiable {
    var id: String { name ?? UUID().uuidString }
    
    let name: String?
    let sizeMegabytes: Int?
    let availableMegabytes: Int?
    let partitionType: String?
    let percentUsed: Int?
    let fileVault2State: String?
    let fileVault2ProgressPercent: Int?
    let lvmManaged: Bool?
}

// MARK: - Applications

struct Application: Codable, Hashable, Sendable, Identifiable {
    var id: String { "\(bundleId ?? "")-\(path ?? "")" }
    
    let name: String?
    let path: String?
    let version: String?
    let cfBundleShortVersionString: String?
    let cfBundleVersion: String?
    let macAppStore: Bool?
    let sizeMegabytes: Int?
    let bundleId: String?
    let updateAvailable: Bool?
    let externalVersionId: String?
}

// MARK: - User and Location

struct UserAndLocation: Codable, Hashable, Sendable {
    let username: String?
    let realname: String?
    let email: String?
    let position: String?
    let phone: String?
    let departmentId: String?
    let buildingId: String?
    let room: String?
    let extensionAttributes: [ExtensionAttribute]?
}

// MARK: - Configuration Profiles

struct ConfigurationProfile: Codable, Hashable, Sendable, Identifiable {
    var id: String? { profileIdentifier }
    
    let profileId: String?
    let username: String?
    let lastInstalled: String?
    let removable: Bool?
    let displayName: String?
    let profileIdentifier: String?
    
    private enum CodingKeys: String, CodingKey {
        case profileId = "id"
        case username
        case lastInstalled
        case removable
        case displayName
        case profileIdentifier
    }
}

// MARK: - Services

struct Service: Codable, Hashable, Sendable, Identifiable {
    var id: String { name ?? UUID().uuidString }
    
    let name: String?
}

// MARK: - Hardware

struct Hardware: Codable, Hashable, Sendable {
    let make: String?
    let model: String?
    let modelIdentifier: String?
    let serialNumber: String?
    let processorSpeedMhz: Int?
    let processorCount: Int?
    let coreCount: Int?
    let processorType: String?
    let processorArchitecture: String?
    let busSpeedMhz: Int?
    let cacheSizeKilobytes: Int?
    let networkAdapterType: String?
    let macAddress: String?
    let altNetworkAdapterType: String?
    let altMacAddress: String?
    let totalRamMegabytes: Int?
    let openRamSlots: Int?
    let batteryCapacityPercent: Int?
    let batteryHealth: String?
    let smcVersion: String?
    let nicSpeed: String?
    let opticalDrive: String?
    let bootRom: String?
    let bleCapable: Bool?
    let supportsIosAppInstalls: Bool?
    let appleSilicon: Bool?
    let provisioningUdid: String?
    let extensionAttributes: [ExtensionAttribute]?
}

// MARK: - Certificates

struct Certificate: Codable, Hashable, Sendable, Identifiable {
    var id: String { sha1Fingerprint ?? UUID().uuidString }
    
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

// MARK: - Attachments

struct Attachment: Codable, Hashable, Sendable, Identifiable {
    let id: String?
    let name: String?
    let fileType: String?
    let sizeBytes: Int?
}

// MARK: - Package Receipts

struct PackageReceipts: Codable, Hashable, Sendable {
    let installedByJamfPro: [String]?
    let installedByInstallerSwu: [String]?
    let cached: [String]?
}

// MARK: - Security

struct Security: Codable, Hashable, Sendable {
    let sipStatus: String?
    let gatekeeperStatus: String?
    let xprotectVersion: String?
    let autoLoginDisabled: Bool?
    let remoteDesktopEnabled: Bool?
    let activationLockEnabled: Bool?
    let secureBootLevel: String?
    let externalBootLevel: String?
    let bootstrapTokenAllowed: Bool?
    let bootstrapTokenEscrowedStatus: String?
    let recoveryLockEnabled: Bool?
    let firewallEnabled: Bool?
    let lastAttestationAttempt: String?
    let lastSuccessfulAttestation: String?
    let attestationStatus: String?
}

// MARK: - Operating System

struct OperatingSystem: Codable, Hashable, Sendable {
    let name: String?
    let version: String?
    let build: String?
    let supplementalBuildVersion: String?
    let rapidSecurityResponse: String?
    let activeDirectoryStatus: String?
    let fileVault2Status: String?
    let softwareUpdateDeviceId: String?
    let extensionAttributes: [ExtensionAttribute]?
}

// MARK: - Licensed Software

struct LicensedSoftware: Codable, Hashable, Sendable, Identifiable {
    let id: String?
    let name: String?
}

// MARK: - Software Updates

struct SoftwareUpdate: Codable, Hashable, Sendable, Identifiable {
    var id: String { packageName ?? UUID().uuidString }
    
    let name: String?
    let packageName: String?
    let version: String?
}

// MARK: - Group Memberships

struct GroupMembership: Codable, Hashable, Sendable, Identifiable {
    var id: String { groupId ?? UUID().uuidString }
    
    let groupId: String?
    let groupName: String?
    let groupDescription: String?
    let smartGroup: Bool?
}

// MARK: - Extension Attributes

struct ExtensionAttribute: Codable, Hashable, Sendable, Identifiable {
    var id: String { "\(definitionId ?? 0)" }
    
    let definitionId: Int?
    let name: String?
    let description: String?
    let values: [String]?
    let dataType: String?
    let options: [String]?
    let inputType: String?
    let enabled: Bool?
    let multiValue: Bool?
    
    enum CodingKeys: String, CodingKey {
        case definitionId
        case name
        case description
        case values
        case dataType
        case options
        case inputType
        case enabled
        case multiValue
    }
}

/// How the profile identifies a single Extension Attribute. `id` matches the
/// stable `definitionId`; `name` is the deprecated form kept for one release
/// (an admin renaming the EA in Jamf silently breaks a name match).
enum VPNIPExtensionAttributeRef: Codable, Equatable, Sendable {
    case id(Int)
    case name(String)

    /// Whether this reference identifies the given attribute.
    func matches(_ attribute: ExtensionAttribute) -> Bool {
        switch self {
        case .id(let id): return attribute.definitionId == id
        case .name(let name): return attribute.name == name
        }
    }
}

// MARK: - Content Caching

struct ContentCaching: Codable, Hashable, Sendable {
    let computerContentCachingInformationId: String?
    let parents: [ContentCachingParent]?
    let alerts: [ContentCachingAlert]?
    let activated: Bool?
    let active: Bool?
    let actualCacheBytesUsed: Int?
    let cacheDetails: [ContentCacheDetail]?
    let cacheBytesFree: Int?
    let cacheBytesLimit: Int?
    let cacheStatus: String?
    let cacheBytesUsed: Int?
    let dataMigrationCompleted: Bool?
    let dataMigrationProgressPercentage: Int?
    let dataMigrationError: DataMigrationError?
    let maxCachePressureLast1HourPercentage: Int?
    let personalCacheBytesFree: Int?
    let personalCacheBytesLimit: Int?
    let personalCacheBytesUsed: Int?
    let port: Int?
    let publicAddress: String?
    let registrationError: String?
    let registrationResponseCode: Int?
    let registrationStarted: String?
    let registrationStatus: String?
    let restrictedMedia: Bool?
    let serverGuid: String?
    let startupStatus: String?
    let tetheratorStatus: String?
    let totalBytesAreSince: String?
    let totalBytesDropped: Int?
    let totalBytesImported: Int?
    let totalBytesReturnedToChildren: Int?
    let totalBytesReturnedToClients: Int?
    let totalBytesReturnedToPeers: Int?
    let totalBytesStoredFromOrigin: Int?
    let totalBytesStoredFromParents: Int?
    let totalBytesStoredFromPeers: Int?
}

struct ContentCachingParent: Codable, Hashable, Sendable, Identifiable {
    var id: String { guid ?? UUID().uuidString }
    
    let guid: String?
    let healthy: Bool?
    let address: String?
    let port: Int?
    let details: ContentCachingParentDetails?
}

struct ContentCachingParentDetails: Codable, Hashable, Sendable {
    let acPower: Bool?
    let cacheSizeBytes: Int?
    let capabilities: ContentCachingCapabilities?
    let portable: Bool?
    let localNetwork: [ContentCachingLocalNetwork]?
}

struct ContentCachingCapabilities: Codable, Hashable, Sendable {
    let imports: Bool?
    let namespaces: Bool?
    let personalContent: Bool?
    let queryParameters: Bool?
    let sharedContent: Bool?
    let prioritization: Bool?
}

struct ContentCachingLocalNetwork: Codable, Hashable, Sendable, Identifiable {
    var id: String { guid ?? UUID().uuidString }
    
    let speed: Int?
    let wired: Bool?
    let guid: String?
}

struct ContentCachingAlert: Codable, Hashable, Sendable, Identifiable {
    var id: String { "\(cacheBytesLimit ?? 0)" }
    
    let cacheBytesLimit: Int?
    let className: String?
    let pathPreventingAccess: String?
    let postDate: String?
    let reservedVolumeBytes: Int?
    let resource: String?
}

struct ContentCacheDetail: Codable, Hashable, Sendable, Identifiable {
    var id: String { categoryName ?? UUID().uuidString }
    
    let categoryName: String?
    let diskSpaceBytesUsed: Int?
}

struct DataMigrationError: Codable, Hashable, Sendable {
    let code: Int?
    let domain: String?
    let userInfo: [DataMigrationUserInfo]?
}

struct DataMigrationUserInfo: Codable, Hashable, Sendable {
    let key: String?
    let value: String?
}

// MARK: - iBeacons

struct IBeacon: Codable, Hashable, Sendable, Identifiable {
    let id: String?
    let name: String?
}

// MARK: - Computer Extensions

extension Computer {
    /// Display name for the computer (falls back to serial number or ID)
    var displayName: String {
        general?.name ?? hardware?.serialNumber ?? id
    }
    
    /// The computer's serial number
    var serialNumber: String? {
        hardware?.serialNumber
    }
    
    /// The computer's model name
    var modelName: String? {
        hardware?.model
    }
    
    /// The computer's OS version
    var osVersion: String? {
        operatingSystem?.version
    }
    
    /// The assigned username
    var assignedUser: String? {
        userAndLocation?.username
    }
    
    /// The assigned user's real name
    var assignedUserRealName: String? {
        userAndLocation?.realname
    }
    
    /// Whether the computer is managed
    var isManaged: Bool {
        general?.remoteManagement?.managed ?? false
    }
    
    /// Whether the computer is supervised
    var isSupervised: Bool {
        general?.supervised ?? false
    }
    
    /// Whether FileVault is enabled
    var isFileVaultEnabled: Bool {
        diskEncryption?.fileVault2Enabled ?? false
    }
    
    /// Last check-in time
    var lastCheckIn: Date? {
        guard let dateString = general?.lastContactTime else { return nil }
        return ISO8601DateFormatter().date(from: dateString)
    }
    
    /// Last check-in time as formatted string
    var lastCheckInFormatted: String? {
        guard let date = lastCheckIn else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    /// Total RAM in GB
    var totalRAMGB: Double? {
        guard let ramMB = hardware?.totalRamMegabytes else { return nil }
        return Double(ramMB) / 1024.0
    }
    
    /// Available storage in GB
    var availableStorageGB: Double? {
        guard let storageMB = storage?.bootDriveAvailableSpaceMegabytes else { return nil }
        return Double(storageMB) / 1024.0
    }
    
    /// Whether running Apple Silicon
    var isAppleSilicon: Bool {
        hardware?.appleSilicon ?? false
    }
    
    /// Processor description
    var processorDescription: String? {
        hardware?.processorType
    }
    
    /// Primary MAC address
    var macAddress: String? {
        hardware?.macAddress
    }
    
    /// Last reported IP address
    var ipAddress: String? {
        general?.lastReportedIp ?? general?.lastReportedIpV4
    }
}

// MARK: - Convenience Initializer for Preview/Testing

extension Computer {
    /// Create a Computer from a ComputerSearchResult (full conversion with all sections)
    static func fromSearchResult(_ result: ComputerSearchResult) -> Computer {
        Computer(
            id: result.id ?? UUID().uuidString,
            udid: result.udid ?? "",
            general: ComputerGeneral(
                name: result.general?.name,
                lastIpAddress: result.general?.lastIpAddress,
                lastReportedIpV4: result.general?.lastReportedIpV4,
                lastReportedIpV6: result.general?.lastReportedIpV6,
                jamfBinaryVersion: result.general?.jamfBinaryVersion,
                platform: result.general?.platform ?? "Mac",
                barcode1: result.general?.barcode1,
                barcode2: result.general?.barcode2,
                assetTag: result.general?.assetTag,
                remoteManagement: RemoteManagement(
                    managed: result.general?.remoteManagement?.managed,
                    managementUsername: result.general?.remoteManagement?.managementUsername
                ),
                supervised: result.general?.supervised,
                mdmCapable: MDMCapable(
                    capable: result.general?.mdmCapable?.capable,
                    capableUsers: result.general?.mdmCapable?.capableUsers,
                    userManagementInfo: nil
                ),
                reportDate: result.general?.reportDate,
                lastContactTime: result.general?.lastContactTime,
                lastCloudBackupDate: nil,
                lastEnrolledDate: nil,
                mdmProfileExpiration: nil,
                initialEntryDate: nil,
                distributionPoint: nil,
                site: result.general?.site != nil ? Site(id: result.general?.site?.id, name: result.general?.site?.name) : nil,
                itunesStoreAccountActive: nil,
                enrolledViaAutomatedDeviceEnrollment: result.general?.enrolledViaAutomatedDeviceEnrollment,
                userApprovedMdm: result.general?.userApprovedMdm,
                enrollmentMethod: nil,
                declarativeDeviceManagementEnabled: result.general?.declarativeDeviceManagementEnabled,
                managementId: result.general?.managementId,
                lastLoggedInUsernameSelfService: nil,
                lastLoggedInUsernameSelfServiceTimestamp: nil,
                lastLoggedInUsernameBinary: nil,
                lastLoggedInUsernameBinaryTimestamp: nil,
                extensionAttributes: nil,
                lastReportedIp: result.general?.lastReportedIp ?? result.general?.lastIpAddress
            ),
            diskEncryption: result.diskEncryption != nil ? DiskEncryption(
                individualRecoveryKeyValidityStatus: result.diskEncryption?.individualRecoveryKeyValidityStatus,
                institutionalRecoveryKeyPresent: result.diskEncryption?.institutionalRecoveryKeyPresent,
                diskEncryptionConfigurationName: nil,
                fileVault2Enabled: result.diskEncryption?.fileVault2Enabled,
                fileVault2EligibilityMessage: nil,
                fileVault2EnabledUserNames: nil,
                bootPartitionEncryptionDetails: result.diskEncryption?.bootPartitionEncryptionDetails != nil ? BootPartitionEncryptionDetails(
                    partitionName: result.diskEncryption?.bootPartitionEncryptionDetails?.partitionName,
                    partitionFileVault2State: result.diskEncryption?.bootPartitionEncryptionDetails?.partitionFileVault2State,
                    partitionFileVault2Percent: result.diskEncryption?.bootPartitionEncryptionDetails?.partitionFileVault2Percent
                ) : nil
            ) : nil,
            localUserAccounts: result.localUserAccounts?.map { user in
                LocalUserAccount(
                    uid: user.uid,
                    userGuid: nil,
                    username: user.username,
                    fullName: user.fullName,
                    admin: user.admin,
                    userAccountType: user.userAccountType,
                    homeDirectory: user.homeDirectory,
                    homeDirectorySizeMb: user.homeDirectorySizeMb,
                    fileVault2Enabled: user.fileVault2Enabled,
                    passwordMinLength: nil,
                    passwordMaxAge: nil,
                    passwordMinComplexCharacters: nil,
                    passwordRequireAlphanumeric: nil,
                    passwordHistoryDepth: nil,
                    computerAzureActiveDirectoryId: nil,
                    userAzureActiveDirectoryId: nil,
                    azureActiveDirectoryId: nil
                )
            },
            purchasing: nil,
            printers: result.printers?.map { printer in
                Printer(
                    name: printer.name,
                    type: printer.type,
                    uri: printer.uri,
                    location: printer.location
                )
            },
            storage: result.storage != nil ? Storage(
                bootDriveAvailableSpaceMegabytes: result.storage?.bootDriveAvailableSpaceMegabytes,
                disks: result.storage?.disks?.map { disk in
                    Disk(
                        id: disk.id,
                        device: disk.device,
                        model: disk.model,
                        revision: nil,
                        serialNumber: nil,
                        sizeMegabytes: disk.sizeMegabytes,
                        smartStatus: disk.smartStatus,
                        type: disk.type,
                        partitions: disk.partitions?.map { partition in
                            Partition(
                                name: partition.name,
                                sizeMegabytes: partition.sizeMegabytes,
                                availableMegabytes: partition.availableMegabytes,
                                partitionType: partition.partitionType,
                                percentUsed: partition.percentUsed,
                                fileVault2State: partition.fileVault2State,
                                fileVault2ProgressPercent: nil,
                                lvmManaged: nil
                            )
                        }
                    )
                }
            ) : nil,
            applications: result.applications?.map { app in
                Application(
                    name: app.name,
                    path: app.path,
                    version: app.version,
                    cfBundleShortVersionString: nil,
                    cfBundleVersion: nil,
                    macAppStore: app.macAppStore,
                    sizeMegabytes: app.sizeMegabytes,
                    bundleId: app.bundleId,
                    updateAvailable: app.updateAvailable,
                    externalVersionId: app.externalVersionId
                )
            },
            userAndLocation: UserAndLocation(
                username: result.userAndLocation?.username,
                realname: result.userAndLocation?.realname,
                email: result.userAndLocation?.email,
                position: result.userAndLocation?.position,
                phone: result.userAndLocation?.phone,
                departmentId: result.userAndLocation?.departmentId,
                buildingId: result.userAndLocation?.buildingId,
                room: result.userAndLocation?.room,
                extensionAttributes: nil
            ),
            configurationProfiles: result.configurationProfiles?.map { profile in
                ConfigurationProfile(
                    profileId: profile.id,
                    username: profile.username,
                    lastInstalled: profile.lastInstalled,
                    removable: profile.removable,
                    displayName: profile.displayName,
                    profileIdentifier: profile.profileIdentifier
                )
            },
            services: nil,
            hardware: Hardware(
                make: result.hardware?.make,
                model: result.hardware?.model,
                modelIdentifier: result.hardware?.modelIdentifier,
                serialNumber: result.hardware?.serialNumber,
                processorSpeedMhz: result.hardware?.processorSpeedMhz,
                processorCount: result.hardware?.processorCount,
                coreCount: result.hardware?.coreCount,
                processorType: result.hardware?.processorType,
                processorArchitecture: result.hardware?.processorArchitecture,
                busSpeedMhz: nil,
                cacheSizeKilobytes: nil,
                networkAdapterType: result.hardware?.networkAdapterType,
                macAddress: result.hardware?.macAddress,
                altNetworkAdapterType: nil,
                altMacAddress: result.hardware?.altMacAddress,
                totalRamMegabytes: result.hardware?.totalRamMegabytes,
                openRamSlots: nil,
                batteryCapacityPercent: result.hardware?.batteryCapacityPercent,
                batteryHealth: result.hardware?.batteryHealth,
                smcVersion: nil,
                nicSpeed: nil,
                opticalDrive: nil,
                bootRom: result.hardware?.bootRom,
                bleCapable: nil,
                supportsIosAppInstalls: nil,
                appleSilicon: result.hardware?.appleSilicon,
                provisioningUdid: nil,
                extensionAttributes: nil
            ),
            certificates: result.certificates?.map { cert in
                Certificate(
                    commonName: cert.commonName,
                    identity: cert.identity,
                    expirationDate: cert.expirationDate,
                    username: cert.username,
                    lifecycleStatus: cert.lifecycleStatus,
                    certificateStatus: cert.certificateStatus,
                    subjectName: cert.subjectName,
                    serialNumber: cert.serialNumber,
                    sha1Fingerprint: cert.sha1Fingerprint,
                    issuedDate: cert.issuedDate
                )
            },
            attachments: nil,
            packageReceipts: nil,
            security: result.security != nil ? Security(
                sipStatus: result.security?.sipStatus,
                gatekeeperStatus: result.security?.gatekeeperStatus,
                xprotectVersion: result.security?.xprotectVersion,
                autoLoginDisabled: result.security?.autoLoginDisabled,
                remoteDesktopEnabled: nil,
                activationLockEnabled: result.security?.activationLockEnabled,
                secureBootLevel: result.security?.secureBootLevel,
                externalBootLevel: nil,
                bootstrapTokenAllowed: nil,
                bootstrapTokenEscrowedStatus: result.security?.bootstrapTokenEscrowedStatus,
                recoveryLockEnabled: result.security?.recoveryLockEnabled,
                firewallEnabled: result.security?.firewallEnabled,
                lastAttestationAttempt: nil,
                lastSuccessfulAttestation: nil,
                attestationStatus: nil
            ) : nil,
            operatingSystem: OperatingSystem(
                name: result.operatingSystem?.name,
                version: result.operatingSystem?.version,
                build: result.operatingSystem?.build,
                supplementalBuildVersion: result.operatingSystem?.supplementalBuildVersion,
                rapidSecurityResponse: result.operatingSystem?.rapidSecurityResponse,
                activeDirectoryStatus: result.operatingSystem?.activeDirectoryStatus,
                fileVault2Status: result.operatingSystem?.fileVault2Status,
                softwareUpdateDeviceId: nil,
                extensionAttributes: nil
            ),
            licensedSoftware: nil,
            softwareUpdates: result.softwareUpdates?.map { update in
                SoftwareUpdate(
                    name: update.name,
                    packageName: update.packageName,
                    version: update.version
                )
            },
            groupMemberships: result.groupMemberships?.map { group in
                GroupMembership(
                    groupId: group.groupId,
                    groupName: group.groupName,
                    groupDescription: nil,
                    smartGroup: group.smartGroup
                )
            },
            extensionAttributes: result.extensionAttributes?.map { ea in
                ExtensionAttribute(
                    definitionId: ea.definitionId.flatMap { Int($0) },
                    name: ea.name,
                    description: ea.description,
                    values: ea.values,
                    dataType: ea.dataType,
                    options: nil,
                    inputType: nil,
                    enabled: nil,
                    multiValue: nil
                )
            },
            contentCaching: nil,
            ibeacons: nil
        )
    }
    
    /// Create a lightweight Computer from a DeviceListItem for navigation
    /// DeviceView will fetch full details when it loads
    static func fromDeviceListItem(_ item: DeviceListItem) -> Computer {
        Computer(
            id: item.originalId,  // Use originalId for API calls
            udid: "",
            general: ComputerGeneral(
                name: item.name,
                lastIpAddress: nil,
                lastReportedIpV4: nil,
                lastReportedIpV6: nil,
                jamfBinaryVersion: nil,
                platform: "Mac",
                barcode1: nil,
                barcode2: nil,
                assetTag: nil,
                remoteManagement: RemoteManagement(managed: item.isManaged, managementUsername: nil),
                supervised: item.isSupervised,
                mdmCapable: nil,
                reportDate: nil,
                lastContactTime: item.lastCheckIn?.ISO8601Format(),
                lastCloudBackupDate: nil,
                lastEnrolledDate: nil,
                mdmProfileExpiration: nil,
                initialEntryDate: nil,
                distributionPoint: nil,
                site: nil,
                itunesStoreAccountActive: nil,
                enrolledViaAutomatedDeviceEnrollment: nil,
                userApprovedMdm: nil,
                enrollmentMethod: nil,
                declarativeDeviceManagementEnabled: nil,
                managementId: nil,
                lastLoggedInUsernameSelfService: nil,
                lastLoggedInUsernameSelfServiceTimestamp: nil,
                lastLoggedInUsernameBinary: nil,
                lastLoggedInUsernameBinaryTimestamp: nil,
                extensionAttributes: nil,
                lastReportedIp: nil
            ),
            diskEncryption: nil,
            localUserAccounts: nil,
            purchasing: nil,
            printers: nil,
            storage: nil,
            applications: nil,
            userAndLocation: item.assignedUser != nil ? UserAndLocation(
                username: nil,
                realname: item.assignedUser,
                email: nil,
                position: nil,
                phone: nil,
                departmentId: nil,
                buildingId: nil,
                room: nil,
                extensionAttributes: nil
            ) : nil,
            configurationProfiles: nil,
            services: nil,
            hardware: Hardware(
                make: "Apple",
                model: item.model,
                modelIdentifier: item.modelIdentifier,
                serialNumber: item.serialNumber,
                processorSpeedMhz: nil,
                processorCount: nil,
                coreCount: nil,
                processorType: nil,
                processorArchitecture: nil,
                busSpeedMhz: nil,
                cacheSizeKilobytes: nil,
                networkAdapterType: nil,
                macAddress: nil,
                altNetworkAdapterType: nil,
                altMacAddress: nil,
                totalRamMegabytes: nil,
                openRamSlots: nil,
                batteryCapacityPercent: nil,
                batteryHealth: nil,
                smcVersion: nil,
                nicSpeed: nil,
                opticalDrive: nil,
                bootRom: nil,
                bleCapable: nil,
                supportsIosAppInstalls: nil,
                appleSilicon: nil,
                provisioningUdid: nil,
                extensionAttributes: nil
            ),
            certificates: nil,
            attachments: nil,
            packageReceipts: nil,
            security: nil,
            operatingSystem: OperatingSystem(
                name: "macOS",
                version: item.osVersion,
                build: nil,
                supplementalBuildVersion: nil,
                rapidSecurityResponse: nil,
                activeDirectoryStatus: nil,
                fileVault2Status: nil,
                softwareUpdateDeviceId: nil,
                extensionAttributes: nil
            ),
            licensedSoftware: nil,
            softwareUpdates: nil,
            groupMemberships: nil,
            extensionAttributes: nil,
            contentCaching: nil,
            ibeacons: nil
        )
    }
    
    /// Create a Computer from a ComputerInventoryItem (from cache)
    static func fromInventoryItem(_ item: ComputerInventoryItem) -> Computer {
        // Break down complex nested initializations
        let remoteManagement = RemoteManagement(
            managed: item.general?.remoteManagement?.managed ?? false,
            managementUsername: item.general?.remoteManagement?.managementUsername
        )
        
        let site: Site? = item.general?.site.map { Site(id: $0.id, name: $0.name) }
        
        let general = ComputerGeneral(
            name: item.name,
            lastIpAddress: item.general?.lastIpAddress,
            lastReportedIpV4: nil,
            lastReportedIpV6: nil,
            jamfBinaryVersion: item.general?.jamfBinaryVersion,
            platform: item.general?.platform ?? "Mac",
            barcode1: item.general?.barcode1,
            barcode2: item.general?.barcode2,
            assetTag: item.general?.assetTag,
            remoteManagement: remoteManagement,
            supervised: item.general?.supervised ?? false,
            mdmCapable: nil,
            reportDate: item.general?.reportDate,
            lastContactTime: item.general?.lastContactTime,
            lastCloudBackupDate: nil,
            lastEnrolledDate: item.general?.lastEnrolledDate,
            mdmProfileExpiration: item.general?.mdmProfileExpiration,
            initialEntryDate: item.general?.initialEntryDate,
            distributionPoint: nil,
            site: site,
            itunesStoreAccountActive: nil,
            enrolledViaAutomatedDeviceEnrollment: item.general?.enrolledViaAutomatedDeviceEnrollment,
            userApprovedMdm: item.general?.userApprovedMdm,
            enrollmentMethod: nil,
            declarativeDeviceManagementEnabled: item.general?.declarativeDeviceManagementEnabled,
            managementId: item.general?.managementId,
            lastLoggedInUsernameSelfService: nil,
            lastLoggedInUsernameSelfServiceTimestamp: nil,
            lastLoggedInUsernameBinary: nil,
            lastLoggedInUsernameBinaryTimestamp: nil,
            extensionAttributes: nil,
            lastReportedIp: nil
        )
        
        let diskEncryption: DiskEncryption? = item.diskEncryption.map { de in
            DiskEncryption(
                individualRecoveryKeyValidityStatus: de.individualRecoveryKeyValidityStatus,
                institutionalRecoveryKeyPresent: de.institutionalRecoveryKeyPresent,
                diskEncryptionConfigurationName: de.diskEncryptionConfigurationName,
                fileVault2Enabled: nil,
                fileVault2EligibilityMessage: de.fileVault2EligibilityMessage,
                fileVault2EnabledUserNames: de.fileVault2EnabledUserNames,
                bootPartitionEncryptionDetails: nil
            )
        }
        
        let userAndLocation: UserAndLocation?
        if let ul = item.userAndLocation {
            userAndLocation = UserAndLocation(
                username: ul.username,
                realname: ul.realname,
                email: ul.email,
                position: ul.position,
                phone: nil,
                departmentId: nil,
                buildingId: nil,
                room: nil,
                extensionAttributes: nil
            )
        } else {
            userAndLocation = nil
        }
        
        let hardware: Hardware?
        if let hw = item.hardware {
            hardware = Hardware(
                make: hw.make,
                model: hw.model,
                modelIdentifier: hw.modelIdentifier,
                serialNumber: hw.serialNumber,
                processorSpeedMhz: nil,
                processorCount: nil,
                coreCount: nil,
                processorType: hw.processorType,
                processorArchitecture: nil,
                busSpeedMhz: nil,
                cacheSizeKilobytes: nil,
                networkAdapterType: nil,
                macAddress: nil,
                altNetworkAdapterType: nil,
                altMacAddress: nil,
                totalRamMegabytes: hw.totalRamMegabytes,
                openRamSlots: nil,
                batteryCapacityPercent: nil,
                batteryHealth: nil,
                smcVersion: nil,
                nicSpeed: nil,
                opticalDrive: nil,
                bootRom: nil,
                bleCapable: nil,
                supportsIosAppInstalls: nil,
                appleSilicon: hw.appleSilicon,
                provisioningUdid: nil,
                extensionAttributes: nil
            )
        } else {
            hardware = nil
        }
        
        let security: Security?
        if let sec = item.security {
            security = Security(
                sipStatus: sec.sipStatus,
                gatekeeperStatus: sec.gatekeeperStatus,
                xprotectVersion: sec.xprotectVersion,
                autoLoginDisabled: sec.autoLoginDisabled,
                remoteDesktopEnabled: sec.remoteDesktopEnabled,
                activationLockEnabled: sec.activationLockEnabled,
                secureBootLevel: sec.secureBootLevel,
                externalBootLevel: sec.externalBootLevel,
                bootstrapTokenAllowed: sec.bootstrapTokenAllowed,
                bootstrapTokenEscrowedStatus: sec.bootstrapTokenEscrowedStatus,
                recoveryLockEnabled: sec.recoveryLockEnabled,
                firewallEnabled: sec.firewallEnabled,
                lastAttestationAttempt: nil,
                lastSuccessfulAttestation: nil,
                attestationStatus: nil
            )
        } else {
            security = nil
        }
        
        let operatingSystem: OperatingSystem?
        if let os = item.operatingSystem {
            operatingSystem = OperatingSystem(
                name: os.name,
                version: os.version,
                build: os.build,
                supplementalBuildVersion: nil,
                rapidSecurityResponse: nil,
                activeDirectoryStatus: nil,
                fileVault2Status: nil,
                softwareUpdateDeviceId: nil,
                extensionAttributes: nil
            )
        } else {
            operatingSystem = nil
        }
        
        return Computer(
            id: item.id,
            udid: item.udid ?? "",
            general: general,
            diskEncryption: diskEncryption,
            localUserAccounts: nil,
            purchasing: nil,
            printers: nil,
            storage: nil,
            applications: nil,
            userAndLocation: userAndLocation,
            configurationProfiles: nil,
            services: nil,
            hardware: hardware,
            certificates: nil,
            attachments: nil,
            packageReceipts: nil,
            security: security,
            operatingSystem: operatingSystem,
            licensedSoftware: nil,
            softwareUpdates: nil,
            groupMemberships: nil,
            extensionAttributes: nil,
            contentCaching: nil,
            ibeacons: nil
        )
    }
    
    static var preview: Computer {
        Computer(
            id: "958",
            udid: "B5B94226-E80F-5CD4-9A7C-B8BE6067741D",
            general: ComputerGeneral(
                name: "Mac Studio",
                lastIpAddress: "167.73.110.88",
                lastReportedIpV4: "10.0.20.201",
                lastReportedIpV6: "fe80::b8b0:11ff:fefd:58aa",
                jamfBinaryVersion: "11.23.2",
                platform: "Mac",
                barcode1: nil,
                barcode2: nil,
                assetTag: nil,
                remoteManagement: RemoteManagement(managed: true, managementUsername: nil),
                supervised: true,
                mdmCapable: MDMCapable(capable: true, capableUsers: ["user"], userManagementInfo: nil),
                reportDate: "2026-01-19T23:57:00.659Z",
                lastContactTime: "2026-01-19T23:55:32.937Z",
                lastCloudBackupDate: nil,
                lastEnrolledDate: nil,
                mdmProfileExpiration: "2027-12-16T15:50:57Z",
                initialEntryDate: "2025-12-16",
                distributionPoint: nil,
                site: Site(id: "2", name: "Enterprise"),
                itunesStoreAccountActive: true,
                enrolledViaAutomatedDeviceEnrollment: false,
                userApprovedMdm: true,
                enrollmentMethod: EnrollmentMethod(id: "2103", objectName: nil, objectType: "User-initiated"),
                declarativeDeviceManagementEnabled: true,
                managementId: "bc156e0b-5b6e-47f1-b943-b5bda0f0b1dc",
                lastLoggedInUsernameSelfService: nil,
                lastLoggedInUsernameSelfServiceTimestamp: nil,
                lastLoggedInUsernameBinary: "user",
                lastLoggedInUsernameBinaryTimestamp: "2026-01-14T14:05:54.522Z",
                extensionAttributes: nil,
                lastReportedIp: "10.0.20.201"
            ),
            diskEncryption: DiskEncryption(
                individualRecoveryKeyValidityStatus: "VALID",
                institutionalRecoveryKeyPresent: false,
                diskEncryptionConfigurationName: nil,
                fileVault2Enabled: true,
                fileVault2EligibilityMessage: "Eligible",
                fileVault2EnabledUserNames: ["user"],
                bootPartitionEncryptionDetails: BootPartitionEncryptionDetails(
                    partitionName: "Macintosh HD",
                    partitionFileVault2State: "ENCRYPTED",
                    partitionFileVault2Percent: 100
                )
            ),
            localUserAccounts: nil,
            purchasing: Purchasing(
                purchased: true,
                leased: false,
                poNumber: nil,
                lifeExpectancy: 0,
                purchasePrice: nil,
                purchasingAccount: nil,
                purchasingContact: nil,
                appleCareId: nil,
                vendor: nil,
                leaseDate: nil,
                poDate: nil,
                warrantyDate: nil,
                extensionAttributes: nil
            ),
            printers: nil,
            storage: Storage(
                bootDriveAvailableSpaceMegabytes: 131052,
                disks: [
                    Disk(
                        id: "3060729",
                        device: "disk0",
                        model: "APPLE SSD AP1024R",
                        revision: "555",
                        serialNumber: "0ba018114108a612",
                        sizeMegabytes: 1000555,
                        smartStatus: "Verified",
                        type: "NO",
                        partitions: nil
                    )
                ]
            ),
            applications: nil,
            userAndLocation: UserAndLocation(
                username: "user",
                realname: "Test User",
                email: "user@example.com",
                position: "Engineer",
                phone: "+1 (555) 123-4567",
                departmentId: nil,
                buildingId: nil,
                room: nil,
                extensionAttributes: nil
            ),
            configurationProfiles: nil,
            services: nil,
            hardware: Hardware(
                make: "Apple",
                model: "Mac Studio",
                modelIdentifier: "Mac13,2",
                serialNumber: "LYFGQ7J7JQ",
                processorSpeedMhz: 0,
                processorCount: 1,
                coreCount: 20,
                processorType: "Apple M1 Ultra",
                processorArchitecture: "arm64",
                busSpeedMhz: 0,
                cacheSizeKilobytes: 0,
                networkAdapterType: "Ethernet",
                macAddress: "9C:76:0E:7D:F8:18",
                altNetworkAdapterType: "IEEE80211",
                altMacAddress: "9C:76:0E:7B:F2:59",
                totalRamMegabytes: 131072,
                openRamSlots: 0,
                batteryCapacityPercent: -1,
                batteryHealth: "UNSUPPORTED",
                smcVersion: nil,
                nicSpeed: "1 Gbps",
                opticalDrive: nil,
                bootRom: "13822.61.10",
                bleCapable: false,
                supportsIosAppInstalls: true,
                appleSilicon: true,
                provisioningUdid: "00006002-000249020103401E",
                extensionAttributes: nil
            ),
            certificates: nil,
            attachments: nil,
            packageReceipts: nil,
            security: Security(
                sipStatus: "ENABLED",
                gatekeeperStatus: "APP_STORE_AND_IDENTIFIED_DEVELOPERS",
                xprotectVersion: "5325",
                autoLoginDisabled: true,
                remoteDesktopEnabled: true,
                activationLockEnabled: false,
                secureBootLevel: "FULL_SECURITY",
                externalBootLevel: "ALLOW_BOOTING_FROM_EXTERNAL_MEDIA",
                bootstrapTokenAllowed: true,
                bootstrapTokenEscrowedStatus: "ESCROWED",
                recoveryLockEnabled: false,
                firewallEnabled: true,
                lastAttestationAttempt: "2026-01-19T20:23:27.541Z",
                lastSuccessfulAttestation: "2026-01-19T20:23:28.497Z",
                attestationStatus: "SUCCESS"
            ),
            operatingSystem: OperatingSystem(
                name: "macOS",
                version: "15.2.0",
                build: "24C101",
                supplementalBuildVersion: "24C101",
                rapidSecurityResponse: nil,
                activeDirectoryStatus: "example.org",
                fileVault2Status: "BOOT_ENCRYPTED",
                softwareUpdateDeviceId: "J375dAP",
                extensionAttributes: nil
            ),
            licensedSoftware: nil,
            softwareUpdates: nil,
            groupMemberships: nil,
            extensionAttributes: nil,
            contentCaching: nil,
            ibeacons: nil
        )
    }
}
