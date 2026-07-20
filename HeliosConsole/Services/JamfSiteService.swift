//
//  JamfSiteService.swift
//  HeliosConsole
//
//  Jamf Pro site client for the `moveToSite` device action. Master-credential
//  OAuth per the JamfPreStageService / ComputerInventoryService pattern (this
//  is the DEVICE-scoped site client; the Cleanup module has its own
//  JamfCleanupClient.fetchSites/moveComputer for the bulk-cleanup flow, which
//  runs on separate credentials and cannot be reached from a device view).
//
//  API facts this file is built on (Jamf Pro API):
//    • GET  /api/v1/sites            → [{ id: String, name: String }]
//    • PATCH /api/v3/computers-inventory-detail/{id} with
//      { "general": { "siteId": "<id>" } } moves ONE computer between sites.
//      The WRITE schema takes a flat `siteId` string — NOT the nested
//      { site: { id, name } } object the read returns. `{id}` is the Jamf
//      computer INVENTORY id (Computer.id), not the managementId that MDM
//      commands use.
//

import Foundation

struct JamfSiteRecord: Identifiable, Hashable {
    let id: String
    let name: String
}

enum JamfSiteError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Jamf Pro URL."
        case .invalidResponse:
            return "Invalid response from Jamf Pro."
        case .httpError(let code, let message):
            return "Jamf Pro request failed (\(code)): \(message)"
        }
    }
}

final class JamfSiteService: ObservableObject {

    static let shared = JamfSiteService()
    private init() {}

    private var jamfURL: String {
        MDMConfigurationManager.shared.configuration.jamfURL
    }

    // Token cache. Same discipline as JamfPreStageService: NSLock, never held
    // across an await.
    private let tokenLock = NSLock()
    private var cachedBearerToken: String?
    private var tokenExpiration: Date?

    // MARK: - Auth

    private func cachedValidToken() -> String? {
        tokenLock.lock()
        defer { tokenLock.unlock() }
        if let token = cachedBearerToken,
           let expiration = tokenExpiration,
           expiration > Date().addingTimeInterval(60) {
            return token
        }
        return nil
    }

    private func storeToken(_ token: String, expiresIn: Int) {
        tokenLock.lock()
        defer { tokenLock.unlock() }
        cachedBearerToken = token
        tokenExpiration = Date().addingTimeInterval(TimeInterval(expiresIn))
    }

    private func getBearerToken() async throws -> String {
        if let token = cachedValidToken() {
            return token
        }

        let config = MDMConfigurationManager.shared.configuration
        guard let url = URL(string: "\(jamfURL)/api/v1/oauth/token") else {
            throw JamfSiteError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = NetworkTuning.connectionTimeout
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
        request.httpBody = "grant_type=client_credentials&client_id=\(config.masterClientID)&client_secret=\(config.masterClientSecret)"
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw JamfSiteError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw JamfSiteError.httpError(httpResponse.statusCode,
                                          String(data: data, encoding: .utf8) ?? "Unknown error")
        }

        struct TokenResponse: Codable {
            let access_token: String
            let expires_in: Int
        }
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        storeToken(tokenResponse.access_token, expiresIn: tokenResponse.expires_in)
        return tokenResponse.access_token
    }

    private func request(
        _ method: String,
        path: String,
        body: Data? = nil,
        timeout: TimeInterval = NetworkTuning.connectionTimeout
    ) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: "\(jamfURL)\(path)") else {
            throw JamfSiteError.invalidURL
        }
        let token = try await getBearerToken()

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw JamfSiteError.invalidResponse
        }
        return (data, httpResponse)
    }

    // MARK: - Sites

    /// Every Jamf Pro site, sorted by display name. `/api/v1/sites` returns
    /// the full list in one response (there is no paging envelope on this
    /// endpoint), so the caller filters to the role's allow-list itself.
    func fetchSites() async throws -> [JamfSiteRecord] {
        let (data, response) = try await request(
            "GET", path: "/api/v1/sites",
            timeout: NetworkTuning.requestTimeout
        )
        guard response.statusCode == 200 else {
            throw JamfSiteError.httpError(response.statusCode,
                                          String(data: data, encoding: .utf8) ?? "Unknown error")
        }
        struct Entry: Decodable {
            let id: String
            let name: String
        }
        let entries = try JSONDecoder().decode([Entry].self, from: data)
        return entries
            .map { JamfSiteRecord(id: $0.id, name: $0.name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Moves one computer to a site. The write schema takes a flat `siteId`
    /// string, not the nested `site` object the read returns. `computerID`
    /// is the Jamf computer INVENTORY id (Computer.id). Endpoint confirmed
    /// working on-device 2026-07-20 (v3 detail PATCH, not v1).
    func moveComputer(computerID: String, toSiteID siteID: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "general": ["siteId": siteID]
        ])
        let (data, response) = try await request(
            "PATCH",
            path: "/api/v3/computers-inventory-detail/\(computerID)",
            body: body
        )
        guard (200...299).contains(response.statusCode) else {
            throw JamfSiteError.httpError(response.statusCode,
                                          String(data: data, encoding: .utf8) ?? "Unknown error")
        }
    }

    /// Moves one mobile device to a site. Mobile devices use a DIFFERENT
    /// endpoint and body from computers: the v2 UpdateMobileDevice schema
    /// takes a flat root-level `siteId` string (PATCH /api/v2/mobile-devices/{id}),
    /// NOT the computer's `{"general":{"siteId":…}}` wrapper and NOT the
    /// `{"site":{"id":…}}` object the read returns. Endpoint/body confirmed
    /// against developer.jamf.com (UpdateMobileDeviceV2, 2026-07-20).
    /// `mobileDeviceID` is the Jamf mobile-device INVENTORY id (MobileDevice.id).
    func moveMobileDevice(mobileDeviceID: String, toSiteID siteID: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "siteId": siteID
        ])
        let (data, response) = try await request(
            "PATCH",
            path: "/api/v2/mobile-devices/\(mobileDeviceID)",
            body: body
        )
        guard (200...299).contains(response.statusCode) else {
            throw JamfSiteError.httpError(response.statusCode,
                                          String(data: data, encoding: .utf8) ?? "Unknown error")
        }
    }
}
