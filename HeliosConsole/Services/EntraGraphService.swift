//
//  EntraGraphService.swift
//  HeliosConsole
//
//  Microsoft Entra (Graph) device cleanup for the Return to Service flow.
//
//  Ports the Entra half of Erase_and_Delete_Devices.sh: obtain an app-only
//  Microsoft Graph token (certificate PS256 client-assertion preferred, client
//  secret fallback), find Entra device object(s) by displayName, and delete
//  every match so an erased Mac can re-register cleanly with PSSO / Company
//  Portal. All operations are best-effort and never fatal to the erase/delete
//  workflow — the caller logs the summary and moves on.
//
//  App-only device deletion requires the app registration to hold
//  Device.ReadWrite.All AND to be assigned the "Cloud Device Administrator"
//  Entra role; without the role Graph returns 403 on DELETE.
//

import Foundation
import CryptoKit
import Security

/// Result of an Entra cleanup pass for a single display name.
struct EntraCleanupResult {
    enum Outcome {
        case notConfigured      // no usable Entra credentials
        case authFailed         // could not obtain a Graph token
        case lookupFailed       // device query failed
        case noMatch            // query succeeded, nothing named that
        case completed          // ran; see counts
    }
    let outcome: Outcome
    let deleted: Int
    let failed: Int
    /// Human-readable detail suitable for logging / surfacing to the operator.
    let message: String
}

enum EntraGraphError: LocalizedError {
    case missingCredentials
    case certificateParseFailed(String)
    case signingFailed(String)
    case tokenRequestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Entra credentials are incomplete (need tenant, client id, and a certificate or secret)."
        case .certificateParseFailed(let detail):
            return "Could not parse the Entra certificate PEM: \(detail)"
        case .signingFailed(let detail):
            return "Failed to sign the Graph client assertion: \(detail)"
        case .tokenRequestFailed(let detail):
            return "Microsoft Graph token request failed: \(detail)"
        }
    }
}

final class EntraGraphService {
    private let tenantId: String
    private let clientId: String
    private let clientSecret: String?
    private let certPEM: String?

    private let session: URLSession

    /// Preferred initializer — pulls credentials straight from the resolved
    /// MDM configuration. Returns nil when Entra cleanup is not configured.
    convenience init?(configuration: MDMConfiguration) {
        guard configuration.isEntraConfigured,
              let tenant = configuration.entraTenantId,
              let client = configuration.entraClientId else {
            return nil
        }
        self.init(
            tenantId: tenant,
            clientId: client,
            clientSecret: configuration.entraClientSecret,
            certPEM: configuration.entraCertPEM
        )
    }

    init(tenantId: String, clientId: String, clientSecret: String?, certPEM: String?) {
        self.tenantId = tenantId
        self.clientId = clientId
        self.clientSecret = (clientSecret?.isEmpty == false) ? clientSecret : nil
        self.certPEM = (certPEM?.isEmpty == false) ? certPEM : nil

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = NetworkTuning.requestTimeout
        cfg.timeoutIntervalForResource = NetworkTuning.requestTimeout * 1.5  // keeps the shipped 60->90 proportion
        self.session = URLSession(configuration: cfg)
    }

    // MARK: - Public API

    /// Delete every Entra device object whose displayName matches `displayName`.
    /// Never throws — always returns a summary the caller can log.
    func deleteDevices(displayName: String) async -> EntraCleanupResult {
        guard !displayName.isEmpty else {
            return EntraCleanupResult(outcome: .noMatch, deleted: 0, failed: 0,
                                      message: "No device name to match in Entra.")
        }

        let token: String
        do {
            token = try await fetchAccessToken()
        } catch {
            return EntraCleanupResult(outcome: .authFailed, deleted: 0, failed: 0,
                                      message: error.localizedDescription)
        }

        let ids: [String]
        do {
            ids = try await findDeviceIds(displayName: displayName, token: token)
        } catch {
            return EntraCleanupResult(outcome: .lookupFailed, deleted: 0, failed: 0,
                                      message: "Entra device lookup failed for '\(displayName)': \(error.localizedDescription)")
        }

        if ids.isEmpty {
            return EntraCleanupResult(outcome: .noMatch, deleted: 0, failed: 0,
                                      message: "No Entra device object found for '\(displayName)'.")
        }

        var deleted = 0
        var failed = 0
        for id in ids {
            if await deleteDevice(id: id, token: token) {
                deleted += 1
            } else {
                failed += 1
            }
        }

        let msg = "Entra cleanup for '\(displayName)': \(deleted) deleted, \(failed) failed (of \(ids.count) match(es))."
        return EntraCleanupResult(outcome: .completed, deleted: deleted, failed: failed, message: msg)
    }

    // MARK: - Token

    /// Obtain an app-only Graph token. Prefers certificate client-assertion
    /// (PS256), falls back to the client secret. Mirrors get_graph_token.
    func fetchAccessToken() async throws -> String {
        // Cloud endpoints from core entra.cloudInstance (global/usgov/china).
        let authorityHost = MDMConfigurationManager.shared.configuration.entraAuthorityHost
        let tokenURLString = "https://\(authorityHost)/\(tenantId)/oauth2/v2.0/token"
        guard let url = URL(string: tokenURLString) else {
            throw EntraGraphError.tokenRequestFailed("Invalid token endpoint URL")
        }

        var form: [String: String] = [
            "client_id": clientId,
            "grant_type": "client_credentials",
            "scope": "https://\(MDMConfigurationManager.shared.configuration.entraGraphHost)/.default"
        ]

        if let certPEM {
            let assertion = try buildClientAssertion(certPEM: certPEM, audience: tokenURLString)
            form["client_assertion_type"] = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
            form["client_assertion"] = assertion
            NSLog("🔐 Entra: authenticating to Graph with a certificate (client assertion)")
        } else if let clientSecret {
            form["client_secret"] = clientSecret
            NSLog("🔐 Entra: authenticating to Graph with a client secret")
        } else {
            throw EntraGraphError.missingCredentials
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Self.formURLEncode(form).data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw EntraGraphError.tokenRequestFailed("No HTTP response")
        }
        guard http.statusCode == 200 else {
            let detail = Self.extractGraphError(data) ?? "HTTP \(http.statusCode)"
            throw EntraGraphError.tokenRequestFailed(detail)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String, !accessToken.isEmpty else {
            throw EntraGraphError.tokenRequestFailed("Response contained no access_token")
        }
        return accessToken
    }

    // MARK: - Device lookup & delete

    private func findDeviceIds(displayName: String, token: String) async throws -> [String] {
        // OData string literal escaping: a single quote is doubled.
        let escaped = displayName.replacingOccurrences(of: "'", with: "''")

        var components = URLComponents(string: "https://\(MDMConfigurationManager.shared.configuration.entraGraphHost)/v1.0/devices")!
        components.queryItems = [
            URLQueryItem(name: "$filter", value: "displayName eq '\(escaped)'"),
            URLQueryItem(name: "$count", value: "true"),
            URLQueryItem(name: "$select", value: "id,deviceId,displayName,operatingSystem,approximateLastSignInDateTime")
        ]
        guard let url = components.url else {
            throw EntraGraphError.tokenRequestFailed("Invalid device query URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // $count=true on /devices requires an advanced query.
        request.setValue("eventual", forHTTPHeaderField: "ConsistencyLevel")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let detail = Self.extractGraphError(data) ?? "HTTP \(code)"
            throw NSError(domain: "EntraGraphService", code: code,
                          userInfo: [NSLocalizedDescriptionKey: detail])
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = json["value"] as? [[String: Any]] else {
            return []
        }
        return value.compactMap { $0["id"] as? String }
    }

    /// Returns true on a successful delete (HTTP 204). Logs and returns false
    /// otherwise; a 403 means the app is missing the Cloud Device Administrator
    /// role.
    private func deleteDevice(id: String, token: String) async -> Bool {
        guard let url = URL(string: "https://\(MDMConfigurationManager.shared.configuration.entraGraphHost)/v1.0/devices/\(id)") else {
            return false
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            switch code {
            case 204, 200:
                NSLog("🗑️ Entra: deleted device object \(id)")
                return true
            case 403:
                NSLog("❌ Entra delete 403 for \(id) — app needs the 'Cloud Device Administrator' role in addition to Device.ReadWrite.All")
                return false
            default:
                NSLog("❌ Entra: failed to delete device object \(id) (HTTP \(code))")
                return false
            }
        } catch {
            NSLog("❌ Entra: delete request error for \(id): \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Client assertion (PS256)

    /// Build a signed JWT client assertion using the RSA private key + cert in
    /// the PEM. header alg PS256, x5t#S256 = base64url(SHA256(DER cert)).
    /// Mirrors build_graph_assertion.
    private func buildClientAssertion(certPEM: String, audience: String) throws -> String {
        let (certDER, keyDER) = try Self.parsePEM(certPEM)

        // x5t#S256 — SHA-256 thumbprint of the DER certificate, base64url.
        let thumbprint = Data(SHA256.hash(data: certDER))
        let x5t = Self.base64URLEncode(thumbprint)

        let now = Int(Date().timeIntervalSince1970)
        let exp = now + 300
        let jti = UUID().uuidString

        let header: [String: Any] = ["alg": "PS256", "typ": "JWT", "x5t#S256": x5t]
        let payload: [String: Any] = [
            "aud": audience,
            "iss": clientId,
            "sub": clientId,
            "jti": jti,
            "nbf": now,
            "exp": exp,
            "iat": now
        ]

        let headerB64 = try Self.base64URLEncodeJSON(header)
        let payloadB64 = try Self.base64URLEncodeJSON(payload)
        let signingInput = "\(headerB64).\(payloadB64)"

        guard let signingData = signingInput.data(using: .utf8) else {
            throw EntraGraphError.signingFailed("Could not encode signing input")
        }

        let signature = try Self.signPS256(message: signingData, rsaPrivateKeyDER: keyDER)
        let sigB64 = Self.base64URLEncode(signature)
        return "\(signingInput).\(sigB64)"
    }

    /// RSA-PSS (SHA-256, salt length = digest length) signature over `message`.
    private static func signPS256(message: Data, rsaPrivateKeyDER: Data) throws -> Data {
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(rsaPrivateKeyDER as CFData,
                                             attributes as CFDictionary,
                                             &error) else {
            let detail = (error?.takeRetainedValue()).map { CFErrorCopyDescription($0) as String } ?? "unknown"
            throw EntraGraphError.signingFailed("Could not import RSA private key: \(detail)")
        }

        let algorithm: SecKeyAlgorithm = .rsaSignatureMessagePSSSHA256
        guard SecKeyIsAlgorithmSupported(key, .sign, algorithm) else {
            throw EntraGraphError.signingFailed("Key does not support RSA-PSS SHA-256")
        }

        guard let sig = SecKeyCreateSignature(key, algorithm, message as CFData, &error) else {
            let detail = (error?.takeRetainedValue()).map { CFErrorCopyDescription($0) as String } ?? "unknown"
            throw EntraGraphError.signingFailed(detail)
        }
        return sig as Data
    }

    // MARK: - PEM / DER helpers

    /// Extract the certificate DER and an RSA private key DER (PKCS#1) from a
    /// PEM holding both a CERTIFICATE and a PRIVATE KEY block. PKCS#8
    /// (BEGIN PRIVATE KEY) is unwrapped to PKCS#1 for SecKeyCreateWithData.
    static func parsePEM(_ pem: String) throws -> (certDER: Data, keyDER: Data) {
        guard let certDER = pemBlock(pem, label: "CERTIFICATE") else {
            throw EntraGraphError.certificateParseFailed("no CERTIFICATE block found")
        }

        if let pkcs1 = pemBlock(pem, label: "RSA PRIVATE KEY") {
            return (certDER, pkcs1)
        }
        if let pkcs8 = pemBlock(pem, label: "PRIVATE KEY") {
            let pkcs1 = try pkcs1FromPKCS8(pkcs8)
            return (certDER, pkcs1)
        }
        if pemBlock(pem, label: "ENCRYPTED PRIVATE KEY") != nil {
            throw EntraGraphError.certificateParseFailed("encrypted private keys are not supported; deploy an unencrypted PEM")
        }
        throw EntraGraphError.certificateParseFailed("no PRIVATE KEY block found")
    }

    /// Decode the base64 body of a single PEM block with the given label.
    private static func pemBlock(_ pem: String, label: String) -> Data? {
        let begin = "-----BEGIN \(label)-----"
        let end = "-----END \(label)-----"
        guard let beginRange = pem.range(of: begin),
              let endRange = pem.range(of: end, range: beginRange.upperBound..<pem.endIndex) else {
            return nil
        }
        let body = pem[beginRange.upperBound..<endRange.lowerBound]
        let base64 = body.components(separatedBy: .newlines).joined()
        return Data(base64Encoded: base64, options: .ignoreUnknownCharacters)
    }

    /// Strip the PKCS#8 PrivateKeyInfo wrapper to recover the inner PKCS#1
    /// RSAPrivateKey. Minimal DER walk:
    ///   SEQUENCE { INTEGER version, SEQUENCE algId, OCTET STRING privateKey }
    /// The OCTET STRING contents are the PKCS#1 key.
    private static func pkcs1FromPKCS8(_ der: Data) throws -> Data {
        let bytes = [UInt8](der)
        var idx = 0

        func readLength() throws -> Int {
            guard idx < bytes.count else { throw EntraGraphError.certificateParseFailed("PKCS#8 truncated") }
            let first = bytes[idx]; idx += 1
            if first & 0x80 == 0 { return Int(first) }
            let count = Int(first & 0x7F)
            guard count > 0, count <= 4, idx + count <= bytes.count else {
                throw EntraGraphError.certificateParseFailed("PKCS#8 bad length")
            }
            var len = 0
            for _ in 0..<count { len = (len << 8) | Int(bytes[idx]); idx += 1 }
            return len
        }

        func expectTag(_ tag: UInt8) throws {
            guard idx < bytes.count, bytes[idx] == tag else {
                throw EntraGraphError.certificateParseFailed("PKCS#8 expected tag 0x\(String(tag, radix: 16))")
            }
            idx += 1
        }

        // Outer SEQUENCE
        try expectTag(0x30); _ = try readLength()
        // version INTEGER — skip
        try expectTag(0x02); let vLen = try readLength(); idx += vLen
        // AlgorithmIdentifier SEQUENCE — skip whole thing
        try expectTag(0x30); let algLen = try readLength(); idx += algLen
        // privateKey OCTET STRING — contents are the PKCS#1 RSAPrivateKey
        try expectTag(0x04); let keyLen = try readLength()
        guard idx + keyLen <= bytes.count else {
            throw EntraGraphError.certificateParseFailed("PKCS#8 key overruns buffer")
        }
        return Data(bytes[idx..<(idx + keyLen)])
    }

    // MARK: - Encoding helpers

    private static func base64URLEncode(_ data: Data) -> String {
        var s = data.base64EncodedString()
        s = s.replacingOccurrences(of: "+", with: "-")
        s = s.replacingOccurrences(of: "/", with: "_")
        s = s.replacingOccurrences(of: "=", with: "")
        return s
    }

    private static func base64URLEncodeJSON(_ object: [String: Any]) throws -> String {
        // Deterministic, compact JSON — key order is irrelevant for JWT.
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return base64URLEncode(data)
    }

    private static func formURLEncode(_ params: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }

    private static func extractGraphError(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let err = json["error"] as? [String: Any] {
            let code = err["code"] as? String
            let message = err["message"] as? String
            return [code, message].compactMap { $0 }.joined(separator: ": ")
        }
        // Token endpoint returns error as a string plus error_description.
        if let err = json["error"] as? String {
            let desc = json["error_description"] as? String
            return [err, desc].compactMap { $0 }.joined(separator: ": ")
        }
        return nil
    }
}
