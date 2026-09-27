//
//  ComputerResultCard.swift
//  test
//
//  Created by heath on 1/25/26.
//

import SwiftUI

// MARK: - Computer Result Card

struct ComputerResultCard: View {
    let computer: Computer
    let onSelect: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 20) {
                DeviceIconView(
                    modelIdentifier: computer.hardware?.modelIdentifier,
                    modelName: computer.modelName,
                    platform: .macOS,
                    size: 56
                )
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text(computer.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        
                        if computer.isSupervised {
                            StatusBadge("Supervised", color: .blue, size: .compact)
                        }
                        
                        if computer.isManaged {
                            StatusBadge("Managed", color: .green, size: .compact)
                        }
                        
                        if computer.isFileVaultEnabled {
                            StatusBadge("Encrypted", color: .purple, size: .compact)
                        }
                    }
                    
                    HStack(spacing: 20) {
                        infoLabel(icon: nil, text: computer.serialNumber ?? "N/A")
                        infoLabel(icon: "desktopcomputer", text: computer.modelName ?? "Unknown")
                        if let version = computer.osVersion {
                            infoLabel(icon: "gear", text: "macOS \(version)")
                        }
                    }
                    
                    if let username = computer.assignedUserRealName ?? computer.assignedUser {
                        HStack(spacing: 6) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 10))
                            Text(username)
                                .font(.system(size: 12))
                            
                            if let email = computer.userAndLocation?.email {
                                Text("•")
                                    .font(.system(size: 10))
                                Text(email)
                                    .font(.system(size: 12))
                            }
                        }
                        .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    if let lastContact = computer.lastCheckInFormatted {
                        Text(lastContact)
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.gray.opacity(0.5))
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(isHovered ? 0.08 : 0.03))
                    .background(.ultraThinMaterial.opacity(0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(isHovered ? 0.15 : 0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
                    .font(.system(size: 10))
            }
            Text(text)
                .font(.system(size: 12))
                .lineLimit(1)
        }
        .foregroundColor(.gray)
    }
}

// MARK: - Search Result Row (Unified)

struct SearchResultRow: View {
    let result: UnifiedSearchResult
    let onSelect: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 20) {
                // Device icon - realistic CoreTypes icon when available
                DeviceIconView(
                    modelIdentifier: result.modelIdentifier,
                    modelName: result.model,
                    platform: result.platform,
                    size: 56
                )
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text(result.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        
                        // Platform badge
                        Text(result.platform.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(result.platform.color))
                        
                        if result.isSupervised {
                            StatusBadge("Supervised", color: .blue, size: .compact)
                        }
                        
                        if result.isManaged {
                            StatusBadge("Managed", color: .green, size: .compact)
                        }
                    }
                    
                    HStack(spacing: 20) {
                        infoLabel(icon: nil, text: result.serialNumber)
                        infoLabel(icon: "laptopcomputer", text: result.model)
                        if result.osVersion != "N/A" {
                            infoLabel(icon: "gear", text: "\(result.platform == .macOS ? "macOS" : result.platform.rawValue) \(result.osVersion)")
                        }
                    }
                    
                    if let username = result.assignedUser {
                        HStack(spacing: 6) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 10))
                            Text(username)
                                .font(.system(size: 12))
                        }
                        .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray.opacity(0.5))
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(isHovered ? 0.08 : 0.03))
                    .background(.ultraThinMaterial.opacity(0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(isHovered ? 0.15 : 0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
                    .font(.system(size: 10))
            }
            Text(text)
                .font(.system(size: 12))
                .lineLimit(1)
        }
        .foregroundColor(.gray)
    }
}
