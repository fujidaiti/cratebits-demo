//
//  CacheController.swift
//  CratebitsDemo
//
//  Created by Claude on 2025/07/20.
//

import Foundation

// MARK: - Cache Controller Events

/// キャッシュコントローラーのイベント
enum CacheControllerEvent: Equatable {
    case cacheHit(appleMusicID: String)
    case cacheMiss(appleMusicID: String)
    case downloadStarted(appleMusicID: String)
    case downloadCompleted(appleMusicID: String)
    case downloadFailed(appleMusicID: String, error: String)
    case cacheEvicted(appleMusicID: String)
}

// MARK: - Cache Controller Protocol

/// キャッシュコントローラーのプロトコル
protocol CacheControllerProtocol {
    /// ListenNowリストが更新された時（NewQueueボタン）
    func updateListenNowItems(_ items: [ListenNowItem]) async
    
    /// フォーカス変更時の処理（Cursor-based）
    func handleFocusChange(to cursor: ListenNowCursor) async
    
    /// カルーセル内移動時の軽量処理
    func handleCarouselFocusChange(to cursor: ListenNowCursor) async
    
    /// キャッシュされたアイテムを取得
    func getCachedItem(for appleMusicID: String) async -> StoredCacheItem?
    
    /// キャッシュ状態をチェック
    func isCached(_ appleMusicID: String) async -> Bool
    
    /// 現在キャッシュされているキー一覧
    var cachedKeys: Set<String> { get async }
}


// MARK: - Cache Controller Implementation

/// キャッシュコントローラー本体
actor CacheController: CacheControllerProtocol {
    
    // MARK: - Dependencies
    
    private let strategy: CacheStrategy
    private let dataSource: CacheDataSource
    let storage: CacheStorage // 外部からアクセス可能に
    
    // MARK: - State
    
    private var currentItems: [ListenNowItem] = []
    private var _currentCursor = ListenNowCursor(pageIndex: 0, trackIndex: 0)
    
    // Return the current cursor - access will be async when called from outside the actor
    var currentCursor: ListenNowCursor {
        return _currentCursor
    }
    private var pendingOperations: Set<String> = []
    
    // MARK: - Events
    
    /// イベント通知用
    private(set) var events: [CacheControllerEvent] = []
    
    // MARK: - Initialization
    
    init(
        strategy: CacheStrategy = CacheStrategy(),
        dataSource: CacheDataSource,
        storage: CacheStorage
    ) {
        self.strategy = strategy
        self.dataSource = dataSource
        self.storage = storage
    }
    
    // MARK: - Public Methods
    
    var cachedKeys: Set<String> {
        get async {
            await storage.storedKeys
        }
    }
    
    func getCachedItem(for appleMusicID: String) async -> StoredCacheItem? {
        let item = await storage.retrieve(for: appleMusicID)
        if item != nil {
            emitEvent(.cacheHit(appleMusicID: appleMusicID))
        } else {
            emitEvent(.cacheMiss(appleMusicID: appleMusicID))
        }
        return item
    }
    
    func isCached(_ appleMusicID: String) async -> Bool {
        return await storage.contains(appleMusicID)
    }
    
    // MARK: - ListenNow API
    
    func updateListenNowItems(_ items: [ListenNowItem]) async {
        print("[CacheController] Updating ListenNow items: \(items.count) items")
        
        self.currentItems = items
        
        // リストが更新された場合、現在のカーソル位置を正規化
        self._currentCursor = _currentCursor.normalized(for: items)
        
        // 新しいリストに対する初期キャッシュ戦略を実行
        let operations = strategy.calculateInitialCacheOperations(
            for: items,
            initialCursor: _currentCursor
        )
        
        print("[CacheController] List update operations: \(operations.count)")
        await executeOperations(operations)
    }
    
    func handleFocusChange(to cursor: ListenNowCursor) async {
        print("[CacheController] Focus changing from \(_currentCursor) to \(cursor)")
        
        let oldCursor = _currentCursor
        let normalizedCursor = cursor.normalized(for: currentItems)
        
        // カーソル位置が実際に変わっていない場合はスキップ
        if oldCursor == normalizedCursor {
            print("[CacheController] No actual cursor change detected, skipping")
            return
        }
        
        self._currentCursor = normalizedCursor
        
        // ページ移動 vs カルーセル移動を判定
        if normalizedCursor.isPageMovement(from: oldCursor) {
            print("[CacheController] Page movement detected")
            await handlePageChange(to: normalizedCursor)
        } else {
            print("[CacheController] Carousel movement detected")
            await handleCarouselChange(to: normalizedCursor)
        }
    }
    
    func handleCarouselFocusChange(to cursor: ListenNowCursor) async {
        print("[CacheController] Carousel focus changing from \(_currentCursor) to \(cursor)")
        
        let normalizedCursor = cursor.normalized(for: currentItems)
        self._currentCursor = normalizedCursor
        
        await handleCarouselChange(to: normalizedCursor)
    }
    
    // MARK: - Private Movement Handlers
    
    private func handlePageChange(to cursor: ListenNowCursor) async {
        let operations = await strategy.calculateCacheOperations(
            for: currentItems,
            cursor: cursor,
            currentlyCached: storage.storedKeys
        )
        
        print("[CacheController] Page change operations: \(operations.count)")
        await executeOperations(operations)
    }
    
    private func handleCarouselChange(to cursor: ListenNowCursor) async {
        guard let currentPage = cursor.getCurrentPage(from: currentItems) else {
            print("[CacheController] Invalid cursor position for carousel change")
            return
        }
        
        let operations = await strategy.calculateCarouselCacheOperations(
            for: currentPage,
            trackIndex: cursor.trackIndex,
            currentlyCached: storage.storedKeys
        )
        
        print("[CacheController] Carousel change operations: \(operations.count)")
        await executeOperations(operations)
    }
    
    // MARK: - Private Methods
    
    private func executeOperations(_ operations: [CacheOperation]) async {
        // Group operations by type
        let loadOperations = operations.compactMap { operation in
            if case .load(let appleMusicID, let priority) = operation {
                return (appleMusicID, priority)
            }
            return nil
        }
        
        let removeOperations = operations.compactMap { operation in
            if case .remove(let appleMusicID) = operation {
                return appleMusicID
            }
            return nil
        }
        
        // Execute remove operations immediately
        for appleMusicID in removeOperations {
            await storage.remove(for: appleMusicID)
            emitEvent(.cacheEvicted(appleMusicID: appleMusicID))
        }
        
        // Execute load operations with priority ordering
        let sortedLoadOperations = loadOperations.sorted { $0.1 < $1.1 }
        
        // Execute immediate priority items synchronously, others concurrently
        let immediatePriorityOps = sortedLoadOperations.filter { $0.1 == .immediate }
        let otherOps = sortedLoadOperations.filter { $0.1 != .immediate }
        
        // Load immediate priority items first
        for (appleMusicID, _) in immediatePriorityOps {
            await loadItem(appleMusicID: appleMusicID)
        }
        
        // Load other items concurrently
        await withTaskGroup(of: Void.self) { group in
            for (appleMusicID, _) in otherOps {
                group.addTask {
                    await self.loadItem(appleMusicID: appleMusicID)
                }
            }
        }
    }
    
    private func loadItem(appleMusicID: String) async {
        print("[CacheController] 🔄 loadItem called for: \(appleMusicID)")
        
        // Skip if already pending or cached
        let isPending = pendingOperations.contains(appleMusicID)
        let isCached = await storage.contains(appleMusicID)
        
        print("[CacheController] 📊 loadItem status - isPending: \(isPending), isCached: \(isCached)")
        
        guard !isPending && !isCached else {
            print("[CacheController] ⏭️ Skipping loadItem for \(appleMusicID) - already pending or cached")
            return
        }
        
        print("[CacheController] 🚀 Starting download for: \(appleMusicID)")
        pendingOperations.insert(appleMusicID)
        emitEvent(.downloadStarted(appleMusicID: appleMusicID))
        
        defer {
            pendingOperations.remove(appleMusicID)
            print("[CacheController] 🧹 Cleaned up pending operation for: \(appleMusicID)")
        }
        
        do {
            print("[CacheController] 📡 Fetching preview for: \(appleMusicID)")
            guard let item = await dataSource.fetchPreview(for: appleMusicID) else {
                print("[CacheController] ❌ No data received for: \(appleMusicID)")
                emitEvent(.downloadFailed(appleMusicID: appleMusicID, error: "No data received"))
                return
            }
            
            print("[CacheController] 💾 Storing item for: \(appleMusicID) - title: \(item.title)")
            try await storage.store(item, for: appleMusicID)
            print("[CacheController] ✅ Successfully stored: \(appleMusicID)")
            emitEvent(.downloadCompleted(appleMusicID: appleMusicID))
            
        } catch {
            print("[CacheController] ❌ Storage error for \(appleMusicID): \(error)")
            emitEvent(.downloadFailed(appleMusicID: appleMusicID, error: error.localizedDescription))
        }
    }
    
    nonisolated private func emitEvent(_ event: CacheControllerEvent) {
        // Note: Since we can't mutate actor state from nonisolated context,
        // we'll just print the event. In a real app, you might use a different event system.
        print("[CacheController] Event: \(event)")
    }
    
    // MARK: - Test Support
    
    /// イベント履歴をクリア（テスト用）
    func clearEvents() {
        events.removeAll()
    }
    
    /// 現在の状態をダンプ（デバッグ用）
    func dumpState() async -> [String: Any] {
        return [
            "currentCursor": _currentCursor.description,
            "currentItemsCount": currentItems.count,
            "cachedKeys": Array(await storage.storedKeys),
            "pendingOperations": Array(pendingOperations),
            "eventsCount": events.count,
            "currentAppleMusicID": _currentCursor.getCurrentAppleMusicID(from: currentItems) ?? "none"
        ]
    }
}