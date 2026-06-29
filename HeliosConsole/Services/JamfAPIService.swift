//
//  JamfAPIError 2.swift
//  test
//
//  Created by heath on 1/19/26.
//


import Foundation

// MARK: - Jamf Credentials Model
struct JamfCredentials: Codable {
    let clientID: String
    let clientSecret: String
    let email: String
    let expiresAt: Date?
    
    var isExpired: Bool {
        guard let expiresAt = expiresAt else {
            return false
        }
        return expiresAt < Date()
    }
}

enum JamfAPIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case networkError(Error)
    case decodingError(Error)
    case serverError(statusCode: Int, message: String)
    case credentialsNotFound
    case expiredCredentials
    case authenticationFailed
    case invalidEmailFormat
    case roleNotFound
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        case .credentialsNotFound:
            return "No credentials found for this email"
        case .expiredCredentials:
            return "Credentials have expired. Please sign in again."
        case .authenticationFailed:
            return "Failed to authenticate with Jamf API"
        case .invalidEmailFormat:
            return "Invalid email address format"
        case .roleNotFound:
            return "Required role not found in Jamf Pro"
        }
    }
}

// MARK: - Jamf API Response Models
struct JamfAPIClientCredential: Codable {
    let id: Int
    let clientId: String
    let displayName: String?
    let enabled: Bool
    let accessTokenLifetimeSeconds: Int?
    let appType: String?
    let authorizationScopes: [String]?
    
    enum CodingKeys: String, CodingKey {
        case id
        case clientId
        case displayName
        case enabled
        case accessTokenLifetimeSeconds
        case appType
        case authorizationScopes
    }
}

struct JamfAPIClientCredentialsListResponse: Codable {
    let totalCount: Int?
    let results: [JamfAPIClientCredential]
}

struct JamfAPIClientCredentialCreateRequest: Codable {
    let displayName: String
    let authorizationScopes: [String]
}

struct JamfAPIClientCredentialCreateResponse: Codable {
    let id: Int
    let clientId: String
    let clientSecret: String
    let displayName: String?
    let enabled: Bool
    let accessTokenLifetimeSeconds: Int?
    let appType: String?
    let authorizationScopes: [String]?
    
    enum CodingKeys: String, CodingKey {
        case id
        case clientId
        case clientSecret
        case displayName
        case enabled
        case accessTokenLifetimeSeconds
        case appType
        case authorizationScopes
    }
}

struct JamfAPIClientCredentialUpdateRequest: Codable {
    let displayName: String?
    let authorizationScopes: [String]?
    let enabled: Bool?
}

struct JamfBearerTokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    let scope: String?
    let expiresIn: Int
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case expiresIn = "expires_in"
    }
}

struct JamfRole: Codable {
    let id: String
    let displayName: String
}

struct JamfRolesListResponse: Codable {
    let totalCount: Int?
    let results: [JamfRole]
}

class JamfAPIService {
    static let shared = JamfAPIService()
    
    private var cachedBearerToken: String?
    private var tokenExpiration: Date?
    private var cachedUserRoleId: String? // Role for user credentials, not master
    
    private init() {}
    
    // MARK: - Configuration Properties
    private var configuration: MDMConfiguration {
        return MDMConfigurationManager.shared.configuration
    }
    
    private var jamfURL: String {
        return configuration.jamfURL
    }
    
    private var masterClientID: String {
        return configuration.masterClientID
    }
    
    private var masterClientSecret: String {
        return configuration.masterClientSecret
    }
    
    private var userRoleName: String {
        return configuration.requiredRoleName
    }
    
    // MARK: - Main Authentication Method
    /// Authenticates a user by email and creates/retrieves their API credentials
    /// The master API credentials are used to authenticate this request - they already have the necessary permissions
    /// The created/updated user credentials will be assigned the role specified in userRoleName (e.g., SVC_WATCHER_USER)
    func authenticateWithEmail(_ email: String) async throws -> JamfCredentials {
        // Validate email format
        guard isValidEmail(email) else {
            throw JamfAPIError.invalidEmailFormat
        }
        
        // Get bearer token using master API credentials (these already have necessary permissions)
        let bearerToken = try await getBearerToken()
        
        // The role NAME to assign (not the ID) - Jamf API expects the role name in authorizationScopes
        let roleName = userRoleName
        
        // Search for existing credential by email
        if let existingCredential = try await searchCredentialByEmail(email, bearerToken: bearerToken) {
            // Credential exists, verify it has the correct user role assigned
            let hasCorrectRole = existingCredential.authorizationScopes?.contains(roleName) ?? false
            
            if !hasCorrectRole {
                // Update the user credential to add the required role
                try await updateCredentialRole(
                    id: existingCredential.id,
                    roleName: roleName,
                    bearerToken: bearerToken
                )
            }
            
            // Check if we have the secret stored in Keychain
            let keychain = KeychainManager.shared
            if let storedCredentials = keychain.loadJamfCredentials(),
               storedCredentials.email == email,
               storedCredentials.clientID == existingCredential.clientId {
                // We have matching credentials stored with the secret
                return storedCredentials
            } else {
                // Secret not available in Keychain
                // We cannot retrieve the secret from Jamf API after creation
                // Must create new user credentials with the required role
                return try await createUserCredential(for: email, roleName: roleName, bearerToken: bearerToken)
            }
        } else {
            // No existing credential, create new user credential with required role
            return try await createUserCredential(for: email, roleName: roleName, bearerToken: bearerToken)
        }
    }
    
    // MARK: - Get Bearer Token (Using Master Credentials)
    /// Authenticates using the master API client credentials
    /// The master credentials must already have the necessary permissions to create/manage API integrations
    /// No role assignment is needed for the master credentials
    private func getBearerToken() async throws -> String {
        // Check if we have a valid cached token
        if let token = cachedBearerToken,
           let expiration = tokenExpiration,
           expiration > Date().addingTimeInterval(60) { // 1 minute buffer
            return token
        }
        
        // Jamf Pro API OAuth endpoint
        guard let url = URL(string: "\(jamfURL)/api/v1/oauth/token") else {
            throw JamfAPIError.invalidURL
        }
        
        NSLog("🔐 Requesting bearer token from: %@", url.absoluteString)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
        
        // Build form body with credentials (per Jamf documentation)
        let parameters = [
            "grant_type": "client_credentials",
            "client_id": masterClientID,
            "client_secret": masterClientSecret
        ]
        let bodyString = parameters.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        request.httpBody = Data(bodyString.utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw JamfAPIError.invalidResponse
            }
            
            NSLog("🔐 Token response status: %d", httpResponse.statusCode)
            
            // Log the raw response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                NSLog("🔐 Token response body: %@", responseString)
            }
            
            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                NSLog("❌ Token error: %@", errorMessage)
                throw JamfAPIError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
            }
            
            // Try to decode - log any errors
            do {
                let tokenResponse = try JSONDecoder().decode(JamfBearerTokenResponse.self, from: data)
                
                // Cache the token
                cachedBearerToken = tokenResponse.accessToken
                
                // Calculate expiration from expires_in (seconds)
                tokenExpiration = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
                
                NSLog("✅ Bearer token obtained successfully (expires in %d seconds)", tokenResponse.expiresIn)
                return tokenResponse.accessToken
            } catch let decodeError {
                NSLog("❌ Decode error: %@", decodeError.localizedDescription)
                NSLog("❌ Decode error details: %@", String(describing: decodeError))
                throw JamfAPIError.decodingError(decodeError)
            }
            
        } catch let error as JamfAPIError {
            throw error
        } catch {
            throw JamfAPIError.networkError(error)
        }
    }
    
    // MARK: - Get User Role ID
    /// Retrieves the role ID for the role that will be assigned to user credentials
    /// This role (e.g., SVC_WATCHER_USER) defines what permissions the user will have
    /// The master credentials are NOT assigned this role - they already have the necessary permissions
    private func getUserRoleId(bearerToken: String) async throws -> String {
        // Check if we have cached role ID
        if let roleId = cachedUserRoleId {
            return roleId
        }
        
        guard let url = URL(string: "\(jamfURL)/api/v1/api-roles") else {
            throw JamfAPIError.invalidURL
        }
        
        NSLog("🔍 Fetching API roles from: %@", url.absoluteString)
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw JamfAPIError.invalidResponse
            }
            
            NSLog("🔍 Roles response status: %d", httpResponse.statusCode)
            
            // Log the raw response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                NSLog("🔍 Roles response body: %@", responseString)
            }
            
            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw JamfAPIError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
            }
            
            do {
                let rolesResponse = try JSONDecoder().decode(JamfRolesListResponse.self, from: data)
                
                NSLog("🔍 Found %d roles", rolesResponse.results.count)
                for role in rolesResponse.results {
                    NSLog("🔍 Role: %@ (id: %@)", role.displayName, role.id)
                }
                
                // Find the role that will be assigned to user credentials
                guard let role = rolesResponse.results.first(where: { $0.displayName == userRoleName }) else {
                    NSLog("❌ Role '%@' not found!", userRoleName)
                    throw JamfAPIError.roleNotFound
                }
                
                // Cache the role ID
                cachedUserRoleId = role.id
                
                return role.id
            } catch let decodeError {
                NSLog("❌ Roles decode error: %@", decodeError.localizedDescription)
                NSLog("❌ Roles decode error details: %@", String(describing: decodeError))
                throw JamfAPIError.decodingError(decodeError)
            }
            
        } catch let error as JamfAPIError {
            throw error
        } catch {
            throw JamfAPIError.networkError(error)
        }
    }
    
    // MARK: - Search Credential by Email
    private func searchCredentialByEmail(_ email: String, bearerToken: String) async throws -> JamfAPIClientCredential? {
        // List all API client credentials and search for matching email in displayName
        guard let url = URL(string: "\(jamfURL)/api/v1/api-integrations") else {
            throw JamfAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw JamfAPIError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw JamfAPIError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
            }
            
            let listResponse = try JSONDecoder().decode(JamfAPIClientCredentialsListResponse.self, from: data)
            
            // Search for credential with email in displayName
            // Format is: "email@example.com (client_id)"
            let matchingCredential = listResponse.results.first { credential in
                guard let displayName = credential.displayName else { return false }
                return displayName.lowercased().hasPrefix(email.lowercased())
            }
            
            return matchingCredential
            
        } catch let error as JamfAPIError {
            throw error
        } catch let error as DecodingError {
            throw JamfAPIError.decodingError(error)
        } catch {
            throw JamfAPIError.networkError(error)
        }
    }
    
    // MARK: - Create User Credential
    /// Creates a new API credential for a user with the specified role
    /// Flow: 1) Create integration, 2) Enable it, 3) Generate client credentials
    private func createUserCredential(for email: String, roleName: String, bearerToken: String) async throws -> JamfCredentials {
        // Step 1: Create the integration
        guard let createUrl = URL(string: "\(jamfURL)/api/v1/api-integrations") else {
            throw JamfAPIError.invalidURL
        }
        
        let createRequest = JamfAPIClientCredentialCreateRequest(
            displayName: email,
            authorizationScopes: [roleName]
        )
        
        var request = URLRequest(url: createUrl)
        request.httpMethod = "POST"
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(createRequest)
        
        let (createData, createResponse) = try await URLSession.shared.data(for: request)
        
        guard let createHttpResponse = createResponse as? HTTPURLResponse,
              createHttpResponse.statusCode == 201 || createHttpResponse.statusCode == 200 else {
            let errorMessage = String(data: createData, encoding: .utf8) ?? "Unknown error"
            throw JamfAPIError.serverError(statusCode: (createResponse as? HTTPURLResponse)?.statusCode ?? 0, message: errorMessage)
        }
        
        // Parse create response to get ID
        guard let createJson = try? JSONSerialization.jsonObject(with: createData) as? [String: Any],
              let integrationId = createJson["id"] as? Int else {
            throw JamfAPIError.decodingError(NSError(domain: "JamfAPI", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not parse integration ID"]))
        }
        
        NSLog("✅ Created integration with ID: %d", integrationId)
        
        // Step 2: Enable the integration
        // Jamf Pro API PUT requires both displayName and authorizationScopes
        guard let enableUrl = URL(string: "\(jamfURL)/api/v1/api-integrations/\(integrationId)") else {
            throw JamfAPIError.invalidURL
        }
        
        var enableRequest = URLRequest(url: enableUrl)
        enableRequest.httpMethod = "PUT"
        enableRequest.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        enableRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        enableRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let enableBody: [String: Any] = [
            "displayName": email,
            "enabled": true,
            "authorizationScopes": [roleName]
        ]
        enableRequest.httpBody = try JSONSerialization.data(withJSONObject: enableBody)
        
        let (enableData, enableResponse) = try await URLSession.shared.data(for: enableRequest)
        
        guard let enableHttpResponse = enableResponse as? HTTPURLResponse,
              enableHttpResponse.statusCode == 200 else {
            let errorMessage = String(data: enableData, encoding: .utf8) ?? "Unknown error"
            throw JamfAPIError.serverError(statusCode: (enableResponse as? HTTPURLResponse)?.statusCode ?? 0, message: errorMessage)
        }
        
        NSLog("✅ Enabled integration")
        
        // Brief delay for server-side state propagation
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Step 3: Generate client credentials
        guard let credentialsUrl = URL(string: "\(jamfURL)/api/v1/api-integrations/\(integrationId)/client-credentials") else {
            throw JamfAPIError.invalidURL
        }
        
        var credRequest = URLRequest(url: credentialsUrl)
        credRequest.httpMethod = "POST"
        credRequest.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        credRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (credData, credResponse) = try await URLSession.shared.data(for: credRequest)
        
        guard let credHttpResponse = credResponse as? HTTPURLResponse,
              credHttpResponse.statusCode == 200 else {
            let errorMessage = String(data: credData, encoding: .utf8) ?? "Unknown error"
            throw JamfAPIError.serverError(statusCode: (credResponse as? HTTPURLResponse)?.statusCode ?? 0, message: errorMessage)
        }
        
        // Parse credentials response
        guard let credJson = try? JSONSerialization.jsonObject(with: credData) as? [String: Any],
              let clientId = credJson["clientId"] as? String,
              let clientSecret = credJson["clientSecret"] as? String else {
            throw JamfAPIError.decodingError(NSError(domain: "JamfAPI", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not parse client credentials"]))
        }
        
        NSLog("✅ Generated client credentials")
        
        // Default expiration to 90 days
        let expirationDate = Calendar.current.date(byAdding: .day, value: 90, to: Date())
        
        return JamfCredentials(
            clientID: clientId,
            clientSecret: clientSecret,
            email: email,
            expiresAt: expirationDate
        )
    }
    
    // MARK: - Update Credential Display Name
    private func updateCredentialDisplayName(id: Int, displayName: String, bearerToken: String) async throws {
        guard let url = URL(string: "\(jamfURL)/api/v1/api-integrations/\(id)") else {
            throw JamfAPIError.invalidURL
        }
        
        // GET current integration to preserve required fields
        var getRequest = URLRequest(url: url)
        getRequest.httpMethod = "GET"
        getRequest.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        getRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (getData, getResponse) = try await URLSession.shared.data(for: getRequest)
        guard let getHttpResponse = getResponse as? HTTPURLResponse,
              getHttpResponse.statusCode == 200,
              let getJson = try? JSONSerialization.jsonObject(with: getData) as? [String: Any],
              let currentScopes = getJson["authorizationScopes"] as? [String] else {
            throw JamfAPIError.invalidResponse
        }
        
        let currentEnabled = getJson["enabled"] as? Bool ?? true
        
        // PUT with all required fields
        let updateBody: [String: Any] = [
            "displayName": displayName,
            "authorizationScopes": currentScopes,
            "enabled": currentEnabled
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: updateBody)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw JamfAPIError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw JamfAPIError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
            }
            
        } catch let error as JamfAPIError {
            throw error
        } catch {
            throw JamfAPIError.networkError(error)
        }
    }
    
    // MARK: - Update Credential Role
    /// Updates a user credential to add/change the assigned role
    /// This ensures the user credential has the required permissions (e.g., SVC_WATCHER_USER)
    private func updateCredentialRole(id: Int, roleName: String, bearerToken: String) async throws {
        guard let url = URL(string: "\(jamfURL)/api/v1/api-integrations/\(id)") else {
            throw JamfAPIError.invalidURL
        }
        
        // GET current integration to preserve required fields
        var getRequest = URLRequest(url: url)
        getRequest.httpMethod = "GET"
        getRequest.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        getRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (getData, getResponse) = try await URLSession.shared.data(for: getRequest)
        guard let getHttpResponse = getResponse as? HTTPURLResponse,
              getHttpResponse.statusCode == 200,
              let getJson = try? JSONSerialization.jsonObject(with: getData) as? [String: Any],
              let currentDisplayName = getJson["displayName"] as? String else {
            throw JamfAPIError.invalidResponse
        }
        
        let currentEnabled = getJson["enabled"] as? Bool ?? true
        
        // PUT with all required fields
        let updateBody: [String: Any] = [
            "displayName": currentDisplayName,
            "authorizationScopes": [roleName],
            "enabled": currentEnabled
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: updateBody)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw JamfAPIError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw JamfAPIError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
            }
            
        } catch let error as JamfAPIError {
            throw error
        } catch {
            throw JamfAPIError.networkError(error)
        }
    }
    
    // MARK: - Refresh Credentials
    func refreshCredentials(for email: String) async throws -> JamfCredentials {
        let bearerToken = try await getBearerToken()
        
        // Create new user credential with required role (by name)
        return try await createUserCredential(for: email, roleName: userRoleName, bearerToken: bearerToken)
    }
    
    // MARK: - Test Methods (for debugging)
    /// Public method to test bearer token retrieval
    func testGetBearerToken() async throws -> String {
        return try await getBearerToken()
    }
    
    /// Public method to test roles API - returns raw JSON string
    func testGetRoles(bearerToken: String) async throws -> String {
        guard let url = URL(string: "\(jamfURL)/api/v1/api-roles") else {
            throw JamfAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw JamfAPIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw JamfAPIError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        // Return raw JSON for inspection
        let rawJSON = String(data: data, encoding: .utf8) ?? "Could not decode"
        return rawJSON
    }
    
    /// Public method to test integrations API - returns raw JSON string
    func testGetIntegrations(bearerToken: String) async throws -> String {
        guard let url = URL(string: "\(jamfURL)/api/v1/api-integrations") else {
            throw JamfAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw JamfAPIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw JamfAPIError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        // Return raw JSON for inspection
        let rawJSON = String(data: data, encoding: .utf8) ?? "Could not decode"
        return rawJSON
    }
    
    /// Public method to test create integration - returns raw JSON string
    func testCreateIntegration(email: String, bearerToken: String) async throws -> String {
        // Step 1: Create the integration
        guard let url = URL(string: "\(jamfURL)/api/v1/api-integrations") else {
            throw JamfAPIError.invalidURL
        }
        
        let integrationDisplayName = "TEST3_\(email)"
        
        let createRequest = JamfAPIClientCredentialCreateRequest(
            displayName: integrationDisplayName,
            authorizationScopes: [userRoleName]
        )
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(createRequest)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 201 || httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            return "Create failed: \(errorMessage)"
        }
        
        let createResponse = String(data: data, encoding: .utf8) ?? ""
        
        // Parse the response to get the ID
        guard let jsonData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let integrationId = jsonData["id"] as? Int else {
            return "Created but couldn't parse ID:\n\(createResponse)"
        }
        
        // Step 2: Enable the integration (displayName and authorizationScopes are REQUIRED)
        guard let enableUrl = URL(string: "\(jamfURL)/api/v1/api-integrations/\(integrationId)") else {
            return "Created but failed to build enable URL.\n\nCreate response:\n\(createResponse)"
        }
        
        var enableRequest = URLRequest(url: enableUrl)
        enableRequest.httpMethod = "PUT"
        enableRequest.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        enableRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        enableRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Must include displayName — it's required by the Jamf Pro PUT schema
        let enableBody: [String: Any] = [
            "displayName": integrationDisplayName,
            "enabled": true,
            "authorizationScopes": [userRoleName]
        ]
        enableRequest.httpBody = try JSONSerialization.data(withJSONObject: enableBody)
        
        let (enableData, enableResponse) = try await URLSession.shared.data(for: enableRequest)
        
        guard let enableHttpResponse = enableResponse as? HTTPURLResponse,
              enableHttpResponse.statusCode == 200 else {
            let enableError = String(data: enableData, encoding: .utf8) ?? "Unknown"
            return "Created but enable failed (status \((enableResponse as? HTTPURLResponse)?.statusCode ?? 0)):\n\(enableError)\n\nCreate response:\n\(createResponse)"
        }
        
        // Brief delay for server-side state propagation
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Step 3: Generate client credentials
        guard let credentialsUrl = URL(string: "\(jamfURL)/api/v1/api-integrations/\(integrationId)/client-credentials") else {
            return "Created & enabled but failed to build credentials URL.\n\nCreate response:\n\(createResponse)"
        }
        
        var credRequest = URLRequest(url: credentialsUrl)
        credRequest.httpMethod = "POST"
        credRequest.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        credRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (credData, credResponse) = try await URLSession.shared.data(for: credRequest)
        
        guard let credHttpResponse = credResponse as? HTTPURLResponse else {
            return "Created & enabled but credentials call failed.\n\nCreate response:\n\(createResponse)"
        }
        
        let credResult = String(data: credData, encoding: .utf8) ?? "No data"
        
        return "✅ CREDENTIALS RESPONSE (status \(credHttpResponse.statusCode)):\n\(credResult)"
    }
    
    // MARK: - Email Validation
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    // MARK: - Mock Authentication (For Development/Testing)
    func mockAuthenticate(email: String) async throws -> JamfCredentials {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        
        // Simulate success or failure based on email format
        guard isValidEmail(email) else {
            throw JamfAPIError.invalidEmailFormat
        }
        
        // Generate mock credentials
        let clientID = "client_" + UUID().uuidString.prefix(12).lowercased()
        let clientSecret = "secret_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let expiresAt = Calendar.current.date(byAdding: .day, value: 90, to: Date())
        
        return JamfCredentials(
            clientID: clientID,
            clientSecret: clientSecret,
            email: email,
            expiresAt: expiresAt
        )
    }
}
