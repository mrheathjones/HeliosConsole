//
//  DeviceLogsSectionView.swift
//  Helios
//
//  Per-device audit log section of the computer detail view.
//

import SwiftUI

struct DeviceLogsSectionView: View {
    let computer: Computer
    @ObservedObject private var actionLogService = ActionLogService.shared

    var body: some View {
        let deviceLogs = actionLogService.logs(forDeviceId: computer.id)
        
        return VStack(alignment: .leading, spacing: 24) {
            SectionHeader("Action Logs", icon: "doc.text.magnifyingglass")
            
            if deviceLogs.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.gray.opacity(0.4))
                    Text("No actions logged yet")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.gray)
                    Text("Actions performed on this device will appear here for auditing.")
                        .font(.system(size: 13))
                        .foregroundColor(.gray.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            } else {
                VStack(spacing: 8) {
                    ForEach(deviceLogs) { entry in
                        HStack(spacing: 12) {
                            // Status indicator
                            Circle()
                                .fill(entry.success ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            
                            // Action info
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(entry.actionName)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white)
                                    
                                    Text(entry.source.rawValue)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.blue)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.15))
                                        .cornerRadius(4)
                                }
                                
                                HStack(spacing: 8) {
                                    Text(entry.timestamp, style: .date)
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                    Text(entry.timestamp, style: .time)
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                    if let ip = entry.ipAddressUsed {
                                        Text(ip)
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundColor(.gray)
                                    }
                                }
                                
                                if let error = entry.errorMessage, !entry.success {
                                    Text(error)
                                        .font(.system(size: 11))
                                        .foregroundColor(.red.opacity(0.8))
                                        .lineLimit(2)
                                }
                            }
                            
                            Spacer()
                            
                            // Result badge
                            Text(entry.success ? "Success" : "Failed")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(entry.success ? .green : .red)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background((entry.success ? Color.green : Color.red).opacity(0.15))
                                .cornerRadius(6)
                            
                            // Performed by
                            Text(entry.performedBy)
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                                .frame(width: 120, alignment: .trailing)
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(8)
                    }
                }
            }
        }
    }
}
