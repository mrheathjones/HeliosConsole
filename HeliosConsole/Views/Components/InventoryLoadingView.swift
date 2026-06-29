//
//  InventoryLoadingView.swift
//  Helios
//
//  Modern loading view displayed while inventory data loads after login
//

import SwiftUI
import Combine

struct InventoryLoadingView: View {
    @State private var isAnimating = false
    @State private var pulseAnimation = false
    @State private var rotationAngle: Double = 0
    @State private var progressValue: Double = 0
    @State private var currentStatusIndex = 0
    @State private var showStatusText = false
    
    let statusMessages = [
        "Connecting to Jamf Pro...",
        "Authenticating...",
        "Fetching computer inventory...",
        "Fetching mobile devices...",
        "Processing device data...",
        "Almost ready..."
    ]
    
    var body: some View {
        ZStack {
            // Animated background
            AnimatedBackgroundView(animate: $isAnimating)
            
            // Content
            VStack(spacing: 40) {
                Spacer()
                
                // Logo and animated rings
                ZStack {
                    // Outer rotating ring
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [.blue.opacity(0.1), .cyan.opacity(0.5), .blue.opacity(0.1)],
                                center: .center,
                                startAngle: .degrees(0),
                                endAngle: .degrees(360)
                            ),
                            lineWidth: 3
                        )
                        .frame(width: 140, height: 140)
                        .rotationEffect(.degrees(rotationAngle))
                    
                    // Middle pulsing ring
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.blue.opacity(0.3), .cyan.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 110, height: 110)
                        .scaleEffect(pulseAnimation ? 1.1 : 0.95)
                        .opacity(pulseAnimation ? 0.5 : 0.8)
                    
                    // Inner glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.blue.opacity(0.2), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 50
                            )
                        )
                        .frame(width: 100, height: 100)
                        .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                    
                    // App icon/logo
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(white: 0.15),
                                        Color(white: 0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 70, height: 70)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(
                                        LinearGradient(
                                            colors: [.white.opacity(0.2), .white.opacity(0.05)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
                        
                        // Sun icon for Helios
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.orange, .yellow],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: .orange.opacity(0.5), radius: 10, x: 0, y: 0)
                    }
                }
                
                // App name
                VStack(spacing: 8) {
                    Text("HELIOS")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .tracking(6)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    Text("Device Management Console")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // Loading indicator section
                VStack(spacing: 24) {
                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Track
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 4)
                            
                            // Progress
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [.blue, .cyan],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * progressValue, height: 4)
                            
                            // Shimmer effect
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [.clear, .white.opacity(0.3), .clear],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: 60, height: 4)
                                .offset(x: isAnimating ? geometry.size.width : -60)
                                .animation(
                                    .linear(duration: 1.5).repeatForever(autoreverses: false),
                                    value: isAnimating
                                )
                                .mask(
                                    RoundedRectangle(cornerRadius: 4)
                                        .frame(width: geometry.size.width * progressValue, height: 4)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                )
                        }
                    }
                    .frame(width: 280, height: 4)
                    
                    // Status text
                    HStack(spacing: 8) {
                        // Animated dots
                        HStack(spacing: 4) {
                            ForEach(0..<3) { index in
                                Circle()
                                    .fill(Color.cyan)
                                    .frame(width: 6, height: 6)
                                    .scaleEffect(isAnimating ? 1.0 : 0.5)
                                    .opacity(isAnimating ? 1.0 : 0.3)
                                    .animation(
                                        .easeInOut(duration: 0.6)
                                        .repeatForever(autoreverses: true)
                                        .delay(Double(index) * 0.2),
                                        value: isAnimating
                                    )
                            }
                        }
                        
                        Text(statusMessages[currentStatusIndex])
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.gray)
                            .opacity(showStatusText ? 1 : 0)
                            .animation(.easeInOut(duration: 0.3), value: showStatusText)
                    }
                }
                .padding(.bottom, 60)
            }
            .padding(.horizontal, 40)
        }
        .onAppear {
            startAnimations()
        }
    }
    
    private func startAnimations() {
        // Start background animation
        isAnimating = true
        
        // Pulse animation
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            pulseAnimation = true
        }
        
        // Rotation animation
        withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
            rotationAngle = 360
        }
        
        // Show status text
        withAnimation(.easeIn(duration: 0.5)) {
            showStatusText = true
        }
        
        // Progress animation
        animateProgress()
        
        // Cycle through status messages
        cycleStatusMessages()
    }
    
    private func animateProgress() {
        // Animate progress in stages
        let stages: [(Double, Double)] = [
            (0.15, 0.3),  // Quick start
            (0.35, 0.8),  // Slower middle
            (0.55, 1.2),
            (0.75, 0.6),
            (0.90, 1.0),
            (0.98, 0.5)   // Almost done, slow down
        ]
        
        var totalDelay: Double = 0
        
        for (progress, duration) in stages {
            totalDelay += duration
            DispatchQueue.main.asyncAfter(deadline: .now() + totalDelay) {
                withAnimation(.easeOut(duration: duration)) {
                    progressValue = progress
                }
            }
        }
    }
    
    private func cycleStatusMessages() {
        // Cycle through messages with animation
        let messageInterval: Double = 1.0
        
        for (index, _) in statusMessages.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * messageInterval) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showStatusText = false
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    currentStatusIndex = index
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showStatusText = true
                    }
                }
            }
        }
    }
}

// MARK: - Inventory Loading Manager

@MainActor
class InventoryLoadingManager: ObservableObject {
    private var computerInventoryService: ComputerInventoryService?
    private var mobileDeviceService: MobileDeviceInventoryService?
    private var hasStartedLoading = false
    
    weak var launchState: AppLaunchStateManager?
    
    func startLoadingIfNeeded() {
        guard !hasStartedLoading else { return }
        hasStartedLoading = true
        
        // Create services
        computerInventoryService = ComputerInventoryService()
        mobileDeviceService = MobileDeviceInventoryService()
        
        Task { @MainActor in
            await loadAllInventory()
        }
    }
    
    private func loadAllInventory() async {
        // Small initial delay for UI animation
        try? await Task.sleep(nanoseconds: 800_000_000)
        
        let computerCache = ComputerInventoryCache.shared
        let mobileCache = MobileDeviceInventoryCache.shared
        
        // Check if we already have cached data
        if computerCache.hasCachedData && mobileCache.hasCachedData {
            let counts = DeviceCounts(
                macOS: computerCache.totalCount,
                iOS: mobileCache.iOSCount,
                iPadOS: mobileCache.iPadOSCount,
                visionOS: mobileCache.visionOSCount
            )
            try? await Task.sleep(nanoseconds: 500_000_000)
            launchState?.completeInventoryLoad(counts: counts)
            return
        }
        
        // Fetch computers using master API
        if let computerService = computerInventoryService {
            await computerService.fetchAllComputers()
        }
        
        // Small delay between calls
        try? await Task.sleep(nanoseconds: 300_000_000)
        
        // Fetch mobile devices using master API
        if let mobileService = mobileDeviceService {
            await mobileService.fetchAllDevices()
        }
        
        // Get counts from cache (services populate the cache)
        let counts = DeviceCounts(
            macOS: computerCache.totalCount,
            iOS: mobileCache.iOSCount,
            iPadOS: mobileCache.iPadOSCount,
            visionOS: mobileCache.visionOSCount
        )
        
        // Small delay for smooth transition
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        // Signal completion via the launch state manager
        launchState?.completeInventoryLoad(counts: counts)
    }
}

// MARK: - Loading View Container

struct InventoryLoadingContainer: View {
    @ObservedObject var launchState: AppLaunchStateManager
    @StateObject private var loadingManager = InventoryLoadingManager()
    
    var body: some View {
        InventoryLoadingView()
            .onAppear {
                loadingManager.launchState = launchState
                loadingManager.startLoadingIfNeeded()
            }
    }
}

// MARK: - Device Counts

struct DeviceCounts {
    var macOS: Int = 0
    var iOS: Int = 0
    var iPadOS: Int = 0
    var visionOS: Int = 0
    
    var total: Int {
        macOS + iOS + iPadOS + visionOS
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Inventory Loading View") {
    InventoryLoadingView()
        .frame(width: 800, height: 600)
}
#endif
