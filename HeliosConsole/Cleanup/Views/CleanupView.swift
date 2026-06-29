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
    @State private var model = CleanupViewModel()
    @State private var showSettings = false

    var body: some View {
        ZStack {
            AppBackground()

            if model.settings.isConfigured {
                NavigationStack {
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
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                CleanupSettingsView()
            }
            .environment(model)
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
