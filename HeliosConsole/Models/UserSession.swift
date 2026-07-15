//
//  UserSession.swift
//  HeliosConsole
//
//  App-wide identity/tier holder, deliberately decoupled from the view
//  hierarchy so services and command handlers can gate on the operator's
//  access tier without reaching into SwiftUI environment objects.
//

import Foundation
import Combine

@MainActor
final class UserSession: ObservableObject {
    static let shared = UserSession()

    @Published private(set) var tier: UserAccessTier = .none
    /// Raw app-role values from the Entra token's roles claim (empty in
    /// email mode). Read by role-set gates — e.g. the Cleanup module's
    /// `signIn.entra.cleanupRoles` check — alongside the derived tier.
    @Published private(set) var roles: [String] = []
    @Published private(set) var email: String = ""
    @Published private(set) var displayName: String = ""

    private init() {}

    func establish(tier: UserAccessTier, roles: [String], email: String, displayName: String) {
        self.tier = tier
        self.roles = roles
        self.email = email
        self.displayName = displayName
    }

    /// Fail-closed reset to defaults (tier .none, no identity, no roles).
    func clear() {
        tier = .none
        roles = []
        email = ""
        displayName = ""
    }
}
