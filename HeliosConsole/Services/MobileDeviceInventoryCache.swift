//
//  MobileDeviceInventoryCache.swift
//  test
//
//  Created by heath on 1/21/26.
//


//
//  MobileDeviceInventoryCache.swift
//  Helios
//
//  Cache manager for mobile device inventory data (iOS, iPadOS, visionOS)
//  Persists data to disk for session reuse, clears on app launch
//

import Foundation
import Combine

final class MobileDeviceInventoryCache: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = MobileDeviceInventoryCache()
    
    // MARK: - Published Properties
    
    @Published private(set) var devices: [MobileDeviceInventoryItem] = []
    @Published private(set) var totalCount: Int = 0
    @Published private(set) var lastFetchDate: Date?
    @Published private(set) var isCacheValid: Bool = false
    
    // Platform counts
    @Published private(set) var iOSCount: Int = 0
    @Published private(set) var iPadOSCount: Int = 0
    @Published private(set) var visionOSCount: Int = 0
    
    // MARK: - Private Properties
    
    private let cacheFileName = "mobile_device_inventory_cache.json"
    private let metadataFileName = "mobile_device_inventory_metadata.json"
    
    private var cacheFileURL: URL {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let appCacheDir = cacheDir.appendingPathComponent("Helios", isDirectory: true)
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: appCacheDir, withIntermediateDirectories: true)
        
        return appCacheDir.appendingPathComponent(cacheFileName)
    }
    
    private var metadataFileURL: URL {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let appCacheDir = cacheDir.appendingPathComponent("Helios", isDirectory: true)
        return appCacheDir.appendingPathComponent(metadataFileName)
    }
    
    // MARK: - Cache Metadata
    
    private struct CacheMetadata: Codable {
        let totalCount: Int
        let iOSCount: Int
        let iPadOSCount: Int
        let visionOSCount: Int
        let fetchDate: Date
        let sessionId: String
    }
    
    // Session ID changes on each app launch - shared with computer inventory
    private static var currentSessionId: String {
        // Use the same session ID mechanism as ComputerInventoryCache
        // This is set once per app launch
        struct SessionHolder {
            static let id = UUID().uuidString
        }
        return SessionHolder.id
    }
    
    // MARK: - Initialization
    
    private init() {
        // Load cache on init, but only if it's from current session
        loadCacheIfValid()
    }
    
    // MARK: - Public Methods
    
    /// Check if we have valid cached data for this session
    var hasCachedData: Bool {
        return isCacheValid && !devices.isEmpty
    }
    
    /// Update cache with new data
    func updateCache(devices: [MobileDeviceInventoryItem], totalCount: Int) {
        self.devices = devices
        self.totalCount = totalCount
        self.lastFetchDate = Date()
        self.isCacheValid = true
        
        // Update platform counts
        updatePlatformCounts()
        
        // Save to disk asynchronously
        Task.detached(priority: .background) {
            await self.saveCacheToDisk()
        }
        
        NSLog("✅ MobileDeviceInventoryCache: Updated cache with %d devices (iOS: %d, iPadOS: %d, visionOS: %d)", 
              devices.count, iOSCount, iPadOSCount, visionOSCount)
    }
    
    /// Clear the cache (called on logout or manual refresh)
    func clearCache() {
        devices = []
        totalCount = 0
        iOSCount = 0
        iPadOSCount = 0
        visionOSCount = 0
        lastFetchDate = nil
        isCacheValid = false
        
        // Delete cache files
        try? FileManager.default.removeItem(at: cacheFileURL)
        try? FileManager.default.removeItem(at: metadataFileURL)
        
        NSLog("🗑️ MobileDeviceInventoryCache: Cache cleared")
    }
    
    /// Force refresh - invalidates cache so next load fetches fresh data
    func invalidateCache() {
        isCacheValid = false
        NSLog("⚠️ MobileDeviceInventoryCache: Cache invalidated")
    }
    
    /// Get devices for a specific platform
    func devices(for platform: PlatformType) -> [MobileDeviceInventoryItem] {
        switch platform {
        case .iOS:
            return devices.filter { $0.platformType == .iOS }
        case .iPadOS:
            return devices.filter { $0.platformType == .iPadOS }
        case .visionOS:
            return devices.filter { $0.platformType == .visionOS }
        default:
            return devices
        }
    }
    
    // MARK: - Private Methods
    
    private func updatePlatformCounts() {
        iOSCount = devices.filter { $0.platformType == .iOS }.count
        iPadOSCount = devices.filter { $0.platformType == .iPadOS }.count
        visionOSCount = devices.filter { $0.platformType == .visionOS }.count
    }
    
    private func loadCacheIfValid() {
        // Check if metadata exists and is from current session
        guard let metadataData = try? Data(contentsOf: metadataFileURL),
              let metadata = try? JSONDecoder().decode(CacheMetadata.self, from: metadataData) else {
            NSLog("📂 MobileDeviceInventoryCache: No valid metadata found")
            isCacheValid = false
            return
        }
        
        // Check if cache is from current session
        guard metadata.sessionId == Self.currentSessionId else {
            NSLog("📂 MobileDeviceInventoryCache: Cache is from previous session, will fetch fresh data")
            // Clear old cache files
            try? FileManager.default.removeItem(at: cacheFileURL)
            try? FileManager.default.removeItem(at: metadataFileURL)
            isCacheValid = false
            return
        }
        
        // Load cached devices
        guard let cacheData = try? Data(contentsOf: cacheFileURL),
              let cachedDevices = try? JSONDecoder().decode([MobileDeviceInventoryItem].self, from: cacheData) else {
            NSLog("📂 MobileDeviceInventoryCache: Failed to load cache data")
            isCacheValid = false
            return
        }
        
        // Cache is valid!
        self.devices = cachedDevices
        self.totalCount = metadata.totalCount
        self.iOSCount = metadata.iOSCount
        self.iPadOSCount = metadata.iPadOSCount
        self.visionOSCount = metadata.visionOSCount
        self.lastFetchDate = metadata.fetchDate
        self.isCacheValid = true
        
        NSLog("✅ MobileDeviceInventoryCache: Loaded %d devices from cache (iOS: %d, iPadOS: %d, visionOS: %d)", 
              cachedDevices.count, iOSCount, iPadOSCount, visionOSCount)
    }
    
    private func saveCacheToDisk() async {
        do {
            // Save devices
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            
            let devicesData = try encoder.encode(devices)
            try devicesData.write(to: cacheFileURL, options: .atomic)
            
            // Save metadata
            let metadata = CacheMetadata(
                totalCount: totalCount,
                iOSCount: iOSCount,
                iPadOSCount: iPadOSCount,
                visionOSCount: visionOSCount,
                fetchDate: lastFetchDate ?? Date(),
                sessionId: Self.currentSessionId
            )
            let metadataData = try encoder.encode(metadata)
            try metadataData.write(to: metadataFileURL, options: .atomic)
            
            NSLog("💾 MobileDeviceInventoryCache: Saved cache to disk (%d devices)", devices.count)
        } catch {
            NSLog("❌ MobileDeviceInventoryCache: Failed to save cache: %@", error.localizedDescription)
        }
    }
}
