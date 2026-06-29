//
//  HealthMetricView.swift
//  test
//
//  Created by heath on 1/19/26.
//


import SwiftUI

// MARK: - Health Metric View
struct HealthMetricView: View {
    let title: String
    let percentage: String
    let isHealthy: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(isHealthy ? Color.green : Color.red, lineWidth: 6)
                    .frame(width: 80, height: 80)
                
                Text(percentage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.blue)
                .multilineTextAlignment(.center)
                .frame(height: 36)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Simple Metric Card
struct SimpleMetricCard: View {
    let title: String
    let count: Int
    var isCompact: Bool = false
    
    var body: some View {
        VStack(spacing: isCompact ? 8 : 12) {
            Text(title)
                .font(.system(size: isCompact ? 16 : 20, weight: .bold))
                .foregroundColor(.blue)
            
            Text("\(count)")
                .font(.system(size: isCompact ? 36 : 48, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(isCompact ? 16 : 24)
        .background(Color(white: 0.18))
        .cornerRadius(10)
    }
}

// MARK: - macOS Version Card
struct MacOSVersionCard: View {
    let versionName: String
    let subtitle: String
    let count: Int
    let status: SupportStatus
    
    enum SupportStatus {
        case supported
        case limited
        case unsupported
        
        var icon: String {
            switch self {
            case .supported: return "checkmark.circle.fill"
            case .limited: return "exclamationmark.circle.fill"
            case .unsupported: return "nosign"
            }
        }
        
        var color: Color {
            switch self {
            case .supported: return .green
            case .limited: return .orange
            case .unsupported: return .red
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(versionName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.blue)
                
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            
            HStack(spacing: 20) {
                Text("\(count)")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.white)
                
                Image(systemName: status.icon)
                    .font(.system(size: 32))
                    .foregroundColor(status.color)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(white: 0.18))
        .cornerRadius(10)
    }
}
