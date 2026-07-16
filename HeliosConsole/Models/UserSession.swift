//
//  UserSession.swift
//  HeliosConsole
//
//  App-wide identity/capability holder, deliberately decoupled from the view
//  hierarchy so services and command handlers can gate on what the signed-in
//  operator may do without reaching into SwiftUI environment objects.
//
//  Capabilities are RESOLVED, never derived here: AuthViewModel matches the
//  identity's role names (the Entra roles claim, or the access domain's
//  `role` key) against the profile's role definitions and hands the union in.
//  This type holds the answer and nothing else — no policy lives here.
//

import Foundation
import Combine

@MainActor
final class UserSession: ObservableObject {
    static let shared = UserSession()

    /// Role names the identity presented — the raw Entra roles claim, or the
    /// single access-domain `role` value. Names that match no definition in
    /// the profile appear here but contribute no capability. Kept for display
    /// and audit logging; gate on `capabilities`, never on this.
    @Published private(set) var roles: [String] = []

    /// What the operator may actually do: the union of the profile-defined
    /// roles they hold. `.none` until established — fail-closed.
    @Published private(set) var capabilities: UserCapabilities = .none

    @Published private(set) var email: String = ""
    @Published private(set) var displayName: String = ""

    private init() {}

    func establish(
        email: String,
        displayName: String,
        roles: [String],
        capabilities: UserCapabilities
    ) {
        self.email = email
        self.displayName = displayName
        self.roles = roles
        self.capabilities = capabilities
    }

    /// Fail-closed reset to defaults (no capabilities, no identity, no roles).
    func clear() {
        roles = []
        capabilities = .none
        email = ""
        displayName = ""
    }
}
