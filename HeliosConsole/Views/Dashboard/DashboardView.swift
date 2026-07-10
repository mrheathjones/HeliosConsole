//
//  DashboardView.swift
//  Helios
//
//  Main dashboard container with sidebar navigation and view routing
//

import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var deepLinkRouter: DeepLinkRouter
    @State private var viewModel = DashboardViewModel()
    @State private var selectedDestination: NavigationDestination = .dashboard
    @State private var isInNestedView: Bool = false
    
    // Initial device counts passed from loading screen
    var initialDeviceCounts: DeviceCounts = DeviceCounts()
    
    // Navigation reset triggers - increment to force view reset
    @State private var dashboardResetTrigger: UUID = UUID()
    @State private var devicesResetTrigger: UUID = UUID()
    
    private let sidebarWidth: CGFloat = 260
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            SidebarView(
                selectedDestination: $selectedDestination,
                isInNestedView: $isInNestedView,
                onNavigate: handleNavigation
            )
            .environmentObject(authViewModel)
            
            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 1)
            
            // Main Content
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if deepLinkRouter.pendingRequest != nil {
                handleDeepLinkNavigation()
            }
        }
        .onChange(of: deepLinkRouter.pendingRequest) { oldValue, newValue in
            if newValue != nil {
                handleDeepLinkNavigation()
            }
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: Notification.Name("com.helios.console.deeplink"))) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                deepLinkRouter.checkForPendingDeepLink()
                if deepLinkRouter.pendingRequest != nil {
                    handleDeepLinkNavigation()
                }
            }
        }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        switch selectedDestination {
        case .dashboard:
            DashboardContentView(
                viewModel: viewModel,
                isInNestedView: $isInNestedView,
                initialDeviceCounts: initialDeviceCounts
            )
            .id(dashboardResetTrigger)
        case .devices:
            DevicesView(isInNestedView: $isInNestedView)
                .environmentObject(deepLinkRouter)
                .id(devicesResetTrigger)
        case .announcements:
            AnnouncementsView()
        case .logs:
            LogsView()
        case .reports:
            ReportsView()
        case .enrollments:
            EnrollmentsView()
        case .cleanup:
            CleanupView(isInNestedView: $isInNestedView)
        case .settings:
            SettingsView()
        }
    }
    
    private func handleNavigation(to destination: NavigationDestination) {
        // Reset nested view state
        isInNestedView = false
        
        // If navigating to same destination, reset its trigger to force view recreation
        if selectedDestination == destination {
            switch destination {
            case .dashboard:
                dashboardResetTrigger = UUID()
            case .devices:
                devicesResetTrigger = UUID()
            default:
                break
            }
        }
        
        // Update destination
        selectedDestination = destination
    }
    
    /// Handle a deep link navigation request from the menu bar companion app.
    /// Simply switches to the Devices tab — DevicesView reads from the router directly.
    private func handleDeepLinkNavigation() {
        selectedDestination = .devices
    }
}

@Observable
@MainActor
class DashboardViewModel {
    var isLoading = false
    var selectedNavigationItem: String = "dashboard"
    
    func refresh() async {
        isLoading = true
        try? await Task.sleep(for: .seconds(1))
        isLoading = false
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Dashboard View") {
    DashboardView()
        .environmentObject(AuthViewModel())
        .environmentObject(DeepLinkRouter())
        .frame(width: 1400, height: 900)
}
#endif
