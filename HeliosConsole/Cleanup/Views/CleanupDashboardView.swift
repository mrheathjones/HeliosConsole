//
//  CleanupDashboardView.swift
//  HeliosConsole
//
//  Cleanup landing page: fleet-health metrics. Every card navigates to a
//  filtered device list. Ported from Clean Slate's DashboardView.
//

import SwiftUI

struct CleanupDashboardView: View {
    @Environment(CleanupViewModel.self) private var model
    @AppStorage("dashboard.cleanupSitesExpanded") private var sitesExpanded = true
    /// 0 = unset → use the MDM profile's default (config = default, user-overridable).
    @AppStorage(CleanupSettings.Key.staleDays) private var staleDaysStored = 0

    /// The stale threshold actually in effect: the user's in-app choice if set,
    /// otherwise the config-profile default.
    private var effectiveStaleDays: Int {
        staleDaysStored > 0 ? staleDaysStored : MDMConfigurationManager.shared.configuration.cleanupStaleDays
    }

    /// Dropdown options — the common presets plus the current/MDM value so it's
    /// always selectable even if it isn't a preset.
    private var staleDayOptions: [Int] {
        Array(Set([7, 14, 30, 45, 60, 90, 120, 180, 365, effectiveStaleDays]))
            .filter { $0 > 0 }
            .sorted()
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 190, maximum: 280), spacing: 14)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerBar

                if let error = model.loadError, model.devices.isEmpty {
                    errorCard(error)
                }

                LazyVGrid(columns: columns, spacing: 14) {
                    MetricCard(
                        title: "Total Computers",
                        value: model.totalComputers.map(String.init) ?? "—",
                        caption: "in Jamf Pro",
                        icon: "desktopcomputer",
                        color: .blue,
                        link: DeviceFilter.allStale
                    )
                    MetricCard(
                        title: "Stale Devices",
                        value: String(model.managedStale.count),
                        caption: "managed, quiet \(model.settings.staleDays)+ days",
                        icon: "clock.badge.exclamationmark",
                        color: .orange,
                        link: DeviceFilter.allStale
                    )
                    MetricCard(
                        title: "Stale Over 1 Year",
                        value: String(model.staleOverYearCount),
                        caption: "managed, silent 365+ days",
                        icon: "exclamationmark.octagon",
                        color: .red,
                        link: DeviceFilter.overOneYear
                    )
                    MetricCard(
                        title: "Unmanaged",
                        value: String(model.unmanagedStaleCount),
                        caption: "stale records already unmanaged",
                        icon: "antenna.radiowaves.left.and.right.slash",
                        color: .purple,
                        link: DeviceFilter.unmanaged
                    )
                    if let top = model.topStaleSite {
                        MetricCard(
                            title: "Most Stale Site",
                            value: top.name,
                            caption: "\(top.count) stale devices",
                            icon: "building.2",
                            color: .teal,
                            link: DeviceFilter.site(top.name),
                            valueIsText: true
                        )
                    }
                }

                if !model.staleBySite.isEmpty {
                    siteBreakdown
                }

                if model.settings.isProtectConfigured {
                    protectSection
                }

                if let lastRefresh = model.lastRefresh {
                    Text("Updated \(lastRefresh.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
        .overlay {
            if model.isLoading && model.devices.isEmpty && model.loadError == nil {
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large)
                    Text("Surveying the fleet…")
                        .foregroundStyle(.secondary)
                }
                .glassCard()
            }
        }
        .task {
            if model.devices.isEmpty {
                await model.refresh()
            }
        }
        .refreshable {
            await model.refresh()
        }
    }

    // MARK: - Site breakdown

    private var siteBreakdown: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.snappy) { sitesExpanded.toggle() }
            } label: {
                HStack {
                    Label("Stale by Site", systemImage: "building.2.crop.circle")
                        .font(.headline)
                    Spacer()
                    Text("\(model.staleBySite.count) sites")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(sitesExpanded ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if sitesExpanded {
                ForEach(model.staleBySite) { site in
                    NavigationLink(value: DeviceFilter.site(site.name)) {
                        HStack {
                            Text(site.name)
                            Spacer()
                            Text("\(site.count)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)

                    if site.id != model.staleBySite.last?.id {
                        Divider()
                    }
                }
                .padding(.top, 6)
            }
        }
        .glassCard()
    }

    // MARK: - Jamf Protect section

    private var protectSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Jamf Protect", systemImage: "shield.lefthalf.filled")
                .font(.headline)

            if let error = model.protectError {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.callout)
                    Spacer()
                }
                .glassCard()
            }

            LazyVGrid(columns: columns, spacing: 14) {
                MetricCard(
                    title: "Protect Computers",
                    value: model.protectLoaded ? String(model.protectDevices.count) : "—",
                    caption: "records in Jamf Protect",
                    icon: "shield",
                    color: .indigo,
                    link: ProtectFilter.all
                )
                MetricCard(
                    title: "Protect Stale",
                    value: model.protectLoaded ? String(model.protectStaleDevices.count) : "—",
                    caption: "no check-in for \(model.settings.staleDays)+ days",
                    icon: "shield.slash",
                    color: .pink,
                    link: ProtectFilter.stale
                )
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
            Spacer()
            Button("Retry") { Task { await model.refresh() } }
                .buttonStyle(.bordered)
        }
        .glassCard()
    }

    // MARK: - Inline header (actions live in the content, top-right — Helios's
    // window has no nav toolbar, so SwiftUI .toolbar items would land over the
    // sidebar/traffic-lights).

    private var headerBar: some View {
        HStack(spacing: 10) {
            Text("Cleanup")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)

            Spacer()

            staleDaysMenu

            headerIconButton("arrow.clockwise", help: "Refresh", disabled: model.isLoading) {
                Task { await model.refresh() }
            }
        }
    }

    private func headerIconButton(
        _ systemName: String,
        help: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 32, height: 32)
                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .help(help)
    }

    private var staleDaysMenu: some View {
        Menu {
            Picker("Stale after", selection: Binding(
                get: { effectiveStaleDays },
                set: { staleDaysStored = $0 }
            )) {
                ForEach(staleDayOptions, id: \.self) { days in
                    Text("\(days) days").tag(days)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "clock.badge.questionmark")
                Text("Stale: \(effectiveStaleDays)d")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(Color.white.opacity(0.1)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onChange(of: staleDaysStored) {
            Task { await model.refresh() }
        }
        .help("Devices with no Jamf check-in for this many days are stale. Default comes from your MDM profile; change it here anytime.")
    }
}

// MARK: - Metric card

private struct MetricCard<Destination: Hashable>: View {
    let title: String
    let value: String
    let caption: String
    let icon: String
    let color: Color
    let link: Destination
    var valueIsText = false

    var body: some View {
        NavigationLink(value: link) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(color)
                        .frame(width: 30, height: 30)
                        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Text(value)
                    .font(valueIsText ? .title3.bold() : .system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassCard()
    }
}
