//
//  DeviceOverviewView.swift
//  Helios
//
//  Overview section of the computer detail view: quick-stat cards,
//  device health, and general/hardware/security summaries.
//

import SwiftUI

struct DeviceOverviewView: View {
    let computer: Computer
    @ObservedObject private var configManager = MDMConfigurationManager.shared
    @State private var showingUpdatesPopover: Bool = false

    // MARK: - Overview Section
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader("Overview", icon: "square.grid.2x2")
            
            // Quick Stats. Cards always stretch to fill the full section width;
            // when the window gets too narrow for a row to hold them at a
            // legible 190pt, ViewThatFits drops to the next arrangement rather
            // than squeezing. (An adaptive LazyVGrid can't do this — with only
            // five items a wide window leaves the trailing columns empty.)
            ViewThatFits(in: .horizontal) {
                quickStatRow(0..<5)

                VStack(spacing: 16) {
                    quickStatRow(0..<3)
                    quickStatRow(3..<5)
                }

                VStack(spacing: 16) {
                    quickStatRow(0..<2)
                    quickStatRow(2..<4)
                    quickStatRow(4..<5)
                }

                VStack(spacing: 16) {
                    ForEach(0..<5, id: \.self) { index in
                        quickStatRow(index..<(index + 1))
                    }
                }
            }
            
            // Device Health Section
            DeviceHealthSection(computer: computer)
            
            // General Info
            DetailCard(title: "General Information", icon: "info.circle") {
                DetailRow("Device Name", computer.general?.name)
                DetailRow("Serial Number", computer.serialNumber)
                DetailRow("UDID", computer.udid)
                DetailRow("Management ID", computer.general?.managementId)
                DetailRow("Asset Tag", computer.general?.assetTag)
                DetailRow("Site", computer.general?.site?.name)
                DetailRow("Platform", computer.general?.platform)
                DetailRow("Jamf Binary", computer.general?.jamfBinaryVersion)
            }
            
            // Hardware Summary
            DetailCard(title: "Hardware Summary", icon: "cpu") {
                DetailRow("Model", computer.modelName)
                DetailRow("Model Identifier", computer.hardware?.modelIdentifier)
                DetailRow("Processor", computer.processorDescription)
                DetailRow("Architecture", computer.hardware?.processorArchitecture)
                DetailRow("Apple Silicon", computer.isAppleSilicon ? "Yes" : "No")
                DetailRow("Memory", computer.totalRAMGB.map { "\(Int($0)) GB" })
            }
            
            // Security Summary
            DetailCard(title: "Security Summary", icon: "shield.checkered") {
                DetailRow("FileVault", computer.isFileVaultEnabled ? "Enabled" : "Disabled")
                DetailRow("SIP Status", computer.security?.sipStatus)
                DetailRow("Gatekeeper", DeviceFormatting.gatekeeperStatus(computer.security?.gatekeeperStatus))
                DetailRow("Firewall", computer.security?.firewallEnabled == true ? "Enabled" : "Disabled")
                DetailRow("Secure Boot", computer.security?.secureBootLevel)
            }
        }
    }
    
    // MARK: - Quick Stat Row Layout

    /// One row of quick-stat cards. Each card carries a 190pt `minWidth` so the
    /// row's ideal width reflects what it needs to stay legible — that's what
    /// `ViewThatFits` measures — while `maxWidth: .infinity` makes the cards
    /// share whatever width the row is actually given.
    private func quickStatRow(_ range: Range<Int>) -> some View {
        HStack(spacing: 16) {
            ForEach(Array(range), id: \.self) { index in
                quickStatCard(index)
                    .frame(minWidth: 190, maxWidth: .infinity)
            }
        }
        .frame(height: 170)
    }

    @ViewBuilder
    private func quickStatCard(_ index: Int) -> some View {
        switch index {
        case 0:
            overviewStatCard(
                title: "Last Check-in",
                value: DeviceFormatting.date(computer.general?.reportDate) ?? "N/A",
                icon: "clock.fill",
                color: .blue
            )
        case 1:
            batteryHealthCard
        case 2:
            storageCard
        case 3:
            ipAddressCard
        default:
            availableUpdatesCard
        }
    }

    // MARK: - Battery Health Card

    private var batteryHealthCard: some View {
        let batteryHealth = computer.hardware?.batteryHealth
        let batteryCapacity = computer.hardware?.batteryCapacityPercent
        
        // Determine if battery info is available (not unsupported/N/A and has valid capacity)
        let hasBattery = batteryHealth != nil &&
                         batteryHealth?.uppercased() != "UNSUPPORTED" &&
                         batteryCapacity != nil &&
                         batteryCapacity != -1
        
        let displayValue: String
        let healthColor: Color
        
        if hasBattery, let health = batteryHealth, let capacity = batteryCapacity {
            displayValue = "\(capacity)%"
            // Color based on health status
            switch health.uppercased() {
            case "NORMAL", "GOOD":
                healthColor = .green
            case "SERVICE_RECOMMENDED", "SERVICE RECOMMENDED":
                healthColor = .orange
            case "REPLACE_SOON", "REPLACE SOON":
                healthColor = .orange
            case "REPLACE_NOW", "REPLACE NOW", "SERVICE_BATTERY", "SERVICE BATTERY":
                healthColor = .red
            default:
                healthColor = .purple
            }
        } else {
            displayValue = "N/A"
            healthColor = .purple
        }
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: hasBattery ? "battery.100" : "battery.0")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(healthColor)
                Spacer()
            }
            
            Spacer()
            
            Text(displayValue)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            
            if hasBattery, let health = computer.hardware?.batteryHealth {
                Text(formatBatteryHealth(health))
                    .font(.system(size: 10))
                    .foregroundColor(healthColor.opacity(0.8))
            }
            
            Spacer()
            
            Text("Battery Health")
                .font(.system(size: 12))
                .foregroundColor(.gray)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
                .background(.ultraThinMaterial.opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
    
    private func formatBatteryHealth(_ health: String) -> String {
        switch health.uppercased() {
        case "NORMAL", "GOOD": return "Normal"
        case "SERVICE_RECOMMENDED", "SERVICE RECOMMENDED": return "Service Recommended"
        case "REPLACE_SOON", "REPLACE SOON": return "Replace Soon"
        case "REPLACE_NOW", "REPLACE NOW": return "Replace Now"
        case "SERVICE_BATTERY", "SERVICE BATTERY": return "Service Battery"
        case "UNSUPPORTED": return "No Battery"
        default: return health
        }
    }
    
    // MARK: - Storage Card with Bar Graph
    
    private var storageCard: some View {
        // Get storage info - try to find boot drive partition or use disk info
        let availableMB = computer.storage?.bootDriveAvailableSpaceMegabytes
        let totalMB = getBootDriveTotalSize()
        
        let availableGB = availableMB.map { Double($0) / 1024.0 }
        let totalGB = totalMB.map { Double($0) / 1024.0 }
        
        let usedPercentage: Double
        if let available = availableMB, let total = totalMB, total > 0 {
            usedPercentage = Double(total - available) / Double(total)
        } else {
            usedPercentage = 0
        }
        
        let usedPercentageInt = Int(usedPercentage * 100)
        
        // Color based on usage
        let barColor: Color = {
            if usedPercentage > 0.9 { return .red }
            if usedPercentage > 0.75 { return .orange }
            return .orange
        }()
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "internaldrive")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.orange)
                Spacer()
                
                // Percentage used badge
                if availableMB != nil && totalMB != nil {
                    Text("\(usedPercentageInt)% Used")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(barColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(barColor.opacity(0.2))
                        )
                }
            }
            
            Spacer()
            
            if let available = availableGB {
                Text(String(format: "%.1f GB", available))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else {
                Text("N/A")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            // Storage bar graph
            if let _ = availableMB, let total = totalGB {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background bar
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 6)
                        
                        // Used space bar
                        RoundedRectangle(cornerRadius: 3)
                            .fill(barColor)
                            .frame(width: geometry.size.width * usedPercentage, height: 6)
                    }
                }
                .frame(height: 6)
                
                // Show total size
                Text(String(format: "of %.0f GB", total))
                    .font(.system(size: 10))
                    .foregroundColor(.gray.opacity(0.8))
            }
            
            Spacer()
            
            Text("Available Storage")
                .font(.system(size: 12))
                .foregroundColor(.gray)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
                .background(.ultraThinMaterial.opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
    
    private func getBootDriveTotalSize() -> Int? {
        // Try to get total size from the boot partition or first disk
        if let disks = computer.storage?.disks {
            // Look for the boot partition in any disk
            for disk in disks {
                if let partitions = disk.partitions {
                    // Find partition named "Macintosh HD" or similar boot partition
                    if let bootPartition = partitions.first(where: {
                        $0.name?.lowercased().contains("macintosh") == true ||
                        $0.partitionType?.uppercased() == "BOOT"
                    }) {
                        return bootPartition.sizeMegabytes
                    }
                }
                // Fallback to disk size
                if let diskSize = disk.sizeMegabytes {
                    return diskSize
                }
            }
        }
        return nil
    }
    
    // MARK: - IP Address Card (VPN or Regular)
    
    private var ipAddressCard: some View {
        // Check for the configured VPN IP extension attribute first
        // (core jamfPro.vpnIPExtensionAttributeEnabled / …ID; off = LAN IP only).
        let vpnIP = configManager.configuration.vpnIPExtensionAttribute
            .flatMap { computer.extensionAttributeValue($0) }
        // Only consider VPN valid if it has a value that's not empty or "N/A"
        let hasVPN = vpnIP != nil && !vpnIP!.isEmpty && vpnIP!.uppercased() != "N/A"
        
        let ipAddress = hasVPN ? vpnIP : computer.ipAddress
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: hasVPN ? "lock.shield" : "network")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.green)
                Spacer()
                
                if hasVPN {
                    // VPN indicator badge
                    Text("VPN")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.green.opacity(0.2))
                        )
                }
            }
            
            Spacer()
            
            Text(ipAddress ?? "N/A")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            
            Spacer()
            
            Text("IP Address")
                .font(.system(size: 12))
                .foregroundColor(.gray)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
                .background(.ultraThinMaterial.opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
    
    // MARK: - Available Updates Card
    
    private var availableUpdatesCard: some View {
        let updates = computer.softwareUpdates ?? []
        let updateCount = updates.count
        
        let color: Color = updateCount > 0 ? .cyan : .green
        let icon = updateCount > 0 ? "arrow.down.circle" : "checkmark.circle"
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(color)
                Spacer()
                
                if updateCount > 0 {
                    // Updates available badge
                    Text("\(updateCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 18, height: 18)
                        .background(
                            Circle()
                                .fill(color)
                        )
                }
            }
            
            Spacer()
            
            Text(updateCount > 0 ? "\(updateCount) Available" : "Up to Date")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            
            Spacer()
            
            Text("Updates")
                .font(.system(size: 12))
                .foregroundColor(.gray)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
                .background(.ultraThinMaterial.opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
        .onTapGesture {
            if updateCount > 0 {
                showingUpdatesPopover.toggle()
            }
        }
        .popover(isPresented: $showingUpdatesPopover, arrowEdge: .bottom) {
            updatesPopoverContent(updates: updates)
        }
    }
    
    private func updatesPopoverContent(updates: [SoftwareUpdate]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.cyan)
                Text("Available Updates")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
            }
            .padding(.bottom, 4)
            
            Divider()
            
            ForEach(updates) { update in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(update.name ?? "Unknown Update")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                        Spacer()
                        if let version = update.version {
                            Text(version)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let packageName = update.packageName {
                        Text(packageName)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
                
                if update.id != updates.last?.id {
                    Divider()
                }
            }
        }
        .padding(16)
        .frame(width: 350)
    }
    
    private func overviewStatCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(color)
                Spacer()
            }
            
            Spacer()
            
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            
            Spacer()
            
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.gray)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
                .background(.ultraThinMaterial.opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}
