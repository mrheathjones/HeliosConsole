//
//  ComputerHistoryService.swift
//  HeliosConsole
//
//  Fetches a computer's Policy Logs + MDM command history from the Jamf
//  **Classic** API (`/JSSResource/computerhistory/id/{id}`). There is no
//  modern Jamf Pro (v1/v2) equivalent for these datasets, so Classic is
//  unavoidable here.
//
//  Token routing mirrors ComputerSearchService: it resolves on the
//  `.deviceSearch` scope so history reads follow the exact same master/user
//  credential decision as device-detail loads (a read scope, master by
//  default). No new CredentialScope is introduced.
//

import Foundation

// MARK: - Error

enum ComputerHistoryError: LocalizedError {
    case invalidURL
    case notAuthenticated
    case computerNotFound
    case httpError(statusCode: Int, message: String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL configuration"
        case .notAuthenticated:
            return "Authentication required. Please log in."
        case .computerNotFound:
            return "No history found for this computer"
        case .httpError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        case .decoding(let message):
            return "Failed to parse history: \(message)"
        }
    }
}

// MARK: - Service

@MainActor
final class ComputerHistoryService: ObservableObject {

    // MARK: Private state

    private var cachedBearerToken: String?
    private var tokenExpiration: Date?

    private var configuration: MDMConfiguration {
        MDMConfigurationManager.shared.configuration
    }

    private var jamfURL: String { configuration.jamfURL }

    // MARK: Public API

    /// Fetch Policy Logs + MDM command history for a computer.
    ///
    /// We request the whole `computerhistory` record and decode only the two
    /// buckets we render. (Classic's combined-subset path — `subset/A&B` — is
    /// brittle to URL-encode; the full record is the robust choice, and Policy
    /// Logs dominate the payload regardless of subset narrowing.)
    func fetchHistory(id: String) async throws -> ComputerHistory {
        let token = try await getBearerToken()

        guard let url = URL(string: "\(jamfURL)/JSSResource/computerhistory/id/\(id)") else {
            throw ComputerHistoryError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = NetworkTuning.requestTimeout
        // Classic defaults to XML; ask for JSON explicitly. `computerhistory`
        // honors this header.
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ComputerHistoryError.httpError(statusCode: -1, message: "No HTTP response")
        }

        if http.statusCode == 404 {
            throw ComputerHistoryError.computerNotFound
        }

        guard (200...299).contains(http.statusCode) else {
            let message = String(data: data.prefix(300), encoding: .utf8) ?? "Unknown error"
            throw ComputerHistoryError.httpError(statusCode: http.statusCode, message: message)
        }

        // Log the raw payload prefix so the response shape is visible in
        // Console even when decoding "succeeds" into an empty result.
        let raw = String(data: data, encoding: .utf8) ?? ""
        NSLog("📥 computerhistory raw (first 1500): %@", String(raw.prefix(1500)))

        // Classic is supposed to honor `Accept: application/json`, but if it
        // ever returns XML the JSON decode fails with an opaque error — detect
        // and report it plainly.
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") {
            throw ComputerHistoryError.decoding(
                "Jamf returned XML, not JSON. Response began: \(String(raw.prefix(160)))"
            )
        }

        do {
            let decoded = try JSONDecoder().decode(ComputerHistoryResponse.self, from: data)
            return decoded.computerHistory ?? .empty
        } catch {
            throw ComputerHistoryError.decoding(
                "\(error.localizedDescription) — response began: \(String(raw.prefix(160)))"
            )
        }
    }

    // MARK: Token

    /// Mirrors ComputerSearchService.getBearerToken(): route on `.deviceSearch`.
    /// User → shared per-user session (fail-closed); master → mint/cached from
    /// the MDM master client.
    private func getBearerToken() async throws -> String {
        if configuration.credentialSource(for: .deviceSearch) == .user {
            return try await JamfUserSession.shared.bearerToken()
        }

        if let token = cachedBearerToken,
           let expiration = tokenExpiration,
           expiration > Date().addingTimeInterval(60) {
            return token
        }

        let masterClientID = configuration.masterClientID
        let masterClientSecret = configuration.masterClientSecret

        guard let url = URL(string: "\(jamfURL)/api/v1/oauth/token") else {
            throw ComputerHistoryError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = NetworkTuning.connectionTimeout
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
        request.httpBody = "grant_type=client_credentials&client_id=\(masterClientID)&client_secret=\(masterClientSecret)"
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ComputerHistoryError.httpError(statusCode: code, message: message)
        }

        struct TokenResponse: Codable {
            let access_token: String
            let expires_in: Int
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        cachedBearerToken = tokenResponse.access_token
        tokenExpiration = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in))
        return tokenResponse.access_token
    }
}
