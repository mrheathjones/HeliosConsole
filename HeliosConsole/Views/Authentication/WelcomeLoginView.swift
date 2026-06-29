//
//  WelcomeLoginView.swift
//  test
//
//  Created by heath on 1/19/26.
//


import SwiftUI
import Combine

// MARK: - App Launch State Manager
class AppLaunchStateManager: ObservableObject {
    @Published var inventoryLoadComplete = false
    @Published var deviceCounts = DeviceCounts()
    
    @MainActor
    func completeInventoryLoad(counts: DeviceCounts) {
        self.deviceCounts = counts
        self.inventoryLoadComplete = true
    }
    
    @MainActor
    func resetForNewLogin() {
        inventoryLoadComplete = false
        deviceCounts = DeviceCounts()
    }
}

struct WelcomeLoginView: View {
    @StateObject private var viewModel = AuthViewModel()
    @StateObject private var launchState = AppLaunchStateManager()
    @State private var showBiometricSetup = false
    
    var body: some View {
        ZStack {
            // Main content
            if viewModel.isLoggedIn {
                if !launchState.inventoryLoadComplete {
                    // Show loading view while inventory loads
                    InventoryLoadingContainer(launchState: launchState)
                        .transition(.opacity)
                } else {
                    DashboardView(initialDeviceCounts: launchState.deviceCounts)
                        .environmentObject(viewModel)
                        .transition(.opacity)
                        .onAppear {
                            checkBiometricSetup()
                        }
                }
            } else if viewModel.showBiometricPrompt {
                BiometricPromptView(viewModel: viewModel)
            } else {
                if viewModel.hasSeenWelcome {
                    LoginView(viewModel: viewModel, showLogin: .constant(true))
                } else {
                    WelcomeView(viewModel: viewModel)
                }
            }
            
            // Biometric setup overlay
            if showBiometricSetup {
                BiometricSetupPromptView(viewModel: viewModel, isPresented: $showBiometricSetup)
                    .zIndex(999)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: launchState.inventoryLoadComplete)
        .onChange(of: viewModel.isLoggedIn) { _, isLoggedIn in
            if isLoggedIn {
                // Reset loading state when user logs in
                launchState.resetForNewLogin()
            }
        }
    }
    
    private func checkBiometricSetup() {
        // Only show if biometric is available but not enabled
        guard viewModel.biometricManager.biometricType != .none,
              !viewModel.biometricManager.isBiometricEnabled,
              !showBiometricSetup else {
            return
        }
        
        // Delay showing the prompt
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak viewModel] in
            guard viewModel != nil else { return }
            showBiometricSetup = true
        }
    }
}
