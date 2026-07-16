//
//  AuthViewModel.swift
//  Helios
//
//  Authentication view model for managing user sessions
//

import SwiftUI
import AppKit
import Combine
import LocalAuthentication

class AuthViewModel: ObservableObject {
    @Published var isLoggedIn = false {
        didSet {
            if isLoggedIn { startIdleLockIfNeeded() } else { stopIdleLock() }
        }
    }
    @Published var currentUser: User?
    @Published var hasSeenWelcome: Bool {
        didSet {
            UserDefaults.standard.set(hasSeenWelcome, forKey: "hasSeenWelcome")
        }
    }
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showBiometricPrompt = false
    /// True while a persisted Entra refresh token is being redeemed at
    /// launch — WelcomeLoginView shows a progress state instead of flashing
    /// the login form before the outcome is known.
    @Published var isRestoringEntraSession = false

    private let keychain = KeychainManager.shared
    let biometricManager = BiometricAuthManager()

    /// Entra refresh token parked while the biometric gate is up on a cold
    /// restore. Redeemed only after a successful unlock — an unlock alone is
    /// never a session in Entra mode (fail-closed).
    private var pendingEntraRefreshToken: String?

    // Idle lock (ui.authentication sessionTimeout)
    private var activityMonitor: Any?
    private var idleCheckTimer: Timer?
    private var lastActivityAt = Date()

    // MARK: - Managed configuration (ui.authentication; absent block = defaults)

    private var mdmConfiguration: MDMConfiguration {
        MDMConfigurationManager.shared.configuration
    }

    var signInMethod: MDMConfiguration.SignInMethod { mdmConfiguration.signInMethod }
    var isEntraSignInConfigured: Bool { mdmConfiguration.isEntraSignInConfigured }

    private var authenticationSettings: AuthenticationSettings? { mdmConfiguration.authentication }
    private var requireBiometric: Bool { authenticationSettings?.effectiveRequireBiometric ?? false }
    var isBiometricSetupAllowed: Bool { authenticationSettings?.effectiveAllowBiometricSetup ?? true }
    private var sessionTimeoutMinutes: Int { authenticationSettings?.effectiveSessionTimeoutMinutes ?? 0 }
    private var allowRememberMe: Bool { authenticationSettings?.effectiveAllowRememberMe ?? true }

    /// Whether restore / idle lock must pass through the biometric prompt.
    /// requireBiometric (managed) overrides the user's local opt-out, but
    /// missing hardware never locks an operator out — log and proceed.
    private var biometricGateActive: Bool {
        guard biometricManager.biometricType != .none else {
            if requireBiometric {
                NSLog("⚠️ requireBiometric is set but no biometric hardware is available — proceeding without the gate")
            }
            return false
        }
        return biometricManager.isBiometricEnabled || requireBiometric
    }

    init() {
        self.hasSeenWelcome = UserDefaults.standard.bool(forKey: "hasSeenWelcome")
        restoreSession()
    }

    deinit {
        if let activityMonitor {
            NSEvent.removeMonitor(activityMonitor)
        }
        idleCheckTimer?.invalidate()
    }

    // MARK: - Session restore

    private func restoreSession() {
        guard allowRememberMe else {
            // Managed policy: sessions never persist. Wipe anything left
            // over (incl. the Entra refresh token) — fresh sign-in required.
            clearSession()
            return
        }
        switch signInMethod {
        case .entra:
            restoreEntraSession()
        case .email:
            restoreEmailSession()
        }
    }

    private func restoreEmailSession() {
        guard let authToken = keychain.loadAuthToken(),
              !authToken.isEmpty else {
            return
        }

        let email = keychain.loadUserEmail() ?? ""
        let name = keychain.loadUserName() ?? ""
        let refreshToken = keychain.loadRefreshToken()

        guard !email.isEmpty else {
            clearSession()
            return
        }

        self.currentUser = User(
            email: email,
            name: name,
            authToken: authToken,
            refreshToken: refreshToken
        )

        if biometricGateActive {
            // Capabilities are established only after the unlock succeeds
            // (see authenticateWithBiometrics) — a pending prompt is not a
            // session.
            showBiometricPrompt = true
        } else {
            establishMDMSession(email: email, displayName: name)
            self.isLoggedIn = true
        }
    }

    private func restoreEntraSession() {
        // The legacy authToken slot is NOT the session key in Entra mode;
        // only a redeemable refresh token constitutes a session.
        guard let refreshToken = keychain.loadEntraRefreshToken(),
              !refreshToken.isEmpty else {
            return
        }

        let email = keychain.loadUserEmail() ?? ""
        let name = keychain.loadUserName() ?? ""
        currentUser = User(email: email, name: name, authToken: "", refreshToken: nil)

        if biometricGateActive {
            pendingEntraRefreshToken = refreshToken
            showBiometricPrompt = true
        } else {
            redeemEntraRefreshToken(refreshToken)
        }
    }

    private func redeemEntraRefreshToken(_ refreshToken: String) {
        isRestoringEntraSession = true
        Task { @MainActor in
            defer { self.isRestoringEntraSession = false }

            guard let service = EntraAuthService(configuration: self.mdmConfiguration) else {
                NSLog("⚠️ Entra session restore aborted: sign-in is no longer configured")
                self.failEntraRestore()
                return
            }
            do {
                // Fail-closed revalidation: the roles come from the FRESH
                // token — a role revoked since last sign-in ends the session.
                let identity = try await service.refreshSession(refreshToken: refreshToken)
                self.establishEntraSession(with: identity)
                NSLog("✅ Entra session restored (roles: %@)", identity.roles.joined(separator: ", "))
            } catch {
                // Any refresh failure → signed out. No cached-capability fallback.
                NSLog("⚠️ Entra session refresh failed (fail-closed): %@", error.localizedDescription)
                self.failEntraRestore()
            }
        }
    }

    @MainActor
    private func failEntraRestore() {
        currentUser = nil
        showBiometricPrompt = false
        clearSession()
        isLoggedIn = false
    }

    // MARK: - Biometrics

    func authenticateWithBiometrics(completion: ((Bool) -> Void)? = nil) {
        biometricManager.authenticate(reason: "Unlock \(Branding.productName)") { [weak self] success, error in
            guard let self = self else { return }

            DispatchQueue.main.async {
                if success {
                    self.showBiometricPrompt = false
                    // Branch on the CONFIGURED method, never on whether a
                    // token happens to be parked: establishMDMSession
                    // resolves from the access `role` key, which is ignored
                    // outright under signIn.method=entra, so inferring the
                    // mode from a nil pendingEntraRefreshToken would resolve
                    // Entra capabilities from a key that has no authority.
                    if self.signInMethod == .entra {
                        guard let pendingToken = self.pendingEntraRefreshToken else {
                            // Entra mode with nothing parked: no token to
                            // revalidate, and no other admissible source of
                            // role names — only a full Microsoft sign-in may
                            // unlock (fail-closed).
                            NSLog("⚠️ Biometric unlock in Entra mode with no parked refresh token — requiring full sign-in (fail-closed)")
                            self.currentUser = nil
                            self.clearSession()
                            self.isLoggedIn = false
                            self.errorMessage = "Please sign in with Microsoft to continue."
                            completion?(false)
                            return
                        }
                        // Cold restore in Entra mode: unlocking is not a
                        // session — the refresh token still has to be
                        // redeemed for freshly resolved capabilities
                        // (fail-closed).
                        self.pendingEntraRefreshToken = nil
                        self.redeemEntraRefreshToken(pendingToken)
                    } else {
                        // Email mode: re-resolve capabilities from the
                        // CURRENT profile on every unlock, so a role edit
                        // applies at idle-unlock as well as at launch.
                        let user = self.currentUser
                        self.establishMDMSession(
                            email: user?.email ?? "",
                            displayName: user?.name ?? ""
                        )
                        self.isLoggedIn = true
                    }
                    completion?(true)
                } else {
                    if let error = error {
                        self.errorMessage = self.biometricManager.getErrorDescription(error)
                    }

                    if let laError = error as? LAError, laError.code == .userCancel {
                        self.clearSession()
                        self.currentUser = nil
                        self.showBiometricPrompt = false
                    }

                    completion?(false)
                }
            }
        }
    }

    // MARK: - Email sign-in

    func loginWithEmail(_ email: String, completion: ((Bool) -> Void)? = nil) {
        isLoading = true
        errorMessage = nil

        Task { @MainActor in
            do {
                // Authenticate with Jamf Pro API using the master credentials
                NSLog("🔐 Authenticating with Jamf Pro for: %@", email)

                let jamfCredentials = try await JamfAPIService.shared.authenticateWithEmail(email)

                NSLog("✅ Jamf credentials received")
                NSLog("   Client ID: %@...", String(jamfCredentials.clientID.prefix(12)))

                // Save Jamf credentials to Keychain for API calls
                let credentialsSaved = keychain.saveJamfCredentials(jamfCredentials)

                if !credentialsSaved {
                    NSLog("⚠️ Failed to save Jamf credentials to Keychain")
                }

                // Extract name from email or use default
                let name = email.components(separatedBy: "@").first?.capitalized ?? "User"

                // Create user object
                let user = User(
                    email: email,
                    name: name,
                    authToken: jamfCredentials.clientID,
                    refreshToken: nil
                )

                // Save user info to keychain
                let userSaved = saveUserToKeychain(user)

                if userSaved && credentialsSaved {
                    self.currentUser = user
                    self.hasSeenWelcome = true
                    // Capabilities BEFORE isLoggedIn — the UI reads them the
                    // moment it renders.
                    self.establishMDMSession(email: email, displayName: name)
                    self.isLoggedIn = true
                    self.isLoading = false
                    NSLog("✅ Login successful")
                    completion?(true)
                } else {
                    self.errorMessage = "Failed to save credentials securely"
                    self.isLoading = false
                    completion?(false)
                }

            } catch let error as JamfAPIError {
                NSLog("❌ Jamf API error: %@", error.localizedDescription)
                self.errorMessage = error.localizedDescription
                self.isLoading = false
                completion?(false)

            } catch {
                NSLog("❌ Login error: %@", error.localizedDescription)
                self.errorMessage = "Authentication failed: \(error.localizedDescription)"
                self.isLoading = false
                completion?(false)
            }
        }
    }

    // MARK: - Entra sign-in

    func loginWithEntra(completion: ((Bool) -> Void)? = nil) {
        guard isEntraSignInConfigured,
              let service = EntraAuthService(configuration: mdmConfiguration) else {
            errorMessage = EntraAuthService.AuthError.notConfigured.errorDescription
            completion?(false)
            return
        }

        isLoading = true
        errorMessage = nil

        Task { @MainActor in
            do {
                let identity = try await service.signInInteractively()
                self.establishEntraSession(with: identity)
                NSLog("✅ Entra sign-in successful (roles: %@)", identity.roles.joined(separator: ", "))
                // Jamf provisioning is non-fatal and can stall for the full
                // request timeout when Jamf is unreachable — run it off the
                // sign-in critical path so the user lands in the app now.
                Task { @MainActor in
                    await self.provisionJamfCredentialsIfEnabled(email: identity.email)
                }
                completion?(true)
            } catch EntraAuthService.AuthError.cancelled {
                // User closed the Microsoft window — not an error state.
                self.isLoading = false
                completion?(false)
            } catch let error as EntraAuthService.AuthError {
                // .notAuthorized already carries its role-assignment guidance.
                self.errorMessage = error.errorDescription
                self.isLoading = false
                completion?(false)
            } catch {
                self.errorMessage = "Sign-in failed: \(error.localizedDescription)"
                self.isLoading = false
                completion?(false)
            }
        }
    }

    /// NON-FATAL per-user Jamf provisioning after Entra verified the email —
    /// dashboards run on the master credentials; only per-user attribution
    /// and search degrade when this fails.
    @MainActor
    private func provisionJamfCredentialsIfEnabled(email: String) async {
        guard mdmConfiguration.effectiveProvisionJamfCredentials else { return }
        do {
            NSLog("🔐 Provisioning per-user Jamf credentials for Entra-verified email")
            let jamfCredentials = try await JamfAPIService.shared.authenticateWithEmail(email)
            if !keychain.saveJamfCredentials(jamfCredentials) {
                NSLog("⚠️ Failed to save Jamf credentials to Keychain")
            }
        } catch {
            NSLog("⚠️ Per-user Jamf provisioning failed (non-fatal): %@", error.localizedDescription)
        }
    }

    // MARK: - Capability resolution
    //
    // Capabilities come from the CONFIG, always — never from the app. Both
    // sign-in modes resolve the identity's role NAMES against the access
    // domain's role definitions:
    //   • Entra: the id_token roles claim (re-resolved from the FRESH token
    //     on every restore/unlock, so a revocation applies at launch and at
    //     idle-unlock).
    //   • Email/MDM: the access domain's single `role` key.
    // A name matching no definition contributes nothing, and no match at all
    // means .none — the user is signed in but sees the empty state.

    /// Establishes the MDM-role session for the email flow. Deliberately
    /// NEVER refuses sign-in: an org whose profile is missing or whose
    /// `role` names nothing would otherwise be hard-locked out of the app
    /// with no way to see the error. They sign in to an empty state instead.
    ///
    /// Non-isolated, and synchronous on the main thread when possible, for
    /// the same reason as `clearSession()`: callers set `isLoggedIn = true`
    /// on the next line, and a deferred establish would leave the UI reading
    /// `.none` for a tick — flashing the empty state at a fully entitled
    /// user. (Also callable from `init` → `restoreEmailSession`, which is
    /// not MainActor-isolated.)
    private func establishMDMSession(email: String, displayName: String) {
        let roleName = mdmConfiguration.mdmRoleName
        let capabilities = mdmConfiguration.capabilities(forRoleNames: [roleName])

        // Diagnose the two failures separately — they need different fixes.
        // "No matching definition" is a NAME test, not a capability test: a
        // role that IS defined but lists nothing also resolves to .none, and
        // reporting that as a name mismatch sends the admin hunting a typo
        // that isn't there.
        if roleName.isEmpty {
            NSLog("⚠️ No access-domain 'role' delivered — signing in with NO capabilities (fail-closed)")
        } else if mdmConfiguration.roleDefinitions[roleName] == nil {
            NSLog("⚠️ Access-domain role '%@' matches no definition in the profile's roles block — signing in with NO capabilities (fail-closed; role names are case-sensitive)", roleName)
        } else if capabilities == .none {
            NSLog("⚠️ Access-domain role '%@' IS defined in the profile's roles block but grants nothing — signing in with NO capabilities (add modules/actions to the definition)", roleName)
        }

        let roles = roleName.isEmpty ? [] : [roleName]
        let establish: @MainActor () -> Void = {
            UserSession.shared.establish(
                email: email,
                displayName: displayName,
                roles: roles,
                capabilities: capabilities
            )
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated(establish)
        } else {
            Task { @MainActor in establish() }
        }
    }

    /// Shared tail of interactive Entra sign-in and refresh restore. The
    /// legacy authToken slot stays empty in Entra mode — the refresh token
    /// is the only session key.
    @MainActor
    private func establishEntraSession(with identity: EntraIdentity) {
        if !allowRememberMe {
            NSLog("ℹ️ allowRememberMe is disabled by policy — Entra session will not persist")
        } else if let refreshToken = identity.refreshToken, !refreshToken.isEmpty {
            if !keychain.saveEntraRefreshToken(refreshToken) {
                NSLog("⚠️ Failed to save the Entra refresh token — session won't survive relaunch")
            }
        } else {
            NSLog("⚠️ Microsoft returned no refresh token — session won't survive relaunch")
        }
        _ = keychain.saveUserEmail(identity.email)
        _ = keychain.saveUserName(identity.displayName)

        // Resolved from the token's roles against the CURRENT config, so a
        // role revoked in Entra OR withdrawn from the profile takes effect
        // on the next restore/unlock. EntraAuthService's gate tested only
        // that a role NAME exists in the profile — it says nothing about
        // what that name grants — so .none here is not necessarily a
        // mid-session profile change: a defined role whose lists are all
        // empty resolves the same way. Either way the user lands on the
        // empty state, fail-closed.
        let capabilities = mdmConfiguration.capabilities(forRoleNames: identity.roles)
        UserSession.shared.establish(
            email: identity.email,
            displayName: identity.displayName,
            roles: identity.roles,
            capabilities: capabilities
        )
        currentUser = User(email: identity.email, name: identity.displayName, authToken: "", refreshToken: nil)
        hasSeenWelcome = true
        isLoggedIn = true
        isLoading = false
    }

    func logout() {
        currentUser = nil
        errorMessage = nil
        clearSession()
        isLoggedIn = false
        showBiometricPrompt = false
    }

    func enableBiometricAuth() {
        biometricManager.setBiometricEnabled(true)
    }

    func disableBiometricAuth() {
        biometricManager.setBiometricEnabled(false)
    }

    private func saveUserToKeychain(_ user: User) -> Bool {
        var allSuccess = true

        allSuccess = keychain.saveAuthToken(user.authToken) && allSuccess
        allSuccess = keychain.saveUserEmail(user.email) && allSuccess
        allSuccess = keychain.saveUserName(user.name) && allSuccess

        if let refreshToken = user.refreshToken {
            allSuccess = keychain.saveRefreshToken(refreshToken) && allSuccess
        }

        return allSuccess
    }

    func clearSession() {
        pendingEntraRefreshToken = nil
        keychain.clearAllAuthData()
        clearUserSession()
    }

    /// Wipes the app-wide identity/capability holder WITHOUT touching the
    /// keychain — the idle-lock path needs exactly this, since the stored
    /// credentials must survive so biometric/re-login can restore them.
    ///
    /// Clears synchronously when possible: deferring the wipe past the
    /// caller's isLoggedIn=false would leave stale capabilities/roles
    /// readable for a tick, and a fast re-login's establish could be
    /// clobbered by the late clear.
    private func clearUserSession() {
        if Thread.isMainThread {
            MainActor.assumeIsolated { UserSession.shared.clear() }
        } else {
            Task { @MainActor in
                UserSession.shared.clear()
            }
        }
    }

    func markWelcomeAsSeen() {
        hasSeenWelcome = true
    }

    func resetApp() {
        hasSeenWelcome = false
        currentUser = nil
        isLoggedIn = false
        errorMessage = nil
        showBiometricPrompt = false
        clearSession()
        biometricManager.setBiometricEnabled(false)
        UserDefaults.standard.removeObject(forKey: "hasSeenWelcome")
    }

    // MARK: - Idle lock (ui.authentication sessionTimeout)

    private func startIdleLockIfNeeded() {
        stopIdleLock()
        guard sessionTimeoutMinutes > 0 else { return }

        lastActivityAt = Date()
        activityMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        ) { [weak self] event in
            // Coalesce: the idle check runs on 30 s granularity, so
            // sub-second rewrites (scrollWheel fires per tick) are noise.
            if let self, Date().timeIntervalSince(self.lastActivityAt) > 1 {
                self.lastActivityAt = Date()
            }
            return event
        }

        let timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkIdleTimeout()
        }
        timer.tolerance = 5
        idleCheckTimer = timer
    }

    private func stopIdleLock() {
        if let activityMonitor {
            NSEvent.removeMonitor(activityMonitor)
            self.activityMonitor = nil
        }
        idleCheckTimer?.invalidate()
        idleCheckTimer = nil
    }

    private func checkIdleTimeout() {
        guard isLoggedIn, sessionTimeoutMinutes > 0 else { return }
        let limit = TimeInterval(sessionTimeoutMinutes) * 60
        guard Date().timeIntervalSince(lastActivityAt) >= limit else { return }
        lockForIdleTimeout()
    }

    private func lockForIdleTimeout() {
        NSLog("🔒 Session locked after %d minutes of inactivity", sessionTimeoutMinutes)
        isLoggedIn = false

        if biometricGateActive {
            if signInMethod == .entra {
                // Entra mode: an unlock is never a session — park the
                // refresh token so a successful unlock routes through
                // redeemEntraRefreshToken (fresh id_token → freshly resolved
                // capabilities, fail-closed), exactly like cold restore. A
                // role revoked since sign-in must not survive the unlock.
                guard let refreshToken = keychain.loadEntraRefreshToken(),
                      !refreshToken.isEmpty else {
                    // No redeemable token (e.g. allowRememberMe off) means
                    // revalidation is impossible — only a full Microsoft
                    // sign-in may unlock (fail-closed).
                    currentUser = nil
                    clearSession()
                    errorMessage = "Session locked due to inactivity. Please sign in again."
                    return
                }
                pendingEntraRefreshToken = refreshToken
            }
            // Cancel/failure falls back to full sign-in via clearSession
            // (existing prompt behavior).
            showBiometricPrompt = true
        } else if signInMethod == .entra {
            // No biometric gate in Entra mode: only a full Microsoft
            // sign-in may unlock — fail-closed.
            currentUser = nil
            clearSession()
            errorMessage = "Session locked due to inactivity. Please sign in again."
        } else {
            // Email mode: the keychain stays intact so the login screen (or
            // a later biometric unlock) can re-authenticate — but UserSession
            // must NOT keep serving the locked-out operator's identity and
            // capabilities to services and command handlers for the whole
            // locked window. Both restore paths re-establish it before
            // setting isLoggedIn.
            clearUserSession()
            errorMessage = "Session locked due to inactivity. Please sign in again."
        }
    }
}
