//
//  MyDevicesView.swift
//  HeliosConsole
//
//  The `myDevices` module: the signed-in person's own Macs, iPhones, iPads and
//  Vision Pros, with the facts they would otherwise open a ticket to ask for —
//  serial, OS version, last check-in, free space, encryption state, battery.
//
//  READ-ONLY. This view issues no action and renders no action control of its
//  own. Opening a device pushes the SAME detail views the Devices module uses,
//  which gate every action on the role's `computerActions` /
//  `mobileDeviceActions` grants — so an end-user role sees information and
//  nothing else, while an admin looking at their own Mac keeps whatever their
//  role already allows. One code path, one set of gates.
//
//  When the identity lookup finds nothing, the view falls back (config
//  permitting) to the Mac Helios is running on and SAYS SO — an unlabelled
//  fallback would read as "this is assigned to you", which it is not.
//

import SwiftUI

struct MyDevicesView: View {
    @Binding var isInNestedView: Bool

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var session = UserSession.shared
    @ObservedObject private var configManager = MDMConfigurationManager.shared
    @StateObject private var service = MyDevicesService()

    @State private var navigationPath = NavigationPath()
    @State private var loadingDeviceID: String?
    @State private var detailError: String?

    private var isDark: Bool { colorScheme == .dark }

    private var settings: FeaturesConfiguration.MyDevicesSettings {
        configManager.configuration.features?.effectiveMyDevices ?? .empty
    }

    /// The page title tracks the sidebar row's managed label, so an org that
    /// renames the row to "My Equipment" gets the same word in both places.
    private var title: String {
        let override = configManager.configuration.sidebarItems
            .first { $0.id == NavigationDestination.myDevices.rawValue }?
            .title
        let trimmed = override?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? NavigationDestination.myDevices.title : trimmed
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            content
                .navigationDestination(for: Computer.self) { computer in
                    DeviceView(computer: computer)
                }
                .navigationDestination(for: MobileDevice.self) { device in
                    MobileDeviceView(device: device)
                }
        }
        .onChange(of: navigationPath.count) { _, newValue in
            withAnimation(.easeInOut(duration: 0.2)) {
                isInNestedView = newValue > 0
            }
        }
        .onAppear {
            // The route can be re-entered with a stale nested flag (the sidebar
            // owns it, not this view) — same reset DevicesView performs.
            isInNestedView = navigationPath.count > 0
        }
        .task {
            // The machine layer can disable the module outright; don't spend a
            // Jamf round trip discovering that.
            guard settings.effectiveEnabled else { return }
            if service.origin == .idle {
                await service.load()
            }
        }
        // A different person signing in must never inherit the previous
        // operator's devices, even for one frame.
        .onChange(of: session.email) { _, _ in
            service.reset()
            navigationPath = NavigationPath()
            Task { await service.load() }
        }
    }

    private var content: some View {
        ZStack {
            AnimatedBackgroundView(animate: .constant(true))

            VStack(spacing: 0) {
                header

                if !settings.effectiveEnabled {
                    messageState(
                        icon: "square.dashed",
                        tint: .orange,
                        title: "Not Available",
                        message: "\(title) is turned off on this Mac."
                    )
                } else if service.isLoading && service.devices.isEmpty {
                    loadingState
                } else if service.devices.isEmpty {
                    emptyState
                } else {
                    deviceList
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(isDark ? .white : Color(red: 0.1, green: 0.1, blue: 0.15))

                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }

                Spacer()

                RefreshButton(isLoading: service.isLoading) {
                    Task { await service.load() }
                }
            }

            identityCard
        }
        .padding(.horizontal, 40)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }

    private var subtitle: String {
        switch service.origin {
        case .idle:
            return "Looking up the devices assigned to you…"
        case .assigned:
            let count = service.devices.count
            return count == 1 ? "1 device assigned to you" : "\(count) devices assigned to you"
        case .localDevice:
            return "No assigned devices found — showing this Mac"
        case .empty:
            return "No devices found for your account"
        }
    }

    /// Who Helios thinks you are. Present on every state because it is the
    /// first thing that explains an empty list: a person seeing their address
    /// here and no devices below knows to check the assignment in Jamf, not
    /// their sign-in.
    private var identityCard: some View {
        HStack(spacing: 14) {
            ProfileAvatarView(size: 44)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.displayName.isEmpty ? "Signed in" : session.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isDark ? .white : .primary)

                if !session.email.isEmpty {
                    Text(session.email)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }

                if !service.matchedUsernames.isEmpty {
                    Text("Jamf user: \(service.matchedUsernames.joined(separator: ", "))")
                        .font(.system(size: 11))
                        .foregroundColor(.gray.opacity(0.8))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - List

    private var deviceList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if service.origin == .localDevice {
                    noticeBanner(
                        icon: "desktopcomputer",
                        tint: .orange,
                        text: "Nothing in Jamf Pro is assigned to your account, so this is the Mac you are using right now. It may be assigned to someone else."
                    )
                }

                if let note = service.directoryLookupNote {
                    noticeBanner(icon: "info.circle", tint: .blue, text: note)
                }

                if let error = service.errorMessage {
                    noticeBanner(icon: "exclamationmark.triangle", tint: .red, text: error)
                }

                if let detailError {
                    noticeBanner(icon: "exclamationmark.triangle", tint: .red, text: detailError)
                }

                ForEach(service.devices) { device in
                    MyDeviceCard(
                        device: device,
                        isLoading: loadingDeviceID == device.id,
                        onOpen: { open(device) }
                    )
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 32)
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Finding your devices…")
                .font(.system(size: 14))
                .foregroundColor(.gray)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            if let error = service.errorMessage {
                messageState(
                    icon: "exclamationmark.triangle",
                    tint: .red,
                    title: "Couldn't Load Your Devices",
                    message: error
                )
            } else {
                messageState(
                    icon: "laptopcomputer.slash",
                    tint: .orange,
                    title: "No Devices Found",
                    message: noDevicesMessage
                )
            }

            if let note = service.directoryLookupNote {
                noticeBanner(icon: "info.circle", tint: .blue, text: note)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 32)
            }
        }
    }

    private var noDevicesMessage: String {
        var message = "Nothing in Jamf Pro is assigned to "
        message += session.email.isEmpty ? "your account" : session.email
        message += "."
        if settings.effectiveShowLocalDeviceFallback, LocalDeviceIdentity.serialNumber != nil {
            message += "\nThis Mac isn't enrolled under a record we can read either."
        }
        message += "\nContact your IT team if you believe this is wrong."
        return message
    }

    private func messageState(icon: String, tint: Color, title: String, message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(tint.opacity(0.1))
                    .frame(width: 110, height: 110)

                Image(systemName: icon)
                    .font(.system(size: 42, weight: .medium))
                    .foregroundColor(tint.opacity(0.7))
            }

            VStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(isDark ? .white : .primary)

                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func noticeBanner(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(tint)

            Text(text)
                .font(.system(size: 12))
                .foregroundColor(isDark ? .white.opacity(0.85) : .primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Navigation

    /// Macs push straight through (the list already carries the full
    /// inventory record). Mobile devices need one extra GET because the
    /// detail view takes the by-id shape, not the collection shape — the same
    /// two-step the Devices list performs.
    private func open(_ device: MyDevice) {
        detailError = nil

        switch device {
        case .computer(let computer):
            navigationPath.append(computer)
        case .mobileDevice(let item):
            loadingDeviceID = device.id
            Task {
                do {
                    let detail = try await service.mobileDeviceDetail(id: item.id)
                    loadingDeviceID = nil
                    navigationPath.append(detail)
                } catch {
                    loadingDeviceID = nil
                    detailError = "Couldn't open \(device.name): \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Device Card

/// One device, summarized. Deliberately richer than a list row: this is the
/// only place a non-admin sees their device, so the card carries the facts a
/// support call would otherwise ask for instead of making them open a detail
/// page to find a serial number.
struct MyDeviceCard: View {
    let device: MyDevice
    var isLoading: Bool = false
    let onOpen: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 16) {
                headerRow
                Divider().opacity(isDark ? 0.15 : 0.4)
                factGrid
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isDark
                          ? Color.white.opacity(isHovered ? 0.07 : 0.04)
                          : Color.white.opacity(isHovered ? 0.9 : 0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isDark
                            ? Color.white.opacity(isHovered ? 0.14 : 0.07)
                            : Color.black.opacity(isHovered ? 0.12 : 0.07), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 16) {
            ZStack {
                if isLoading {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(device.platform.color.opacity(0.1))
                        .frame(width: 56, height: 56)
                    ProgressView()
                        .controlSize(.small)
                        .tint(device.platform.color)
                } else {
                    DeviceIconView(
                        modelIdentifier: device.modelIdentifier,
                        modelName: device.modelName,
                        platform: device.platform,
                        size: 56
                    )
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(device.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isDark ? .white : .primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(device.modelName)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)

                    if device.isSupervised {
                        badge("Supervised", color: .blue)
                    }

                    badge(
                        device.isManaged ? "Managed" : "Unmanaged",
                        color: device.isManaged ? .green : .orange
                    )
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.gray.opacity(0.5))
        }
    }

    /// Fixed two-column layout rather than an adaptive grid: the fact count is
    /// small and known, and an adaptive grid reflows to one column at the
    /// window widths this app actually opens at.
    private var factGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), alignment: .topLeading),
                      GridItem(.flexible(), alignment: .topLeading)],
            alignment: .leading,
            spacing: 14
        ) {
            fact(icon: "number", label: "Serial Number", value: device.serialNumber ?? "Unknown")
            fact(
                icon: "gear",
                label: "Operating System",
                value: "\(device.platform.rawValue) \(device.osVersion ?? "Unknown")"
            )
            fact(
                icon: "clock.arrow.circlepath",
                label: "Last Check-in",
                value: lastCheckInText
            )
            fact(icon: "person", label: "Assigned To", value: device.assignedUser ?? "Unassigned")

            if let storage = device.storage {
                storageFact(storage)
            }

            if let encrypted = device.isEncrypted {
                fact(
                    icon: encrypted ? "lock.fill" : "lock.open",
                    label: encryptionLabel,
                    value: encrypted ? "On" : "Off",
                    tint: encrypted ? .green : .orange
                )
            }

            if let battery = device.batteryLevel {
                fact(
                    icon: "battery.100",
                    label: "Battery",
                    value: "\(battery)%",
                    tint: battery < 20 ? .orange : nil
                )
            }
        }
    }

    private var encryptionLabel: String {
        device.platform == .macOS ? "FileVault" : "Data Protection"
    }

    private var lastCheckInText: String {
        guard let date = device.lastCheckIn else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func fact(icon: String, label: String, value: String, tint: Color? = nil) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(tint ?? .gray)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.gray)

                Text(value)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(tint ?? (isDark ? .white.opacity(0.9) : .primary))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func storageFact(_ storage: (fraction: Double, summary: String)) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "internaldrive")
                .font(.system(size: 11))
                .foregroundColor(storage.fraction > 0.9 ? .orange : .gray)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 4) {
                Text("Storage")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.gray)

                Text(storage.summary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isDark ? .white.opacity(0.9) : .primary)

                ProgressView(value: min(max(storage.fraction, 0), 1))
                    .progressViewStyle(.linear)
                    .tint(storage.fraction > 0.9 ? .orange : .blue)
                    .frame(maxWidth: 160)
            }
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color))
    }
}
