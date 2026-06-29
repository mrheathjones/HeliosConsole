//
//  ComputerInventoryCache.swift
//  test
//
//  Created by heath on 1/21/26.
//


//
//  ComputerInventoryCache.swift
//  Helios
//
//  Cache manager for computer inventory data
//  Persists data to disk for session reuse, clears on app launch
//

import Foundation
import Combine

@MainActor
final class ComputerInventoryCache: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = ComputerInventoryCache()
    
    // MARK: - Published Properties
    
    @Published private(set) var computers: [ComputerInventoryItem] = []
    @Published private(set) var totalCount: Int = 0
    @Published private(set) var lastFetchDate: Date?
    @Published private(set) var isCacheValid: Bool = false
    
    // MARK: - Private Properties
    
    private let cacheFileName = "computer_inventory_cache.json"
    private let metadataFileName = "computer_inventory_metadata.json"
    
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
        let fetchDate: Date
        let sessionId: String
    }
    
    // Session ID changes on each app launch
    private static let currentSessionId: String = UUID().uuidString
    
    // MARK: - Initialization
    
    private init() {
        // Load cache on init, but only if it's from current session
        loadCacheIfValid()
    }
    
    // MARK: - Public Methods
    
    /// Check if we have valid cached data for this session
    var hasCachedData: Bool {
        return isCacheValid && !computers.isEmpty
    }
    
    /// Update cache with new data
    func updateCache(computers: [ComputerInventoryItem], totalCount: Int) {
        self.computers = computers
        self.totalCount = totalCount
        self.lastFetchDate = Date()
        self.isCacheValid = true
        
        // Save to disk asynchronously
        Task.detached(priority: .background) {
            await self.saveCacheToDisk()
        }
        
        NSLog("✅ ComputerInventoryCache: Updated cache with %d computers", computers.count)
    }
    
    /// Clear the cache (called on logout or manual refresh)
    func clearCache() {
        computers = []
        totalCount = 0
        lastFetchDate = nil
        isCacheValid = false
        
        // Delete cache files
        try? FileManager.default.removeItem(at: cacheFileURL)
        try? FileManager.default.removeItem(at: metadataFileURL)
        
        NSLog("🗑️ ComputerInventoryCache: Cache cleared")
    }
    
    /// Force refresh - invalidates cache so next load fetches fresh data
    func invalidateCache() {
        isCacheValid = false
        NSLog("⚠️ ComputerInventoryCache: Cache invalidated")
    }
    
    // MARK: - Private Methods
    
    private func loadCacheIfValid() {
        // Check if metadata exists and is from current session
        guard let metadataData = try? Data(contentsOf: metadataFileURL),
              let metadata = try? JSONDecoder().decode(CacheMetadata.self, from: metadataData) else {
            NSLog("📂 ComputerInventoryCache: No valid metadata found")
            isCacheValid = false
            return
        }
        
        // Check if cache is from current session
        guard metadata.sessionId == Self.currentSessionId else {
            NSLog("📂 ComputerInventoryCache: Cache is from previous session, will fetch fresh data")
            // Clear old cache files
            try? FileManager.default.removeItem(at: cacheFileURL)
            try? FileManager.default.removeItem(at: metadataFileURL)
            isCacheValid = false
            return
        }
        
        // Load cached computers
        guard let cacheData = try? Data(contentsOf: cacheFileURL),
              let cachedComputers = try? JSONDecoder().decode([ComputerInventoryItem].self, from: cacheData) else {
            NSLog("📂 ComputerInventoryCache: Failed to load cache data")
            isCacheValid = false
            return
        }
        
        // Cache is valid!
        self.computers = cachedComputers
        self.totalCount = metadata.totalCount
        self.lastFetchDate = metadata.fetchDate
        self.isCacheValid = true
        
        NSLog("✅ ComputerInventoryCache: Loaded %d computers from cache", cachedComputers.count)
    }
    
    private func saveCacheToDisk() async {
        do {
            // Save computers
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            
            let computersData = try encoder.encode(computers)
            try computersData.write(to: cacheFileURL, options: .atomic)
            
            // Save metadata
            let metadata = CacheMetadata(
                totalCount: totalCount,
                fetchDate: lastFetchDate ?? Date(),
                sessionId: Self.currentSessionId
            )
            let metadataData = try encoder.encode(metadata)
            try metadataData.write(to: metadataFileURL, options: .atomic)
            
            NSLog("💾 ComputerInventoryCache: Saved cache to disk (%d computers)", computers.count)
        } catch {
            NSLog("❌ ComputerInventoryCache: Failed to save cache: %@", error.localizedDescription)
        }
    }
}
