//
//  ScopeIDInspector.swift
//  Helios
//
//  Lists every Jamf site and group present in the fleet alongside its id.
//
//  The Health Scorecard is targeted entirely by id — a site or group can be
//  renamed in Jamf, and a rename must never silently change what is counted.
//  But Helios displays no Jamf ids anywhere else, so without this an admin has
//  to dig them out of Jamf by hand to author a targeting profile. That is a hard
//  blocker on the model being usable, not a convenience.
//
//  Built from cached inventory rather than a directory API, so it costs no
//  request and can only ever show ids that real devices actually carry — an id
//  listed here is guaranteed to match something.
//

import SwiftUI

struct ScopeIDInspector: View {
    @ObservedObject private var calculator = HealthMetricsCalculator.shared
    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""
    @State private var copiedID: String? = nil

    private var entries: [HealthMetricsCalculator.ScopeDirectoryEntry] {
        let all = calculator.scopeDirectory
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.id.contains(query)
        }
    }

    private var grouped: [(kind: HealthMetricsCalculator.ScopeDirectoryEntry.Kind,
                           items: [HealthMetricsCalculator.ScopeDirectoryEntry])] {
        let kinds: [HealthMetricsCalculator.ScopeDirectoryEntry.Kind] =
            [.site, .computerGroup, .mobileGroup]
        return kinds.compactMap { kind in
            let items = entries.filter { $0.kind == kind }
            return items.isEmpty ? nil : (kind: kind, items: items)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().opacity(0.3)

            if calculator.scopeDirectory.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(grouped, id: \.kind) { section in
                            sectionView(section.kind, section.items)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(width: 560, height: 620)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Scope IDs")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }

            Text("Health Scorecard targets are written with these ids, not names — a site renamed in Jamf keeps its id, so what you measure doesn't change underneath you. Click an id to copy it.")
                .font(.system(size: 12))
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Filter by name or id", text: $searchText)
                .textFieldStyle(.roundedBorder)
        }
        .padding(16)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "questionmark.folder")
                .font(.system(size: 28))
                .foregroundColor(.gray)
            Text("No sites or groups found in the current inventory")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
            Text("Sites come from the GENERAL inventory section and groups from GROUP_MEMBERSHIPS (computers) or GROUPS (mobile). If those aren't in features → inventorySections, there is nothing to list.")
                .font(.system(size: 12))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionView(
        _ kind: HealthMetricsCalculator.ScopeDirectoryEntry.Kind,
        _ items: [HealthMetricsCalculator.ScopeDirectoryEntry]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(kind.rawValue.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.gray)
                Text(items.first?.configKeyHint ?? "")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.blue.opacity(0.8))
                Spacer()
            }

            ForEach(items, id: \.identity) { entry in
                row(entry)
            }
        }
    }

    private func row(_ entry: HealthMetricsCalculator.ScopeDirectoryEntry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                    if let isSmart = entry.isSmart {
                        Text(isSmart ? "smart" : "static")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.gray)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(3)
                    }
                }
                Text("\(entry.deviceCount) device\(entry.deviceCount == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }

            Spacer()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.id, forType: .string)
                copiedID = entry.identity
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if copiedID == entry.identity { copiedID = nil }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(entry.id)
                        .font(.system(size: 12, design: .monospaced))
                    Image(systemName: copiedID == entry.identity ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                }
                .foregroundColor(copiedID == entry.identity ? .green : .blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06))
                .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .help("Copy id for use in healthScorecard targets")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.03))
        .cornerRadius(6)
    }
}
