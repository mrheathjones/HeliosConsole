//
//  MyDevicesService.swift
//  HeliosConsole
//
//  Backs the `myDevices` module: "which devices are assigned to the person
//  signed into Helios right now, and what should they know about them?"
//
//  THE PROBLEM THIS SOLVES. Helios knows the operator by EMAIL (the Entra UPN,
//  or the address used by the built-in email flow). Jamf inventory records
//  carry a `userAndLocation.username`, which in most tenants is a directory
//  short name (`hea08299`) with no derivable relationship to that email. So
//  the service does not guess: it asks Jamf's own user directory
//  (`/api/v1/users?filter=email=="…"`) for the records belonging to that
//  address, takes EVERY username they carry — one person routinely holds both
//  a short-name record and a UPN-style one — and searches inventory for all of
//  them at once. Only when that endpoint is unavailable (no Read Users
//  privilege) does it fall back to the candidates derivable from the email.
//
//  CREDENTIALS. Reuses the existing `.deviceSearch` scope (same as
//  ComputerSearchService / ComputerHistoryService) — this is a read of the
//  same inventory by the same person, so it introduces no new routing knob.
//
//  API ROLE PRIVILEGES: Read Computers, Read Mobile Devices, and — for the
//  accurate identity mapping — Read Users. A 403 on the users lookup is
//  NON-FATAL and logged; the module degrades to the derived candidates rather
//  than failing.
//
//  READ-ONLY BY CONSTRUCTION: this service issues GETs and nothing else. No
//  MDM command, no write endpoint, no action path is reachable from here.
//

import Combine
import Foundation

// MARK: - Model

/// One device belonging to the signed-in user. Wraps the two inventory shapes
/// the app already has rather than inventing a third, so tapping a card can
/// push the SAME detail views the Devices module uses.
enum MyDevice: Identifiable, Hashable {
    case computer(Computer)
    case mobileDevice(MobileDeviceInventoryItem)

    var id: String {
        switch self {
        case .computer(let computer): return "computer-\(computer.id)"
        case .mobileDevice(let device): return "mobile-\(device.id)"
        }
    }

    /// The Jamf record id WITHOUT the type prefix — what API calls take.
    var recordID: String {
        switch self {
        case .computer(let computer): return computer.id
        case .mobileDevice(let device): return device.id
        }
    }

    var platform: PlatformType {
        switch self {
        case .computer: return .macOS
        case .mobileDevice(let device): return device.platformType
        }
    }

    var name: String {
        switch self {
        case .computer(let computer): return computer.general?.name ?? "Unknown"
        case .mobileDevice(let device): return device.deviceName
        }
    }

    var serialNumber: String? {
        switch self {
        case .computer(let computer): return computer.hardware?.serialNumber
        case .mobileDevice(let device): return device.serialNumber
        }
    }

    var modelName: String {
        switch self {
        case .computer(let computer): return computer.hardware?.model ?? "Mac"
        case .mobileDevice(let device): return device.displayModel
        }
    }

    var modelIdentifier: String? {
        switch self {
        case .computer(let computer): return computer.hardware?.modelIdentifier
        case .mobileDevice(let device): return device.modelIdentifier
        }
    }

    var osVersion: String? {
        switch self {
        case .computer(let computer): return computer.operatingSystem?.version
        case .mobileDevice(let device): return device.osVersion
        }
    }

    /// Resolved through `HealthEvaluator.resolveCheckIn` rather than
    /// `Computer.lastCheckIn`: that accessor parses with a bare
    /// `ISO8601DateFormatter`, which rejects the fractional seconds Jamf
    /// actually sends, and it never falls back to `reportDate`.
    var lastCheckIn: Date? {
        switch self {
        case .computer(let computer):
            return HealthEvaluator.resolveCheckIn(
                lastContactTime: computer.general?.lastContactTime,
                reportDate: computer.general?.reportDate
            )
        case .mobileDevice(let device):
            return device.lastInventoryUpdate
        }
    }

    var isManaged: Bool {
        switch self {
        case .computer(let computer): return computer.isManaged
        case .mobileDevice(let device): return device.isManaged
        }
    }

    var isSupervised: Bool {
        switch self {
        case .computer(let computer): return computer.isSupervised
        case .mobileDevice(let device): return device.isSupervised
        }
    }

    /// The assigned user as Jamf records it — shown so a person can see WHY a
    /// device is on their list (and spot a stale assignment).
    var assignedUser: String? {
        switch self {
        case .computer(let computer):
            return computer.userAndLocation?.realname ?? computer.userAndLocation?.username
        case .mobileDevice(let device):
            return device.assignedUser
        }
    }

    /// Storage as (usedFraction, "123 GB free of 494 GB"), when inventory
    /// carries it. Computers report the boot partition; mobile devices report
    /// whole-device capacity.
    var storage: (fraction: Double, summary: String)? {
        switch self {
        case .computer(let computer):
            guard let partition = Self.bootPartition(of: computer) else { return nil }
            return Self.usage(capacityMb: partition.sizeMegabytes, availableMb: partition.availableMegabytes)
        case .mobileDevice(let device):
            return Self.usage(
                capacityMb: device.hardware?.capacityMb,
                availableMb: device.hardware?.availableSpaceMb
            )
        }
    }

    /// The boot partition when Jamf labels one, otherwise the first partition
    /// of the first disk — a single-disk Mac reports exactly one either way.
    private static func bootPartition(of computer: Computer) -> Partition? {
        let partitions: [Partition] = (computer.storage?.disks ?? []).flatMap { $0.partitions ?? [] }
        let boot = partitions.first { partition in
            (partition.partitionType ?? "").uppercased().contains("BOOT")
        }
        return boot ?? partitions.first
    }

    private static func usage(capacityMb: Int?, availableMb: Int?) -> (fraction: Double, summary: String)? {
        guard let capacity = capacityMb, capacity > 0 else { return nil }
        let available = availableMb ?? 0
        let fraction = Double(capacity - available) / Double(capacity)
        let summary = "\(gigabytes(available)) free of \(gigabytes(capacity))"
        return (fraction, summary)
    }

    /// Whether the device's data is encrypted at rest: FileVault on a Mac,
    /// data protection (i.e. a passcode is set) on a mobile device. Nil when
    /// the inventory sections needed to tell were not fetched.
    var isEncrypted: Bool? {
        switch self {
        case .computer(let computer):
            guard computer.diskEncryption != nil else { return nil }
            return computer.isFileVaultEnabled
        case .mobileDevice(let device):
            guard let security = device.security else { return nil }
            return security.dataProtected ?? security.passcodePresent
        }
    }

    /// Battery percentage — mobile devices only (Jamf does not inventory Mac
    /// battery level).
    var batteryLevel: Int? {
        switch self {
        case .computer: return nil
        case .mobileDevice(let device): return device.hardware?.batteryLevel
        }
    }

    private static func gigabytes(_ megabytes: Int) -> String {
        let gigabytes = Double(megabytes) / 1024
        return gigabytes >= 100
            ? String(format: "%.0f GB", gigabytes)
            : String(format: "%.1f GB", gigabytes)
    }
}

// MARK: - Service

@MainActor
final class MyDevicesService: ObservableObject {

    /// Why the list looks the way it does. The view says this out loud —
    /// "we found nothing for you" and "here is your Mac, which may not be
    /// assigned to you in Jamf" are very different messages.
    enum Origin: Equatable {
        /// Nothing has been loaded yet.
        case idle
        /// Devices matched to the signed-in identity.
        case assigned
        /// No assignment matched; showing the Mac Helios is running on.
        case localDevice
        /// Nothing matched and the local Mac is not in Jamf (or the fallback
        /// is disabled).
        case empty
    }

    @Published private(set) var devices: [MyDevice] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var origin: Origin = .idle
    @Published private(set) var lastRefresh: Date?

    /// The Jamf usernames the signed-in identity resolved to, in the order
    /// they were tried. Surfaced in the view's "how we matched you" footer so
    /// an empty result is diagnosable by the person looking at it.
    @Published private(set) var matchedUsernames: [String] = []

    /// Set when the directory lookup was attempted but could not be used
    /// (typically a missing Read Users privilege). Display-only.
    @Published private(set) var directoryLookupNote: String?

    private var configuration: MDMConfiguration {
        MDMConfigurationManager.shared.configuration
    }

    private var settings: FeaturesConfiguration.MyDevicesSettings {
        configuration.features?.effectiveMyDevices ?? .empty
    }

    private var jamfURL: String { configuration.jamfURL }

    private var cachedToken: String?
    private var tokenExpiration: Date?

    // MARK: - Loading

    /// Resolves the signed-in identity and loads their devices. Safe to call
    /// repeatedly — a load already in flight wins and the call returns.
    func load() async {
        guard !isLoading else { return }

        let email = UserSession.shared.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = UserSession.shared.displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        isLoading = true
        errorMessage = nil
        directoryLookupNote = nil

        defer {
            isLoading = false
            lastRefresh = Date()
        }

        guard !jamfURL.isEmpty else {
            errorMessage = "Helios is not configured for a Jamf Pro server."
            origin = .empty
            return
        }

        let token: String
        do {
            token = try await bearerToken()
        } catch {
            errorMessage = "Could not authenticate with Jamf Pro: \(error.localizedDescription)"
            origin = .empty
            return
        }

        // 1. Identity → the usernames Jamf knows this person by.
        let usernames = await resolveUsernames(email: email, token: token)
        matchedUsernames = usernames

        // 2. Inventory, both platforms in parallel, each gated by the same
        //    features switch the rest of the app honors.
        let features = configuration.features
        let computersEnabled = features?.effectiveComputers.effectiveEnabled ?? true
        let mobilesEnabled = features?.effectiveMobileDevices.effectiveEnabled ?? true

        async let computersTask = computersEnabled
            ? fetchComputers(usernames: usernames, email: email, realName: displayName, token: token)
            : []
        async let mobilesTask = mobilesEnabled
            ? fetchMobileDevices(usernames: usernames, email: email, realName: displayName, token: token)
            : []

        let (computers, mobiles) = await (computersTask, mobilesTask)

        var found: [MyDevice] = computers.map { .computer($0) } + mobiles.map { .mobileDevice($0) }

        // 3. Nothing assigned? Offer the one device we can always identify.
        if found.isEmpty {
            if settings.effectiveShowLocalDeviceFallback, computersEnabled,
               let serial = LocalDeviceIdentity.serialNumber,
               let local = await fetchComputer(serialNumber: serial, token: token) {
                devices = [.computer(local)]
                origin = .localDevice
                return
            }
            devices = []
            origin = .empty
            return
        }

        found.sort { lhs, rhs in
            // Macs first, then by name — a person's Mac is what they came for.
            if (lhs.platform == .macOS) != (rhs.platform == .macOS) {
                return lhs.platform == .macOS
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        let capped = Array(found.prefix(settings.effectiveMaxDevices))
        if capped.count < found.count {
            NSLog("⚠️ MyDevices: %d device(s) matched, capped to %d by features.myDevices.maxDevices",
                  found.count, settings.effectiveMaxDevices)
        }
        devices = capped
        origin = .assigned
    }

    /// Full detail for a mobile device, in the shape `MobileDeviceView` takes.
    /// The list carries the `/detail` collection shape, which is a different
    /// model — so opening a mobile device costs one extra GET, exactly as the
    /// Devices list already does.
    func mobileDeviceDetail(id: String) async throws -> MobileDevice {
        let token = try await bearerToken()
        let sections = [
            "GENERAL", "HARDWARE", "USER_AND_LOCATION", "PURCHASING", "SECURITY",
            "APPLICATIONS", "NETWORK", "CERTIFICATES", "PROFILES", "GROUPS",
            "EXTENSION_ATTRIBUTES"
        ].map { "section=\($0)" }.joined(separator: "&")

        guard let url = URL(string: "\(jamfURL)/api/v2/mobile-devices/\(id)/detail?\(sections)") else {
            throw MyDevicesError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(for: authorized(url, token: token))
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw MyDevicesError.httpError(statusCode: code)
        }
        return try JSONDecoder().decode(MobileDevice.self, from: data)
    }

    // MARK: - Identity resolution

    /// The usernames to search inventory for, most-authoritative first:
    /// Jamf's own user records for this email, then the candidates derivable
    /// from the email itself (each gated by its own switch). Case-insensitively
    /// de-duplicated, order preserved.
    private func resolveUsernames(email: String, token: String) async -> [String] {
        var ordered: [String] = []
        var seen: Set<String> = []

        func append(_ candidate: String?) {
            guard let candidate = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !candidate.isEmpty,
                  seen.insert(candidate.lowercased()).inserted else { return }
            ordered.append(candidate)
        }

        if settings.effectiveResolveDirectoryUsers, !email.isEmpty {
            for record in await fetchDirectoryUsers(email: email, token: token) {
                append(record.username)
            }
        }

        if settings.effectiveMatchUsernameFromEmail {
            append(email)
        }

        if settings.effectiveMatchUsernameLocalPart, let localPart = email.split(separator: "@").first {
            append(String(localPart))
        }

        return ordered
    }

    /// `/api/v1/users?filter=email=="…"` — Jamf's mapping from email address
    /// to the username(s) inventory records are actually keyed by. Fail-soft
    /// in every direction: a 403 (no Read Users privilege), a transport error
    /// or a decode failure all return [] and leave the derived candidates to
    /// carry the lookup.
    private func fetchDirectoryUsers(email: String, token: String) async -> [JamfDirectoryUser] {
        let filter = "email==\"\(rsqlEscaped(email))\""
        guard var components = URLComponents(string: "\(jamfURL)/api/v1/users") else { return [] }
        components.queryItems = [
            URLQueryItem(name: "page", value: "0"),
            URLQueryItem(name: "page-size", value: "100"),
            URLQueryItem(name: "sort", value: "id:asc"),
            URLQueryItem(name: "filter", value: filter)
        ]
        guard let url = components.url else { return [] }

        do {
            let (data, response) = try await URLSession.shared.data(for: authorized(url, token: token))
            guard let http = response as? HTTPURLResponse else { return [] }

            guard (200...299).contains(http.statusCode) else {
                if http.statusCode == 401 || http.statusCode == 403 {
                    directoryLookupNote = "Jamf user directory lookup was denied (the API role needs Read Users) — matched on the sign-in address only."
                    NSLog("⚠️ MyDevices: /api/v1/users returned %d — falling back to derived usernames", http.statusCode)
                } else {
                    NSLog("⚠️ MyDevices: /api/v1/users returned %d", http.statusCode)
                }
                return []
            }

            let decoded = try JSONDecoder().decode(JamfDirectoryUserResponse.self, from: data)
            NSLog("✅ MyDevices: directory lookup matched %d user record(s)", decoded.results.count)
            return decoded.results
        } catch {
            NSLog("⚠️ MyDevices: directory lookup failed: %@", error.localizedDescription)
            return []
        }
    }

    // MARK: - Inventory

    /// Computers assigned to any resolved username (plus, when enabled, the
    /// email and real-name matches) in ONE request: RSQL ORs the clauses with
    /// `,`, so N usernames cost one round trip, not N.
    private func fetchComputers(
        usernames: [String],
        email: String,
        realName: String,
        token: String
    ) async -> [Computer] {
        var clauses = usernames.map { "userAndLocation.username==\"\(rsqlEscaped($0))\"" }
        if settings.effectiveMatchEmail, !email.isEmpty {
            clauses.append("userAndLocation.email==\"\(rsqlEscaped(email))\"")
        }
        if settings.effectiveMatchRealName, !realName.isEmpty {
            clauses.append("userAndLocation.realname==\"\(rsqlEscaped(realName))\"")
        }
        guard !clauses.isEmpty else { return [] }

        return await fetchComputers(filter: clauses.joined(separator: ","), token: token)
    }

    /// The local-Mac fallback's lookup: this hardware serial, whoever it is
    /// assigned to.
    private func fetchComputer(serialNumber: String, token: String) async -> Computer? {
        let results = await fetchComputers(
            filter: "hardware.serialNumber==\"\(rsqlEscaped(serialNumber))\"",
            token: token
        )
        return results.first
    }

    private func fetchComputers(filter: String, token: String) async -> [Computer] {
        // The detail views render these sections; reusing the configured list
        // keeps My Devices and Devices showing the same facts. STORAGE is
        // added on top because the card reports free space and that section is
        // NOT in the shared default (nothing else in the app needed it) — a
        // handful of records makes the extra payload irrelevant. It is
        // appended only when the endpoint accepts it and the profile has not
        // already asked for it.
        var sectionNames = (configuration.features?.effectiveComputers ?? .empty)
            .validatedInventorySections
        if !sectionNames.contains("STORAGE") {
            sectionNames.append("STORAGE")
        }
        let sections = sectionNames
            .map { "section=\($0)" }
            .joined(separator: "&")

        guard var components = URLComponents(string: "\(jamfURL)/api/v1/computers-inventory") else {
            return []
        }
        components.percentEncodedQuery = sections
            + "&page=0&page-size=\(settings.effectiveMaxDevices)"
            + "&filter=\(percentEncoded(filter))"

        guard let url = components.url else { return [] }

        do {
            let (data, response) = try await URLSession.shared.data(for: authorized(url, token: token))
            guard let http = response as? HTTPURLResponse else { return [] }
            guard (200...299).contains(http.statusCode) else {
                NSLog("❌ MyDevices: computers-inventory returned %d", http.statusCode)
                if errorMessage == nil, http.statusCode == 401 || http.statusCode == 403 {
                    errorMessage = "Your Jamf Pro access does not allow reading computers."
                }
                return []
            }

            struct Response: Codable {
                let totalCount: Int
                let results: [ComputerSearchResult]
            }

            let decoded = try JSONDecoder().decode(Response.self, from: data)
            return decoded.results.map { Computer.fromSearchResult($0) }
        } catch {
            NSLog("❌ MyDevices: computer lookup failed: %@", error.localizedDescription)
            if errorMessage == nil {
                errorMessage = "Could not load your Macs: \(error.localizedDescription)"
            }
            return []
        }
    }

    /// Mobile devices for the same identity. NOTE the different vocabulary:
    /// `/api/v2/mobile-devices/detail` filters on FLAT field names
    /// (`username`, `emailAddress`, `fullName`) where computers-inventory uses
    /// dotted paths. Getting this wrong 400s the request.
    private func fetchMobileDevices(
        usernames: [String],
        email: String,
        realName: String,
        token: String
    ) async -> [MobileDeviceInventoryItem] {
        var clauses = usernames.map { "username==\"\(rsqlEscaped($0))\"" }
        if settings.effectiveMatchEmail, !email.isEmpty {
            clauses.append("emailAddress==\"\(rsqlEscaped(email))\"")
        }
        if settings.effectiveMatchRealName, !realName.isEmpty {
            clauses.append("fullName==\"\(rsqlEscaped(realName))\"")
        }
        guard !clauses.isEmpty else { return [] }

        let sections = (configuration.features?.effectiveMobileDevices ?? .empty)
            .validatedInventorySections
            .map { "section=\($0)" }
            .joined(separator: "&")

        guard var components = URLComponents(string: "\(jamfURL)/api/v2/mobile-devices/detail") else {
            return []
        }
        components.percentEncodedQuery = sections
            + "&page=0&page-size=\(settings.effectiveMaxDevices)"
            + "&filter=\(percentEncoded(clauses.joined(separator: ",")))"

        guard let url = components.url else { return [] }

        do {
            let (data, response) = try await URLSession.shared.data(for: authorized(url, token: token))
            guard let http = response as? HTTPURLResponse else { return [] }
            guard (200...299).contains(http.statusCode) else {
                NSLog("❌ MyDevices: mobile-devices/detail returned %d", http.statusCode)
                if errorMessage == nil, http.statusCode == 401 || http.statusCode == 403 {
                    errorMessage = "Your Jamf Pro access does not allow reading mobile devices."
                }
                return []
            }

            let decoded = try JSONDecoder().decode(MobileDeviceInventoryResponse.self, from: data)
            return decoded.results
        } catch {
            NSLog("❌ MyDevices: mobile device lookup failed: %@", error.localizedDescription)
            return []
        }
    }

    // MARK: - Request plumbing

    private func authorized(_ url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = NetworkTuning.connectionTimeout
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// Strips the characters that would break out of an RSQL string literal.
    /// Values reaching here are directory data and the signed-in identity —
    /// not attacker-controlled — but a stray quote in a display name would
    /// otherwise 400 the whole request.
    private func rsqlEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\\", with: "")
    }

    /// Percent-encodes a built RSQL filter for the query string. `,` `;` `=`
    /// must survive verbatim (they are RSQL's OR, AND and comparison), which
    /// `.urlQueryAllowed` already guarantees — but that set also passes `&`
    /// and `+` through, and either one inside a value (a real name like
    /// "Smith & Sons") would split the query or decode as a space.
    private static let filterAllowed = CharacterSet.urlQueryAllowed
        .subtracting(CharacterSet(charactersIn: "&+"))

    private func percentEncoded(_ filter: String) -> String {
        filter.addingPercentEncoding(withAllowedCharacters: Self.filterAllowed) ?? filter
    }

    // MARK: - Token

    /// Routed by the `.deviceSearch` scope, exactly like the device search and
    /// history reads this sits beside. A `.user` result is fail-closed: the
    /// call throws rather than silently falling back to the master client.
    private func bearerToken() async throws -> String {
        if configuration.credentialSource(for: .deviceSearch) == .user {
            return try await JamfUserSession.shared.bearerToken()
        }

        if let cachedToken, let tokenExpiration, tokenExpiration > Date().addingTimeInterval(60) {
            return cachedToken
        }

        let clientID = configuration.masterClientID
        let clientSecret = configuration.masterClientSecret
        guard !clientID.isEmpty, !clientSecret.isEmpty else {
            throw MyDevicesError.noCredentials
        }

        guard let url = URL(string: "\(jamfURL)/api/v1/oauth/token") else {
            throw MyDevicesError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = NetworkTuning.connectionTimeout
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
        request.httpBody = "grant_type=client_credentials&client_id=\(clientID)&client_secret=\(clientSecret)"
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw MyDevicesError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        struct TokenResponse: Codable {
            let access_token: String
            let expires_in: Int
        }

        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        cachedToken = decoded.access_token
        tokenExpiration = Date().addingTimeInterval(TimeInterval(decoded.expires_in))
        return decoded.access_token
    }

    /// Drops the cached master token and every resolved result — called when
    /// the signed-in identity changes so one operator's devices can never
    /// linger on another's screen.
    func reset() {
        cachedToken = nil
        tokenExpiration = nil
        devices = []
        matchedUsernames = []
        directoryLookupNote = nil
        errorMessage = nil
        origin = .idle
        lastRefresh = nil
    }
}

// MARK: - Directory user (api/v1/users)

/// One Jamf user record. Only the fields the mapping needs are decoded — the
/// endpoint also returns phone, position and photo settings.
struct JamfDirectoryUser: Codable, Identifiable, Hashable {
    let id: String
    let username: String?
    let realname: String?
    let email: String?
}

struct JamfDirectoryUserResponse: Codable {
    let totalCount: Int
    let results: [JamfDirectoryUser]
}

// MARK: - Errors

enum MyDevicesError: LocalizedError {
    case invalidURL
    case noCredentials
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Jamf Pro URL configuration."
        case .noCredentials:
            return "No Jamf Pro credentials are available."
        case .httpError(let statusCode):
            return "Jamf Pro returned an error (\(statusCode))."
        }
    }
}
