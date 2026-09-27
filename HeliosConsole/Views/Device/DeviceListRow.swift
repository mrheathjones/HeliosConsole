//
//  DeviceListRow.swift
//  test
//
//  Created by heath on 1/25/26.
//

import SwiftUI

// MARK: - Device List Row

struct DeviceListRow: View {
    let device: DeviceListItem
    let platform: PlatformType
    var isLoading: Bool = false
    let onSelect: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // Device icon - realistic CoreTypes icon when available
                ZStack {
                    if isLoading {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(platform.color.opacity(0.1))
                            .frame(width: 44, height: 44)
                        
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(platform.color)
                    } else {
                        DeviceIconView(
                            modelIdentifier: device.modelIdentifier,
                            modelName: device.model,
                            platform: platform,
                            size: 44
                        )
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text(device.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        
                        if device.isSupervised {
                            StatusBadge("Supervised", color: .blue, size: .compact)
                        }
                        
                        if device.isManaged {
                            StatusBadge("Managed", color: .green, size: .compact)
                        }
                    }
                    
                    HStack(spacing: 16) {
                        infoLabel(icon: nil, text: device.serialNumber)
                        infoLabel(icon: "laptopcomputer", text: device.model)
                        infoLabel(icon: "gear", text: "\(platform.rawValue) \(device.osVersion)")
                    }
                }
                
                Spacer()
                
                if let user = device.assignedUser {
                    HStack(spacing: 6) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 10))
                        Text(user)
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.gray)
                    .frame(width: 140, alignment: .leading)
                } else {
                    Text("Unassigned")
                        .font(.system(size: 12))
                        .foregroundColor(.gray.opacity(0.5))
                        .frame(width: 140, alignment: .leading)
                }
                
                Text(device.lastCheckInFormatted)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .frame(width: 80, alignment: .trailing)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.gray.opacity(0.5))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(isHovered ? 0.06 : 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(isHovered ? 0.1 : 0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
    
    private func infoLabel(icon: String?, text: String) -> some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 9))
            }
            Text(text)
                .font(.system(size: 11))
                .lineLimit(1)
        }
        .foregroundColor(.gray)
    }
}
