//
//  JamfCleanupClient.swift
//  HeliosConsole
//
//  Async Jamf Pro API client for the Cleanup feature. OAuth 2.0
//  client-credentials (Helios master client). Uses the modern Jamf Pro
//  API where it exists and falls back to the Classic API for the
//  incremental static-group add. Ported from Clean Slate's JamfProClient;
//  token path standardized to Helios's `api/v1/oauth/token`.
//

import Foundation

actor JamfCleanupClient {
    private let baseURL: URL
    private let clientID: String
    private let clientSecret: String
    private let pageSize: Int
    private let session: URLSession

    private var accessToken: String?
    private var tokenExpiry: Date = .distantPast

    init(baseURL: URL, clientID: String, clientSecret: String, pageSize: Int = 100) {
        self.baseURL = baseURL
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.pageSize = max(1, min(pageSize, 200))
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: config)
    }

    // MARK: - OAuth token lifecycle

    private func validToken() async throws -> String {
        if let token = accessToken, Date() < tokenExpiry {
            return token
        }
        return try await fetchToken()
    }

    private func fetchToken() async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/v1/oauth/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form = "grant_type=client_credentials"
            + "&client_id=\(Self.formEncode(clientID))"
            + "&client_secret=\(Self.formEncode(clientSecret))"
        request.httpBody = form.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw JamfCleanupError.badURL }
        guard http.statusCode == 200 else {
            throw JamfCleanupError.authenticationFailed("HTTP \(http.statusCode). Check the client ID and secret.")
        }

        struct TokenResponse: Decodable {
            let access_token: String
            let expires_in: Int
        }
        let tokenResponse: TokenResponse
        do {
            tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw JamfCleanupError.decoding("OAuth token response: \(error.localizedDescription)")
        }

        accessToken = tokenResponse.access_token
        // Refresh ahead of expiry; tolerate short-lived tokens.
        let margin = min(300, tokenResponse.expires_in / 2)
        tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in - margin))
        return tokenResponse.access_token
    }

    /// Invalidate the current token server-side. Abandoned tokens hold a
    /// Jamf Pro database connection until they expire — always call this
    /// when a session ends.
    func invalidateToken() async {
        guard let token = accessToken else { return }
        accessToken = nil
        tokenExpiry = .distantPast
        var request = URLRequest(url: baseURL.appendingPathComponent("api/v1/auth/invalidate-token"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await session.data(for: request)
    }

    // MARK: - Request plumbing

    @discardableResult
    private func send(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        contentType: String? = nil,
        accept: String = "application/json"
    ) async throws -> Data {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false
        ) else { throw JamfCleanupError.badURL }
        if !queryItems.isEmpty { components.queryItems = queryItems }
        guard let url = components.url else { throw JamfCleanupError.badURL }

        func makeRequest(token: String) -> URLRequest {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(accept, forHTTPHeaderField: "Accept")
            if let body, let contentType {
                request.httpBody = body
                request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            }
            return request
        }

        var token = try await validToken()
        var (data, response) = try await session.data(for: makeRequest(token: token))
        guard var http = response as? HTTPURLResponse else { throw JamfCleanupError.badURL }

        // One reactive refresh on 401, then give up.
        if http.statusCode == 401 {
            accessToken = nil
            token = try await fetchToken()
            (data, response) = try await session.data(for: makeRequest(token: token))
            guard let retried = response as? HTTPURLResponse else { throw JamfCleanupError.badURL }
            http = retried
        }

        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw JamfCleanupError.http(http.statusCode, snippet)
        }
        return data
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            if let date = isoFractional.date(from: value) ?? iso.date(from: value) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unrecognized date: \(value)"
            ))
        }
        return decoder
    }()

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso = ISO8601DateFormatter()

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    // MARK: - Connection test

    /// Returns the Jamf Pro version if the URL + credentials work.
    func testConnection() async throws -> String {
        let data = try await send(method: "GET", path: "api/v1/jamf-pro-version")
        struct Version: Decodable { let version: String }
        return (try? Self.decoder.decode(Version.self, from: data).version) ?? "unknown"
    }

    // MARK: - Stale computers

    /// All computers whose last check-in is older than `days` days,
    /// oldest first. Paginates until complete (server-side filter, so the
    /// stale set is complete regardless of any UI cache).
    func fetchStaleComputers(olderThanDays days: Int) async throws -> [StaleDevice] {
        let cutoff = Date().addingTimeInterval(-TimeInterval(days) * 86_400)
        let cutoffString = Self.iso.string(from: cutoff)
        let filter = "general.lastContactTime=lt=\"\(cutoffString)\""

        var devices: [StaleDevice] = []
        var page = 0
        var totalCount = Int.max

        while devices.count < totalCount {
            let queryItems = [
                URLQueryItem(name: "section", value: "GENERAL"),
                URLQueryItem(name: "section", value: "HARDWARE"),
                URLQueryItem(name: "section", value: "USER_AND_LOCATION"),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "page-size", value: String(pageSize)),
                URLQueryItem(name: "sort", value: "general.lastContactTime:asc"),
                URLQueryItem(name: "filter", value: filter),
            ]
            let data = try await send(
                method: "GET", path: "api/v3/computers-inventory", queryItems: queryItems
            )
            let list: ComputerInventoryList
            do {
                list = try Self.decoder.decode(ComputerInventoryList.self, from: data)
            } catch {
                throw JamfCleanupError.decoding("computers-inventory: \(error)")
            }
            totalCount = list.totalCount
            devices.append(contentsOf: list.results.compactMap(StaleDevice.init))
            if list.results.isEmpty { break }
            page += 1
        }
        return devices
    }

    /// Total computer count in Jamf Pro (one record requested, count read
    /// from the envelope).
    func fetchTotalComputerCount() async throws -> Int {
        let data = try await send(
            method: "GET",
            path: "api/v3/computers-inventory",
            queryItems: [
                URLQueryItem(name: "section", value: "GENERAL"),
                URLQueryItem(name: "page", value: "0"),
                URLQueryItem(name: "page-size", value: "1"),
            ]
        )
        do {
            return try Self.decoder.decode(ComputerInventoryList.self, from: data).totalCount
        } catch {
            throw JamfCleanupError.decoding("computer count: \(error)")
        }
    }

    // MARK: - Lookups

    func fetchSites() async throws -> [JamfSite] {
        let data = try await send(method: "GET", path: "api/v1/sites")
        do {
            return try Self.decoder.decode([JamfSite].self, from: data)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            throw JamfCleanupError.decoding("sites: \(error)")
        }
    }

    func fetchStaticGroups() async throws -> [StaticGroup] {
        struct GroupList: Decodable {
            struct Entry: Decodable {
                let id: String
                let name: String
            }
            let totalCount: Int
            let results: [Entry]
        }

        var groups: [StaticGroup] = []
        var page = 0
        var totalCount = Int.max
        while groups.count < totalCount {
            let data = try await send(
                method: "GET",
                path: "api/v3/computer-groups/static-groups",
                queryItems: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "page-size", value: "200"),
                    URLQueryItem(name: "sort", value: "name:asc"),
                ]
            )
            let list: GroupList
            do {
                list = try JSONDecoder().decode(GroupList.self, from: data)
            } catch {
                throw JamfCleanupError.decoding("static groups: \(error)")
            }
            totalCount = list.totalCount
            groups.append(contentsOf: list.results.compactMap { entry in
                Int(entry.id).map { StaticGroup(id: $0, name: entry.name) }
            })
            if list.results.isEmpty { break }
            page += 1
        }
        return groups
    }

    // MARK: - Actions

    /// Sends the unmanage (remove MDM profile) command, then flips the
    /// inventory record's managed flag to false so the record reflects
    /// the intent immediately. The device must still reach APNs once for
    /// the profile to actually come off — for long-dead devices the
    /// command simply stays pending.
    /// Requires "Send Computer Unmanage Command" + "Update Computers".
    func unmanage(computerID: Int) async throws {
        try await send(
            method: "POST",
            path: "api/v1/computer-inventory/\(computerID)/remove-mdm-profile"
        )
        let body = try JSONSerialization.data(withJSONObject: [
            "general": ["managed": false]
        ])
        try await send(
            method: "PATCH",
            path: "api/v3/computers-inventory-detail/\(computerID)",
            body: body,
            contentType: "application/json"
        )
    }

    /// Adds all computers to a static group in a single bulk call.
    /// Classic API on purpose: the modern v3 static-group PUT replaces
    /// the entire membership, while Classic `computer_additions` is the
    /// only incremental add.
    func addComputers(_ computerIDs: [Int], toStaticGroup groupID: Int) async throws {
        let additions = computerIDs
            .map { "<computer><id>\($0)</id></computer>" }
            .joined()
        let xml = "<computer_group><id>\(groupID)</id><computer_additions>\(additions)</computer_additions></computer_group>"
        try await send(
            method: "PUT",
            path: "JSSResource/computergroups/id/\(groupID)",
            body: Data(xml.utf8),
            contentType: "text/xml",
            accept: "application/xml"
        )
    }

    /// Moves one computer to a site. The write schema takes a flat
    /// `siteId` string, not the nested `site` object the read returns.
    func moveComputer(_ computerID: Int, toSite siteID: Int) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "general": ["siteId": String(siteID)]
        ])
        try await send(
            method: "PATCH",
            path: "api/v3/computers-inventory-detail/\(computerID)",
            body: body,
            contentType: "application/json"
        )
    }

    /// Deletes the computer record. This does NOT unenroll the device —
    /// it only removes the Jamf Pro record.
    func deleteComputer(_ computerID: Int) async throws {
        try await send(method: "DELETE", path: "api/v3/computers-inventory/\(computerID)")
    }
}
