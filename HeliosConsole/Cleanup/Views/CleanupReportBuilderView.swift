//
//  CleanupReportBuilderView.swift
//  HeliosConsole
//
//  Build a custom cleanup report: pick a scope, title, columns, and
//  summary, then export to CSV, Markdown, or PDF. Ported from Clean Slate's
//  ReportBuilderView.
//

import SwiftUI
import UniformTypeIdentifiers

struct CleanupReportBuilderView: View {
    @Environment(CleanupViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var scope: Scope = .allStale
    @State private var title = "Helios Cleanup Report"
    @State private var columns: Set<ReportColumn> = Set(ReportColumn.allCases)
    @State private var includeSummary = true

    @State private var document: ExportDocument?
    @State private var contentType: UTType = .pdf
    @State private var exportName = "report"
    @State private var isExporting = false

    enum Scope: Hashable, CaseIterable, Identifiable {
        case allStale, overOneYear, unmanaged, protectAll, protectStale
        var id: Self { self }

        var title: String {
            switch self {
            case .allStale: "Stale Devices (managed)"
            case .overOneYear: "Stale Over 1 Year"
            case .unmanaged: "Unmanaged"
            case .protectAll: "Jamf Protect — All"
            case .protectStale: "Jamf Protect — Stale"
            }
        }

        var isProtect: Bool { self == .protectAll || self == .protectStale }
    }

    private var protectScopesAvailable: Bool { model.settings.isProtectConfigured }

    private var availableScopes: [Scope] {
        Scope.allCases.filter { !$0.isProtect || protectScopesAvailable }
    }

    /// Number of rows the current scope would produce.
    private var rowCount: Int {
        switch scope {
        case .allStale: model.devices.count(where: DeviceFilter.allStale.matches)
        case .overOneYear: model.devices.count(where: DeviceFilter.overOneYear.matches)
        case .unmanaged: model.devices.count(where: DeviceFilter.unmanaged.matches)
        case .protectAll: model.protectDevices.count
        case .protectStale: model.protectStaleDevices.count
        }
    }

    private var canExport: Bool {
        rowCount >= 0 && (scope.isProtect || !columns.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Report") {
                    TextField("Title", text: $title)
                    Picker("Scope", selection: $scope) {
                        ForEach(availableScopes) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    LabeledContent("Rows", value: "\(rowCount)")
                }

                if !scope.isProtect {
                    Section {
                        ForEach(ReportColumn.allCases) { column in
                            Toggle(column.title, isOn: binding(for: column))
                        }
                    } header: {
                        Text("Columns")
                    } footer: {
                        if columns.isEmpty {
                            Text("Select at least one column.")
                                .foregroundStyle(.red)
                        }
                    }
                } else {
                    Section {
                        Text("Host Name, Serial Number, Last Check-in, Days Stale")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Columns")
                    }
                }

                Section {
                    Toggle("Include summary section", isOn: $includeSummary)
                }

                Section {
                    ForEach(CleanupExportFormat.allCases) { format in
                        Button {
                            export(format)
                        } label: {
                            Label("Export as \(format.displayName)", systemImage: format.systemImage)
                        }
                        .disabled(!canExport)
                    }
                } header: {
                    Text("Export")
                } footer: {
                    Text("Files can be saved or shared. CSV opens in Excel or Numbers; Markdown suits wikis and tickets; PDF is print-ready.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Report Builder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .fileExporter(
                isPresented: $isExporting,
                document: document,
                contentType: contentType,
                defaultFilename: exportName
            ) { _ in
                document = nil
            }
        }
        .frame(minWidth: 460, minHeight: 540)
        .task {
            // Ensure Protect data is present if a Protect scope is picked.
            if protectScopesAvailable && !model.protectLoaded {
                await model.refresh()
            }
        }
    }

    private func binding(for column: ReportColumn) -> Binding<Bool> {
        Binding(
            get: { columns.contains(column) },
            set: { isOn in
                if isOn { columns.insert(column) } else { columns.remove(column) }
            }
        )
    }

    private func export(_ format: CleanupExportFormat) {
        let table = buildTable()
        document = ExportDocument(data: exportData(table, as: format))
        contentType = format.utType
        exportName = ExportNaming.filename("Helios", scope.title, date: Date())
        isExporting = true
    }

    private func buildTable() -> ReportTable {
        let now = Date()
        let subtitle = "Scope: \(scope.title)"
        switch scope {
        case .allStale, .overOneYear, .unmanaged:
            let filter: DeviceFilter = switch scope {
            case .overOneYear: .overOneYear
            case .unmanaged: .unmanaged
            default: .allStale
            }
            let devices = model.devices.filter(filter.matches)
            return ReportBuilders.deviceTable(
                title: title,
                subtitle: subtitle,
                devices: devices,
                columns: Array(columns),
                staleDays: model.settings.staleDays,
                includeSummary: includeSummary,
                generatedAt: now
            )
        case .protectAll:
            return ReportBuilders.protectTable(
                title: title, subtitle: subtitle,
                devices: model.protectDevices,
                staleDays: model.settings.staleDays,
                includeSummary: includeSummary, generatedAt: now
            )
        case .protectStale:
            return ReportBuilders.protectTable(
                title: title, subtitle: subtitle,
                devices: model.protectStaleDevices,
                staleDays: model.settings.staleDays,
                includeSummary: includeSummary, generatedAt: now
            )
        }
    }
}
