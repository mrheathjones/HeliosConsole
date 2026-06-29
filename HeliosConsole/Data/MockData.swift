//
//  MockData.swift
//  Helios
//
//  Mock data for testing - parsed from jamfComputerInventoryOutput.txt
//

import Foundation

// MARK: - Mock Data Provider

enum MockData {
    
    /// Returns a test Computer parsed from embedded JSON
    static var testComputer: Computer {
        let jsonData = testComputerJSON.data(using: .utf8)!
        do {
            let computer = try JSONDecoder().decode(Computer.self, from: jsonData)
            return computer
        } catch {
            fatalError("Failed to decode test computer: \(error)")
        }
    }
    
    // MARK: - Embedded JSON
    
    static let testComputerJSON = """
{
  "id": "958",
  "udid": "B5B94226-E80F-5CD4-9A7C-B8BE6067741D",
  "general": {
    "name": "C02XX0000XXX",
    "lastIpAddress": "167.73.110.88",
    "lastReportedIpV4": "10.0.20.201",
    "lastReportedIpV6": "fe80::b8b0:11ff:fefd:58aa",
    "jamfBinaryVersion": "11.23.2-t1767621885710",
    "platform": "Mac",
    "barcode1": null,
    "barcode2": null,
    "assetTag": "C02XX0000XXX",
    "remoteManagement": {
      "managed": true,
      "managementUsername": null
    },
    "supervised": true,
    "mdmCapable": {
      "capable": true,
      "capableUsers": ["testuser"],
      "userManagementInfo": [
        {
          "capableUser": "testuser",
          "managementId": "7afd746a-0634-441e-9c93-08f7ac22aaa2"
        }
      ]
    },
    "reportDate": "2026-01-19T23:57:00.659Z",
    "lastContactTime": "2026-01-19T23:55:32.937Z",
    "lastCloudBackupDate": null,
    "lastEnrolledDate": "2025-12-16T15:50:57Z",
    "mdmProfileExpiration": "2027-12-16T15:50:57Z",
    "initialEntryDate": "2025-12-16",
    "distributionPoint": null,
    "site": {
      "id": "2",
      "name": "Enterprise"
    },
    "itunesStoreAccountActive": true,
    "enrolledViaAutomatedDeviceEnrollment": false,
    "userApprovedMdm": true,
    "enrollmentMethod": {
      "id": "2103",
      "objectName": null,
      "objectType": "User-initiated - no invitation"
    },
    "declarativeDeviceManagementEnabled": true,
    "managementId": "bc156e0b-5b6e-47f1-b943-b5bda0f0b1dc",
    "lastLoggedInUsernameSelfService": null,
    "lastLoggedInUsernameSelfServiceTimestamp": null,
    "lastLoggedInUsernameBinary": "testuser",
    "lastLoggedInUsernameBinaryTimestamp": "2026-01-14T14:05:54.522Z",
    "extensionAttributes": [
      {
        "definitionId": 92,
        "name": "jamf-patch-mozilla-firefox",
        "description": "Extension Attribute provided by JAMF Nation patch service",
        "values": [],
        "dataType": "STRING",
        "options": [],
        "inputType": "SCRIPT",
        "enabled": true,
        "multiValue": false
      },
      {
        "definitionId": 97,
        "name": "jamf-patch-microsoft-onedrive",
        "description": "Extension Attribute provided by JAMF Nation patch service",
        "values": ["25238.1204.0001"],
        "dataType": "STRING",
        "options": [],
        "inputType": "SCRIPT",
        "enabled": true,
        "multiValue": false
      }
    ],
    "lastReportedIp": "10.0.20.201"
  },
  "diskEncryption": {
    "individualRecoveryKeyValidityStatus": "VALID",
    "institutionalRecoveryKeyPresent": false,
    "diskEncryptionConfigurationName": null,
    "fileVault2Enabled": true,
    "fileVault2EligibilityMessage": "Eligible",
    "fileVault2EnabledUserNames": ["testuser", "macadmin", "macsupport"],
    "bootPartitionEncryptionDetails": {
      "partitionName": "Macintosh HD (Boot Partition)",
      "partitionFileVault2State": "ENCRYPTED",
      "partitionFileVault2Percent": 100
    }
  },
  "localUserAccounts": [
    {
      "uid": "501",
      "userGuid": "FFFEEECA-6DB1-4234-8BC1-84D4DD53461B",
      "username": "testuser",
      "fullName": "Test User",
      "admin": true,
      "userAccountType": "LOCAL",
      "homeDirectory": "/Users/testuser",
      "homeDirectorySizeMb": 45632,
      "fileVault2Enabled": true,
      "passwordMinLength": 4,
      "passwordMaxAge": null,
      "passwordMinComplexCharacters": null,
      "passwordRequireAlphanumeric": false,
      "passwordHistoryDepth": null,
      "computerAzureActiveDirectoryId": null,
      "userAzureActiveDirectoryId": null,
      "azureActiveDirectoryId": "ABC123-DEF456"
    },
    {
      "uid": "502",
      "userGuid": "FFFEEECB-6DB1-4234-8BC1-84D4DD53461C",
      "username": "macsupport",
      "fullName": "Mac Support",
      "admin": true,
      "userAccountType": "LOCAL",
      "homeDirectory": "/Users/macsupport",
      "homeDirectorySizeMb": 1024,
      "fileVault2Enabled": true,
      "passwordMinLength": 4,
      "passwordMaxAge": null,
      "passwordMinComplexCharacters": null,
      "passwordRequireAlphanumeric": false,
      "passwordHistoryDepth": null,
      "computerAzureActiveDirectoryId": null,
      "userAzureActiveDirectoryId": null,
      "azureActiveDirectoryId": null
    },
    {
      "uid": "503",
      "userGuid": "FFFEEECB-6DB1-4234-8BC1-84D4DD53461D",
      "username": "guest",
      "fullName": "Guest User",
      "admin": false,
      "userAccountType": "GUEST",
      "homeDirectory": "/Users/Guest",
      "homeDirectorySizeMb": 0,
      "fileVault2Enabled": false,
      "passwordMinLength": 0,
      "passwordMaxAge": null,
      "passwordMinComplexCharacters": null,
      "passwordRequireAlphanumeric": false,
      "passwordHistoryDepth": null,
      "computerAzureActiveDirectoryId": null,
      "userAzureActiveDirectoryId": null,
      "azureActiveDirectoryId": null
    }
  ],
  "purchasing": {
    "purchased": true,
    "leased": false,
    "poNumber": "PO-2025-12345",
    "lifeExpectancy": 48,
    "purchasePrice": "$3,999.00",
    "purchasingAccount": "IT Department",
    "purchasingContact": "procurement@company.com",
    "appleCareId": "AC-123456789",
    "vendor": "Apple Inc.",
    "leaseDate": null,
    "poDate": "2025-11-15",
    "warrantyDate": "2028-11-15",
    "extensionAttributes": []
  },
  "printers": [
    {
      "name": "HP LaserJet Pro MFP",
      "type": "Brother HL-L2350DW series",
      "uri": "lpd://10.0.20.50/queue",
      "location": "2nd Floor Copy Room"
    },
    {
      "name": "Xerox WorkCentre",
      "type": "Xerox WorkCentre 6515DN",
      "uri": "ipp://10.0.20.51/ipp/print",
      "location": "Main Office"
    }
  ],
  "storage": {
    "bootDriveAvailableSpaceMegabytes": 131052,
    "disks": [
      {
        "id": "3060729",
        "device": "disk0",
        "model": "APPLE SSD AP1024R",
        "revision": "955.120.5",
        "serialNumber": "0ba018114108a612",
        "sizeMegabytes": 1000555,
        "smartStatus": "Verified",
        "type": "SSD",
        "partitions": [
          {
            "name": "Macintosh HD",
            "sizeMegabytes": 1000555,
            "availableMegabytes": 131052,
            "partitionType": "BOOT",
            "percentUsed": 87,
            "fileVault2State": "ENCRYPTED",
            "fileVault2ProgressPercent": 100,
            "lvmManaged": true
          }
        ]
      }
    ]
  },
  "applications": [
    {
      "name": "Xcode",
      "path": "/Applications/Xcode.app",
      "version": "16.2",
      "cfBundleShortVersionString": "16.2",
      "cfBundleVersion": "23507",
      "macAppStore": true,
      "sizeMegabytes": 12847,
      "bundleId": "com.apple.dt.Xcode",
      "updateAvailable": false,
      "externalVersionId": null
    },
    {
      "name": "Microsoft Word",
      "path": "/Applications/Microsoft Word.app",
      "version": "16.93",
      "cfBundleShortVersionString": "16.93",
      "cfBundleVersion": "24121630",
      "macAppStore": false,
      "sizeMegabytes": 2156,
      "bundleId": "com.microsoft.Word",
      "updateAvailable": true,
      "externalVersionId": null
    },
    {
      "name": "Slack",
      "path": "/Applications/Slack.app",
      "version": "4.41.97",
      "cfBundleShortVersionString": "4.41.97",
      "cfBundleVersion": "1705678432",
      "macAppStore": false,
      "sizeMegabytes": 456,
      "bundleId": "com.tinyspeck.slackmacgap",
      "updateAvailable": false,
      "externalVersionId": null
    },
    {
      "name": "zoom.us",
      "path": "/Applications/zoom.us.app",
      "version": "6.3.5",
      "cfBundleShortVersionString": "6.3.5",
      "cfBundleVersion": "47470",
      "macAppStore": false,
      "sizeMegabytes": 234,
      "bundleId": "us.zoom.xos",
      "updateAvailable": false,
      "externalVersionId": null
    },
    {
      "name": "Safari",
      "path": "/Applications/Safari.app",
      "version": "18.2",
      "cfBundleShortVersionString": "18.2",
      "cfBundleVersion": "20620.1.16.11.6",
      "macAppStore": false,
      "sizeMegabytes": 45,
      "bundleId": "com.apple.Safari",
      "updateAvailable": false,
      "externalVersionId": null
    },
    {
      "name": "1Password 7",
      "path": "/Applications/1Password 7.app",
      "version": "7.9.11",
      "cfBundleShortVersionString": "7.9.11",
      "cfBundleVersion": "70911002",
      "macAppStore": true,
      "sizeMegabytes": 156,
      "bundleId": "com.agilebits.onepassword7",
      "updateAvailable": true,
      "externalVersionId": null
    },
    {
      "name": "Visual Studio Code",
      "path": "/Applications/Visual Studio Code.app",
      "version": "1.96.4",
      "cfBundleShortVersionString": "1.96.4",
      "cfBundleVersion": "1.96.4",
      "macAppStore": false,
      "sizeMegabytes": 567,
      "bundleId": "com.microsoft.VSCode",
      "updateAvailable": false,
      "externalVersionId": null
    },
    {
      "name": "iTerm",
      "path": "/Applications/iTerm.app",
      "version": "3.5.10",
      "cfBundleShortVersionString": "3.5.10",
      "cfBundleVersion": "3.5.10",
      "macAppStore": false,
      "sizeMegabytes": 48,
      "bundleId": "com.googlecode.iterm2",
      "updateAvailable": false,
      "externalVersionId": null
    }
  ],
  "userAndLocation": {
    "username": "testuser",
    "realname": "Test User",
    "email": "testuser@example.org",
    "position": "Senior Systems Engineer",
    "phone": "+1 (616) 555-0123",
    "departmentId": "IT-MAC-001",
    "buildingId": "HQ-MAIN",
    "room": "3rd Floor - IT"
  },
  "configurationProfiles": [
    {
      "id": "1001",
      "username": "",
      "lastInstalled": "2026-01-15T10:30:00Z",
      "removable": false,
      "displayName": "FileVault 2 Enforcement",
      "profileIdentifier": "com.company.filevault"
    },
    {
      "id": "1002",
      "username": "",
      "lastInstalled": "2026-01-15T10:30:00Z",
      "removable": false,
      "displayName": "Wi-Fi Configuration",
      "profileIdentifier": "com.company.wifi"
    },
    {
      "id": "1003",
      "username": "",
      "lastInstalled": "2026-01-15T10:30:00Z",
      "removable": true,
      "displayName": "VPN Configuration",
      "profileIdentifier": "com.company.vpn"
    },
    {
      "id": "1004",
      "username": "",
      "lastInstalled": "2026-01-18T14:22:00Z",
      "removable": false,
      "displayName": "Security Baseline - Enterprise",
      "profileIdentifier": "com.company.security.baseline"
    },
    {
      "id": "1005",
      "username": "",
      "lastInstalled": "2026-01-10T09:00:00Z",
      "removable": false,
      "displayName": "Jamf Protect Settings",
      "profileIdentifier": "com.jamf.protect"
    }
  ],
  "services": [],
  "hardware": {
    "make": "Apple",
    "model": "Mac Studio",
    "modelIdentifier": "Mac13,2",
    "serialNumber": "LYFGQ7J7JQ",
    "processorSpeedMhz": 0,
    "processorCount": 1,
    "coreCount": 20,
    "processorType": "Apple M1 Ultra",
    "processorArchitecture": "arm64",
    "busSpeedMhz": 0,
    "cacheSizeKilobytes": 0,
    "networkAdapterType": "Ethernet",
    "macAddress": "9C:76:0E:7D:F8:18",
    "altNetworkAdapterType": "IEEE80211",
    "altMacAddress": "9C:76:0E:7B:F2:59",
    "totalRamMegabytes": 131072,
    "openRamSlots": 0,
    "batteryCapacityPercent": -1,
    "batteryHealth": "UNSUPPORTED",
    "smcVersion": null,
    "nicSpeed": "1 Gbps",
    "opticalDrive": null,
    "bootRom": "13822.61.10",
    "bleCapable": false,
    "supportsIosAppInstalls": true,
    "appleSilicon": true,
    "provisioningUdid": "00006002-000249020103401E",
    "extensionAttributes": []
  },
  "certificates": [
    {
      "commonName": "Apple Development: Test User",
      "identity": true,
      "expirationDate": "2027-01-15T00:00:00Z",
      "username": "testuser",
      "lifecycleStatus": "ACTIVE",
      "certificateStatus": "VALID",
      "subjectName": "Apple Development: Test User (ABC123)",
      "serialNumber": "ABC123456789",
      "sha1Fingerprint": "A1B2C3D4E5F6789012345678901234567890ABCD",
      "issuedDate": "2026-01-15T00:00:00Z"
    },
    {
      "commonName": "Apple Distribution: Company Inc",
      "identity": true,
      "expirationDate": "2027-06-01T00:00:00Z",
      "username": "",
      "lifecycleStatus": "ACTIVE",
      "certificateStatus": "VALID",
      "subjectName": "Apple Distribution: Company Inc (XYZ789)",
      "serialNumber": "XYZ789012345",
      "sha1Fingerprint": "B2C3D4E5F67890123456789012345678901BCDE",
      "issuedDate": "2026-06-01T00:00:00Z"
    }
  ],
  "attachments": [],
  "packageReceipts": {
    "installedByJamfPro": ["Slack-4.41.97.pkg", "zoom.us-6.3.5.pkg", "VSCode-1.96.4.pkg"],
    "installedByInstallerSwu": ["macOS Sequoia 15.2"],
    "cached": []
  },
  "security": {
    "sipStatus": "ENABLED",
    "gatekeeperStatus": "APP_STORE_AND_IDENTIFIED_DEVELOPERS",
    "xprotectVersion": "5325",
    "autoLoginDisabled": true,
    "remoteDesktopEnabled": true,
    "activationLockEnabled": false,
    "secureBootLevel": "FULL_SECURITY",
    "externalBootLevel": "ALLOW_BOOTING_FROM_EXTERNAL_MEDIA",
    "bootstrapTokenAllowed": true,
    "bootstrapTokenEscrowedStatus": "ESCROWED",
    "recoveryLockEnabled": false,
    "firewallEnabled": true,
    "lastAttestationAttempt": "2026-01-19T20:23:27.541Z",
    "lastSuccessfulAttestation": "2026-01-19T20:23:28.497Z",
    "attestationStatus": "SUCCESS"
  },
  "operatingSystem": {
    "name": "macOS",
    "version": "15.2.0",
    "build": "24C101",
    "supplementalBuildVersion": "24C101",
    "rapidSecurityResponse": null,
    "activeDirectoryStatus": "example.org",
    "fileVault2Status": "BOOT_ENCRYPTED",
    "softwareUpdateDeviceId": "J375dAP",
    "extensionAttributes": []
  },
  "licensedSoftware": [],
  "softwareUpdates": [
    {
      "name": "macOS Sequoia 15.2.1",
      "packageName": "macOS Sequoia 15.2.1-24C83",
      "version": "15.2.1"
    }
  ],
  "groupMemberships": [
    {
      "groupId": "101",
      "groupName": "All Managed Macs",
      "groupDescription": "All computers managed by Jamf Pro",
      "smartGroup": true
    },
    {
      "groupId": "102",
      "groupName": "Mac Studio Devices",
      "groupDescription": "All Mac Studio computers",
      "smartGroup": true
    },
    {
      "groupId": "103",
      "groupName": "IT Department",
      "groupDescription": "Computers assigned to IT staff",
      "smartGroup": false
    },
    {
      "groupId": "104",
      "groupName": "FileVault Enabled",
      "groupDescription": "Computers with FileVault encryption enabled",
      "smartGroup": true
    },
    {
      "groupId": "105",
      "groupName": "Apple Silicon Macs",
      "groupDescription": "All Apple Silicon based Macs",
      "smartGroup": true
    }
  ],
  "extensionAttributes": [
    {
      "definitionId": 1,
      "name": "EA_Jamf_Management_Status",
      "description": "Verifies if the endpoint is managed by this instance of Jamf Pro",
      "values": ["Managed"],
      "dataType": "STRING",
      "options": [],
      "inputType": "SCRIPT",
      "enabled": true,
      "multiValue": false
    },
    {
      "definitionId": 68,
      "name": "EA_Microsoft_EntraID_Registration_Status",
      "description": "Reports Microsoft Entra ID registration status",
      "values": ["Registered [User: testuser@example.org]"],
      "dataType": "STRING",
      "options": [],
      "inputType": "SCRIPT",
      "enabled": true,
      "multiValue": false
    },
    {
      "definitionId": 79,
      "name": "EA_Secure_Token_Status",
      "description": "Reports if the current user has a Secure Token or not",
      "values": ["Enabled"],
      "dataType": "STRING",
      "options": [],
      "inputType": "SCRIPT",
      "enabled": true,
      "multiValue": false
    },
    {
      "definitionId": 85,
      "name": "EA_FileVault_Disk_Encryption_Status",
      "description": "Reports on FileVault Disk Encryption Status",
      "values": ["On"],
      "dataType": "STRING",
      "options": [],
      "inputType": "SCRIPT",
      "enabled": true,
      "multiValue": false
    },
    {
      "definitionId": 93,
      "name": "EA_Local_Admins",
      "description": "This script gets a list of all local admins",
      "values": ["macsupport\\ntestuser"],
      "dataType": "STRING",
      "options": [],
      "inputType": "SCRIPT",
      "enabled": true,
      "multiValue": false
    },
    {
      "definitionId": 95,
      "name": "Jamf Connect - UserUPN",
      "description": "Displays the value of the UserUPN attribute for the Jamf Connect user",
      "values": ["testuser@example.org"],
      "dataType": "STRING",
      "options": [],
      "inputType": "SCRIPT",
      "enabled": true,
      "multiValue": false
    }
  ],
  "contentCaching": {
    "computerContentCachingInformationId": "934",
    "parents": [],
    "alerts": [],
    "activated": false,
    "active": false,
    "actualCacheBytesUsed": 0,
    "cacheDetails": [],
    "cacheBytesFree": 129047870464,
    "cacheBytesLimit": 0,
    "cacheStatus": "OK",
    "cacheBytesUsed": 0,
    "dataMigrationCompleted": false,
    "dataMigrationProgressPercentage": 0,
    "dataMigrationError": {
      "code": 0,
      "domain": null,
      "userInfo": []
    },
    "maxCachePressureLast1HourPercentage": 0,
    "personalCacheBytesFree": 129047870464,
    "personalCacheBytesLimit": 0,
    "personalCacheBytesUsed": 0,
    "port": 0,
    "publicAddress": null,
    "registrationError": "NOT_ACTIVATED",
    "registrationResponseCode": 403,
    "registrationStarted": null,
    "registrationStatus": "CONTENT_CACHING_FAILED",
    "restrictedMedia": false,
    "serverGuid": "EFDD0EA5-8CF2-49CB-9F6D-2F88325E58B5",
    "startupStatus": "FAILED",
    "tetheratorStatus": "CONTENT_CACHING_DISABLED",
    "totalBytesAreSince": "2026-01-19T20:14:37Z",
    "totalBytesDropped": 0,
    "totalBytesImported": 0,
    "totalBytesReturnedToChildren": 0,
    "totalBytesReturnedToClients": 0,
    "totalBytesReturnedToPeers": 0,
    "totalBytesStoredFromOrigin": 0,
    "totalBytesStoredFromParents": 0,
    "totalBytesStoredFromPeers": 0
  },
  "ibeacons": []
}
"""
}
