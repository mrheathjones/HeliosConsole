//
//  AnnouncementsView.swift
//  HeliosConsole
//
//  View for displaying announcements pushed via MDM configuration profiles
//  Pure SwiftUI (uses Environment openURL instead of NSWorkspace)
//

import SwiftUI

struct AnnouncementsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @ObservedObject private var announcementService = AnnouncementService.shared
    
    @State private var selectedAnnouncement: Announcement?
    @State private var filter: AnnouncementFilter = .all
    @State private var showingAddSheet = false
    @State private var searchText = ""
    
    private var isDark: Bool { colorScheme == .dark }
    
    private var filteredAnnouncements: [Announcement] {
        var results = announcementService.activeAnnouncements
        
        switch filter {
        case .all:
            break
        case .unread:
            results = results.filter { !announcementService.isRead($0) }
        case .critical:
            results = results.filter { $0.type == .critical || $0.priority == .urgent }
        case .type(let type):
            results = results.filter { $0.type == type }
        }
        
        if !searchText.isEmpty {
            results = results.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.message.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return results
    }
    
    var body: some View {
        ZStack {
            AnimatedBackgroundView(animate: .constant(true))
            
            VStack(spacing: 0) {
                headerSection
                
                if announcementService.isLoading && announcementService.announcements.isEmpty {
                    loadingView
                } else if announcementService.activeAnnouncements.isEmpty {
                    emptyStateView
                } else {
                    contentView
                }
            }
        }
        .sheet(item: $selectedAnnouncement) { announcement in
            AnnouncementDetailSheet(announcement: announcement, openURL: openURL)
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Announcements")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(isDark ? .white : .primary)
                    
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: sourceIcon)
                                .font(.system(size: 10))
                            Text("Source: \(announcementService.activeSource.rawValue)")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(sourceColor)
                        
                        if let lastRefresh = announcementService.lastRefresh {
                            Text("•")
                                .foregroundColor(.gray)
                            Text("Updated: \(lastRefresh.formatted(date: .omitted, time: .shortened))")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    if announcementService.unreadCount > 0 && announcementService.showUnreadBadge {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 8, height: 8)
                            Text("\(announcementService.unreadCount) unread")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.orange)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(8)
                    }
                    
                    if announcementService.unreadCount > 0 {
                        Button {
                            announcementService.markAllAsRead()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 12))
                                Text("Mark All Read")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(isDark ? .white : .primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Button {
                        announcementService.refresh()
                    } label: {
                        HStack(spacing: 6) {
                            if announcementService.isLoading {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text("Refresh")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(announcementService.isLoading)
                    
                    // Local file / debug menu
                    Menu {
                        Section("Local Announcements File") {
                            if announcementService.localFileExists {
                                Button {
                                    announcementService.openLocalDirectory()
                                } label: {
                                    Label("Open in Finder", systemImage: "folder")
                                }
                                
                                Button {
                                    openURL(announcementService.localFileURL)
                                } label: {
                                    Label("Edit announcements.json", systemImage: "pencil")
                                }
                            } else {
                                Button {
                                    announcementService.createLocalAnnouncementsFile()
                                } label: {
                                    Label("Create Local File", systemImage: "doc.badge.plus")
                                }
                            }
                            
                            Text("Path: \(AnnouncementService.localAnnouncementsFilePath)")
                                .font(.caption)
                        }
                        
                        #if DEBUG
                        // Testing helpers never ship to production builds.
                        Divider()

                        Section("Testing") {
                            Button {
                                announcementService.addSampleAnnouncements()
                            } label: {
                                Label("Add Sample Announcements", systemImage: "plus.circle")
                            }

                            Button {
                                announcementService.clearLocalAnnouncements()
                            } label: {
                                Label("Clear Test Announcements", systemImage: "trash")
                            }
                        }
                        #endif
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(isDark ? .white : .primary)
                            .frame(width: 36, height: 36)
                            .background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                            .cornerRadius(8)
                    }
                }
            }
            
            // Error banner
            if let error = announcementService.error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(isDark ? .white : .primary)
                    Spacer()
                }
                .padding(12)
                .background(Color.orange.opacity(0.15))
                .cornerRadius(8)
            }
            
            // Filter bar
            HStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterPill("All", filter: .all)
                        filterPill("Unread", filter: .unread, badge: announcementService.unreadCount)
                        filterPill("Critical", filter: .critical, color: .red)
                        
                        Divider()
                            .frame(height: 20)
                            .padding(.horizontal, 4)
                        
                        ForEach(AnnouncementType.allCases) { type in
                            filterPill(type.displayName, filter: .type(type), color: colorForType(type))
                        }
                    }
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("Search announcements...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                .cornerRadius(8)
                .frame(maxWidth: 300)
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }
    
    private var sourceIcon: String {
        switch announcementService.activeSource {
        case .mdm: return "lock.shield"
        case .localFile: return "doc.text"
        case .userDefaults: return "testtube.2"
        case .none: return "questionmark.circle"
        }
    }
    
    private var sourceColor: Color {
        switch announcementService.activeSource {
        case .mdm: return .green
        case .localFile: return .blue
        case .userDefaults: return .purple
        case .none: return .gray
        }
    }
    
    private func filterPill(_ title: String, filter: AnnouncementFilter, color: Color = .gray, badge: Int = 0) -> some View {
        let isSelected = self.filter == filter
        
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.filter = filter
            }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(color))
                }
            }
            .foregroundColor(isSelected ? .white : (isDark ? .white.opacity(0.7) : .primary.opacity(0.7)))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? color : (isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)))
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Content
    
    private var contentView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredAnnouncements) { announcement in
                    AnnouncementCard(
                        announcement: announcement,
                        isRead: announcementService.isRead(announcement),
                        onTap: {
                            announcementService.markAsRead(announcement)
                            selectedAnnouncement = announcement
                        },
                        onDismiss: (announcement.dismissible && announcementService.allowUserDismiss) ? {
                            withAnimation {
                                announcementService.dismiss(announcement)
                            }
                        } : nil
                    )
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 20)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "megaphone.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundColor(.orange.opacity(0.6))
            }
            
            VStack(spacing: 12) {
                Text("No Announcements")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(isDark ? .white : .primary)
                
                Text("Announcements can be loaded from:")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                
                VStack(alignment: .leading, spacing: 8) {
                    sourceRow(icon: "lock.shield", text: "MDM Configuration Profile", color: .green)
                    sourceRow(icon: "doc.text", text: "Local JSON file", color: .blue)
                }
                .padding(.top, 8)
            }
            
            VStack(spacing: 12) {
                if announcementService.localFileExists {
                    HStack(spacing: 12) {
                        Button {
                            announcementService.openLocalDirectory()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "folder")
                                Text("Open Folder")
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(isDark ? .white : .primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            openURL(announcementService.localFileURL)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "pencil")
                                Text("Edit File")
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.blue)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Button {
                        announcementService.createLocalAnnouncementsFile()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.badge.plus")
                            Text("Create Local Announcements File")
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                
                Text("File path: \(AnnouncementService.localAnnouncementsFilePath)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.gray.opacity(0.7))
                    .padding(.top, 4)
            }
            .padding(.top, 8)
            
            #if DEBUG
            // Testing helper never ships to production builds.
            Button {
                announcementService.addSampleAnnouncements()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "testtube.2")
                    Text("Add Sample Announcements for Testing")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.purple)
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
            #endif
            
            Spacer()
        }
    }
    
    private func sourceRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(isDark ? .white.opacity(0.8) : .primary.opacity(0.8))
        }
    }
    
    // MARK: - Loading
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading announcements...")
                .font(.system(size: 14))
                .foregroundColor(.gray)
            Spacer()
        }
    }
    
    private func colorForType(_ type: AnnouncementType) -> Color {
        switch type {
        case .info: return .blue
        case .warning: return .orange
        case .critical: return .red
        case .success: return .green
        case .maintenance: return .purple
        case .update: return .cyan
        }
    }
}

// MARK: - Announcement Filter

enum AnnouncementFilter: Equatable {
    case all
    case unread
    case critical
    case type(AnnouncementType)
}

// MARK: - Announcement Card

struct AnnouncementCard: View {
    let announcement: Announcement
    let isRead: Bool
    let onTap: () -> Void
    let onDismiss: (() -> Void)?
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    
    private var isDark: Bool { colorScheme == .dark }
    
    private var typeColor: Color {
        switch announcement.type {
        case .info: return .blue
        case .warning: return .orange
        case .critical: return .red
        case .success: return .green
        case .maintenance: return .purple
        case .update: return .cyan
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(typeColor.opacity(isDark ? 0.2 : 0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: announcement.type.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(typeColor)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        if !isRead {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 8, height: 8)
                        }
                        
                        Text(announcement.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(isDark ? .white : .primary)
                            .lineLimit(1)
                        
                        if announcement.priority == .urgent || announcement.priority == .high {
                            Text(announcement.priority.rawValue.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(announcement.priority == .urgent ? Color.red : Color.orange))
                        }
                        
                        if announcement.requiredReading && !isRead {
                            Text("REQUIRED")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.red))
                        }
                        
                        Spacer()
                        
                        Text(announcement.createdAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    
                    Text(AnnouncementMarkdownView.inlineAttributed(announcement.message))
                        .font(.system(size: 13))
                        .foregroundColor(isDark ? .white.opacity(0.7) : .primary.opacity(0.7))
                        .lineLimit(2)
                    
                    if announcement.actionURL != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right.circle")
                                .font(.system(size: 11))
                            Text(announcement.actionLabel ?? "Learn More")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(typeColor)
                    }
                }
                
                if let onDismiss = onDismiss {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray.opacity(0.5))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isDark ? Color.white.opacity(isHovered ? 0.06 : 0.03) : Color.white.opacity(isHovered ? 0.9 : 0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        !isRead ? typeColor.opacity(0.3) : (isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.08)),
                        lineWidth: !isRead ? 2 : 1
                    )
            )
            .shadow(color: isDark ? .clear : .black.opacity(0.05), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Announcement Detail Sheet

struct AnnouncementDetailSheet: View {
    let announcement: Announcement
    let openURL: OpenURLAction
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    private var typeColor: Color {
        switch announcement.type {
        case .info: return .blue
        case .warning: return .orange
        case .critical: return .red
        case .success: return .green
        case .maintenance: return .purple
        case .update: return .cyan
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(typeColor.opacity(isDark ? 0.2 : 0.15))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: announcement.type.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(typeColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(announcement.type.displayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(typeColor)
                        
                        if announcement.priority == .urgent || announcement.priority == .high {
                            Text(announcement.priority.rawValue.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(announcement.priority == .urgent ? Color.red : Color.orange))
                        }
                    }
                    
                    Text(announcement.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(isDark ? .white : .primary)
                }
                
                Spacer()
                
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.gray)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)))
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .background(isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    AnnouncementMarkdownView(text: announcement.message)
                        .font(.system(size: 15))
                        .foregroundColor(isDark ? .white.opacity(0.9) : .primary.opacity(0.9))
                        .lineSpacing(4)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        metadataRow(icon: "calendar", label: "Posted", value: announcement.createdAt.formatted(date: .long, time: .shortened))
                        
                        if let expiresAt = announcement.expiresAt {
                            metadataRow(icon: "clock", label: "Expires", value: expiresAt.formatted(date: .long, time: .shortened))
                        }
                        
                        metadataRow(icon: "flag", label: "Priority", value: announcement.priority.rawValue.capitalized)
                        
                        if announcement.requiredReading {
                            metadataRow(icon: "exclamationmark.circle", label: "Required Reading", value: "Yes", color: .red)
                        }
                    }
                    .padding(16)
                    .background(isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
                    .cornerRadius(12)
                    
                    if let urlString = announcement.actionURL, let url = URL(string: urlString) {
                        Button {
                            openURL(url)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.up.right.square")
                                Text(announcement.actionLabel ?? "Learn More")
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(typeColor)
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 500, height: 450)
        .background(isDark ? Color(white: 0.12) : Color.white)
    }
    
    private func metadataRow(icon: String, label: String, value: String, color: Color = .gray) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
                .frame(width: 20)
            
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.gray)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 13))
                .foregroundColor(isDark ? .white : .primary)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Announcements View") {
    AnnouncementsView()
        .frame(width: 1200, height: 800)
        .onAppear {
            AnnouncementService.shared.addSampleAnnouncements()
        }
}
#endif
