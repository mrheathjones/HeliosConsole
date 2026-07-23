//
//  ComputerHistoryModels.swift
//  HeliosConsole
//
//  Decoded shapes for the Jamf **Classic** API `computerhistory` endpoint.
//  We model only the two buckets the Device Details "History" section renders:
//  Policy Logs and MDM Commands.
//
//  Classic's JSON is notoriously inconsistent, so decoding here is deliberately
//  DEFENSIVE and never throws:
//    * Numeric fields arrive as JSON numbers OR quoted strings depending on the
//      field and Jamf version — `policy_id`, every `*_epoch`, etc. Each scalar
//      is decoded flexibly (number-or-string) so a type surprise can't nuke the
//      whole payload.
//    * Empty collections sometimes serialize as "" instead of []/{} — every
//      container is decoded with `try?` so that degrades to nil, not a throw.
//    * Unmodeled subsets (usage logs, screen sharing, audits, …) are ignored.
//
//  Classic wraps everything under a top-level `computer_history` key and uses
//  snake_case throughout.
//

import Foundation

// MARK: - Flexible scalar decoding

private extension KeyedDecodingContainer {
    /// Decode a value that Jamf might send as a String, Int, Double, or Bool,
    /// normalized to String. Returns nil for absent/null/unconvertible.
    func flexibleString(_ key: Key) -> String? {
        // `try?` flattens both the throw and decodeIfPresent's own optional into
        // a single-level Optional, so one `let` binding is correct here.
        // Treat empty strings as absent so `??` fallback chains work.
        if let v = try? decodeIfPresent(String.self, forKey: key), !v.isEmpty { return v }
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return String(v) }
        if let v = try? decodeIfPresent(Double.self, forKey: key) {
            return v == v.rounded() ? String(Int64(v)) : String(v)
        }
        if let v = try? decodeIfPresent(Bool.self, forKey: key) { return String(v) }
        return nil
    }

    /// Decode an integer that might be a JSON number or a quoted string.
    func flexibleInt(_ key: Key) -> Int? {
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return v }
        if let v = try? decodeIfPresent(String.self, forKey: key) { return Int(v) }
        if let v = try? decodeIfPresent(Double.self, forKey: key) { return Int(v) }
        return nil
    }
}

// MARK: - Top-level wrapper

struct ComputerHistoryResponse: Decodable {
    let computerHistory: ComputerHistory?

    enum CodingKeys: String, CodingKey {
        case computerHistory = "computer_history"
    }

    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
            computerHistory = nil
            return
        }
        computerHistory = (try? c.decodeIfPresent(ComputerHistory.self, forKey: .computerHistory)) ?? nil
    }
}

struct ComputerHistory: Decodable {
    let policyLogs: [PolicyLogEntry]?
    let commands: CommandHistory?

    enum CodingKeys: String, CodingKey {
        case policyLogs = "policy_logs"
        case commands
    }

    init(policyLogs: [PolicyLogEntry]?, commands: CommandHistory?) {
        self.policyLogs = policyLogs
        self.commands = commands
    }

    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
            policyLogs = nil
            commands = nil
            return
        }
        policyLogs = (try? c.decodeIfPresent([PolicyLogEntry].self, forKey: .policyLogs)) ?? nil
        commands = (try? c.decodeIfPresent(CommandHistory.self, forKey: .commands)) ?? nil
    }

    static let empty = ComputerHistory(policyLogs: nil, commands: nil)

    var isEmpty: Bool {
        (policyLogs?.isEmpty ?? true) && (commands?.isEmpty ?? true)
    }
}

// MARK: - Date resolution

/// Resolves a Jamf Classic timestamp from its epoch-milliseconds string, with
/// an ISO8601 `*_utc` string fallback (e.g. "2016-06-16T13:00:00.000-0700").
enum JamfHistoryDate {
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    /// Jamf's human-readable `date_time` (e.g. "2024-01-15 10:30:45"), in the
    /// JSS server's local time zone.
    private static let plainFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    /// Resolve the best available representation: epoch ms → ISO8601 `*_utc` →
    /// the plain `date_time` string.
    static func parse(epoch: String?, utc: String?, plain: String? = nil) -> Date? {
        if let epoch, let ms = Double(epoch), ms > 0 {
            return Date(timeIntervalSince1970: ms / 1000)
        }
        if let utc, !utc.isEmpty {
            if let d = isoFractional.date(from: utc) ?? iso.date(from: utc) { return d }
        }
        if let plain, !plain.isEmpty {
            return plainFormatter.date(from: plain)
        }
        return nil
    }
}

// MARK: - Policy Logs

struct PolicyLogEntry: Decodable, Identifiable, Hashable {
    let policyId: Int?
    let policyName: String?
    let username: String?
    let dateTime: String?
    let dateTimeEpoch: String?
    let dateTimeUtc: String?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case policyId = "policy_id"
        case policyName = "policy_name"
        case username
        case status
        // Jamf's policy_logs use `date_completed*` (verified against a live
        // computerhistory response). `date_time*` is kept as a fallback for
        // versions/subsets that use the other naming.
        case dateCompleted = "date_completed"
        case dateCompletedEpoch = "date_completed_epoch"
        case dateCompletedUtc = "date_completed_utc"
        case dateTime = "date_time"
        case dateTimeEpoch = "date_time_epoch"
        case dateTimeUtc = "date_time_utc"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        policyId = c.flexibleInt(.policyId)
        policyName = c.flexibleString(.policyName)
        username = c.flexibleString(.username)
        status = c.flexibleString(.status)
        dateTime = c.flexibleString(.dateCompleted) ?? c.flexibleString(.dateTime)
        dateTimeEpoch = c.flexibleString(.dateCompletedEpoch) ?? c.flexibleString(.dateTimeEpoch)
        dateTimeUtc = c.flexibleString(.dateCompletedUtc) ?? c.flexibleString(.dateTimeUtc)
    }

    /// Classic gives no stable per-row id; synthesize one from policy + time so
    /// SwiftUI `ForEach` stays stable across refreshes.
    var id: String { "\(policyId ?? -1)-\(dateTimeEpoch ?? dateTime ?? "0")" }

    var date: Date? { JamfHistoryDate.parse(epoch: dateTimeEpoch, utc: dateTimeUtc, plain: dateTime) }

    /// Jamf reports policy outcomes as "Completed" / "Failed".
    var isSuccess: Bool {
        (status ?? "").caseInsensitiveCompare("Completed") == .orderedSame
    }
}

// MARK: - Commands (Management History)

struct CommandHistory: Decodable, Hashable {
    let completed: [CommandEntry]?
    let pending: [CommandEntry]?
    let failed: [CommandEntry]?

    enum CodingKeys: String, CodingKey {
        case completed, pending, failed
    }

    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
            completed = nil
            pending = nil
            failed = nil
            return
        }
        completed = (try? c.decodeIfPresent([CommandEntry].self, forKey: .completed)) ?? nil
        pending = (try? c.decodeIfPresent([CommandEntry].self, forKey: .pending)) ?? nil
        failed = (try? c.decodeIfPresent([CommandEntry].self, forKey: .failed)) ?? nil
    }

    var isEmpty: Bool {
        (completed?.isEmpty ?? true)
            && (pending?.isEmpty ?? true)
            && (failed?.isEmpty ?? true)
    }
}

/// One MDM command row. Classic uses a different timestamp key per bucket
/// (`completed*` / `issued*` / `failed*` / `last_push*`); we decode all epoch +
/// utc variants and expose a single best-available `date`. For the *failed*
/// bucket Jamf overloads `status` with the error text, which the view surfaces.
struct CommandEntry: Decodable, Identifiable, Hashable {
    let name: String?
    let status: String?
    let username: String?
    let completedEpoch: String?
    let completedUtc: String?
    let issuedEpoch: String?
    let issuedUtc: String?
    let failedEpoch: String?
    let failedUtc: String?
    let lastPushEpoch: String?
    let lastPushUtc: String?

    enum CodingKeys: String, CodingKey {
        case name
        case status
        case username
        case completedEpoch = "completed_epoch"
        case completedUtc = "completed_utc"
        case issuedEpoch = "issued_epoch"
        case issuedUtc = "issued_utc"
        case failedEpoch = "failed_epoch"
        case failedUtc = "failed_utc"
        case lastPushEpoch = "last_push_epoch"
        case lastPushUtc = "last_push_utc"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.flexibleString(.name)
        status = c.flexibleString(.status)
        username = c.flexibleString(.username)
        completedEpoch = c.flexibleString(.completedEpoch)
        completedUtc = c.flexibleString(.completedUtc)
        issuedEpoch = c.flexibleString(.issuedEpoch)
        issuedUtc = c.flexibleString(.issuedUtc)
        failedEpoch = c.flexibleString(.failedEpoch)
        failedUtc = c.flexibleString(.failedUtc)
        lastPushEpoch = c.flexibleString(.lastPushEpoch)
        lastPushUtc = c.flexibleString(.lastPushUtc)
    }

    var id: String {
        "\(name ?? "?")-\(completedEpoch ?? failedEpoch ?? issuedEpoch ?? lastPushEpoch ?? "0")"
    }

    /// Most-relevant timestamp for the bucket this command came from
    /// (completed → failed → issued → last push).
    var date: Date? {
        JamfHistoryDate.parse(epoch: completedEpoch, utc: completedUtc)
            ?? JamfHistoryDate.parse(epoch: failedEpoch, utc: failedUtc)
            ?? JamfHistoryDate.parse(epoch: issuedEpoch, utc: issuedUtc)
            ?? JamfHistoryDate.parse(epoch: lastPushEpoch, utc: lastPushUtc)
    }
}
