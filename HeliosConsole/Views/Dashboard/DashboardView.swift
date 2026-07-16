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
    /// Observed so the route gates re-evaluate when capabilities land after
    /// sign-in (matches SidebarView).
    @ObservedObject private var session = UserSession.shared
    /// Observed so the route gates re-evaluate when a profile push changes
    /// the machine layer mid-session (matches DeviceView).
    @ObservedObject private var configManager = MDMConfigurationManager.shared
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
            landOnAvailableDestination(config: configManager.configuration)
            if deepLinkRouter.pendingRequest != nil {
                handleDeepLinkNavigation()
            }
        }
        .onChange(of: session.capabilities) { _, _ in
            landOnAvailableDestination(config: configManager.configuration)
        }
        // A mid-session profile push can kill the module the user is sitting
        // on; move them off it rather than leaving them on Not Authorized.
        // The publisher carries the NEW configuration — @Published fires
        // before the property is stored, so don't re-read the manager here.
        .onReceive(configManager.$configuration) { configuration in
            landOnAvailableDestination(config: configuration)
        }
        .onChange(of: deepLinkRouter.pendingRequest) { oldValue, newValue in
            if newValue != nil {
                handleDeepLinkNavigation()
            }
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: Notification.Name("com.herojoneslabs.helios.console.deeplink"))) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                deepLinkRouter.checkForPendingDeepLink()
                if deepLinkRouter.pendingRequest != nil {
                    handleDeepLinkNavigation()
                }
            }
        }
    }
    
    /// The route the user can actually reach — `nil` when they can reach
    /// none, which is the real "nothing to show" condition: it accounts for
    /// the machine layer's kill switches and for granted module ids that have
    /// no route at all (e.g. `myDevice`), neither of which a bare
    /// "has any module" test can see.
    private var reachableDestination: NavigationDestination? {
        SidebarView.availableDestination(
            matching: selectedDestination,
            config: configManager.configuration,
            capabilities: session.capabilities
        )
    }

    /// The default selection is `.dashboard`, which a user's roles may not
    /// grant — move them to a row they can actually reach rather than opening
    /// on Not Authorized. Re-runs when capabilities change (sign-in, unlock)
    /// and when the configuration changes (profile push). Nothing reachable →
    /// nothing to land on; noModulesView covers that.
    private func landOnAvailableDestination(config: MDMConfiguration) {
        if let destination = SidebarView.availableDestination(
            matching: selectedDestination,
            config: config,
            capabilities: session.capabilities
        ), destination != selectedDestination {
            selectedDestination = destination
        }
    }

    /// Defense in depth: the sidebar already hides rows the user's roles
    /// don't grant, but EVERY route re-checks BOTH layers here — this
    /// codebase never lets enforcement live only in navigation visibility.
    @ViewBuilder
    private var mainContent: some View {
        if reachableDestination == nil {
            noModulesView
        } else {
            switch selectedDestination {
            case .dashboard:
                gated(.dashboard) {
                    DashboardContentView(
                        viewModel: viewModel,
                        isInNestedView: $isInNestedView,
                        initialDeviceCounts: initialDeviceCounts
                    )
                    .id(dashboardResetTrigger)
                }
            case .devices:
                gated(.devices) {
                    DevicesView(isInNestedView: $isInNestedView)
                        .environmentObject(deepLinkRouter)
                        .id(devicesResetTrigger)
                }
            case .announcements:
                gated(.announcements) { AnnouncementsView() }
            case .logs:
                gated(.logs) { LogsView() }
            case .reports:
                gated(.reports) { ReportsView() }
            case .enrollments:
                gated(.enrollments) { EnrollmentsView() }
            case .cleanup:
                gated(.cleanup) { CleanupView(isInNestedView: $isInNestedView) }
            case .settings:
                gated(.settings) { SettingsView() }
            }
        }
    }

    /// Renders `content` only when BOTH layers allow the route: the machine
    /// layer (this Mac's kill switches — SidebarView.machineAllows, the same
    /// predicate the sidebar prunes rows with) AND the user layer (the roles
    /// grant the module id). Either denial shows Not Authorized — a route
    /// reached without a click, e.g. by deep link, gets the same treatment.
    @ViewBuilder
    private func gated<Content: View>(
        _ destination: NavigationDestination,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if SidebarView.machineAllows(destination, config: configManager.configuration),
           session.capabilities.canAccess(module: destination.rawValue) {
            content()
        } else {
            notAuthorizedView(module: destination.title)
        }
    }

    private func notAuthorizedView(module: String) -> some View {
        emptyState(
            icon: "lock.shield",
            tint: .orange,
            title: "Not Authorized",
            subtitle: "\(module) is not available for your account."
        )
    }

    /// Shown when the user's roles grant no module at all — without it the
    /// window would render blank. Log Out stays available in the sidebar.
    private var noModulesView: some View {
        emptyState(
            icon: "square.dashed",
            tint: .orange,
            title: "Nothing to Show",
            subtitle: "No modules are available for your account.\nContact your administrator to request access."
        )
    }

    private func emptyState(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        ZStack {
            AnimatedBackgroundView(animate: .constant(true))

            VStack(spacing: 24) {

                ZStack {
                    Circle()
                        .fill(tint.opacity(0.1))
                        .frame(width: 120, height: 120)

                    Image(systemName: icon)
                        .font(.system(size: 48, weight: .medium))
                        .foregroundColor(tint.opacity(0.6))
                }

                VStack(spacing: 12) {
                    Text(title)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)

                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
