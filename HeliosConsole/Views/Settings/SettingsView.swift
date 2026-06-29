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
import LocalAuthentication

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var showingResetAlert = false
    @State private var biometricTestResult: String?
    @State private var showBiometricResult = false
    
    private var isDark: Bool {
        colorScheme == .dark
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
                        appearanceSection
                        securitySection
                        displaySection
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
                
                Text("Configure Helios Console preferences")
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
    
    // MARK: - Security Section
    
    private var securitySection: some View {
        settingsCard(title: "Security", icon: "lock.shield.fill", iconColor: .green) {
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
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue, Color.purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 64, height: 64)
                        
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Helios Console")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(isDark ? .white : .primary)
                        
                        Text("Version 1.0.0 (Build 1)")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                        
                        Text("macOS Device Management")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                }
                
                Divider()
                    .background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                
                // Links
                VStack(spacing: 12) {
                    aboutLinkRow(icon: "book.fill", title: "Documentation", color: .blue)
                    aboutLinkRow(icon: "questionmark.circle.fill", title: "Help & Support", color: .green)
                    aboutLinkRow(icon: "exclamationmark.bubble.fill", title: "Report an Issue", color: .orange)
                    aboutLinkRow(icon: "star.fill", title: "Rate Helios", color: .yellow)
                }
                
                Divider()
                    .background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                
                // Copyright
                Text("© 2026 Helios Console. All rights reserved.")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
        }
    }
    
    private func aboutLinkRow(icon: String, title: String, color: Color) -> some View {
        Button {
            // Handle link tap
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