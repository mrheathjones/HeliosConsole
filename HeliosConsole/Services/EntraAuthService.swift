//
//  EntraAuthService.swift
//  HeliosConsole
//
//  Interactive Entra ID operator sign-in: OpenID Connect authorization-code
//  flow with PKCE via ASWebAuthenticationSession. Complements
//  EntraGraphService (app-only client-credentials for device cleanup) —
//  this service authenticates the human operator and returns the id_token's
//  raw roles claim, strictly fail-closed: a token carrying no role DEFINED
//  IN THE PROFILE is rejected outright, never admitted with a default.
//
//  This service does NOT resolve capabilities — it only proves identity and
//  eligibility. AuthViewModel maps the returned role names onto the access
//  domain's role definitions (MDMConfiguration.capabilities(forRoleNames:)),
//  so the config stays the single source of what a role may do.
//
//  Tokens arrive directly from the token endpoint over TLS, so per OIDC
//  Core 3.1.3.7 the id_token signature check may be omitted; claim
//  validation (aud / iss / exp / nonce) is still enforced.
//

import AppKit
import AuthenticationServices
import CryptoKit
import Foundation
import Security

struct EntraIdentity {
    let email: String          // preferred_username, fallback email claim
    let displayName: String    // name claim, fallback email
    let roles: [String]        // raw roles claim; resolved against the profile
    let refreshToken: String?  // from offline_access
    let idTokenExpiresAt: Date
}

final class EntraAuthService: NSObject {

    enum AuthError: LocalizedError {
        case notConfigured
        case cancelled
        case authorizationFailed(String)
        case tokenExchangeFailed(String)
        case invalidIDToken(String)
        case notAuthorized(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Entra sign-in is not configured. Deploy the sign-in settings in the managed configuration profile."
            case .cancelled:
                return "Sign-in was cancelled."
            case .authorizationFailed(let detail):
                return "Microsoft sign-in failed: \(detail)"
            case .tokenExchangeFailed(let detail):
                return "Could not complete sign-in with Microsoft: \(detail)"
            case .invalidIDToken(let detail):
                return "The Microsoft identity token failed validation: \(detail)"
            case .notAuthorized(let detail):
                return detail
            }
        }
    }

    private struct TokenResponse {
        let idToken: String
        var refreshToken: String?
    }

    private static let redirectURI = "heliosauth://callback"
    private static let callbackScheme = "heliosauth"
    private static let scope = "openid profile email offline_access"

    private let tenantId: String
    private let clientId: String
    private let authorityHost: String

    /// The sign-in eligibility gate: `MDMConfiguration.hasAnyDefinedRole` —
    /// the single implementation of the rule — closed over the profile's
    /// role index, snapshotted at init. A closure rather than the
    /// configuration itself so the auth service doesn't retain a copy of it
    /// (it carries Jamf/Entra secrets this service has no business holding).
    ///
    /// Refuses everything when the profile defines no roles. That is
    /// deliberate: with no roles defined, a successful sign-in could only
    /// ever land on an empty app.
    private let hasAnyDefinedRole: ([String]) -> Bool

    /// Role names from the profile, for the refusal log ONLY — never for the
    /// decision, which stays the closure above so the rule has one home.
    /// A name mismatch between the Entra app-role Value and the profile is the
    /// most common setup error and is invisible without this.
    private let definedRoleNamesForDiagnostics: [String]

    private let allowedGroupIds: [String]

    private let session: URLSession

    /// Kept strong for the lifetime of the browser hand-off — deallocating
    /// the ASWebAuthenticationSession mid-flight cancels it.
    private var activeWebAuthSession: ASWebAuthenticationSession?

    init?(configuration: MDMConfiguration) {
        guard configuration.isEntraSignInConfigured else { return nil }
        self.tenantId = configuration.entraSignInTenantId
        self.clientId = configuration.entraSignInClientId
        self.authorityHost = configuration.entraSignInAuthorityHost
        let roleDefinitions = configuration.roleDefinitions
        self.hasAnyDefinedRole = {
            MDMConfiguration.hasAnyDefinedRole(in: $0, definitions: roleDefinitions)
        }
        self.definedRoleNamesForDiagnostics = roleDefinitions.keys.sorted()
        self.allowedGroupIds = configuration.effectiveEntraAllowedGroupIds

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = NetworkTuning.requestTimeout
        cfg.timeoutIntervalForResource = NetworkTuning.requestTimeout * 1.5
        self.session = URLSession(configuration: cfg)
        super.init()
    }

    // MARK: - Public API

    @MainActor
    func signInInteractively() async throws -> EntraIdentity {
        let codeVerifier = Self.randomURLSafeString()
        let codeChallenge = EntraGraphService.base64URLEncode(
            Data(SHA256.hash(data: Data(codeVerifier.utf8)))
        )
        let state = Self.randomURLSafeString()
        let nonce = Self.randomURLSafeString()

        var components = URLComponents(string: "https://\(authorityHost)/\(tenantId)/oauth2/v2.0/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "response_mode", value: "query"),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "prompt", value: "select_account")
        ]
        guard let authorizeURL = components?.url else {
            throw AuthError.authorizationFailed("Could not build the authorize URL")
        }

        let callbackURL = try await runWebAuthSession(url: authorizeURL)

        let params = Self.queryParameters(of: callbackURL)
        // Error before state: an error redirect may omit state, and the
        // real failure must surface instead of "State mismatch".
        if let error = params["error"] {
            throw AuthError.authorizationFailed(params["error_description"] ?? error)
        }
        guard params["state"] == state else {
            throw AuthError.authorizationFailed("State mismatch on the sign-in callback")
        }
        guard let code = params["code"], !code.isEmpty else {
            throw AuthError.authorizationFailed("No authorization code was returned")
        }

        let tokens = try await requestTokens(form: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": clientId,
            "code_verifier": codeVerifier
        ])
        return try identity(from: tokens, expectedNonce: nonce)
    }

    /// Redeem a refresh token for a fresh id_token and re-read the roles
    /// claim from the NEW token (fail-closed revalidation — a role or group
    /// revoked since the last sign-in ends the session; the caller
    /// re-resolves capabilities from these fresh names).
    func refreshSession(refreshToken: String) async throws -> EntraIdentity {
        var tokens = try await requestTokens(form: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientId,
            "scope": Self.scope
        ])
        // Entra may rotate the refresh token; keep the old one when it doesn't.
        if tokens.refreshToken == nil {
            tokens.refreshToken = refreshToken
        }
        return try identity(from: tokens, expectedNonce: nil)
    }

    // MARK: - Browser hand-off

    @MainActor
    private func runWebAuthSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let webSession = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: Self.callbackScheme
            ) { [weak self] callbackURL, error in
                // ASWebAuthenticationSession delivers its completion on the
                // main thread; safe to release the strong reference here.
                self?.activeWebAuthSession = nil
                if let error {
                    if let sessionError = error as? ASWebAuthenticationSessionError,
                       sessionError.code == .canceledLogin {
                        continuation.resume(throwing: AuthError.cancelled)
                    } else {
                        continuation.resume(throwing: AuthError.authorizationFailed(error.localizedDescription))
                    }
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: AuthError.authorizationFailed("No callback URL was returned"))
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            webSession.presentationContextProvider = self
            // Non-ephemeral so the Microsoft Enterprise SSO extension and
            // existing session cookies can satisfy the sign-in silently.
            webSession.prefersEphemeralWebBrowserSession = false
            activeWebAuthSession = webSession
            if !webSession.start() {
                activeWebAuthSession = nil
                continuation.resume(throwing: AuthError.authorizationFailed("Could not open the sign-in window"))
            }
        }
    }

    // MARK: - Token endpoint

    private func requestTokens(form: [String: String]) async throws -> TokenResponse {
        let tokenURLString = "https://\(authorityHost)/\(tenantId)/oauth2/v2.0/token"
        guard let url = URL(string: tokenURLString) else {
            throw AuthError.tokenExchangeFailed("Invalid token endpoint URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = EntraGraphService.formURLEncode(form).data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.tokenExchangeFailed("No HTTP response")
        }
        guard http.statusCode == 200 else {
            let detail = EntraGraphService.extractGraphError(data) ?? "HTTP \(http.statusCode)"
            throw AuthError.tokenExchangeFailed(detail)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let idToken = json["id_token"] as? String, !idToken.isEmpty else {
            throw AuthError.tokenExchangeFailed("Response contained no id_token")
        }
        return TokenResponse(
            idToken: idToken,
            refreshToken: json["refresh_token"] as? String
        )
    }

    // MARK: - id_token validation & authorization

    private func identity(from tokens: TokenResponse, expectedNonce: String?) throws -> EntraIdentity {
        let claims = try validatedClaims(idToken: tokens.idToken, expectedNonce: expectedNonce)

        // Group gate runs before role mapping so a group restriction can
        // never be bypassed by a role match.
        if !allowedGroupIds.isEmpty {
            // Groups overage: Entra omits the groups claim and signals via
            // hasgroups / _claim_names when the user is in too many groups.
            if claims["hasgroups"] != nil || claims["_claim_names"] != nil {
                throw AuthError.notAuthorized(
                    "Your account is in more groups than Microsoft can list inside the sign-in token, so the allowed-groups check cannot be evaluated. Ask your admin to gate Helios Console access with app role assignments instead of group membership."
                )
            }
            let groups = claims["groups"] as? [String] ?? []
            guard groups.contains(where: { allowedGroupIds.contains($0) }) else {
                throw AuthError.notAuthorized(
                    "Your account is not a member of any group allowed to use Helios Console. Contact your admin about Helios role assignment."
                )
            }
        }

        // Sign-in eligibility (MDMConfiguration.hasAnyDefinedRole): the token
        // must carry at least one role that the PROFILE defines. Role names
        // the profile never names — however many the tenant assigns — are
        // not a Helios role and are refused.
        // Shared by interactive sign-in and refresh (both funnel through
        // this method), so revalidation applies the same rule: a role
        // un-assigned in Entra, or removed from the profile, ends the
        // session at the next refresh.
        //
        // Capabilities are NOT derived here — AuthViewModel resolves them
        // from these names against the current configuration.
        let roles = claims["roles"] as? [String] ?? []
        guard hasAnyDefinedRole(roles) else {
            // Console-only: the on-screen copy stays non-technical (an end user
            // is not owed the role taxonomy), but an admin testing setup needs
            // to see WHY — names match exactly and case-sensitively.
            let tokenRoles = roles.isEmpty ? "(none — the token carried no roles claim)" : roles.joined(separator: ", ")
            let defined = definedRoleNamesForDiagnostics.isEmpty
                ? "(none — the access profile delivered no roles block)"
                : definedRoleNamesForDiagnostics.joined(separator: ", ")
            print("⚠️ signIn: refused — no role in the token matches the profile.\n"
                  + "    token roles (Entra app-role Values): \(tokenRoles)\n"
                  + "    defined in access.roles[].name:       \(defined)\n"
                  + "    Names must match EXACTLY (case-sensitive).")
            throw AuthError.notAuthorized(
                "You signed in successfully, but your account has no Helios Console role. Contact your admin about Helios role assignment."
            )
        }

        let preferredUsername = (claims["preferred_username"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let email = preferredUsername ?? (claims["email"] as? String) ?? ""
        let name = (claims["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? email
        let exp = (claims["exp"] as? NSNumber)?.doubleValue ?? 0

        return EntraIdentity(
            email: email,
            displayName: name,
            roles: roles,
            refreshToken: tokens.refreshToken,
            idTokenExpiresAt: Date(timeIntervalSince1970: exp)
        )
    }

    /// Decode the payload segment and validate aud / iss / exp / nonce.
    /// `expectedNonce` is nil on the refresh_token grant (no nonce there).
    private func validatedClaims(idToken: String, expectedNonce: String?) throws -> [String: Any] {
        let segments = idToken.components(separatedBy: ".")
        guard segments.count == 3 else {
            throw AuthError.invalidIDToken("token is not a JWT (expected 3 segments, got \(segments.count))")
        }
        guard let payloadData = Self.base64URLDecode(segments[1]),
              let claims = (try? JSONSerialization.jsonObject(with: payloadData)) as? [String: Any] else {
            throw AuthError.invalidIDToken("could not decode the token payload")
        }

        // aud is a single string in practice, but the JWT spec also allows
        // an array of strings — accept both, refuse any other shape.
        let audMatches: Bool
        switch claims["aud"] {
        case let aud as String: audMatches = aud == clientId
        case let aud as [String]: audMatches = aud.contains(clientId)
        default: audMatches = false
        }
        guard audMatches else {
            throw AuthError.invalidIDToken("audience does not match the configured client id (aud must be the client id string, or a string array containing it)")
        }

        // Exact issuer match, built from the SAME configured values as the
        // endpoints. Intentionally incompatible with tenantId set to
        // "common"/"organizations" — the directory (tenant) GUID is
        // required (see docs/EntraAuthSetup.md).
        let expectedIssuer = "https://\(authorityHost)/\(tenantId)/v2.0"
        let receivedIssuer = claims["iss"] as? String ?? "<missing>"
        guard receivedIssuer == expectedIssuer else {
            throw AuthError.invalidIDToken("issuer mismatch: expected \(expectedIssuer), received \(receivedIssuer.prefix(120))")
        }
        guard let exp = (claims["exp"] as? NSNumber)?.doubleValue,
              Date(timeIntervalSince1970: exp) > Date() else {
            throw AuthError.invalidIDToken("token is expired")
        }
        if let expectedNonce {
            guard let nonce = claims["nonce"] as? String, nonce == expectedNonce else {
                throw AuthError.invalidIDToken("nonce does not match this sign-in attempt")
            }
        }
        return claims
    }

    // MARK: - Helpers

    /// 32 CSPRNG bytes, base64url — used for the PKCE verifier, state, nonce.
    private static func randomURLSafeString() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed (\(status))")
        return EntraGraphService.base64URLEncode(Data(bytes))
    }

    private static func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        return Data(base64Encoded: base64)
    }

    private static func queryParameters(of url: URL) -> [String: String] {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return [:]
        }
        return items.reduce(into: [:]) { $0[$1.name] = $1.value }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension EntraAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow
            ?? NSApplication.shared.windows.first
            ?? ASPresentationAnchor()
    }
}
