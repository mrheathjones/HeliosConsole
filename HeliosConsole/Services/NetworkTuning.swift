//
//  NetworkTuning.swift
//  HeliosConsole
//
//  Admin-tunable network timeouts, delivered by the core domain
//  (jamfPro.connectionTimeout / jamfPro.requestTimeout — see
//  schemas/Helios_Core_SCHEMA.json). Every URLRequest / URLSession
//  construction site reads these instead of hard-coding a literal, so
//  orgs on slow links or SSL-inspecting proxies can tune the app from
//  the config profile.
//
//  connectionTimeout — quick, interactive calls (auth, commands, search).
//  requestTimeout    — heavy calls (full inventory, detail endpoints,
//                      paginated sweeps) and session-level configuration.
//

import Foundation

enum NetworkTuning {

    /// Timeout for quick, interactive calls. Schema default 30 s.
    static var connectionTimeout: TimeInterval {
        TimeInterval(MDMConfigurationManager.shared.configuration.connectionTimeoutSeconds)
    }

    /// Timeout for heavy or paginated calls. Schema default 60 s.
    static var requestTimeout: TimeInterval {
        TimeInterval(MDMConfigurationManager.shared.configuration.requestTimeoutSeconds)
    }
}
