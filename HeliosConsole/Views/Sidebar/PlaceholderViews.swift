//
//  PlaceholderViews.swift
//  Helios
//
//  Placeholder views for sidebar navigation destinations
//

import SwiftUI

// MARK: - Devices View

struct DevicesView: View {
    @Binding var isInNestedView: Bool
    @EnvironmentObject var deepLinkRouter: DeepLinkRouter
    @State private var navigationPath = NavigationPath()
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            DeviceListView(platform: .all, navigationPath: $navigationPath)
                .navigationDestination(for: Computer.self) { computer in
                    DeviceView(computer: computer)
                }
                .navigationDestination(for: MobileDevice.self) { device in
                    MobileDeviceView(device: device)
                }
        }
        .onChange(of: navigationPath.count) { oldValue, newValue in
            withAnimation(.easeInOut(duration: 0.2)) {
                isInNestedView = newValue > 0
            }
        }
        .onAppear {
            isInNestedView = false
            consumeDeepLinkIfPresent()
        }
        .onChange(of: deepLinkRouter.pendingRequest) { oldValue, newValue in
            if newValue != nil {
                consumeDeepLinkIfPresent()
            }
        }
    }
    
    /// Check the router for a pending request, consume it, and push the device.
    private func consumeDeepLinkIfPresent() {
        guard let request = deepLinkRouter.pendingRequest else { return }
        
        NSLog("🔗 DevicesView: Consuming deep link — type: %@, id: %@",
              request.deviceType.rawValue, request.deviceID)
        
        // Clear immediately so it doesn't re-fire
        deepLinkRouter.clearRequest()
        
        // Push the device onto the nav stack after a brief delay to let the view settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            switch request.deviceType {
            case .computer:
                let json = """
                {"id":"\(request.deviceID)","udid":""}
                """.data(using: .utf8)!
                if let stub = try? JSONDecoder().decode(Computer.self, from: json) {
                    navigationPath.append(stub)
                }
            case .mobiledevice:
                let json = """
                {"id":"\(request.deviceID)"}
                """.data(using: .utf8)!
                if let stub = try? JSONDecoder().decode(MobileDevice.self, from: json) {
                    navigationPath.append(stub)
                }
            }
        }
    }
}

// MARK: - Announcements View

// NOTE: AnnouncementsView has been moved to Views/Announcements/AnnouncementsView.swift

// MARK: - Reports View

// NOTE: ReportsView has been moved to Views/Reports/ReportsView.swift

// NOTE: EnrollmentsView has been moved to Views/Enrollments/EnrollmentsView.swift

// NOTE: SettingsView has been moved to Views/Settings/SettingsView.swift

// MARK: - Shared Components

private func headerSection(title: String, icon: String) -> some View {
    HStack(alignment: .center) {
        Text(title)
            .font(.system(size: 28, weight: .bold))
            .foregroundColor(.white)
        
        Spacer()
    }
    .padding(.horizontal, 40)
    .padding(.top, 24)
    .padding(.bottom, 24)
}

private func placeholderContent(icon: String, title: String, description: String, color: Color) -> some View {
    VStack(spacing: 24) {
        Spacer()
        
        ZStack {
            Circle()
                .fill(color.opacity(0.1))
                .frame(width: 120, height: 120)
            
            Image(systemName: icon)
                .font(.system(size: 48, weight: .medium))
                .foregroundColor(color.opacity(0.6))
        }
        
        VStack(spacing: 12) {
            Text(title)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
            
            Text(description)
                .font(.system(size: 16))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        
        Text("Coming Soon")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(color.opacity(0.2))
            )
            .overlay(
                Capsule()
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
        
        Spacer()
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Devices View") {
    @Previewable @State var isNested = false
    DevicesView(isInNestedView: $isNested)
        .environmentObject(DeepLinkRouter())
        .frame(width: 1200, height: 800)
}

#Preview("Settings View") {
    SettingsView()
        .frame(width: 1200, height: 800)
}
#endif
