//
//  SettingsView.swift
//  test
//
//  Created by heath on 1/21/26.
//


//
//  SettingsView.swift
//  Helios
//
//  Comprehensive settings view for app preferences
//

import SwiftUI
import AppKit
import LocalAuthentication
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    /// Observed so the Cleanup section re-evaluates when capabilities land
    /// after sign-in.
    @ObservedObject private var session = UserSession.shared
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var showingResetAlert = false
    @State private var biometricTestResult: String?
    @State private var showBiometricResult = false

    // Cleanup settings — folded in from the former standalone Cleanup Settings
    // sheet. These bind to the exact same keys the Cleanup feature reads, so
    // there is no data migration.
    @AppStorage(CleanupSettings.Key.staleDays) private var cleanupStaleDaysStored = 0
    @AppStorage(CleanupSettings.Key.protectEnabled) private var cleanupProtectEnabled = false
    @AppStorage(CleanupSettings.Key.protectURL) private var cleanupProtectURL = ""
    @AppStorage(CleanupSettings.Key.protectClientID) private var cleanupProtectClientID = ""
    @AppStorage(CleanupSettings.Key.protectAutoCleanup) private var cleanupProtectAutoCleanup = false
    @State private var cleanupProtectPassword = ""
    @State private var cleanupJamfTestResult: String?
    @State private var cleanupJamfTestOK = false
    @State private var cleanupProtectTestResult: String?
    @State private var cleanupProtectTestOK = false
    @State private var cleanupTesting = false
    private let cleanupSettings = CleanupSettings()

    private var isDark: Bool {
        colorScheme == .dark
    }

    private var cleanupEffectiveStaleDays: Int {
        cleanupStaleDaysStored > 0 ? cleanupStaleDaysStored : MDMConfigurationManager.shared.configuration.cleanupStaleDays
    }

    private var cleanupClientIDDisplay: String {
        let id = cleanupSettings.jamfClientID
        guard !id.isEmpty, id != "your-master-client-id" else { return "Not configured" }
        return String(id.prefix(8)) + "…"
    }
    
    var body: some View {
        ZStack {
            AnimatedBackgroundView(animate: .constant(true))
            
            VStack(spacing: 0) {
                // Header
                headerSection
                
                // Content
                ScrollView {
                    VStack(spacing: 24) {
                        profileSection
                        appearanceSection
                        displaySection
                        if session.capabilities.canAccess(module: NavigationDestination.cleanup.rawValue) {
                            cleanupSection
                        }
                        aboutSection
                    }
                    .padding(32)
                }
            }
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(isDark ? .white : .primary)
                
                Text("Configure \(Branding.productName) preferences")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Button {
                showingResetAlert = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12))
                    Text("Reset to Defaults")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .alert("Reset Settings", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    withAnimation {
                        settings.resetToDefaults()
                    }
                }
            } message: {
                Text("This will reset all settings to their default values. This action cannot be undone.")
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 24)
        .padding(.bottom, 24)
    }
    
    // MARK: - Appearance Section
    
    private var appearanceSection: some View {
        settingsCard(title: "Appearance", icon: "paintbrush.fill", iconColor: .purple) {
            VStack(alignment: .leading, spacing: 20) {
                // Description
                Text("Choose how Helios Console appears. Select a theme or follow your system's appearance settings.")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
                    .padding(.bottom, 4)
                
                // Appearance mode picker
                HStack(spacing: 12) {
                    ForEach(AppearanceMode.allCases) { mode in
                        appearanceModeButton(mode)
                    }
                }
                
                Divider()
                    .background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                
                // Preview
                VStack(alignment: .leading, spacing: 12) {
                    Text("Preview")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.gray)
                        .textCase(.uppercase)
                    
                    appearancePreview
                }
            }
        }
    }
    
    private func appearanceModeButton(_ mode: AppearanceMode) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                settings.appearanceMode = mode
            }
        } label: {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(settings.appearanceMode == mode
                              ? Color.blue.opacity(0.15)
                              : (isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.05)))
                        .frame(width: 80, height: 60)
                    
                    Image(systemName: mode.icon)
                        .font(.system(size: 24))
                        .foregroundColor(settings.appearanceMode == mode ? .blue : .gray)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(settings.appearanceMode == mode ? Color.blue : Color.clear, lineWidth: 2)
                )
                
                Text(mode.title)
                    .font(.system(size: 12, weight: settings.appearanceMode == mode ? .semibold : .regular))
                    .foregroundColor(settings.appearanceMode == mode ? .blue : (isDark ? .white : .primary))
            }
        }
        .buttonStyle(.plain)
    }
    
    private var appearancePreview: some View {
        HStack(spacing: 16) {
            // Light preview
            previewCard(isDarkPreview: false, label: "Light")
            
            // Dark preview
            previewCard(isDarkPreview: true, label: "Dark")
        }
    }
    
    private func previewCard(isDarkPreview: Bool, label: String) -> some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isDarkPreview ? Color(white: 0.1) : Color(white: 0.95))
                    .frame(height: 80)
                
                VStack(spacing: 6) {
                    // Mini sidebar + content layout
                    HStack(spacing: 4) {
                        // Sidebar
                        RoundedRectangle(cornerRadius: 2)
                            .fill(isDarkPreview ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                            .frame(width: 30)
                        
                        // Content area
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(isDarkPreview ? Color.blue.opacity(0.3) : Color.blue.opacity(0.2))
                                .frame(height: 20)
                            
                            HStack(spacing: 3) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(isDarkPreview ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(isDarkPreview ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                            }
                            .frame(height: 30)
                        }
                    }
                    .padding(8)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isDarkPreview ? Color.white.opacity(0.1) : Color.black.opacity(0.1), lineWidth: 1)
            )
            
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Profile Section

    private var signInMethod: MDMConfiguration.SignInMethod {
        MDMConfigurationManager.shared.configuration.signInMethod
    }

    /// Custom photo wins, then the Entra directory photo, then initials.
    private var resolvedProfilePicture: NSImage? {
        settings.customProfilePicture ?? session.profilePhoto
    }

    private var profileSection: some View {
        settingsCard(title: "Profile", icon: "person.crop.circle.fill", iconColor: .blue) {
            VStack(alignment: .leading, spacing: 20) {
                // Identity
                HStack(spacing: 16) {
                    profileAvatar

                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.displayName.isEmpty ? "Signed-in user" : session.displayName)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(isDark ? .white : .primary)

                        if !session.email.isEmpty {
                            Text(session.email)
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                                .textSelection(.enabled)
                        }

                        HStack(spacing: 5) {
                            Image(systemName: signInMethod == .entra ? "person.badge.key.fill" : "envelope.fill")
                                .font(.system(size: 10))
                            Text(signInMethod == .entra ? "Microsoft Entra ID" : "Email sign-in")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                    }

                    Spacer()
                }

                // Photo selector
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Button {
                            chooseProfilePicture()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "photo")
                                    .font(.system(size: 12))
                                Text("Choose Photo…")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(.blue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)

                        if settings.customProfilePicture != nil {
                            Button {
                                withAnimation { settings.customProfilePicture = nil }
                            } label: {
                                Text(session.profilePhoto != nil ? "Use Microsoft Photo" : "Remove Photo")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Color.orange.opacity(0.1))
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text(profilePictureCaption)
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }

                Divider()
                    .background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))

                // Role(s) — resolved from the profile's role definitions
                VStack(alignment: .leading, spacing: 10) {
                    groupHeader(session.roles.count == 1 ? "Role" : "Roles")

                    if session.roles.isEmpty {
                        Text("No role assigned — contact your admin about Helios role assignment.")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    } else {
                        HStack(spacing: 8) {
                            ForEach(session.roles, id: \.self) { role in
                                HStack(spacing: 5) {
                                    Image(systemName: "person.badge.shield.checkmark.fill")
                                        .font(.system(size: 10))
                                    Text(role)
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(.green)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                    }
                }

                Divider()
                    .background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))

                // Security — lives inside Profile since it's about how THIS
                // operator unlocks the app.
                VStack(alignment: .leading, spacing: 16) {
                    groupHeader("Security")
                    securityContent
                }
            }
        }
    }

    private var profilePictureCaption: String {
        if settings.customProfilePicture != nil {
            return "Using a custom photo stored on this Mac."
        }
        if session.profilePhoto != nil {
            return "Using your Microsoft directory photo. Choose a photo to override it on this Mac."
        }
        return "Using your initials. Choose a photo to personalize your profile."
    }

    private var profileAvatar: some View {
        ZStack {
            if let image = resolvedProfilePicture {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)

                Text(profileInitials)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .overlay(
            Circle()
                .stroke(isDark ? Color.white.opacity(0.15) : Color.black.opacity(0.1), lineWidth: 1)
        )
    }

    private var profileInitials: String {
        let initials = session.displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        if !initials.isEmpty {
            return String(initials).uppercased()
        }
        if let first = session.email.first {
            return String(first).uppercased()
        }
        return "?"
    }

    private func chooseProfilePicture() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a profile picture"
        panel.prompt = "Use Photo"
        guard panel.runModal() == .OK,
              let url = panel.url,
              let image = NSImage(contentsOf: url) else { return }
        settings.customProfilePicture = image
    }

    // MARK: - Security (inside Profile)

    private var securityContent: some View {
        VStack(alignment: .leading, spacing: 20) {
                // Biometrics toggle
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(settings.biometricsAvailable ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: settings.biometricIcon)
                            .font(.system(size: 20))
                            .foregroundColor(settings.biometricsAvailable ? .green : .gray)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(settings.biometricsAvailable ? settings.biometricTypeName : "Biometric Authentication")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(isDark ? .white : .primary)
                        
                        Text(settings.biometricsAvailable
                             ? "Use \(settings.biometricTypeName) to unlock the app"
                             : "No biometric authentication available on this device")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    if settings.biometricsAvailable {
                        Toggle("", isOn: $settings.biometricsEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    } else {
                        Text("Unavailable")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.gray)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(6)
                    }
                }
                
                if settings.biometricsAvailable && settings.biometricsEnabled {
                    Divider()
                        .background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                    
                    // Test biometrics button
                    Button {
                        testBiometrics()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.shield")
                                .font(.system(size: 14))
                            Text("Test \(settings.biometricTypeName)")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    
                    if showBiometricResult, let result = biometricTestResult {
                        HStack(spacing: 8) {
                            Image(systemName: result.contains("Success") ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(result.contains("Success") ? .green : .red)
                            Text(result)
                                .font(.system(size: 12))
                                .foregroundColor(result.contains("Success") ? .green : .red)
                        }
                        .padding(12)
                        .background((result.contains("Success") ? Color.green : Color.red).opacity(0.1))
                        .cornerRadius(8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                
                // Security info
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)

                    Text("Biometric data is stored securely on your device and never leaves it.")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
                .padding(.top, 4)
        }
    }

    private func testBiometrics() {
        settings.authenticateWithBiometrics(reason: "Test biometric authentication") { success, error in
            withAnimation {
                if success {
                    biometricTestResult = "Success! \(settings.biometricTypeName) is working correctly."
                } else if let error = error {
                    biometricTestResult = "Failed: \(error.localizedDescription)"
                } else {
                    biometricTestResult = "Authentication was cancelled."
                }
                showBiometricResult = true
                
                // Hide result after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation {
                        showBiometricResult = false
                    }
                }
            }
        }
    }
    
    // MARK: - Display Section
    
    private var displaySection: some View {
        settingsCard(title: "Display", icon: "slider.horizontal.3", iconColor: .orange) {
            VStack(alignment: .leading, spacing: 20) {
                // Show device icons toggle
                settingsToggleRow(
                    icon: "desktopcomputer",
                    iconColor: .blue,
                    title: "Show Device Icons",
                    subtitle: "Display system icons for Mac devices based on model",
                    isOn: $settings.showDeviceIcons
                )
                
                Divider()
                    .background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                
                // Default items per page
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.purple.opacity(0.1))
                                .frame(width: 36, height: 36)
                            
                            Image(systemName: "list.number")
                                .font(.system(size: 16))
                                .foregroundColor(.purple)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Items Per Page")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(isDark ? .white : .primary)
                            
                            Text("Default number of items shown in device lists")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Picker("Items per page", selection: $settings.defaultItemsPerPage) {
                        Text("10").tag(10)
                        Text("25").tag(25)
                        Text("50").tag(50)
                        Text("100").tag(100)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 300)
                }
                
                Divider()
                    .background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                
                // Auto refresh interval
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.cyan.opacity(0.1))
                                .frame(width: 36, height: 36)
                            
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16))
                                .foregroundColor(.cyan)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto Refresh")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(isDark ? .white : .primary)
                            
                            Text("Automatically refresh dashboard data")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Picker("Auto refresh", selection: $settings.autoRefreshInterval) {
                        Text("Off").tag(0)
                        Text("1 min").tag(60)
                        Text("5 min").tag(300)
                        Text("15 min").tag(900)
                        Text("30 min").tag(1800)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 400)
                }
            }
        }
    }
    
    private func settingsToggleRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.1))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isDark ? .white : .primary)
                
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
    
    // MARK: - About Section
    
    private var aboutSection: some View {
        settingsCard(title: "About", icon: "info.circle.fill", iconColor: .blue) {
            VStack(alignment: .leading, spacing: 16) {
                // App info
                HStack(spacing: 16) {
                    BrandMark(size: 64)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(Branding.productName)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(isDark ? .white : .primary)

                        Text(appVersionString)
                            .font(.system(size: 13))
                            .foregroundColor(.gray)

                        Text("macOS Device Management")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                }
                
                Divider()
                    .background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                
                // Links — each row only renders when the ui domain
                // delivers its destination URL (dead buttons help no one).
                VStack(spacing: 12) {
                    if let url = Branding.documentationURL {
                        aboutLinkRow(icon: "book.fill", title: "Documentation", color: .blue, url: url)
                    }
                    if let url = Branding.supportURL {
                        aboutLinkRow(icon: "questionmark.circle.fill", title: "Help & Support", color: .green, url: url)
                    }
                    if let url = Branding.feedbackURL {
                        aboutLinkRow(icon: "exclamationmark.bubble.fill", title: "Report an Issue", color: .orange, url: url)
                    }
                }

                Divider()
                    .background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))

                // Copyright (ui domain footerText, or composed default)
                Text(Branding.footerText)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
        }
    }
    
    /// Real product version from the bundle — never a hard-coded string.
    private var appVersionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "Version \(version) (Build \(build))"
    }

    private func aboutLinkRow(icon: String, title: String, color: Color, url: URL) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
                    .frame(width: 24)
                
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(isDark ? .white : .primary)
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.gray)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Cleanup Section

    private var cleanupSection: some View {
        settingsCard(title: "Cleanup", icon: "trash.circle.fill", iconColor: .teal) {
            VStack(alignment: .leading, spacing: 20) {
                // Jamf Pro (MDM-supplied, read-only)
                VStack(alignment: .leading, spacing: 10) {
                    groupHeader("Jamf Pro")
                    cleanupInfoRow(label: "Server URL", value: cleanupSettings.normalizedJamfURL?.absoluteString ?? "Not configured")
                    cleanupInfoRow(label: "API Client", value: cleanupClientIDDisplay)
                    HStack(spacing: 10) {
                        cleanupTestButton { testCleanupJamf() }
                            .disabled(cleanupTesting || !cleanupSettings.isConfigured)
                        if cleanupTesting { ProgressView().controlSize(.small) }
                        if let r = cleanupJamfTestResult { cleanupResultLabel(r, ok: cleanupJamfTestOK) }
                    }
                    Text("Supplied by your Helios MDM configuration profile (the master API client).")
                        .font(.system(size: 11)).foregroundColor(.gray)
                }

                Divider().background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))

                // Stale threshold
                VStack(alignment: .leading, spacing: 8) {
                    groupHeader("Stale Threshold")
                    Stepper(value: Binding(get: { cleanupEffectiveStaleDays }, set: { cleanupStaleDaysStored = $0 }), in: 1...730) {
                        HStack {
                            Text("Stale after").font(.system(size: 14, weight: .medium)).foregroundColor(isDark ? .white : .primary)
                            Spacer()
                            Text("\(cleanupEffectiveStaleDays) days").font(.system(size: 14)).foregroundColor(.gray)
                        }
                    }
                    Text("Devices with no Jamf Pro check-in for this many days are considered stale.")
                        .font(.system(size: 11)).foregroundColor(.gray)
                }

                Divider().background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))

                // Jamf Protect
                VStack(alignment: .leading, spacing: 12) {
                    settingsToggleRow(icon: "shield.lefthalf.filled", iconColor: .indigo, title: "Use Jamf Protect", subtitle: "Show Protect counts and delete Protect records", isOn: $cleanupProtectEnabled)
                    if cleanupProtectEnabled {
                        cleanupTextField(title: "Tenant URL", text: $cleanupProtectURL, prompt: "https://yourorg.protect.jamfcloud.com")
                        cleanupTextField(title: "API Client ID", text: $cleanupProtectClientID, prompt: "Client ID")
                        if cleanupSettings.protectPasswordIsManaged {
                            cleanupInfoRow(label: "API Client Password", value: "Delivered by MDM")
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("API Client Password").font(.system(size: 12)).foregroundColor(.gray)
                                SecureField(cleanupSettings.protectClientPassword.isEmpty ? "Paste password" : "•••••••• (saved)", text: $cleanupProtectPassword)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 13))
                                    .padding(10)
                                    .background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                                    .cornerRadius(8)
                                    .onSubmit { saveCleanupProtectPassword() }
                            }
                        }
                        HStack(spacing: 10) {
                            cleanupTestButton { saveCleanupProtectPassword(); testCleanupProtect() }
                                .disabled(cleanupTesting)
                            if let r = cleanupProtectTestResult { cleanupResultLabel(r, ok: cleanupProtectTestOK) }
                        }
                        settingsToggleRow(icon: "trash", iconColor: .red, title: "Auto-delete Protect record", subtitle: "When deleting a Jamf Pro record, also delete the matching Protect record", isOn: $cleanupProtectAutoCleanup)
                    }
                }
            }
        }
        .onDisappear { saveCleanupProtectPassword() }
    }

    private func groupHeader(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .semibold)).foregroundColor(.gray)
    }

    private func cleanupInfoRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundColor(isDark ? .white.opacity(0.8) : .primary.opacity(0.8))
            Spacer()
            Text(value).font(.system(size: 13)).foregroundColor(.gray).textSelection(.enabled)
        }
    }

    private func cleanupTextField(title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12)).foregroundColor(.gray)
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(10)
                .background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                .cornerRadius(8)
        }
    }

    private func cleanupTestButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Test Connection")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.teal)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private func cleanupResultLabel(_ text: String, ok: Bool) -> some View {
        Label(text, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
            .font(.system(size: 12))
            .foregroundColor(ok ? .green : .red)
    }

    private func saveCleanupProtectPassword() {
        guard !cleanupProtectPassword.isEmpty else { return }
        cleanupSettings.protectClientPassword = cleanupProtectPassword
        cleanupProtectPassword = ""
    }

    private func testCleanupJamf() {
        cleanupTesting = true
        cleanupJamfTestResult = nil
        Task {
            switch await CleanupConnectionTester.testJamf(cleanupSettings) {
            case .success(let m): cleanupJamfTestOK = true; cleanupJamfTestResult = m
            case .failure(let e): cleanupJamfTestOK = false; cleanupJamfTestResult = e.localizedDescription
            }
            cleanupTesting = false
        }
    }

    private func testCleanupProtect() {
        cleanupTesting = true
        cleanupProtectTestResult = nil
        Task {
            switch await CleanupConnectionTester.testProtect(cleanupSettings) {
            case .success(let m): cleanupProtectTestOK = true; cleanupProtectTestResult = m
            case .failure(let e): cleanupProtectTestOK = false; cleanupProtectTestResult = e.localizedDescription
            }
            cleanupTesting = false
        }
    }

    // MARK: - Helper Views

    private func settingsCard<Content: View>(
        title: String,
        icon: String,
        iconColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Section header
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(iconColor)
                
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isDark ? .white : .primary)
            }
            
            // Content
            content()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isDark ? Color.white.opacity(0.03) : Color.white.opacity(0.8))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: isDark ? .clear : .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Preview

#Preview("Settings - Dark") {
    SettingsView()
        .frame(width: 900, height: 800)
        .preferredColorScheme(.dark)
}

#Preview("Settings - Light") {
    SettingsView()
        .frame(width: 900, height: 800)
        .preferredColorScheme(.light)
}