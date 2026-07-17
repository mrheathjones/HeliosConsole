//
//  JamfPreStageService.swift
//  HeliosConsole
//
//  Jamf Pro PreStage enrollment + Inventory Preload client for the
//  Pre-Stage tab (and the prestage-on-assign step). Master-credential
//  OAuth per the ComputerInventoryService pattern.
//
//  API facts this file is built on (Jamf Pro OpenAPI 11.30.0):
//    • /api/v3/computer-prestages pages via page/page-size with a
//      { totalCount, results } envelope; prestage id is a STRING.
//    • /api/v2/computer-prestages/scope returns
//      { serialsByPrestageId: { SERIAL: prestageId } } — the schema says
//      values are strings but Jamf's own example shows bare ints, so the
//      decode accepts both.
//    • Scope mutations (POST {id}/scope, POST {id}/scope/delete-multiple)
//      take { serialNumbers, versionLock }. A 200 returns the scope WITH
//      ITS FRESH versionLock (no re-read needed between chained writes);
//      409 is an optimistic-lock conflict (re-read, retry); 400 means one
//      or more serials are NOT VALID to Jamf — for a device just assigned
//      in ABM that is the "not synced yet" state, and it is TERMINAL
//      until Jamf's ~2-minute ADE sync runs. Never lock-retry a 400.
//    • Inventory Preload supports RSQL (filter=serialNumber=="X");
//      deviceType is the string "Computer" in bodies.
//

import Foundation
import Combine

// MARK: - Models

struct JamfPreStage: Identifiable, Hashable {
    let id: String
    let displayName: String
}

enum PreStageError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int, String)
    /// Scope POST returned 400 — Jamf does not (yet) consider the serial
    /// a valid ADE device. For a serial just assigned in ABM this clears
    /// on its own once Jamf's ADE sync (roughly every two minutes) runs.
    case serialNotEligible(String)
    case conflictRetriesExhausted(String)
    case prestageNotFound(String)
    /// A move failed after the remove leg but the rollback restored the
    /// previous scope — net effect: nothing changed.
    case moveRolledBack(previous: String, underlying: String)
    /// A move failed after the remove leg AND the rollback failed — the
    /// serial currently belongs to NO PreStage and must be re-registered.
    case leftUnscoped(previous: String, underlying: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Jamf Pro URL."
        case .invalidResponse:
            return "Invalid response from Jamf Pro."
        case .httpError(let code, let message):
            return "Jamf Pro request failed (\(code)): \(message)"
        case .serialNotEligible(let serial):
            return "Jamf Pro does not yet recognize serial \(serial) as an Automated Device Enrollment device. If it was just assigned to the MDM server in Apple Business Manager, Jamf's ADE sync (roughly every two minutes) has not picked it up yet — try again shortly."
        case .conflictRetriesExhausted(let prestageId):
            return "PreStage \(prestageId) kept changing while the update was being applied (optimistic-lock conflicts). Try again."
        case .prestageNotFound(let name):
            return "No PreStage named \(name) exists in Jamf Pro."
        case .moveRolledBack(let previous, let underlying):
            return "Assigning the new PreStage failed (\(underlying)). The device was restored to its previous PreStage (id \(previous)) — nothing has changed. Try again."
        case .leftUnscoped(let previous, let underlying):
            return "IMPORTANT: the device was removed from its previous PreStage (id \(previous)) but could not be added to the new one (\(underlying)), and restoring it also failed. The device currently belongs to NO PreStage — register it again before its next enrollment."
        }
    }
}

// MARK: - Service

final class JamfPreStageService: ObservableObject {

    static let shared = JamfPreStageService()
    private init() {}

    private var jamfURL: String {
        MDMConfigurationManager.shared.configuration.jamfURL
    }

    // Token cache. Reads/writes go under tokenLock (never held across an
    // await): the Pre-Stage flow can overlap with prestage-on-assign.
    private let tokenLock = NSLock()
    private var cachedBearerToken: String?
    private var tokenExpiration: Date?

    private let maxConflictRetries = 3

    // MARK: - Auth

    /// Synchronous lock helpers — NSLock must not be held across an await,
    /// and locking directly inside an async function is flagged by Swift 6.
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
            throw PreStageError.invalidURL
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
            throw PreStageError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw PreStageError.httpError(httpResponse.statusCode,
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
            throw PreStageError.invalidURL
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
            throw PreStageError.invalidResponse
        }
        return (data, httpResponse)
    }

    // MARK: - PreStages (v3)

    /// Every computer PreStage, paged, sorted by display name.
    func fetchPreStages() async throws -> [JamfPreStage] {
        struct Page: Codable {
            struct Result: Codable {
                let id: String
                let displayName: String?
            }
            let totalCount: Int
            let results: [Result]
        }

        var prestages: [JamfPreStage] = []
        var page = 0
        let pageSize = 100

        while true {
            let (data, response) = try await request(
                "GET",
                path: "/api/v3/computer-prestages?page=\(page)&page-size=\(pageSize)",
                timeout: NetworkTuning.requestTimeout
            )
            guard response.statusCode == 200 else {
                throw PreStageError.httpError(response.statusCode,
                                              String(data: data, encoding: .utf8) ?? "Unknown error")
            }
            let decoded = try JSONDecoder().decode(Page.self, from: data)
            prestages.append(contentsOf: decoded.results.map {
                JamfPreStage(id: $0.id, displayName: $0.displayName ?? $0.id)
            })
            page += 1
            if decoded.results.isEmpty || page * pageSize >= decoded.totalCount { break }
        }

        return prestages.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    // MARK: - Scope (v2)

    /// serial → prestageId across every PreStage. Jamf's schema declares
    /// the map values as strings but its own example shows ints — decode
    /// both rather than betting on either.
    func fetchAllScopes() async throws -> [String: String] {
        struct ScopeMap: Decodable {
            let serialsByPrestageId: [String: StringOrInt]
        }
        struct StringOrInt: Decodable {
            let value: String
            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let s = try? container.decode(String.self) {
                    value = s
                } else if let i = try? container.decode(Int.self) {
                    value = String(i)
                } else {
                    throw DecodingError.typeMismatch(
                        String.self,
                        .init(codingPath: decoder.codingPath,
                              debugDescription: "prestage id neither string nor int")
                    )
                }
            }
        }

        let (data, response) = try await request(
            "GET", path: "/api/v2/computer-prestages/scope",
            timeout: NetworkTuning.requestTimeout
        )
        guard response.statusCode == 200 else {
            throw PreStageError.httpError(response.statusCode,
                                          String(data: data, encoding: .utf8) ?? "Unknown error")
        }
        let decoded = try JSONDecoder().decode(ScopeMap.self, from: data)
        return decoded.serialsByPrestageId.mapValues { $0.value }
    }

    /// The serial's current PreStage id, or nil when unscoped. Serials in
    /// the scope map are uppercase; compare case-insensitively anyway.
    func currentPreStageId(forSerial serial: String) async throws -> String? {
        let normalized = serial.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let scopes = try await fetchAllScopes()
        if let direct = scopes[normalized] { return direct }
        return scopes.first { $0.key.uppercased() == normalized }?.value
    }

    private struct ScopeResponse: Codable {
        let versionLock: Int
    }

    private func currentVersionLock(prestageId: String) async throws -> Int {
        let (data, response) = try await request(
            "GET", path: "/api/v2/computer-prestages/\(prestageId)/scope"
        )
        guard response.statusCode == 200 else {
            throw PreStageError.httpError(response.statusCode,
                                          String(data: data, encoding: .utf8) ?? "Unknown error")
        }
        return try JSONDecoder().decode(ScopeResponse.self, from: data).versionLock
    }

    private enum ScopeMutation: String {
        case add = "scope"
        case remove = "scope/delete-multiple"
    }

    /// One scope mutation with optimistic-lock retries. 409 → re-read
    /// versionLock and retry (bounded). 400 semantics differ by leg:
    /// on ADD the serial is not (yet) a valid ADE device — TERMINAL,
    /// never retried; on REMOVE it means the serial is already not in
    /// that scope (raced with another admin) — the desired end state
    /// holds, so it is treated as success.
    private func mutateScope(
        prestageId: String,
        serial: String,
        mutation: ScopeMutation
    ) async throws {
        struct Body: Encodable {
            let serialNumbers: [String]
            let versionLock: Int
        }

        var versionLock = try await currentVersionLock(prestageId: prestageId)

        for attempt in 1...maxConflictRetries {
            let body = try JSONEncoder().encode(Body(serialNumbers: [serial], versionLock: versionLock))
            let (data, response) = try await request(
                "POST",
                path: "/api/v2/computer-prestages/\(prestageId)/\(mutation.rawValue)",
                body: body
            )

            switch response.statusCode {
            case 200...299:
                return
            case 400 where mutation == .remove:
                NSLog("ℹ️ JamfPreStageService: serial %@ already absent from PreStage %@ scope (400 on remove)", serial, prestageId)
                return
            case 400:
                throw PreStageError.serialNotEligible(serial)
            case 409:
                NSLog("⚠️ JamfPreStageService: versionLock conflict on PreStage %@ (attempt %d)", prestageId, attempt)
                versionLock = try await currentVersionLock(prestageId: prestageId)
                continue
            default:
                throw PreStageError.httpError(response.statusCode,
                                              String(data: data, encoding: .utf8) ?? "Unknown error")
            }
        }
        throw PreStageError.conflictRetriesExhausted(prestageId)
    }

    /// Assigns a serial to a PreStage scope, moving it out of its current
    /// PreStage first when necessary (a serial lives in at most one
    /// scope). Idempotent: already-in-target is a no-op success.
    ///
    /// A move is two mutations with a hazard between them: if the remove
    /// commits and the add then fails, the serial is UNSCOPED. That state
    /// is never allowed to masquerade as "nothing changed" — a rollback
    /// (re-add to the previous scope) is attempted once, and if the
    /// rollback also fails the thrown error names the exact state.
    func assign(serial: String, toPreStage prestageId: String) async throws {
        let normalized = serial.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        let current = try await currentPreStageId(forSerial: normalized)
        if current == prestageId {
            NSLog("ℹ️ JamfPreStageService: serial %@ already in PreStage %@", normalized, prestageId)
            return
        }
        if let current {
            try await mutateScope(prestageId: current, serial: normalized, mutation: .remove)
            do {
                try await mutateScope(prestageId: prestageId, serial: normalized, mutation: .add)
            } catch let addError {
                // Best-effort rollback so the serial never silently ends
                // up unscoped.
                do {
                    try await mutateScope(prestageId: current, serial: normalized, mutation: .add)
                } catch {
                    NSLog("❌ JamfPreStageService: serial %@ removed from PreStage %@; add AND rollback failed — UNSCOPED", normalized, current)
                    throw PreStageError.leftUnscoped(previous: current, underlying: addError.localizedDescription)
                }
                NSLog("⚠️ JamfPreStageService: add to %@ failed; serial %@ rolled back to PreStage %@", prestageId, normalized, current)
                throw PreStageError.moveRolledBack(previous: current, underlying: addError.localizedDescription)
            }
        } else {
            try await mutateScope(prestageId: prestageId, serial: normalized, mutation: .add)
        }
    }

    // MARK: - Inventory Preload (v2)

    /// Creates or updates the Inventory Preload record for a serial with
    /// the given asset tag (upsert — never a duplicate record). The update
    /// path merges into the FULL existing record before PUTting: Jamf's
    /// PUT is a full replace, so sending only the three known fields would
    /// silently erase username/department/purchasing data an earlier flow
    /// put on the record.
    func upsertInventoryPreload(serial: String, assetTag: String) async throws {
        let normalized = serial.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        // Strict percent-encoding: the serial lands inside an RSQL filter
        // in the query string — anything beyond alphanumerics could inject
        // query parameters or break the expression.
        guard let encodedSerial = normalized.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else {
            throw PreStageError.invalidURL
        }

        let filter = "serialNumber%3D%3D%22\(encodedSerial)%22"
        let (searchData, searchResponse) = try await request(
            "GET",
            path: "/api/v2/inventory-preload/records?page=0&page-size=1&filter=\(filter)"
        )
        guard searchResponse.statusCode == 200 else {
            throw PreStageError.httpError(searchResponse.statusCode,
                                          String(data: searchData, encoding: .utf8) ?? "Unknown error")
        }
        guard let pageJSON = try JSONSerialization.jsonObject(with: searchData) as? [String: Any],
              let results = pageJSON["results"] as? [[String: Any]] else {
            throw PreStageError.invalidResponse
        }

        let (data, response): (Data, HTTPURLResponse)
        let updating: Bool
        if var existing = results.first,
           let recordId = existing["id"].flatMap({ $0 as? String ?? ($0 as? Int).map(String.init) }) {
            updating = true
            existing["serialNumber"] = normalized
            existing["deviceType"] = "Computer"
            existing["assetTag"] = assetTag
            existing.removeValue(forKey: "id")
            let body = try JSONSerialization.data(withJSONObject: existing)
            (data, response) = try await request(
                "PUT", path: "/api/v2/inventory-preload/records/\(recordId)", body: body
            )
        } else {
            updating = false
            let body = try JSONSerialization.data(withJSONObject: [
                "serialNumber": normalized,
                "deviceType": "Computer",
                "assetTag": assetTag,
            ])
            (data, response) = try await request(
                "POST", path: "/api/v2/inventory-preload/records", body: body
            )
        }
        guard (200...299).contains(response.statusCode) else {
            throw PreStageError.httpError(response.statusCode,
                                          String(data: data, encoding: .utf8) ?? "Unknown error")
        }
        NSLog("✅ JamfPreStageService: preload record %@ for serial %@ (assetTag %@)",
              updating ? "updated" : "created", normalized, assetTag)
    }
}
