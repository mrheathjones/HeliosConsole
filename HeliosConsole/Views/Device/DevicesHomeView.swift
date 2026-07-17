//
//  DevicesHomeView.swift
//  HeliosConsole
//
//  The Devices-route container. Wraps the existing DevicesView and adds a
//  role-gated tab strip above it: the app-defined base tab ("Devices") is
//  always present, and every additional tab id granted by the profile's
//  role definitions (UserCapabilities.deviceTabs, ORDERED) that this build
//  knows how to render is appended in the profile's order. Unknown granted
//  ids — tabs shipped by a later app version — are skipped, never errors.
//
//  When only the base tab is granted the strip does not render at all, so
//  unentitled users see zero visual change from the pre-tab Devices route.
//  The strip also hides while a device detail is pushed (isInNestedView),
//  and an incoming deep link forces the base tab so DevicesView's existing
//  deep-link consumption keeps working.
//

import SwiftUI

// MARK: - Devices Tabs

/// The tabs this build of the app knows how to render. `devices` is the
/// app-defined base tab and is never granted by profile — the base device
/// list is gated by the `devices` module, not by `deviceTabs`.
enum DevicesTab: String, CaseIterable, Identifiable {
    case devices
    case abmLookup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .devices: return "Devices"
        case .abmLookup: return "ABM Lookup"
        }
    }

    var icon: String {
        switch self {
        case .devices: return "laptopcomputer"
        case .abmLookup: return "apple.logo"
        }
    }
}

// MARK: - Devices Home View

struct DevicesHomeView: View {
    @Binding var isInNestedView: Bool
    @EnvironmentObject var deepLinkRouter: DeepLinkRouter

    /// Observed so the tab gates re-evaluate the moment a role change lands
    /// (sign-in, sign-out, profile push).
    @ObservedObject private var session = UserSession.shared

    @State private var selectedTab: DevicesTab = .devices

    /// Tabs the operator has actually opened this session. Content mounts
    /// lazily on FIRST selection, then stays mounted (hidden, not destroyed)
    /// so switching tabs never cancels an in-flight ABM sweep or resets a
    /// tab's search/filter/pagination state.
    @State private var activatedTabs: Set<DevicesTab> = [.devices]

    /// The base tab plus every profile-granted tab id that maps to a tab
    /// this build knows, preserving the profile's order. `compactMap` drops
    /// unknown ids; the filter keeps a profile that (incorrectly) lists the
    /// base tab from duplicating it.
    private var grantedTabs: [DevicesTab] {
        [.devices] + session.capabilities.deviceTabs
            .compactMap { DevicesTab(rawValue: $0) }
            .filter { $0 != .devices }
    }

    var body: some View {
        Group {
            if grantedTabs.count <= 1 {
                // Base tab only — render the existing container directly,
                // no strip, zero visual change for unentitled users.
                DevicesView(isInNestedView: $isInNestedView)
            } else {
                ZStack {
                    AnimatedBackgroundView(animate: .constant(true))

                    VStack(spacing: 0) {
                        if !isInNestedView {
                            tabStrip
                        }
                        tabContent
                    }
                }
            }
        }
        .onChange(of: selectedTab) { _, newValue in
            activatedTabs.insert(newValue)
        }
        .onChange(of: session.capabilities) { _, _ in
            // Fail closed: if a role change revokes the selected tab,
            // fall back to the always-granted base tab. Revoked tabs also
            // unmount (tabContent only keeps GRANTED activated tabs alive).
            if !grantedTabs.contains(selectedTab) {
                selectedTab = .devices
            }
            activatedTabs.formIntersection(Set(grantedTabs).union([.devices]))
        }
        .onChange(of: deepLinkRouter.pendingRequest) { _, newValue in
            // Deep links target the base device list — force it into the
            // hierarchy so DevicesView's existing consumption fires.
            if newValue != nil {
                selectedTab = .devices
            }
        }
    }

    // MARK: - Tab Strip

    private var tabStrip: some View {
        HStack(spacing: 8) {
            ForEach(grantedTabs) { tab in
                tabChip(for: tab)
            }
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.3))
    }

    private func tabChip(for tab: DevicesTab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11, weight: .medium))
                Text(tab.title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(selectedTab == tab ? .white : .gray)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(selectedTab == tab ? Color.accentColor : Color.white.opacity(0.05))
            )
            .overlay(
                Capsule()
                    .stroke(selectedTab == tab ? Color.accentColor : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab Content

    /// Every granted tab the operator has opened stays mounted in a ZStack
    /// with only the selected one visible/interactive. Destroying the hidden
    /// tab (the naive switch) would cancel ABMLookupView's in-flight org
    /// sweep and wipe both tabs' @State on every hop — the cross-checking
    /// workflow the tabs exist for.
    private var tabContent: some View {
        ZStack {
            ForEach(grantedTabs.filter { activatedTabs.contains($0) }) { tab in
                content(for: tab)
                    .opacity(selectedTab == tab ? 1 : 0)
                    .allowsHitTesting(selectedTab == tab)
                    .accessibilityHidden(selectedTab != tab)
                    .zIndex(selectedTab == tab ? 1 : 0)
            }
        }
    }

    @ViewBuilder
    private func content(for tab: DevicesTab) -> some View {
        switch tab {
        case .devices:
            DevicesView(isInNestedView: $isInNestedView)
        case .abmLookup:
            ABMLookupView()
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Devices Home") {
    @Previewable @State var isNested = false
    DevicesHomeView(isInNestedView: $isNested)
        .environmentObject(DeepLinkRouter())
        .frame(width: 1200, height: 800)
}
#endif
