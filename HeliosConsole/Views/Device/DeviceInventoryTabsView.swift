//
//  DeviceInventoryTabsView.swift
//  Helios
//
//  The searchable, paginated inventory sections of the computer detail view
//  (applications, profiles, local accounts, certificates, printers, groups,
//  extension attributes). Each list's search/page state is a
//  PaginatedListState held by DeviceInventoryState, which the detail view
//  owns so search, filters, and page survive switching sections.
//

import SwiftUI
import Observation

// MARK: - State

@Observable
final class DeviceInventoryState {
    enum CertificateFilter: String, CaseIterable {
        case all = "All"
        case valid = "Valid"
        case expiring = "Expiring"
        case expired = "Expired"
    }

    let applications = PaginatedListState<Application> { app, text in
        (app.name ?? "").localizedCaseInsensitiveContains(text) ||
        (app.bundleId ?? "").localizedCaseInsensitiveContains(text)
    }

    let profiles = PaginatedListState<ConfigurationProfile> { profile, text in
        (profile.displayName ?? "").localizedCaseInsensitiveContains(text) ||
        (profile.profileIdentifier ?? "").localizedCaseInsensitiveContains(text)
    }

    let localAccounts = PaginatedListState<LocalUserAccount> { account, text in
        (account.fullName ?? "").localizedCaseInsensitiveContains(text) ||
        (account.username ?? "").localizedCaseInsensitiveContains(text)
    }

    let certificates = PaginatedListState<Certificate> { cert, text in
        (cert.commonName ?? "").localizedCaseInsensitiveContains(text) ||
        (cert.subjectName ?? "").localizedCaseInsensitiveContains(text)
    }

    let printers = PaginatedListState<Printer> { printer, text in
        (printer.name ?? "").localizedCaseInsensitiveContains(text) ||
        (printer.location ?? "").localizedCaseInsensitiveContains(text) ||
        (printer.type ?? "").localizedCaseInsensitiveContains(text)
    }

    let groups = PaginatedListState<GroupMembership> { group, text in
        (group.groupName ?? "").localizedCaseInsensitiveContains(text)
    }

    let extensionAttributes = PaginatedListState<ExtensionAttribute> { attr, text in
        (attr.name ?? "").localizedCaseInsensitiveContains(text) ||
        (attr.values?.joined(separator: " ") ?? "").localizedCaseInsensitiveContains(text)
    }

    // Local Accounts tag filters. Each chip is a tag: an account shows only if
    // one of its tags is selected, so no selection means no accounts. System
    // accounts start deselected to keep service users out of the way.
    var filterAdminAccounts: Bool = true {
        didSet { if filterAdminAccounts != oldValue { localAccounts.resetPage() } }
    }
    var filterStandardAccounts: Bool = true {
        didSet { if filterStandardAccounts != oldValue { localAccounts.resetPage() } }
    }
    var filterFileVaultAccounts: Bool = true {
        didSet { if filterFileVaultAccounts != oldValue { localAccounts.resetPage() } }
    }
    var filterSystemAccounts: Bool = false {
        didSet { if filterSystemAccounts != oldValue { localAccounts.resetPage() } }
    }

    // Groups filters
    var filterSmartGroups: Bool = true {
        didSet { if filterSmartGroups != oldValue { groups.resetPage() } }
    }
    var filterStaticGroups: Bool = true {
        didSet { if filterStaticGroups != oldValue { groups.resetPage() } }
    }

    // Certificates filter
    var certificateFilter: CertificateFilter = .all {
        didSet { if certificateFilter != oldValue { certificates.resetPage() } }
    }

    /// False when every tag chip is deselected — nothing can match, and the
    /// empty state says so rather than pretending a filter excluded everything.
    var hasSelectedAccountTags: Bool {
        filterAdminAccounts || filterStandardAccounts
            || filterFileVaultAccounts || filterSystemAccounts
    }
}

// MARK: - View

struct DeviceInventoryTabsView: View {
    let section: DeviceSection
    let computer: Computer
    @Bindable var state: DeviceInventoryState

    var body: some View {
        switch section {
        case .applications:
            applicationsSection
        case .profiles:
            profilesSection
        case .localAccounts:
            localAccountsSection
        case .certificates:
            certificatesSection
        case .printers:
            printersSection
        case .groupMemberships:
            groupMembershipsSection
        case .extensionAttributes:
            extensionAttributesSection
        default:
            EmptyView()
        }
    }

    // MARK: - Applications Section

    private var applicationsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader("Applications (\(computer.applications?.count ?? 0))", icon: "square.grid.2x2")

            if let apps = computer.applications, !apps.isEmpty {
                // Search/filter bar
                SearchBar(text: Bindable(state.applications).searchText, placeholder: "Filter applications...")

                PaginatedRows(state: state.applications, rows: state.applications.filter(apps)) { app in
                    applicationRow(app)
                }
            } else {
                EmptyStateView("No applications found", icon: "app.badge")
            }
        }
    }

    private func applicationRow(_ app: Application) -> some View {
        HStack(spacing: 16) {
            // App icon placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 44, height: 44)
                
                Image(systemName: app.macAppStore == true ? "apple.logo" : "app")
                    .font(.system(size: 18))
                    .foregroundColor(.gray)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(app.name ?? "Unknown")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    
                    if app.updateAvailable == true {
                        Text("Update Available")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                Text(app.version ?? app.cfBundleShortVersionString ?? "")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                
                if let bundleId = app.bundleId {
                    Text(bundleId)
                        .font(.system(size: 11))
                        .foregroundColor(.gray.opacity(0.7))
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                if let size = app.sizeMegabytes {
                    Text(DeviceFormatting.storage(size))
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                
                if app.macAppStore == true {
                    Text("App Store")
                        .font(.system(size: 10))
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    // MARK: - Configuration Profiles Section

    private var profilesSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader("Configuration Profiles (\(computer.configurationProfiles?.count ?? 0))", icon: "doc.badge.gearshape")

            if let profiles = computer.configurationProfiles, !profiles.isEmpty {
                // Search bar
                SearchBar(text: Bindable(state.profiles).searchText, placeholder: "Filter profiles...")

                PaginatedRows(state: state.profiles, rows: state.profiles.filter(profiles)) { profile in
                    profileRow(profile)
                }
            } else {
                EmptyStateView("No configuration profiles", icon: "doc.badge.gearshape")
            }
        }
    }

    private func profileRow(_ profile: ConfigurationProfile) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: "doc.badge.gearshape.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayName ?? "Unknown Profile")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                if let identifier = profile.profileIdentifier {
                    Text(identifier)
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                if profile.removable == true {
                    Text("Removable")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                }
                
                if let installed = profile.lastInstalled {
                    Text(DeviceFormatting.date(installed) ?? "")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    // MARK: - Local Accounts Section

    private var localAccountsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader("Local User Accounts (\(computer.localUserAccounts?.count ?? 0))", icon: "person.2")

            if let accounts = computer.localUserAccounts, !accounts.isEmpty {
                // Search bar
                SearchBar(text: Bindable(state.localAccounts).searchText, placeholder: "Filter accounts...")

                // Filter toggles
                HStack(spacing: 12) {
                    FilterToggle("Admin", isOn: $state.filterAdminAccounts, color: .orange)
                    FilterToggle("Standard", isOn: $state.filterStandardAccounts, color: .blue)
                    FilterToggle("FileVault", isOn: $state.filterFileVaultAccounts, color: .purple)
                    FilterToggle("System", isOn: $state.filterSystemAccounts, color: .teal)

                    Spacer()

                    // Show count of filtered vs total
                    let filteredCount = filteredLocalAccounts(from: accounts).count
                    if filteredCount != accounts.count {
                        Text("\(filteredCount) of \(accounts.count)")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                }

                let filteredAccounts = filteredLocalAccounts(from: accounts)

                if filteredAccounts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 32))
                            .foregroundColor(.gray.opacity(0.5))
                        Text(state.hasSelectedAccountTags ? "No accounts match filters" : "No filtered users")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                        if !state.hasSelectedAccountTags {
                            Text("Select a tag above to show accounts")
                                .font(.system(size: 12))
                                .foregroundColor(.gray.opacity(0.7))
                        }
                        Button("Select All Tags") {
                            state.filterAdminAccounts = true
                            state.filterStandardAccounts = true
                            state.filterFileVaultAccounts = true
                            state.filterSystemAccounts = true
                        }
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    PaginatedRows(state: state.localAccounts, rows: filteredAccounts) { account in
                        localAccountRow(account)
                    }
                }
            } else {
                EmptyStateView("No local user accounts", icon: "person.2")
            }
        }
    }

    private func filteredLocalAccounts(from accounts: [LocalUserAccount]) -> [LocalUserAccount] {
        // Every chip is a tag, and an account shows only while one of its own
        // tags is selected. Deselecting a chip always hides those accounts —
        // there is no "nothing selected means everything" escape hatch.
        state.localAccounts.filter(accounts) { account in
            let matchesType: Bool
            switch account.accountType {
            case .admin: matchesType = state.filterAdminAccounts
            case .standard: matchesType = state.filterStandardAccounts
            case .system: matchesType = state.filterSystemAccounts
            }

            return matchesType
                || (state.filterFileVaultAccounts && account.fileVault2Enabled == true)
        }
    }

    /// Icon + color for an account's type, matching its tag chip.
    private func accountTypeStyle(_ type: LocalUserAccount.AccountType) -> (label: String, icon: String, color: Color) {
        switch type {
        case .admin:    return ("Admin", "person.badge.key.fill", .orange)
        case .standard: return ("Standard", "person.fill", .blue)
        case .system:   return ("System", "gearshape.fill", .teal)
        }
    }

    private func accountTag(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .cornerRadius(4)
    }

    private func localAccountRow(_ account: LocalUserAccount) -> some View {
        let type = accountTypeStyle(account.accountType)

        return HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(type.color.opacity(0.1))
                    .frame(width: 44, height: 44)

                Image(systemName: type.icon)
                    .font(.system(size: 18))
                    .foregroundColor(type.color)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(account.fullName ?? account.username ?? "Unknown")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)

                    accountTag(type.label, color: type.color)

                    if account.fileVault2Enabled == true {
                        accountTag("FileVault", color: .purple)
                    }
                }
                
                Text(account.username ?? "")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                
                if let home = account.homeDirectory {
                    Text(home)
                        .font(.system(size: 11))
                        .foregroundColor(.gray.opacity(0.7))
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("UID: \(account.uid ?? "N/A")")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                
                if let size = account.homeDirectorySizeMb, size > 0 {
                    Text(DeviceFormatting.storage(size))
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    // MARK: - Certificates Section

    private var certificatesSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader("Certificates (\(computer.certificates?.count ?? 0))", icon: "checkmark.seal")

            if let certs = computer.certificates, !certs.isEmpty {
                // Search bar
                SearchBar(text: Bindable(state.certificates).searchText, placeholder: "Filter certificates...")

                // Status filter
                HStack(spacing: 12) {
                    ForEach(DeviceInventoryState.CertificateFilter.allCases, id: \.self) { filter in
                        Button {
                            state.certificateFilter = filter
                        } label: {
                            Text(filter.rawValue)
                                .font(.system(size: 12, weight: state.certificateFilter == filter ? .semibold : .regular))
                                .foregroundColor(state.certificateFilter == filter ? .white : .gray)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(state.certificateFilter == filter ? certificateFilterColor(filter).opacity(0.3) : Color.white.opacity(0.05))
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                }

                let filteredCerts = filteredCertificates(from: certs)

                if filteredCerts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 32))
                            .foregroundColor(.gray.opacity(0.5))
                        Text("No certificates match filters")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                        Button("Show All") {
                            state.certificateFilter = .all
                            state.certificates.searchText = ""
                        }
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    PaginatedRows(state: state.certificates, rows: filteredCerts) { cert in
                        certificateRow(cert)
                    }
                }
            } else {
                EmptyStateView("No certificates found", icon: "checkmark.seal")
            }
        }
    }

    private func certificateFilterColor(_ filter: DeviceInventoryState.CertificateFilter) -> Color {
        switch filter {
        case .all: return .blue
        case .valid: return .green
        case .expiring: return .yellow
        case .expired: return .red
        }
    }

    private func filteredCertificates(from certs: [Certificate]) -> [Certificate] {
        // Apply search filter
        var result = state.certificates.filter(certs)

        // Apply status filter
        switch state.certificateFilter {
        case .all:
            break
        case .valid:
            result = result.filter { $0.certificateStatus == "ISSUED" || $0.lifecycleStatus == "ACTIVE" }
        case .expiring:
            result = result.filter { cert in
                guard let expiryString = cert.expirationDate,
                      let expiryDate = ISO8601DateFormatter().date(from: expiryString) else {
                    return false
                }
                let thirtyDaysFromNow = Date().addingTimeInterval(30 * 24 * 60 * 60)
                return expiryDate > Date() && expiryDate <= thirtyDaysFromNow
            }
        case .expired:
            result = result.filter { cert in
                if cert.certificateStatus == "EXPIRED" {
                    return true
                }
                guard let expiryString = cert.expirationDate,
                      let expiryDate = ISO8601DateFormatter().date(from: expiryString) else {
                    return false
                }
                return expiryDate < Date()
            }
        }

        return result
    }

    private func certificateRow(_ cert: Certificate) -> some View {
        // Determine certificate status and color
        let (statusText, statusColor) = certificateStatusInfo(cert)
        
        return HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(statusColor.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: statusIcon(for: statusText))
                    .font(.system(size: 18))
                    .foregroundColor(statusColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(cert.commonName ?? "Unknown Certificate")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                if let subject = cert.subjectName {
                    Text(subject)
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                if let expiry = cert.expirationDate {
                    Text("Expires: \(DeviceFormatting.date(expiry) ?? expiry)")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
                
                Text(statusText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(statusColor)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
    
    private func certificateStatusInfo(_ cert: Certificate) -> (String, Color) {
        // Check if expired first
        if cert.certificateStatus?.uppercased() == "EXPIRED" {
            return ("EXPIRED", .red)
        }
        
        // Check expiration date
        if let expiryString = cert.expirationDate {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var expiryDate = formatter.date(from: expiryString)
            if expiryDate == nil {
                formatter.formatOptions = [.withInternetDateTime]
                expiryDate = formatter.date(from: expiryString)
            }
            
            if let expiry = expiryDate {
                // Check if expired
                if expiry < Date() {
                    return ("EXPIRED", .red)
                }
                
                // Check if expiring within 30 days
                let thirtyDaysFromNow = Date().addingTimeInterval(30 * 24 * 60 * 60)
                if expiry <= thirtyDaysFromNow {
                    return ("EXPIRING", .yellow)
                }
            }
        }
        
        // Valid certificate
        return ("VALID", .green)
    }
    
    private func statusIcon(for status: String) -> String {
        switch status {
        case "EXPIRED": return "xmark.seal.fill"
        case "EXPIRING": return "exclamationmark.triangle.fill"
        default: return "checkmark.seal.fill"
        }
    }

    // MARK: - Printers Section

    private var printersSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader("Printers (\(computer.printers?.count ?? 0))", icon: "printer")

            if let printers = computer.printers, !printers.isEmpty {
                // Search bar
                SearchBar(text: Bindable(state.printers).searchText, placeholder: "Filter printers...")

                let filteredPrinters = state.printers.filter(printers)

                if filteredPrinters.isEmpty {
                    EmptyStateView("No printers match search", icon: "printer")
                } else {
                    PaginatedRows(state: state.printers, rows: filteredPrinters) { printer in
                        printerRow(printer)
                    }
                }
            } else {
                EmptyStateView("No printers configured", icon: "printer")
            }
        }
    }

    private func printerRow(_ printer: Printer) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.cyan.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: "printer.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.cyan)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(printer.name ?? "Unknown Printer")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                if let type = printer.type {
                    Text(type)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                
                if let uri = printer.uri {
                    Text(uri)
                        .font(.system(size: 11))
                        .foregroundColor(.gray.opacity(0.7))
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            if let location = printer.location, !location.isEmpty {
                Text(location)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    // MARK: - Group Memberships Section

    private var groupMembershipsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader("Group Memberships (\(computer.groupMemberships?.count ?? 0))", icon: "person.3")

            if let groups = computer.groupMemberships, !groups.isEmpty {
                // Search bar
                SearchBar(text: Bindable(state.groups).searchText, placeholder: "Filter groups...")

                // Filter toggles
                HStack(spacing: 12) {
                    FilterToggle("Smart Groups", isOn: $state.filterSmartGroups, color: .purple)
                    FilterToggle("Static Groups", isOn: $state.filterStaticGroups, color: .blue)

                    Spacer()

                    let filteredCount = filteredGroups(from: groups).count
                    if filteredCount != groups.count {
                        Text("\(filteredCount) of \(groups.count)")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                }

                let filteredGroupsList = filteredGroups(from: groups)

                if filteredGroupsList.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 32))
                            .foregroundColor(.gray.opacity(0.5))
                        Text("No groups match filters")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                        Button("Show All") {
                            state.filterSmartGroups = true
                            state.filterStaticGroups = true
                            state.groups.searchText = ""
                        }
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    PaginatedRows(state: state.groups, rows: filteredGroupsList) { group in
                        groupRow(group)
                    }
                }
            } else {
                EmptyStateView("No group memberships", icon: "person.3")
            }
        }
    }

    private func filteredGroups(from groups: [GroupMembership]) -> [GroupMembership] {
        // Apply search filter
        var result = state.groups.filter(groups)

        // Apply type filters
        if !state.filterSmartGroups || !state.filterStaticGroups {
            result = result.filter { group in
                let isSmart = group.smartGroup == true
                if state.filterSmartGroups && isSmart { return true }
                if state.filterStaticGroups && !isSmart { return true }
                return false
            }
        }

        return result
    }

    private func groupRow(_ group: GroupMembership) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(group.smartGroup == true ? Color.purple.opacity(0.1) : Color.blue.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: group.smartGroup == true ? "gearshape.2.fill" : "person.3.fill")
                    .font(.system(size: 18))
                    .foregroundColor(group.smartGroup == true ? .purple : .blue)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(group.groupName ?? "Unknown Group")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                Text("ID: \(group.groupId ?? "N/A")")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Text(group.smartGroup == true ? "Smart Group" : "Static Group")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(group.smartGroup == true ? .purple : .blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((group.smartGroup == true ? Color.purple : Color.blue).opacity(0.1))
                .cornerRadius(6)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    // MARK: - Extension Attributes Section

    private var extensionAttributesSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader("Extension Attributes (\(computer.extensionAttributes?.count ?? 0))", icon: "list.bullet.rectangle")

            if let attrs = computer.extensionAttributes, !attrs.isEmpty {
                // Search bar
                SearchBar(text: Bindable(state.extensionAttributes).searchText, placeholder: "Filter extension attributes...")

                let filteredAttrs = state.extensionAttributes.filter(attrs)

                if filteredAttrs.isEmpty {
                    EmptyStateView("No attributes match search", icon: "list.bullet.rectangle")
                } else {
                    PaginatedRows(state: state.extensionAttributes, rows: filteredAttrs) { attr in
                        extensionAttributeRow(attr)
                    }
                }
            } else {
                EmptyStateView("No extension attributes", icon: "list.bullet.rectangle")
            }
        }
    }

    private func extensionAttributeRow(_ attr: ExtensionAttribute) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.indigo.opacity(0.1))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "tag.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.indigo)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(attr.name ?? "Unknown Attribute")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    
                    if let id = attr.definitionId {
                        Text("ID: \(id)")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                if let dataType = attr.dataType {
                    Text(dataType)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.indigo)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.indigo.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            
            // Value display
            if let values = attr.values, !values.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Value")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.gray)
                    
                    Text(values.joined(separator: ", "))
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(3)
                }
                .padding(.leading, 48)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}
