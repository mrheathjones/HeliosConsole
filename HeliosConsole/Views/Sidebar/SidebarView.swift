//
//  SidebarView.swift
//  Helios
//
//  Sidebar navigation with view routing
//

import SwiftUI

// MARK: - Navigation Destination

enum NavigationDestination: String, CaseIterable, Identifiable {
    case dashboard = "dashboard"
    case devices = "devices"
    case announcements = "announcements"
    case logs = "logs"
    case reports = "reports"
    case enrollments = "enrollments"
    case cleanup = "cleanup"
    case settings = "settings"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .devices: return "Devices"
        case .announcements: return "Announcements"
        case .logs: return "Logs"
        case .reports: return "Reports"
        case .enrollments: return "Enrollments"
        case .cleanup: return "Cleanup"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .devices: return "desktopcomputer"
        case .announcements: return "megaphone"
        case .logs: return "doc.text.magnifyingglass"
        case .reports: return "chart.bar.doc.horizontal"
        case .enrollments: return "person.badge.plus"
        case .cleanup: return "wand.and.sparkles"
        case .settings: return "gearshape"
        }
    }
}

// MARK: - Sidebar View

struct SidebarView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Binding var selectedDestination: NavigationDestination
    @Binding var isInNestedView: Bool
    let onNavigate: (NavigationDestination) -> Void

    @Environment(\.colorScheme) private var colorScheme
    /// Observed so the module gates re-evaluate when capabilities land after
    /// sign-in (they are resolved post-login, not at view init).
    @ObservedObject private var session = UserSession.shared
    @State private var showLogoutModal = false
    
    private let sidebarWidth: CGFloat = 260
    
    private var isDark: Bool {
        colorScheme == .dark
    }
    
    var body: some View {
        ZStack {
            // Sidebar background
            sidebarBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                headerView
                navigationSection
            }
        }
        .frame(width: sidebarWidth)
        .frame(minWidth: sidebarWidth, maxWidth: sidebarWidth)
        .overlay {
            if showLogoutModal {
                LogoutConfirmationModal(
                    isPresented: $showLogoutModal,
                    sidebarWidth: sidebarWidth,
                    onConfirm: {
                        authViewModel.logout()
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showLogoutModal)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: colorScheme)
    }
    
    private var sidebarBackground: some View {
        Group {
            if isDark {
                Color(red: 0.05, green: 0.05, blue: 0.07)
            } else {
                Color(red: 0.95, green: 0.95, blue: 0.97)
            }
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack(spacing: 10) {
            BrandMark(size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(Branding.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isDark ? .white : .primary)

                if !Branding.subtitle.isEmpty {
                    Text(Branding.subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(isDark ? Color.black.opacity(0.2) : Color.black.opacity(0.03))
    }
    
    // MARK: - Navigation Section
    
    private var navigationSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Main navigation items (config-driven — see mainNavigationEntries)
            ForEach(mainNavigationEntries) { entry in
                SidebarNavigationItem(
                    destination: entry.destination,
                    isSelected: selectedDestination == entry.destination && !isInNestedView,
                    action: {
                        onNavigate(entry.destination)
                    },
                    titleOverride: entry.title,
                    iconOverride: entry.icon
                )
            }

            Spacer()

            // Divider
            Rectangle()
                .fill(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.08))
                .frame(height: 1)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            // Settings (ui domain showSettings switch)
            if showSettingsItem {
                SidebarNavigationItem(
                    destination: .settings,
                    isSelected: selectedDestination == .settings && !isInNestedView,
                    action: {
                        onNavigate(.settings)
                    }
                )
            }
            
            // Logout Button
            Button(action: {
                showLogoutModal = true
            }) {
                HStack(spacing: 14) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 14))
                        .foregroundColor(.red.opacity(0.9))
                        .frame(width: 24)
                    
                    Text("Log Out")
                        .foregroundColor(.red.opacity(0.9))
                        .font(.system(size: 14, weight: .medium))
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(isDark ? 0.05 : 0.08))
                )
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 12)
            .padding(.bottom, 20)
        }
        .padding(.top, 16)
    }
    
    /// One resolved sidebar row: destination plus the managed label/icon
    /// overrides from the ui domain's sidebarItems.
    private struct ResolvedSidebarEntry: Identifiable {
        let destination: NavigationDestination
        let title: String
        let icon: String
        var id: String { destination.id }
    }

    /// Sidebar contents are the INTERSECTION of two independent layers, both
    /// of which must allow a row (fail-closed — neither widens the other):
    ///
    ///   Machine layer — the ui domain's sidebarItems controls presence,
    ///     order, label, and icon (ids must be NavigationDestination raw
    ///     values; unknown ids are skipped), and the
    ///     showAnnouncements/showEnrollments/reports switches prune further.
    ///   User layer — the signed-in user's role modules must contain the
    ///     destination id. Cleanup is NOT special-cased any more: it is the
    ///     `cleanup` module id like every other row.
    ///
    /// Settings is pinned below the divider (gated the same way there).
    private var mainNavigationEntries: [ResolvedSidebarEntry] {
        Self.resolvedEntries(
            config: MDMConfigurationManager.shared.configuration,
            capabilities: session.capabilities
        )
    }

    /// The MACHINE-scoped half of a route's gate, in ONE place: the ui
    /// domain's sidebarItems presence/isEnabled plus the per-module kill
    /// switches (showAnnouncements / showEnrollments / features.reports, and
    /// showSettings for the pinned Settings row). Says nothing about the
    /// USER layer — intersect it with `capabilities.canAccess(module:)`.
    ///
    /// Shared by the sidebar rows, `availableDestination(matching:config:capabilities:)`
    /// and DashboardView's route gate, so a module killed on this Mac can
    /// never stay reachable through a route that skipped one of the
    /// conditions (deep links set the destination directly).
    static func machineAllows(_ destination: NavigationDestination, config: MDMConfiguration) -> Bool {
        let ui = config.userInterfaceExtras
        switch destination {
        case .settings:
            // Pinned below the divider — deliberately not a sidebarItems
            // entry, so presence there is not part of its rule.
            return ui?.effectiveShowSettings ?? true
        case .announcements where ui?.effectiveShowAnnouncements == false:
            return false
        case .enrollments where ui?.effectiveShowEnrollments == false:
            return false
        case .reports where config.features?.effectiveReports.effectiveEnabled == false:
            return false // features domain: reports module disabled
        default:
            break
        }
        return config.sidebarItems.contains { $0.id == destination.rawValue && $0.isEnabled }
    }

    /// Shared with `availableDestination(matching:config:capabilities:)` so the
    /// rows a user can click and the route the app lands on can never disagree.
    private static func resolvedEntries(
        config: MDMConfiguration,
        capabilities: UserCapabilities
    ) -> [ResolvedSidebarEntry] {
        var entries: [ResolvedSidebarEntry] = []
        // Stable: `config.sidebarItems` already arrives ordered (managed items
        // by order-then-delivered-position, defaults by their explicit order).
        // A plain sorted(by:) here would re-scramble equal `order` values,
        // undoing the arrangement the config layer just resolved.
        let ordered = config.sidebarItems
            .enumerated()
            .sorted { ($0.element.order, $0.offset) < ($1.element.order, $1.offset) }
            .map(\.element)
        for item in ordered where item.isEnabled {
            guard let destination = NavigationDestination(rawValue: item.id) else {
                print("⚠️ ui: sidebarItems id '\(item.id)' does not match any view — skipped")
                continue
            }
            guard destination != .settings else { continue } // pinned below the divider
            guard machineAllows(destination, config: config) else { continue }
            guard capabilities.canAccess(module: destination.rawValue) else { continue }
            guard !entries.contains(where: { $0.destination == destination }) else { continue }
            entries.append(ResolvedSidebarEntry(
                destination: destination,
                title: item.title.isEmpty ? destination.title : item.title,
                icon: item.icon.isEmpty ? destination.icon : item.icon
            ))
        }
        return entries
    }

    /// ui domain showSettings switch (default true) INTERSECTED with the
    /// user's `settings` module grant. Log Out lives outside this gate — it
    /// must stay reachable for a user with no modules at all.
    private var showSettingsItem: Bool {
        Self.showsSettings(
            config: MDMConfigurationManager.shared.configuration,
            capabilities: session.capabilities
        )
    }

    private static func showsSettings(
        config: MDMConfiguration,
        capabilities: UserCapabilities
    ) -> Bool {
        machineAllows(.settings, config: config)
            && capabilities.canAccess(module: NavigationDestination.settings.rawValue)
    }

    /// `current` when the user can still reach it, otherwise the first row they
    /// can reach (nil when they can reach none). Callers use this to land a user
    /// somewhere real instead of stranding them on a route their roles don't
    /// grant — the default selection cannot know what a given user is allowed.
    static func availableDestination(
        matching current: NavigationDestination,
        config: MDMConfiguration,
        capabilities: UserCapabilities
    ) -> NavigationDestination? {
        if current == .settings, showsSettings(config: config, capabilities: capabilities) {
            return .settings
        }
        let entries = resolvedEntries(config: config, capabilities: capabilities)
        if entries.contains(where: { $0.destination == current }) { return current }
        if let first = entries.first { return first.destination }
        return showsSettings(config: config, capabilities: capabilities) ? .settings : nil
    }
}

// MARK: - Sidebar Navigation Item

struct SidebarNavigationItem: View {
    let destination: NavigationDestination
    let isSelected: Bool
    let action: () -> Void
    /// Managed label/icon overrides from the ui domain's sidebarItems.
    var titleOverride: String? = nil
    var iconOverride: String? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered: Bool = false

    private var isDark: Bool {
        colorScheme == .dark
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: iconOverride ?? destination.icon)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .blue : .gray)
                    .frame(width: 24)

                Text(titleOverride ?? destination.title)
                    .foregroundColor(isSelected ? (isDark ? .white : .primary) : .gray)
                    .font(.system(size: 14, weight: isSelected ? .medium : .regular))
                
                Spacer()
                
                if isSelected {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 12)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return Color.blue.opacity(isDark ? 0.15 : 0.12)
        } else if isHovered {
            return isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.04)
        }
        return Color.clear
    }
}

// MARK: - Logout Confirmation Modal

struct LogoutConfirmationModal: View {
    @Binding var isPresented: Bool
    let sidebarWidth: CGFloat
    let onConfirm: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool {
        colorScheme == .dark
    }
    
    private var modalWidth: CGFloat {
        sidebarWidth - 32
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(isDark ? 0.6 : 0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }
            
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.1))
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.red)
                }
                
                VStack(spacing: 8) {
                    Text("Log Out")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(isDark ? .white : .primary)
                    
                    Text("Are you sure you want to log out of \(Branding.productName)?")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                VStack(spacing: 10) {
                    Button(action: {
                        isPresented = false
                        onConfirm()
                    }) {
                        Text("Log Out")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(Color.red)
                            .cornerRadius(8)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    
                    Button(action: {
                        isPresented = false
                    }) {
                        Text("Cancel")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(isDark ? .white : .primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1), lineWidth: 1)
                            )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(24)
            .frame(width: modalWidth)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isDark ? Color(white: 0.1) : Color.white)
                    .shadow(color: Color.black.opacity(isDark ? 0.5 : 0.2), radius: 30, x: 0, y: 15)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.1), lineWidth: 1)
            )
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Sidebar - Dark") {
    @Previewable @State var selected: NavigationDestination = .dashboard
    @Previewable @State var isNested: Bool = false
    HStack(spacing: 0) {
        SidebarView(
            selectedDestination: $selected,
            isInNestedView: $isNested,
            onNavigate: { _ in }
        )
        .environmentObject(AuthViewModel())
        
        Rectangle()
            .fill(Color(white: 0.12))
    }
    .frame(width: 800, height: 600)
    .preferredColorScheme(.dark)
}

#Preview("Sidebar - Light") {
    @Previewable @State var selected: NavigationDestination = .dashboard
    @Previewable @State var isNested: Bool = false
    HStack(spacing: 0) {
        SidebarView(
            selectedDestination: $selected,
            isInNestedView: $isNested,
            onNavigate: { _ in }
        )
        .environmentObject(AuthViewModel())
        
        Rectangle()
            .fill(Color(white: 0.95))
    }
    .frame(width: 800, height: 600)
    .preferredColorScheme(.light)
}
#endif
