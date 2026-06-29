//
//  MDMConfiguration.swift
//  test
//
//  Created by heath on 1/19/26.
//


import Foundation

struct MDMConfiguration: Codable {
    let jamfURL: String
    let masterClientID: String
    let masterClientSecret: String
    let appTitle: String
    let appSubtitle: String
    let sidebarItems: [SidebarItemConfig]
    let requiredRoleName: String
    let supportURL: String?
    let localAdminUsername: String
    
    // Screen Share feature (enabled via Config Profile)
    // NOTE: The extension attribute name "EA_VPN_IP_ADDRESS" is currently hardcoded.
    // A future enhancement will make this configurable via Config Profile.
    let screenShareEnabled: Bool
    
    // Apple Business Manager API (optional)
    let abmClientId: String?
    let abmKeyId: String?
    let abmPrivateKey: String?
    
    var isABMConfigured: Bool {
        guard let clientId = abmClientId, !clientId.isEmpty,
              let keyId = abmKeyId, !keyId.isEmpty,
              let privateKey = abmPrivateKey, !privateKey.isEmpty else {
            return false
        }
        return true
    }
    
    struct SidebarItemConfig: Codable, Identifiable {
        let id: String
        let icon: String
        let title: String
        let isEnabled: Bool
        let order: Int
        
        init(id: String, icon: String, title: String, isEnabled: Bool = true, order: Int) {
            self.id = id
            self.icon = icon
            self.title = title
            self.isEnabled = isEnabled
            self.order = order
        }
    }
    
    // Default configuration (fallback if no MDM profile)
    static let `default` = MDMConfiguration(
        jamfURL: "https://myorg.jamfcloud.com",
        masterClientID: "your-master-client-id",
        masterClientSecret: "your-master-client-secret",
        appTitle: "Helios",
        appSubtitle: "Console",
        sidebarItems: [
            SidebarItemConfig(id: "dashboard", icon: "chart.bar.fill", title: "Dashboard", order: 1),
            SidebarItemConfig(id: "enterprise", icon: "building.2.fill", title: "Enterprise", order: 2),
            SidebarItemConfig(id: "groundcontrol", icon: "apps.iphone", title: "GroundControl", order: 3),
            SidebarItemConfig(id: "depsearch", icon: "magnifyingglass", title: "DEP Search", order: 4),
            SidebarItemConfig(id: "announcements", icon: "bolt.fill", title: "Announcements", order: 5),
            SidebarItemConfig(id: "settings", icon: "gearshape.fill", title: "Settings", order: 6)
        ],
        requiredRoleName: "SVC_WATCHER_USER",
        supportURL: "https://support.yourcompany.com",
        localAdminUsername: "macadmin",
        screenShareEnabled: false,
        abmClientId: nil,
        abmKeyId: nil,
        abmPrivateKey: nil
    )
}
