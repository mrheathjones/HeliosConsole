//
//  CleanupSettingsView.swift
//  HeliosConsole
//
//  Cleanup feature settings. Jamf Pro credentials are supplied by Helios's
//  MDM configuration and shown read-only here. The stale threshold and the
//  optional Jamf Protect connection are editable; the Protect password is
//  stored in the Keychain.
//

import SwiftUI

struct CleanupSettingsView: View {
    @Environment(CleanupViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @AppStorage(CleanupSettings.Key.staleDays) private var staleDays = 90
    @AppStorage(CleanupSettings.Key.protectEnabled) private var protectEnabled = false
    @AppStorage(CleanupSettings.Key.protectURL) private var protectURL = ""
    @AppStorage(CleanupSettings.Key.protectClientID) private var protectClientID = ""
    @AppStorage(CleanupSettings.Key.protectAutoCleanup) private var protectAutoCleanup = false

    @State private var protectPassword = ""
    @State private var jamfTestResult: String?
    @State private var jamfTestOK = false
    @State private var protectTestResult: String?
    @State private var protectTestOK = false
    @State private var testing = false

    private var jamfURLDisplay: String {
        model.settings.normalizedJamfURL?.absoluteString ?? "Not configured"
    }

    private var clientIDDisplay: String {
        let id = model.settings.jamfClientID
        guard !id.isEmpty, id != "your-master-client-id" else { return "Not configured" }
        return String(id.prefix(8)) + "…"
    }

    var body: some View {
        Form {
            // MARK: Jamf Pro (MDM-supplied)
            Section {
                LabeledContent("Server URL", value: jamfURLDisplay)
                LabeledContent("API Client", value: clientIDDisplay)

                HStack {
                    Button("Test Connection") { testJamf() }
                        .disabled(testing || !model.settings.isConfigured)
                    if testing { ProgressView().controlSize(.small) }
                    if let jamfTestResult {
                        Label(jamfTestResult, systemImage: jamfTestOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(jamfTestOK ? Color.green : Color.red)
                            .font(.callout)
                    }
                }
            } header: {
                Text("Jamf Pro")
            } footer: {
                Text("Supplied by your Helios MDM configuration profile (the master API client). The role needs: Read/Update/Delete Computers, Read/Update Static Computer Groups, Read Sites, and Send Computer Unmanage Command.")
            }

            // MARK: Stale threshold
            Section {
                Stepper(value: $staleDays, in: 1...730) {
                    LabeledContent("Stale after", value: "\(staleDays) days")
                }
                .onChange(of: staleDays) {
                    Task { await model.refresh() }
                }
            } header: {
                Text("Stale Threshold")
            } footer: {
                Text("Devices with no Jamf Pro check-in for this many days are considered stale.")
            }

            // MARK: Jamf Protect
            Section {
                Toggle("Use Jamf Protect", isOn: $protectEnabled)
                if protectEnabled {
                    TextField("Tenant URL", text: $protectURL, prompt: Text("https://yourorg.protect.jamfcloud.com"))
                    TextField("API Client ID", text: $protectClientID)
                    SecureField("API Client Password", text: $protectPassword, prompt: Text(model.settings.protectClientPassword.isEmpty ? "Paste password" : "•••••••• (saved)"))
                        .onSubmit { saveProtectPassword() }

                    HStack {
                        Button("Test Connection") {
                            saveProtectPassword()
                            testProtect()
                        }
                        .disabled(testing)
                        if let protectTestResult {
                            Label(protectTestResult, systemImage: protectTestOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(protectTestOK ? Color.green : Color.red)
                                .font(.callout)
                        }
                    }

                    Toggle("Auto-delete Protect record on Jamf Pro delete", isOn: $protectAutoCleanup)
                }
            } header: {
                Text("Jamf Protect")
            } footer: {
                Text("Optional. Connect a Jamf Protect tenant to see Protect counts on the dashboard and delete Protect records. The password is stored in the Keychain.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Cleanup Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    saveProtectPassword()
                    dismiss()
                }
            }
        }
        .onDisappear { saveProtectPassword() }
        .frame(width: 560, height: 520)
    }

    // MARK: - Helpers

    private func saveProtectPassword() {
        guard !protectPassword.isEmpty else { return }
        model.settings.protectClientPassword = protectPassword
        protectPassword = ""
        Task { await model.resetClients() }
    }

    private func testJamf() {
        testing = true
        jamfTestResult = nil
        Task {
            switch await model.testJamfConnection() {
            case .success(let message): jamfTestOK = true; jamfTestResult = message
            case .failure(let error): jamfTestOK = false; jamfTestResult = error.localizedDescription
            }
            testing = false
        }
    }

    private func testProtect() {
        testing = true
        protectTestResult = nil
        Task {
            switch await model.testProtectConnection() {
            case .success(let message): protectTestOK = true; protectTestResult = message
            case .failure(let error): protectTestOK = false; protectTestResult = error.localizedDescription
            }
            testing = false
        }
    }
}
