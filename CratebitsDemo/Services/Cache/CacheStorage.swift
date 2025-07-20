//
//  CacheStorage.swift
//  CratebitsDemo
//
//  Created by Claude on 2025/07/20.
//

import Foundation
import AVFoundation

// MARK: - Storage Protocol

/// キャッシュストレージの抽象化
@MainActor
protocol CacheStorage {
    /// アイテムを保存
    /// - Parameters:
    ///   - item: キャッシュするアイテム
    ///   - appleMusicID: 保存キー
    func store(_ item: CacheableItem, for appleMusicID: String) async throws
    
    /// アイテムを取得
    /// - Parameter appleMusicID: 取得キー
    /// - Returns: 保存されたアイテム（なければnil）
    func retrieve(for appleMusicID: String) async -> StoredCacheItem?
    
    /// アイテムを削除
    /// - Parameter appleMusicID: 削除キー
    func remove(for appleMusicID: String) async
    
    /// アイテムが存在するかチェック
    /// - Parameter appleMusicID: チェックキー
    /// - Returns: 存在するかどうか
    func contains(_ appleMusicID: String) async -> Bool
    
    /// 現在保存されているすべてのキー
    var storedKeys: Set<String> { get async }
    
    /// すべてのアイテムを削除
    func clearAll() async
}

// MARK: - Stored Cache Item

/// 保存されたキャッシュアイテム
struct StoredCacheItem {
    let item: CacheableItem
    let storedAt: Date
    var accessCount: Int
    var lastAccessed: Date
    
    /// アイテムが利用可能かどうか（AVPlayerベースの場合）
    var isReady: Bool
    
    init(item: CacheableItem, isReady: Bool = false) {
        self.item = item
        self.storedAt = Date()
        self.accessCount = 0
        self.lastAccessed = Date()
        self.isReady = isReady
    }
    
    /// アクセス記録を更新
    func withAccess() -> StoredCacheItem {
        var updated = self
        updated.lastAccessed = Date()
        updated.accessCount += 1
        return updated
    }
    
    /// 準備完了状態を更新
    func withReadiness(_ ready: Bool) -> StoredCacheItem {
        var updated = self
        updated.isReady = ready
        return updated
    }
}

// MARK: - AVPlayer Implementation

/// AVPlayerベースの本番用ストレージ
@MainActor
class AVPlayerCacheStorage: CacheStorage {
    
    private struct CachedPlayerItem {
        let player: AVPlayer
        let storedItem: StoredCacheItem
    }
    
    private var cache: [String: CachedPlayerItem] = [:]
    private let maxCacheSize: Int
    
    init(maxCacheSize: Int = 10) {
        self.maxCacheSize = maxCacheSize
    }
    
    var storedKeys: Set<String> {
        Set(cache.keys)
    }
    
    func store(_ item: CacheableItem, for appleMusicID: String) async throws {
        print("[AVPlayerStorage] Storing item: \(item.title) (ID: \(appleMusicID))")
        
        // LRU eviction if cache is full
        if cache.count >= maxCacheSize && !cache.keys.contains(appleMusicID) {
            evictLeastRecentlyUsed()
        }
        
        // Create AVPlayer
        let player = AVPlayer(url: item.previewURL)
        let storedItem = StoredCacheItem(item: item, isReady: false)
        
        cache[appleMusicID] = CachedPlayerItem(
            player: player,
            storedItem: storedItem
        )
        
        // Monitor player readiness
        observePlayerReadiness(player: player, appleMusicID: appleMusicID)
        
        print("[AVPlayerStorage] Stored player for: \(item.title)")
    }
    
    func retrieve(for appleMusicID: String) -> StoredCacheItem? {
        guard let cachedItem = cache[appleMusicID] else {
            return nil
        }
        
        // Update access time
        let updatedStoredItem = cachedItem.storedItem.withAccess()
        cache[appleMusicID] = CachedPlayerItem(
            player: cachedItem.player,
            storedItem: updatedStoredItem
        )
        
        print("[AVPlayerStorage] Retrieved item: \(updatedStoredItem.item.title)")
        return updatedStoredItem
    }
    
    func remove(for appleMusicID: String) {
        if let cachedItem = cache.removeValue(forKey: appleMusicID) {
            print("[AVPlayerStorage] Removed item: \(cachedItem.storedItem.item.title)")
        }
    }
    
    func contains(_ appleMusicID: String) -> Bool {
        cache.keys.contains(appleMusicID)
    }
    
    func clearAll() {
        let count = cache.count
        cache.removeAll()
        print("[AVPlayerStorage] Cleared all \(count) cached items")
    }
    
    /// AVPlayerを取得（本番用再生のため）
    func getPlayer(for appleMusicID: String) -> AVPlayer? {
        return cache[appleMusicID]?.player
    }
    
    // MARK: - Private Methods
    
    private func evictLeastRecentlyUsed() {
        let lruKey = cache.min { a, b in
            a.value.storedItem.lastAccessed < b.value.storedItem.lastAccessed
        }?.key
        
        if let keyToRemove = lruKey {
            remove(for: keyToRemove)
            print("[AVPlayerStorage] Evicted LRU item: \(keyToRemove)")
        }
    }
    
    private func observePlayerReadiness(player: AVPlayer, appleMusicID: String) {
        // In a real implementation, observe player status
        // For now, simulate readiness after a delay
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            
            if let cachedItem = cache[appleMusicID] {
                let updatedStoredItem = cachedItem.storedItem.withReadiness(true)
                cache[appleMusicID] = CachedPlayerItem(
                    player: cachedItem.player,
                    storedItem: updatedStoredItem
                )
                print("[AVPlayerStorage] Player ready for: \(updatedStoredItem.item.title)")
            }
        }
    }
}

// MARK: - In-Memory Implementation

/// テスト用インメモリストレージ
class InMemoryCacheStorage: CacheStorage {
    
    private var cache: [String: StoredCacheItem] = [:]
    private let maxCacheSize: Int
    
    /// 操作履歴（テスト検証用）
    private(set) var operationLog: [String] = []
    
    init(maxCacheSize: Int = 10) {
        self.maxCacheSize = maxCacheSize
    }
    
    var storedKeys: Set<String> {
        Set(cache.keys)
    }
    
    func store(_ item: CacheableItem, for appleMusicID: String) async throws {
        let operation = "STORE: \(item.title) (ID: \(appleMusicID))"
        operationLog.append(operation)
        print("[InMemoryStorage] \(operation)")
        
        // LRU eviction if cache is full
        if cache.count >= maxCacheSize && !cache.keys.contains(appleMusicID) {
            evictLeastRecentlyUsed()
        }
        
        let storedItem = StoredCacheItem(item: item, isReady: true) // Always ready in mock
        cache[appleMusicID] = storedItem
    }
    
    func retrieve(for appleMusicID: String) -> StoredCacheItem? {
        guard let storedItem = cache[appleMusicID] else {
            let operation = "RETRIEVE_MISS: \(appleMusicID)"
            operationLog.append(operation)
            print("[InMemoryStorage] \(operation)")
            return nil
        }
        
        // Update access time
        let updatedItem = storedItem.withAccess()
        cache[appleMusicID] = updatedItem
        
        let operation = "RETRIEVE_HIT: \(storedItem.item.title) (ID: \(appleMusicID))"
        operationLog.append(operation)
        print("[InMemoryStorage] \(operation)")
        
        return updatedItem
    }
    
    func remove(for appleMusicID: String) {
        if let removedItem = cache.removeValue(forKey: appleMusicID) {
            let operation = "REMOVE: \(removedItem.item.title) (ID: \(appleMusicID))"
            operationLog.append(operation)
            print("[InMemoryStorage] \(operation)")
        }
    }
    
    func contains(_ appleMusicID: String) -> Bool {
        cache.keys.contains(appleMusicID)
    }
    
    func clearAll() {
        let count = cache.count
        cache.removeAll()
        let operation = "CLEAR_ALL: \(count) items"
        operationLog.append(operation)
        print("[InMemoryStorage] \(operation)")
    }
    
    /// 操作ログをクリア（テスト用）
    func clearOperationLog() {
        operationLog.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func evictLeastRecentlyUsed() {
        let lruKey = cache.min { a, b in
            a.value.lastAccessed < b.value.lastAccessed
        }?.key
        
        if let keyToRemove = lruKey {
            remove(for: keyToRemove)
        }
    }
}

// MARK: - Test Helpers

extension InMemoryCacheStorage {
    
    /// キャッシュ状態をダンプ（デバッグ用）
    func dumpCacheState() -> [String: String] {
        return cache.mapValues { storedItem in
            "\(storedItem.item.title) (ready: \(storedItem.isReady), accessed: \(storedItem.accessCount))"
        }
    }
    
    /// 特定の操作が実行されたかチェック
    func didPerformOperation(containing text: String) -> Bool {
        operationLog.contains { $0.contains(text) }
    }
}