//
//  HealthScorecardCard.swift
//  test
//
//  Created by heath on 1/25/26.
//


//
//  HealthScorecardCard.swift
//  Helios
//
//  Health Scorecard Card component with responsive compact mode
//

import SwiftUI

// MARK: - Encryption State Colors

enum EncryptionStateColor {
    static let encrypted = Color.green                          // Full green
    static let encrypting = Color(red: 0.4, green: 0.8, blue: 0.4)  // Lighter green
    static let decrypting = Color(red: 1.0, green: 0.6, blue: 0.6)  // Lighter red
    static let unencrypted = Color.red                          // Full red
    static let unknown = Color.yellow                           // Yellow
}

// MARK: - Health Scorecard Card

struct HealthScorecardCard: View {
    let metric: HealthMetricData
    let onSegmentTap: (HealthSegmentType) -> Void
    var compactMode: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered: Bool = false
    @State private var hoveredSegment: HealthSegmentType?
    @State private var hoveredEncryptionState: String?
    
    private var isDark: Bool {
        colorScheme == .dark
    }
    
    // Computed font sizes based on compact mode
    private var titleSize: CGFloat { compactMode ? 12 : 14 }
    private var percentageSize: CGFloat { compactMode ? 28 : 36 }
    private var percentSignSize: CGFloat { compactMode ? 14 : 18 }
    private var labelSize: CGFloat { compactMode ? 10 : 12 }
    private var countSize: CGFloat { compactMode ? 10 : 12 }
    private var iconBoxSize: CGFloat { compactMode ? 26 : 32 }
    private var iconSize: CGFloat { compactMode ? 12 : 14 }
    private var cardPadding: CGFloat { compactMode ? 14 : 20 }
    private var progressHeight: CGFloat { compactMode ? 4 : 6 }
    
    // Check if this is an encryption card with detailed breakdown
    private var hasEncryptionBreakdown: Bool {
        metric.type == .encrypted && (metric.encryptedCount > 0 || metric.encryptingCount > 0 || metric.decryptingCount > 0 || metric.unencryptedCount > 0)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: compactMode ? 8 : 12) {
            // Header with icon and title
            HStack(spacing: compactMode ? 6 : 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: compactMode ? 6 : 8)
                        .fill(
                            LinearGradient(
                                colors: metric.type.gradientColors.map { $0.opacity(isDark ? 0.2 : 0.15) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: iconBoxSize, height: iconBoxSize)
                    
                    Image(systemName: metric.type.icon)
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: metric.type.gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                Text(metric.type.rawValue)
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundColor(isDark ? .white : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                Spacer()
            }
            
            // Percentage display
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(metric.percentage))")
                    .font(.system(size: percentageSize, weight: .bold))
                    .foregroundColor(isDark ? .white : .primary)
                
                Text("%")
                    .font(.system(size: percentSignSize, weight: .semibold))
                    .foregroundColor(.gray)
            }
            
            // Progress bar - show detailed breakdown for encryption
            if hasEncryptionBreakdown {
                encryptionProgressBar
            } else {
                standardProgressBar
            }
            
            // Segment breakdown - show detailed breakdown for encryption
            if hasEncryptionBreakdown {
                encryptionSegmentBreakdown
            } else {
                standardSegmentBreakdown
            }
        }
        .padding(cardPadding)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: compactMode ? 12 : 16))
        .overlay(
            RoundedRectangle(cornerRadius: compactMode ? 12 : 16)
                .stroke(cardBorder, lineWidth: 1)
        )
        // Neumorphic shadow effect for light mode
        .shadow(color: isDark ? .clear : Color.white.opacity(0.9), radius: compactMode ? 6 : 8, x: compactMode ? -3 : -4, y: compactMode ? -3 : -4)
        .shadow(color: isDark ? .clear : Color.black.opacity(0.12), radius: compactMode ? 8 : 10, x: compactMode ? 4 : 6, y: compactMode ? 4 : 6)
        // Subtle inner glow effect for dark mode
        .shadow(color: isDark ? metric.type.gradientColors.first?.opacity(0.1) ?? .clear : .clear, radius: 20, x: 0, y: 0)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .animation(.easeInOut(duration: 0.3), value: colorScheme)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    // MARK: - Standard Progress Bar
    
    private var standardProgressBar: some View {
        GeometryReader { geometry in
            HStack(spacing: 1) {
                // Compliant (green)
                Rectangle()
                    .fill(Color.green)
                    .frame(width: geometry.size.width * metric.compliantPercentage)
                
                // Non-compliant (red)
                Rectangle()
                    .fill(Color.red)
                    .frame(width: geometry.size.width * metric.nonCompliantPercentage)
                
                // Unknown (yellow)
                Rectangle()
                    .fill(Color.yellow)
                    .frame(width: geometry.size.width * metric.unknownPercentage)
            }
            .cornerRadius(compactMode ? 2 : 3)
        }
        .frame(height: progressHeight)
    }
    
    // MARK: - Encryption Progress Bar
    
    private var encryptionProgressBar: some View {
        GeometryReader { geometry in
            HStack(spacing: 1) {
                // Encrypted (green)
                if metric.encryptedPercentage > 0 {
                    Rectangle()
                        .fill(EncryptionStateColor.encrypted)
                        .frame(width: geometry.size.width * metric.encryptedPercentage)
                }
                
                // Encrypting (lighter green)
                if metric.encryptingPercentage > 0 {
                    Rectangle()
                        .fill(EncryptionStateColor.encrypting)
                        .frame(width: geometry.size.width * metric.encryptingPercentage)
                }
                
                // Unencrypted (red) - includes decrypting and other non-compliant states
                if metric.unencryptedPercentage > 0 {
                    Rectangle()
                        .fill(EncryptionStateColor.unencrypted)
                        .frame(width: geometry.size.width * metric.unencryptedPercentage)
                }
                
                // Unknown (yellow)
                if metric.unknownPercentage > 0 {
                    Rectangle()
                        .fill(EncryptionStateColor.unknown)
                        .frame(width: geometry.size.width * metric.unknownPercentage)
                }
            }
            .cornerRadius(compactMode ? 2 : 3)
        }
        .frame(height: progressHeight)
    }
    
    // MARK: - Standard Segment Breakdown
    
    private var standardSegmentBreakdown: some View {
        VStack(alignment: .leading, spacing: compactMode ? 4 : 8) {
            segmentRow(
                type: .compliant,
                label: "Compliant",
                count: metric.compliantCount,
                percentage: metric.compliantPercentageDisplay
            )
            
            segmentRow(
                type: .nonCompliant,
                label: "Non-Compliant",
                count: metric.nonCompliantCount,
                percentage: metric.nonCompliantPercentageDisplay
            )
            
            segmentRow(
                type: .unknown,
                label: "Unknown",
                count: metric.unknownCount,
                percentage: metric.unknownPercentageDisplay
            )
        }
    }
    
    // MARK: - Encryption Segment Breakdown
    
    private var encryptionSegmentBreakdown: some View {
        VStack(alignment: .leading, spacing: compactMode ? 2 : 4) {
            // Encrypted (compliant)
            encryptionStateRow(
                state: "encrypted",
                label: "Encrypted",
                color: EncryptionStateColor.encrypted,
                count: metric.encryptedCount,
                percentage: metric.encryptedPercentageDisplay,
                segmentType: .compliant
            )
            
            // Encrypting (compliant)
            encryptionStateRow(
                state: "encrypting",
                label: "Encrypting",
                color: EncryptionStateColor.encrypting,
                count: metric.encryptingCount,
                percentage: metric.encryptingPercentageDisplay,
                segmentType: .compliant
            )
            
            // Unencrypted (non-compliant) - includes decrypting and other states
            encryptionStateRow(
                state: "unencrypted",
                label: "Unencrypted",
                color: EncryptionStateColor.unencrypted,
                count: metric.unencryptedCount,
                percentage: metric.unencryptedPercentageDisplay,
                segmentType: .nonCompliant
            )
            
            // Unknown
            encryptionStateRow(
                state: "unknown",
                label: "Unknown",
                color: EncryptionStateColor.unknown,
                count: metric.unknownCount,
                percentage: metric.unknownPercentageDisplay,
                segmentType: .unknown
            )
        }
    }
    
    // MARK: - Card Background
    
    private var cardBackground: some View {
        Group {
            if isDark {
                RoundedRectangle(cornerRadius: compactMode ? 12 : 16)
                    .fill(Color.white.opacity(isHovered ? 0.06 : 0.03))
            } else {
                RoundedRectangle(cornerRadius: compactMode ? 12 : 16)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white,
                                Color(red: 0.94, green: 0.94, blue: 0.96)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
    }
    
    private var cardBorder: Color {
        if isHovered {
            return metric.type.gradientColors.first?.opacity(0.4) ?? Color.blue.opacity(0.4)
        }
        return isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.04)
    }
    
    // MARK: - Segment Row
    
    private func segmentRow(
        type: HealthSegmentType,
        label: String,
        count: Int,
        percentage: Int
    ) -> some View {
        Button {
            onSegmentTap(type)
        } label: {
            HStack(spacing: compactMode ? 4 : 8) {
                Circle()
                    .fill(type.color)
                    .frame(width: compactMode ? 6 : 8, height: compactMode ? 6 : 8)
                
                Text(label)
                    .font(.system(size: labelSize, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.8) : .primary.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                
                Spacer()
                
                Text(compactMode ? formatCompactNumber(count) : count.formatted())
                    .font(.system(size: countSize, weight: .semibold))
                    .foregroundColor(isDark ? .white : .primary)
                
                Text("(\(percentage)%)")
                    .font(.system(size: compactMode ? 9 : 11))
                    .foregroundColor(.gray)
            }
            .padding(.vertical, compactMode ? 2 : 4)
            .padding(.horizontal, compactMode ? 4 : 8)
            .background(
                RoundedRectangle(cornerRadius: compactMode ? 4 : 6)
                    .fill(hoveredSegment == type
                          ? (isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                          : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredSegment = hovering ? type : nil
            }
        }
    }
    
    // MARK: - Encryption State Row
    
    private func encryptionStateRow(
        state: String,
        label: String,
        color: Color,
        count: Int,
        percentage: Int,
        segmentType: HealthSegmentType
    ) -> some View {
        Button {
            onSegmentTap(segmentType)
        } label: {
            HStack(spacing: compactMode ? 4 : 6) {
                Circle()
                    .fill(color)
                    .frame(width: compactMode ? 5 : 6, height: compactMode ? 5 : 6)
                
                Text(label)
                    .font(.system(size: compactMode ? 9 : 11, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.8) : .primary.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                
                Spacer()
                
                Text(compactMode ? formatCompactNumber(count) : count.formatted())
                    .font(.system(size: compactMode ? 9 : 11, weight: .semibold))
                    .foregroundColor(isDark ? .white : .primary)
                
                Text("(\(percentage)%)")
                    .font(.system(size: compactMode ? 8 : 10))
                    .foregroundColor(.gray)
            }
            .padding(.vertical, compactMode ? 1 : 2)
            .padding(.horizontal, compactMode ? 4 : 6)
            .background(
                RoundedRectangle(cornerRadius: compactMode ? 3 : 4)
                    .fill(hoveredEncryptionState == state
                          ? (isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                          : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredEncryptionState = hovering ? state : nil
            }
        }
    }
    
    private func formatCompactNumber(_ num: Int) -> String {
        if num >= 1000 {
            let k = Double(num) / 1000.0
            return String(format: "%.1fK", k)
        }
        return "\(num)"
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Health Scorecard Card - Normal") {
    HStack(spacing: 16) {
        HealthScorecardCard(
            metric: HealthMetricData(
                type: .checkedIn,
                compliantCount: 5420,
                nonCompliantCount: 489,
                unknownCount: 98
            ),
            onSegmentTap: { _ in }
        )
        
        HealthScorecardCard(
            metric: HealthMetricData(
                type: .encrypted,
                compliantCount: 5650,
                nonCompliantCount: 287,
                unknownCount: 70,
                encryptedCount: 5500,
                encryptingCount: 150,
                decryptingCount: 50,
                unencryptedCount: 237
            ),
            onSegmentTap: { _ in }
        )
    }
    .padding(40)
    .background(Color(white: 0.1))
    .preferredColorScheme(.dark)
}

#Preview("Health Scorecard Card - Compact") {
    HStack(spacing: 12) {
        HealthScorecardCard(
            metric: HealthMetricData(
                type: .checkedIn,
                compliantCount: 5420,
                nonCompliantCount: 489,
                unknownCount: 98
            ),
            onSegmentTap: { _ in },
            compactMode: true
        )
        
        HealthScorecardCard(
            metric: HealthMetricData(
                type: .encrypted,
                compliantCount: 5650,
                nonCompliantCount: 287,
                unknownCount: 70,
                encryptedCount: 5500,
                encryptingCount: 150,
                decryptingCount: 50,
                unencryptedCount: 237
            ),
            onSegmentTap: { _ in },
            compactMode: true
        )
        
        HealthScorecardCard(
            metric: HealthMetricData(
                type: .protected,
                compliantCount: 5780,
                nonCompliantCount: 185,
                unknownCount: 42
            ),
            onSegmentTap: { _ in },
            compactMode: true
        )
    }
    .padding(20)
    .background(Color(white: 0.1))
    .preferredColorScheme(.dark)
}
#endif
