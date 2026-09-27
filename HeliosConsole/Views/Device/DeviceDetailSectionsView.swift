//
//  DeviceDetailSectionsView.swift
//  Helios
//
//  Read-only detail sections of the computer detail view (hardware,
//  storage, security, OS, user, disk encryption, purchasing, management).
//

import SwiftUI

struct DeviceDetailSectionsView: View {
    let section: DeviceSection
    let computer: Computer

    var body: some View {
        switch section {
        case .hardware:
            hardwareSection
        case .storage:
            storageSection
        case .security:
            securitySection
        case .operatingSystem:
            operatingSystemSection
        case .userAndLocation:
            userAndLocationSection
        case .diskEncryption:
            diskEncryptionSection
        case .purchasing:
            purchasingSection
        case .management:
            managementSection
        default:
            EmptyView()
        }
    }

    // MARK: - Hardware Section
    
    private var hardwareSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader("Hardware", icon: "cpu")
            
            DetailCard(title: "System Information", icon: "desktopcomputer") {
                DetailRow("Make", computer.hardware?.make)
                DetailRow("Model", computer.hardware?.model)
                DetailRow("Model Identifier", computer.hardware?.modelIdentifier)
                DetailRow("Serial Number", computer.hardware?.serialNumber)
                DetailRow("Provisioning UDID", computer.hardware?.provisioningUdid)
            }
            
            DetailCard(title: "Processor", icon: "cpu") {
                DetailRow("Processor Type", computer.hardware?.processorType)
                DetailRow("Architecture", computer.hardware?.processorArchitecture)
                DetailRow("Processor Count", computer.hardware?.processorCount.map { "\($0)" })
                DetailRow("Core Count", computer.hardware?.coreCount.map { "\($0)" })
                DetailRow("Speed", computer.hardware?.processorSpeedMhz.map { $0 > 0 ? "\($0) MHz" : "N/A" })
                DetailRow("Apple Silicon", computer.hardware?.appleSilicon == true ? "Yes" : "No")
            }
            
            DetailCard(title: "Memory", icon: "memorychip") {
                DetailRow("Total RAM", computer.hardware?.totalRamMegabytes.map { "\($0 / 1024) GB" })
                DetailRow("Open RAM Slots", computer.hardware?.openRamSlots.map { "\($0)" })
                DetailRow("Cache Size", computer.hardware?.cacheSizeKilobytes.map { $0 > 0 ? "\($0) KB" : "N/A" })
            }
            
            DetailCard(title: "Network", icon: "network") {
                DetailRow("Ethernet Adapter", computer.hardware?.networkAdapterType)
                DetailRow("Ethernet MAC", computer.hardware?.macAddress)
                DetailRow("Ethernet Speed", computer.hardware?.nicSpeed)
                DetailRow("Wi-Fi Adapter", computer.hardware?.altNetworkAdapterType)
                DetailRow("Wi-Fi MAC", computer.hardware?.altMacAddress)
            }
            
            DetailCard(title: "System", icon: "gearshape") {
                DetailRow("Boot ROM", computer.hardware?.bootRom)
                DetailRow("SMC Version", computer.hardware?.smcVersion)
                DetailRow("BLE Capable", computer.hardware?.bleCapable == true ? "Yes" : "No")
                DetailRow("Supports iOS Apps", computer.hardware?.supportsIosAppInstalls == true ? "Yes" : "No")
            }
            
            if computer.hardware?.batteryCapacityPercent ?? -1 >= 0 {
                DetailCard(title: "Battery", icon: "battery.100") {
                    DetailRow("Capacity", computer.hardware?.batteryCapacityPercent.map { "\($0)%" })
                    DetailRow("Health", computer.hardware?.batteryHealth)
                }
            }
        }
    }
    
    // MARK: - Storage Section
    
    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader("Storage", icon: "internaldrive")
            
            DetailCard(title: "Boot Drive", icon: "internaldrive.fill") {
                DetailRow("Available Space", computer.storage?.bootDriveAvailableSpaceMegabytes.map { DeviceFormatting.storage($0) })
            }
            
            if let disks = computer.storage?.disks {
                ForEach(disks, id: \.id) { disk in
                    DetailCard(title: disk.device ?? "Disk", icon: "cylinder") {
                        DetailRow("Model", disk.model)
                        DetailRow("Serial Number", disk.serialNumber)
                        DetailRow("Size", disk.sizeMegabytes.map { DeviceFormatting.storage($0) })
                        DetailRow("Type", disk.type)
                        DetailRow("SMART Status", disk.smartStatus)
                        DetailRow("Revision", disk.revision)
                    }
                    
                    if let partitions = disk.partitions {
                        ForEach(partitions, id: \.id) { partition in
                            DetailCard(title: partition.name ?? "Partition", icon: "square.split.bottomrightquarter") {
                                DetailRow("Size", partition.sizeMegabytes.map { DeviceFormatting.storage($0) })
                                DetailRow("Available", partition.availableMegabytes.map { DeviceFormatting.storage($0) })
                                DetailRow("Used", partition.percentUsed.map { "\($0)%" })
                                DetailRow("Type", partition.partitionType)
                                DetailRow("FileVault State", partition.fileVault2State)
                                DetailRow("LVM Managed", partition.lvmManaged == true ? "Yes" : "No")
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Security Section
    
    private var securitySection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader("Security", icon: "shield.checkered")
            
            DetailCard(title: "System Security", icon: "lock.shield") {
                DetailRow("SIP Status", computer.security?.sipStatus)
                DetailRow("Gatekeeper", DeviceFormatting.gatekeeperStatus(computer.security?.gatekeeperStatus))
                DetailRow("XProtect Version", computer.security?.xprotectVersion)
                DetailRow("Firewall", computer.security?.firewallEnabled == true ? "Enabled" : "Disabled")
                DetailRow("Auto Login", computer.security?.autoLoginDisabled == true ? "Disabled" : "Enabled")
                DetailRow("Remote Desktop", computer.security?.remoteDesktopEnabled == true ? "Enabled" : "Disabled")
            }
            
            DetailCard(title: "Boot Security", icon: "lock.rectangle") {
                DetailRow("Secure Boot Level", computer.security?.secureBootLevel)
                DetailRow("External Boot Level", computer.security?.externalBootLevel)
                DetailRow("Activation Lock", computer.security?.activationLockEnabled == true ? "Enabled" : "Disabled")
                DetailRow("Recovery Lock", computer.security?.recoveryLockEnabled == true ? "Enabled" : "Disabled")
            }
            
            DetailCard(title: "Bootstrap Token", icon: "key") {
                DetailRow("Allowed", computer.security?.bootstrapTokenAllowed == true ? "Yes" : "No")
                DetailRow("Escrow Status", computer.security?.bootstrapTokenEscrowedStatus)
            }
            
            DetailCard(title: "Attestation", icon: "checkmark.shield") {
                DetailRow("Status", computer.security?.attestationStatus)
                DetailRow("Last Attempt", DeviceFormatting.date(computer.security?.lastAttestationAttempt))
                DetailRow("Last Success", DeviceFormatting.date(computer.security?.lastSuccessfulAttestation))
            }
        }
    }
    
    // MARK: - Operating System Section
    
    private var operatingSystemSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader("Operating System", icon: "apple.logo")
            
            DetailCard(title: "macOS", icon: "apple.logo") {
                DetailRow("Name", computer.operatingSystem?.name)
                DetailRow("Version", computer.operatingSystem?.version)
                DetailRow("Build", computer.operatingSystem?.build)
                DetailRow("Supplemental Build", computer.operatingSystem?.supplementalBuildVersion)
                DetailRow("Rapid Security Response", computer.operatingSystem?.rapidSecurityResponse)
                DetailRow("Software Update Device ID", computer.operatingSystem?.softwareUpdateDeviceId)
            }
            
            DetailCard(title: "Directory Services", icon: "person.2") {
                DetailRow("Active Directory", computer.operatingSystem?.activeDirectoryStatus)
                DetailRow("FileVault 2 Status", computer.operatingSystem?.fileVault2Status)
            }
            
            if let updates = computer.softwareUpdates, !updates.isEmpty {
                DetailCard(title: "Available Updates", icon: "arrow.down.circle") {
                    ForEach(updates, id: \.id) { update in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(update.name ?? "Unknown Update")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                if let packageName = update.packageName {
                                    Text(packageName)
                                        .font(.system(size: 11))
                                        .foregroundColor(.gray)
                                }
                            }
                            Spacer()
                            Text(update.version ?? "")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }
    
    // MARK: - User and Location Section
    
    private var userAndLocationSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader("User & Location", icon: "person.fill")
            
            DetailCard(title: "Assigned User", icon: "person") {
                DetailRow("Username", computer.userAndLocation?.username)
                DetailRow("Full Name", computer.userAndLocation?.realname)
                DetailRow("Email", computer.userAndLocation?.email)
                DetailRow("Phone", computer.userAndLocation?.phone)
                DetailRow("Position", computer.userAndLocation?.position)
            }
            
            DetailCard(title: "Location", icon: "building.2") {
                DetailRow("Department ID", computer.userAndLocation?.departmentId)
                DetailRow("Building ID", computer.userAndLocation?.buildingId)
                DetailRow("Room", computer.userAndLocation?.room)
            }
            
            DetailCard(title: "Last Login", icon: "clock") {
                DetailRow("Self Service User", computer.general?.lastLoggedInUsernameSelfService)
                DetailRow("Self Service Time", DeviceFormatting.date(computer.general?.lastLoggedInUsernameSelfServiceTimestamp))
                DetailRow("Binary User", computer.general?.lastLoggedInUsernameBinary)
                DetailRow("Binary Time", DeviceFormatting.date(computer.general?.lastLoggedInUsernameBinaryTimestamp))
            }
        }
    }

    // MARK: - Disk Encryption Section
    
    private var diskEncryptionSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader("Disk Encryption", icon: "lock.doc")
            
            DetailCard(title: "FileVault 2", icon: "lock.shield") {
                DetailRow("Status", computer.diskEncryption?.fileVault2Enabled == true ? "Enabled" : "Disabled")
                DetailRow("Eligibility", computer.diskEncryption?.fileVault2EligibilityMessage)
                DetailRow("Recovery Key Status", computer.diskEncryption?.individualRecoveryKeyValidityStatus)
                DetailRow("Institutional Key", computer.diskEncryption?.institutionalRecoveryKeyPresent == true ? "Present" : "Not Present")
                DetailRow("Configuration", computer.diskEncryption?.diskEncryptionConfigurationName)
            }
            
            if let users = computer.diskEncryption?.fileVault2EnabledUserNames, !users.isEmpty {
                DetailCard(title: "FileVault Enabled Users", icon: "person.badge.key") {
                    ForEach(users, id: \.self) { user in
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundColor(.blue)
                            Text(user)
                                .font(.system(size: 13))
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            
            if let boot = computer.diskEncryption?.bootPartitionEncryptionDetails {
                DetailCard(title: "Boot Partition", icon: "internaldrive") {
                    DetailRow("Partition", boot.partitionName)
                    DetailRow("State", boot.partitionFileVault2State)
                    DetailRow("Encryption Progress", boot.partitionFileVault2Percent.map { "\($0)%" })
                }
            }
        }
    }

    // MARK: - Purchasing Section
    
    private var purchasingSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader("Purchasing", icon: "dollarsign.circle")
            
            DetailCard(title: "Purchase Information", icon: "cart") {
                DetailRow("Purchased", computer.purchasing?.purchased == true ? "Yes" : "No")
                DetailRow("Leased", computer.purchasing?.leased == true ? "Yes" : "No")
                DetailRow("PO Number", computer.purchasing?.poNumber)
                DetailRow("PO Date", computer.purchasing?.poDate)
                DetailRow("Purchase Price", computer.purchasing?.purchasePrice)
                DetailRow("Vendor", computer.purchasing?.vendor)
            }
            
            DetailCard(title: "Warranty & Support", icon: "shield") {
                DetailRow("AppleCare ID", computer.purchasing?.appleCareId)
                DetailRow("Warranty Date", computer.purchasing?.warrantyDate)
                DetailRow("Lease Date", computer.purchasing?.leaseDate)
                DetailRow("Life Expectancy", computer.purchasing?.lifeExpectancy.map { "\($0) months" })
            }
            
            DetailCard(title: "Contacts", icon: "person.2") {
                DetailRow("Purchasing Account", computer.purchasing?.purchasingAccount)
                DetailRow("Purchasing Contact", computer.purchasing?.purchasingContact)
            }
        }
    }

    // MARK: - Management Section
    
    private var managementSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader("Management", icon: "gearshape.2")
            
            DetailCard(title: "MDM Status", icon: "checkmark.circle") {
                DetailRow("Managed", computer.general?.remoteManagement?.managed == true ? "Yes" : "No")
                DetailRow("Supervised", computer.general?.supervised == true ? "Yes" : "No")
                DetailRow("MDM Capable", computer.general?.mdmCapable?.capable == true ? "Yes" : "No")
                DetailRow("User Approved MDM", computer.general?.userApprovedMdm == true ? "Yes" : "No")
                DetailRow("DDM Enabled", computer.general?.declarativeDeviceManagementEnabled == true ? "Yes" : "No")
            }
            
            DetailCard(title: "Enrollment", icon: "arrow.down.circle") {
                DetailRow("Method", computer.general?.enrollmentMethod?.objectType)
                DetailRow("ADE Enrolled", computer.general?.enrolledViaAutomatedDeviceEnrollment == true ? "Yes" : "No")
                DetailRow("Initial Entry", computer.general?.initialEntryDate)
                DetailRow("Last Enrolled", DeviceFormatting.date(computer.general?.lastEnrolledDate))
                DetailRow("MDM Profile Expiration", DeviceFormatting.date(computer.general?.mdmProfileExpiration))
            }
            
            DetailCard(title: "Check-in", icon: "clock") {
                DetailRow("Last Contact", DeviceFormatting.date(computer.general?.lastContactTime))
                DetailRow("Last Report", DeviceFormatting.date(computer.general?.reportDate))
                DetailRow("Last Cloud Backup", DeviceFormatting.date(computer.general?.lastCloudBackupDate))
            }
            
            if let capableUsers = computer.general?.mdmCapable?.capableUsers, !capableUsers.isEmpty {
                DetailCard(title: "MDM Capable Users", icon: "person.badge.shield.checkmark") {
                    ForEach(capableUsers, id: \.self) { user in
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundColor(.blue)
                            Text(user)
                                .font(.system(size: 13))
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }
}
