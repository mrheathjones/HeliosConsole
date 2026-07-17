//
//  LogsView.swift
//  HeliosConsole
//
//  Main sidebar view for auditing all MDM actions across devices
//

import SwiftUI

struct LogsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var logService = ActionLogService.shared
    /// Observed so the export gate re-evaluates when capabilities land
    /// after sign-in.
    @ObservedObject private var session = UserSession.shared

    @State private var searchText = ""
    @State private var selectedSource: ActionLogEntry.LogSource? = nil
    @State private var selectedCategory: String? = nil
    @State private var showSuccessOnly: Bool? = nil
    @State private var expandedLogId: UUID? = nil
    @State private var showingClearConfirmation = false
    @State private var showingExportConfirmation = false
    
    private var isDark: Bool { colorScheme == .dark }
    
    private var filteredLogs: [ActionLogEntry] {
        logService.filteredLogs(
            searchText: searchText,
            source: selectedSource,
            category: selectedCategory,
            successOnly: showSuccessOnly
        )
    }
    
    var body: some View {
        ZStack {
            AnimatedBackgroundView(animate: .constant(true))
            
            VStack(spacing: 0) {
                headerSection
                filterBar
                
                if logService.logs.isEmpty {
                    emptyState
                } else if filteredLogs.isEmpty {
                    noResultsState
                } else {
                    logsList
                }
            }
        }
    }
    
    // MARK: - Export

    private func exportCSVToPasteboard() {
        // Defense in depth: the button is not rendered without the grant,
        // but never let enforcement live only in the UI.
        guard session.capabilities.allowExport else { return }
        let csv = logService.exportAsCSV()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(csv, forType: .string)
        showingExportConfirmation = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showingExportConfirmation = false
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    Text("Action Logs")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(isDark ? .white : Color(red: 0.1, green: 0.1, blue: 0.15))
                    
                    if !logService.logs.isEmpty {
                        Text("\(logService.logs.count)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                }
                
                Text("Audit trail of all MDM actions performed from \(Branding.productName)")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                // Export button — the audit trail leaves the app here (via
                // the pasteboard), so it answers to allowExport exactly like
                // the Reports and Cleanup exporters: no grant, no control.
                if session.capabilities.allowExport {
                    Button {
                        exportCSVToPasteboard()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showingExportConfirmation ? "checkmark" : "square.and.arrow.up")
                                .font(.system(size: 12))
                            Text(showingExportConfirmation ? "Copied!" : "Export CSV")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(showingExportConfirmation ? .green : (isDark ? .white : .primary))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(logService.logs.isEmpty)
                }

                // Clear button
                Button {
                    showingClearConfirmation = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                        Text("Clear")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.red.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
                .disabled(logService.logs.isEmpty)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .alert("Clear All Logs?", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                logService.clearLogs()
            }
        } message: {
            Text("This will permanently delete all action logs. This cannot be undone.")
        }
    }
    
    // MARK: - Filter Bar
    
    private var filterBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Search
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                    TextField("Search by device, serial, action, or user...", text: $searchText)
                        .font(.system(size: 13))
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                )
            }
            
            // Filter chips
            HStack(spacing: 8) {
                // Source filter
                filterChip("All Sources", isSelected: selectedSource == nil) {
                    selectedSource = nil
                }
                filterChip(Branding.productName, icon: "sun.max.fill", isSelected: selectedSource == .heliosConsole) {
                    selectedSource = selectedSource == .heliosConsole ? nil : .heliosConsole
                }
                filterChip("Jamf Policy", icon: "server.rack", isSelected: selectedSource == .jamfPolicy) {
                    selectedSource = selectedSource == .jamfPolicy ? nil : .jamfPolicy
                }
                
                Divider()
                    .frame(height: 16)
                
                // Status filter
                filterChip("All Results", isSelected: showSuccessOnly == nil) {
                    showSuccessOnly = nil
                }
                filterChip("Success", icon: "checkmark.circle", color: .green, isSelected: showSuccessOnly == true) {
                    showSuccessOnly = showSuccessOnly == true ? nil : true
                }
                filterChip("Failed", icon: "xmark.circle", color: .red, isSelected: showSuccessOnly == false) {
                    showSuccessOnly = showSuccessOnly == false ? nil : false
                }
                
                if !logService.availableCategories.isEmpty {
                    Divider()
                        .frame(height: 16)
                    
                    // Category filter
                    Menu {
                        Button("All Categories") {
                            selectedCategory = nil
                        }
                        Divider()
                        ForEach(logService.availableCategories, id: \.self) { category in
                            Button(category) {
                                selectedCategory = selectedCategory == category ? nil : category
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.system(size: 10))
                            Text(selectedCategory ?? "Category")
                                .font(.system(size: 11, weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8))
                        }
                        .foregroundColor(selectedCategory != nil ? .white : (isDark ? .gray : .secondary))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(selectedCategory != nil ? Color.blue : (isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)))
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                Text("\(filteredLogs.count) of \(logService.logs.count) entries")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 16)
    }
    
    private func filterChip(_ title: String, icon: String? = nil, color: Color = .blue, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                }
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : (isDark ? .gray : .secondary))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isSelected ? color : (isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)))
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Logs List
    
    private var logsList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(filteredLogs) { entry in
                    logRow(entry)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }
    
    private func logRow(_ entry: ActionLogEntry) -> some View {
        let isExpanded = expandedLogId == entry.id
        
        return VStack(spacing: 0) {
            // Main row
            HStack(spacing: 12) {
                // Status indicator
                Circle()
                    .fill(entry.success ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                
                // Timestamp
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.timestamp, style: .date)
                        .font(.system(size: 11))
                    Text(entry.timestamp, style: .time)
                        .font(.system(size: 11))
                }
                .foregroundColor(.gray)
                .frame(width: 80, alignment: .leading)
                
                // Action
                HStack(spacing: 6) {
                    Text(entry.actionName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isDark ? .white : .primary)
                    
                    Text(entry.actionCategory)
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                        .cornerRadius(4)
                }
                .frame(width: 220, alignment: .leading)
                
                // Device
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.deviceName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isDark ? .white : .primary)
                    Text(entry.deviceSerialNumber)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.gray)
                }
                .frame(width: 160, alignment: .leading)
                
                // Source tag
                HStack(spacing: 4) {
                    Image(systemName: entry.source.icon)
                        .font(.system(size: 9))
                    Text(entry.source.rawValue)
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(entry.source == .heliosConsole ? .orange : .purple)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background((entry.source == .heliosConsole ? Color.orange : Color.purple).opacity(0.12))
                .cornerRadius(4)
                
                Spacer()
                
                // Result badge
                Text(entry.success ? "Success" : "Failed")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(entry.success ? .green : .red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((entry.success ? Color.green : Color.red).opacity(0.12))
                    .cornerRadius(6)
                
                // User
                Text(entry.performedBy)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .frame(width: 100, alignment: .trailing)
                    .lineLimit(1)
                
                // Expand chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(.gray.opacity(0.5))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedLogId = isExpanded ? nil : entry.id
                }
            }
            
            // Expanded detail
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .background(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.05))
                    
                    HStack(spacing: 32) {
                        detailField("Action", entry.actionName)
                        detailField("Category", entry.actionCategory)
                        detailField("Platform", entry.devicePlatform)
                        if let ip = entry.ipAddressUsed {
                            detailField("IP Address", ip)
                        }
                    }
                    
                    HStack(spacing: 32) {
                        detailField("Device ID", entry.deviceId)
                        detailField("Performed By", entry.performedBy)
                        detailField("Source", entry.source.rawValue)
                    }
                    
                    if let error = entry.errorMessage, !entry.success {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.red)
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundColor(.red.opacity(0.9))
                        }
                        .padding(8)
                        .background(Color.red.opacity(0.08))
                        .cornerRadius(6)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isDark ? Color.white.opacity(0.03) : Color.white.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.06), lineWidth: 1)
        )
    }
    
    private func detailField(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isDark ? .white : .primary)
        }
    }
    
    // MARK: - Empty States
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.gray.opacity(0.3))
            
            Text("No Action Logs Yet")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(isDark ? .white : .primary)
            
            Text("Actions performed on devices will be logged here for auditing.\nTry enabling Bluetooth, restarting a device, or viewing a FileVault key.")
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    private var noResultsState: some View {
        VStack(spacing: 12) {
            Spacer()
            
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundColor(.gray.opacity(0.3))
            
            Text("No matching logs")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(isDark ? .white : .primary)
            
            Text("Try adjusting your search or filters.")
                .font(.system(size: 13))
                .foregroundColor(.gray)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Logs View") {
    LogsView()
        .frame(width: 1000, height: 600)
}
#endif
