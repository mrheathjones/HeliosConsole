//
//  DeviceActionsMenu.swift
//  Helios
//
//  The device Actions menu and the presentation flow behind it: which
//  confirmation stage or sheet is showing, the typed-ERASE text, and the
//  Return to Service plan snapshot. Execution itself lives in
//  DeviceCommandExecutor.
//

import SwiftUI
import Observation

// MARK: - Action Flow

@Observable
@MainActor
final class DeviceActionFlow {
    var pendingAction: DeviceAction?
    /// First stage for destructive actions (Erase Device / Return to Service):
    /// a plain-language danger warning shown BEFORE the typed-ERASE
    /// acknowledgement, so the stakes and the specifics are two deliberate
    /// steps rather than one dialog the operator can click through.
    var showingDestructiveWarning: Bool = false
    var showingActionConfirmation: Bool = false
    /// Typed confirmation for destructive actions (operator must type ERASE).
    var confirmationText: String = ""
    /// Snapshot of the Return to Service plan taken when the confirmation
    /// dialog opens: the executed steps must be exactly the steps the
    /// operator confirmed, even if a profile re-push lands mid-dialog.
    var pendingRTSPlan: DeviceCommandExecutor.ReturnToServicePlan? = nil
    var showingUnlockAccountSheet: Bool = false
    var unlockUsername: String = ""
    var showingABMAssignSheet: Bool = false
    var showingPreStageAssignSheet: Bool = false
    var showingSiteMoveSheet: Bool = false

    /// Routes a granted menu action: Unlock User Account opens its own
    /// sheet; everything else goes through the confirmation overlay.
    func trigger(_ action: DeviceAction, executor: DeviceCommandExecutor) {
        let actionPolicy = DeviceActionPolicy.currentForComputers
        if action == .unlockUserAccount {
            showingUnlockAccountSheet = true
            return
        }
        if action == .abmAssign {
            // Server selection happens inside the sheet, so it owns the
            // whole flow (like the unlock-account sheet). Same defense in
            // depth as DeviceCommandExecutor.execute: never trust the menu
            // filter alone.
            if let denial = actionPolicy.denialReason(for: .abmAssign) {
                Task { await executor.reportActionDenial(denial, for: .abmAssign) }
            } else {
                showingABMAssignSheet = true
            }
            return
        }
        if action == .assignPreStage {
            // PreStage selection + optional asset tag happen inside the
            // sheet, so it owns the whole flow (like abmAssign). Same
            // defense in depth: never trust the menu filter alone.
            if let denial = actionPolicy.denialReason(for: .assignPreStage) {
                Task { await executor.reportActionDenial(denial, for: .assignPreStage) }
            } else {
                showingPreStageAssignSheet = true
            }
            return
        }
        if action == .moveToSite {
            // Site selection happens inside the sheet, so it owns the whole
            // flow (like abmAssign / assignPreStage). Same defense in depth:
            // never trust the menu filter alone. Note denialReason also
            // catches the empty-allowedSites case, so a role granted the
            // action with no sites reaches the audit log rather than an
            // empty picker.
            if let denial = actionPolicy.denialReason(for: .moveToSite) {
                Task { await executor.reportActionDenial(denial, for: .moveToSite) }
            } else {
                showingSiteMoveSheet = true
            }
            return
        }
        if action == .returnToService {
            // Freeze the plan the confirmation dialog will describe.
            pendingRTSPlan = DeviceCommandExecutor.ReturnToServicePlan(
                options: actionPolicy.returnToServiceOptions(),
                entraConfigured: MDMConfigurationManager.shared.configuration.isEntraConfigured
            )
        }
        pendingAction = action
        // Destructive actions get the danger warning first; the typed-ERASE
        // acknowledgement only opens once the operator clears that stage.
        if action.isDestructive && action.dangerWarning != nil {
            showingDestructiveWarning = true
        } else {
            showingActionConfirmation = true
        }
    }

    /// Clears every stage of the destructive-action flow. Used by Cancel and
    /// by the scrim tap so no stage can be left armed behind another.
    func dismissConfirmation() {
        showingDestructiveWarning = false
        showingActionConfirmation = false
        pendingAction = nil
        confirmationText = ""
    }

    /// Runs the confirmed action with the plan snapshotted for it.
    func execute(_ action: DeviceAction, with executor: DeviceCommandExecutor, openURL: OpenURLAction) {
        let plan = pendingRTSPlan
        Task {
            await executor.execute(action, returnToServicePlan: plan, openURL: openURL) { sheetAction in
                self.presentSheet(for: sheetAction)
            }
        }
    }

    /// Opens the sheet that owns a sheet-driven action's flow.
    func presentSheet(for action: DeviceAction) {
        switch action {
        case .unlockUserAccount: showingUnlockAccountSheet = true
        case .abmAssign: showingABMAssignSheet = true
        case .assignPreStage: showingPreStageAssignSheet = true
        case .moveToSite: showingSiteMoveSheet = true
        default: break
        }
    }
}

// MARK: - Actions Menu

/// Menu contents are driven entirely by the policy — the access
/// profile's deviceActions allow-list intersected with the user's role
/// capabilities: only granted actions render, sections with no granted
/// action disappear, and the profile's displayName override (menu label
/// only) is honored. Grouping/order stay app-defined. Takes the policy
/// bound by the caller so one render evaluates it once (execution paths
/// still read it fresh).
struct DeviceActionsMenu: View {
    let policy: DeviceActionPolicy
    let isExecuting: Bool
    let onSelect: (DeviceAction) -> Void

    var body: some View {
        Menu {
            ForEach(DeviceAction.MenuSection.allCases, id: \.self) { section in
                let visibleActions = DeviceAction.allCases.filter {
                    $0.menuSection == section && policy.isAllowed($0)
                }
                if !visibleActions.isEmpty {
                    Section(section.title) {
                        ForEach(visibleActions) { action in
                            Button(role: action.isDestructive ? .destructive : nil) {
                                onSelect(action)
                            } label: {
                                Label(ActionBranding.label(for: action), systemImage: ActionBranding.icon(for: action))
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if isExecuting {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 12, weight: .medium))
                }
                Text("Actions")
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .disabled(isExecuting)
    }
}
