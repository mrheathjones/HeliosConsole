//
//  CleanupView.swift
//  HeliosConsole
//
//  Entry point for the Cleanup feature (Jamf stale-device cleanup),
//  hosted in Helios's main content area. Owns the CleanupViewModel and
//  provides internal navigation from dashboard cards to filtered lists.
//

import SwiftUI

struct CleanupView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Binding var isInNestedView: Bool
    @State private var model = CleanupViewModel()
    @State private var showSettings = false
    @State private var navigationPath = NavigationPath()

    var body: some View {
        ZStack {
            // Match Helios's native content background (animated gradient orbs).
            AnimatedBackgroundView(animate: .constant(true))

            if model.settings.isConfigured {
                NavigationStack(path: $navigationPath) {
                    CleanupDashboardView(showSettings: $showSettings)
                        .navigationDestination(for: DeviceFilter.self) { filter in
                            StaleDeviceListView(filter: filter)
                        }
                        .navigationDestination(for: ProtectFilter.self) { filter in
                            ProtectDeviceListView(filter: filter)
                        }
                }
                .background(.clear)
            } else {
                notConfigured
            }
        }
        .environment(model)
        // Hide the sidebar while a filtered list is open, like the main app.
        .onChange(of: navigationPath.count) { _, newValue in
            withAnimation(.easeInOut(duration: 0.2)) {
                isInNestedView = newValue > 0
            }
        }
        .onAppear { isInNestedView = false }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                CleanupSettingsView()
            }
            .environment(model)
        }
        // Release Jamf/Protect tokens server-side when leaving cleanup or
        // backgrounding the app (abandoned tokens hold a Jamf DB connection).
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                Task { await model.invalidateSessions() }
            }
        }
        .onDisappear {
            Task { await model.invalidateSessions() }
        }
    }

    private var notConfigured: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkles")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            Text("Cleanup")
                .font(.largeTitle.bold())

            Text("Find devices that have gone quiet in Jamf Pro — then unmanage, regroup, re-site, or delete them in bulk.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            Text("Cleanup uses Helios's Jamf Pro master API client. Configure it in your MDM configuration profile.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .glassCard()
        .padding(40)
    }
}
