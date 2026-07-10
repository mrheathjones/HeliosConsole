//
//  JamfProtectClient.swift
//  HeliosConsole
//
//  Minimal Jamf Protect GraphQL client for the Cleanup feature:
//  authenticate with an API client, look up a computer by serial number,
//  delete its record. Ported from Clean Slate.
//

import Foundation

actor JamfProtectClient {
    private let baseURL: URL
    private let clientID: String
    private let password: String
    private let session: URLSession

    private var accessToken: String?
    private var tokenExpiry: Date = .distantPast

    init(baseURL: URL, clientID: String, password: String) {
        self.baseURL = baseURL
        self.clientID = clientID
        self.password = password
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: config)
    }

    // MARK: - Auth

    private func validToken() async throws -> String {
        if let token = accessToken, Date() < tokenExpiry {
            return token
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("token"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": clientID,
            "password": password,
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw JamfCleanupError.authenticationFailed("Jamf Protect token request returned HTTP \(code).")
        }
        struct TokenResponse: Decodable {
            let access_token: String
            let expires_in: Int
        }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken = token.access_token
        tokenExpiry = Date().addingTimeInterval(TimeInterval(max(60, token.expires_in - 120)))
        return token.access_token
    }

    func invalidate() {
        accessToken = nil
        tokenExpiry = .distantPast
    }

    // MARK: - GraphQL plumbing

    private func graphQL(query: String, variables: [String: Any]) async throws -> [String: Any] {
        let token = try await validToken()
        var request = URLRequest(url: baseURL.appendingPathComponent("graphql"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Jamf Protect expects the raw token with no "Bearer " prefix.
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "query": query,
            "variables": variables,
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let snippet = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw JamfCleanupError.http(code, snippet)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw JamfCleanupError.decoding("Jamf Protect response was not a JSON object.")
        }
        if let errors = json["errors"] as? [[String: Any]], !errors.isEmpty {
            let messages = errors.compactMap { $0["message"] as? String }.joined(separator: "; ")
            throw JamfCleanupError.protectGraphQL(messages.isEmpty ? "Unknown GraphQL error" : messages)
        }
        return json["data"] as? [String: Any] ?? [:]
    }

    // MARK: - API

    /// Fetches every computer record in the tenant (paginated). Counts
    /// and staleness are computed client-side so we never depend on
    /// unverified server-side filter shapes.
    func fetchAllComputers() async throws -> [ProtectDevice] {
        let query = """
        query list($next: String) {
          listComputers(input: {pageSize: 200, next: $next}) {
            items { uuid serial hostName checkin }
            pageInfo { next }
          }
        }
        """
        var devices: [ProtectDevice] = []
        var next: String?
        for _ in 0..<500 { // safety cap: 100k records
            var variables: [String: Any] = [:]
            if let next { variables["next"] = next }
            let data = try await graphQL(query: query, variables: variables)
            guard let list = data["listComputers"] as? [String: Any],
                  let items = list["items"] as? [[String: Any]]
            else { break }
            devices.append(contentsOf: items.compactMap { item in
                guard let uuid = item["uuid"] as? String else { return nil }
                return ProtectDevice(
                    uuid: uuid,
                    hostName: item["hostName"] as? String ?? "Unknown",
                    serial: item["serial"] as? String ?? "—",
                    checkin: (item["checkin"] as? String).flatMap(Self.parseDate)
                )
            })
            let pageInfo = list["pageInfo"] as? [String: Any]
            guard let cursor = pageInfo?["next"] as? String, !cursor.isEmpty else { break }
            next = cursor
        }
        return devices
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso = ISO8601DateFormatter()

    private static func parseDate(_ value: String) -> Date? {
        isoFractional.date(from: value) ?? iso.date(from: value)
    }

    /// Verifies credentials by listing a single computer.
    func testConnection() async throws {
        let query = """
        query test {
          listComputers(input: {pageSize: 1}) {
            items { uuid }
          }
        }
        """
        _ = try await graphQL(query: query, variables: [:])
    }

    /// Returns the Protect record UUID for a serial number, if one exists.
    /// Tries a server-side serial filter first; if the tenant's schema
    /// rejects it, falls back to paging the computer list and matching
    /// client-side (the shape Jamf's own cleanup scripts use).
    func findComputerUUID(serial: String) async throws -> String? {
        let filtered = """
        query find($serial: String) {
          listComputers(input: {filter: {serial: {equals: $serial}}, pageSize: 50}) {
            items { uuid serial }
          }
        }
        """
        do {
            let data = try await graphQL(query: filtered, variables: ["serial": serial])
            return Self.match(serial: serial, in: data)
        } catch JamfCleanupError.protectGraphQL {
            return try await findByPaging(serial: serial)
        }
    }

    private func findByPaging(serial: String) async throws -> String? {
        let query = """
        query list($next: String) {
          listComputers(input: {pageSize: 200, next: $next}) {
            items { uuid serial }
            pageInfo { next }
          }
        }
        """
        var next: String?
        for _ in 0..<100 { // safety cap: 20k records
            var variables: [String: Any] = [:]
            if let next { variables["next"] = next }
            let data = try await graphQL(query: query, variables: variables)
            if let uuid = Self.match(serial: serial, in: data) { return uuid }
            let list = data["listComputers"] as? [String: Any]
            let pageInfo = list?["pageInfo"] as? [String: Any]
            guard let cursor = pageInfo?["next"] as? String, !cursor.isEmpty else { return nil }
            next = cursor
        }
        return nil
    }

    private static func match(serial: String, in data: [String: Any]) -> String? {
        guard let list = data["listComputers"] as? [String: Any],
              let items = list["items"] as? [[String: Any]]
        else { return nil }
        return items.first {
            ($0["serial"] as? String)?.caseInsensitiveCompare(serial) == .orderedSame
        }?["uuid"] as? String
    }

    /// Deletes a computer record by UUID.
    func deleteComputer(uuid: String) async throws {
        let mutation = """
        mutation remove($uuid: ID!) {
          deleteComputer(uuid: $uuid) {
            hostName
          }
        }
        """
        _ = try await graphQL(query: mutation, variables: ["uuid": uuid])
    }
}
