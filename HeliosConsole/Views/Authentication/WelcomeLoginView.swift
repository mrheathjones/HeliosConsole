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
            } else if viewModel.isRestoringEntraSession {
                // Redeeming the persisted Entra refresh token — avoid a
                // login-form flash while the outcome is unknown.
                entraRestoreProgressView
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
        // Warm the ABM inventory as early as the login screen — ABM auth is
        // app-level (ES256 client-credentials from the config profile), not
        // tied to the user's sign-in, so the 26k-device sweep can run while
        // the user is authenticating instead of starting cold at the tab.
        // No-op when ABM isn't configured or the cache is already valid; the
        // DashboardView .task remains as a post-login fallback (idempotent).
        .task {
            await ABMDeviceCache.shared.preloadIfNeeded()
        }
    }
    
    private var entraRestoreProgressView: some View {
        ZStack {
            AnimatedBackgroundView(animate: .constant(true))

            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)

                Text("Signing you in…")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
            }
        }
        .transition(.opacity)
    }

    private func checkBiometricSetup() {
        // Only show if setup is allowed by managed policy
        // (ui.authentication allowBiometricSetup) and biometric hardware
        // is available but not enabled
        guard viewModel.isBiometricSetupAllowed,
              viewModel.biometricManager.biometricType != .none,
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
