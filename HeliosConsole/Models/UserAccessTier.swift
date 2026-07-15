//
//  UserAccessTier.swift
//  HeliosConsole
//
//  The operator's Helios access level, derived fail-closed from the Entra
//  id_token roles claim (see EntraAuthService). Comparable so gates can
//  read naturally: `tier >= .operator`.
//

import Foundation

enum UserAccessTier: String, Codable, Comparable {
    case admin = "Admin"
    case `operator` = "Operator"
    case none = "None"

    /// Ordering: none < operator < admin.
    private var rank: Int {
        switch self {
        case .none: return 0
        case .operator: return 1
        case .admin: return 2
        }
    }

    static func < (lhs: UserAccessTier, rhs: UserAccessTier) -> Bool {
        lhs.rank < rhs.rank
    }

    var displayName: String {
        switch self {
        case .admin: return "Administrator"
        case .operator: return "Operator"
        case .none: return "No Access"
        }
    }
}
