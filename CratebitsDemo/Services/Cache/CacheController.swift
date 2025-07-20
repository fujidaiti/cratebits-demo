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
@MainActor
protocol CacheControllerProtocol {
    /// ListenNowリストが更新された時（NewQueueボタン）
    func updateListenNowItems(_ items: [ListenNowItem]) async
    
    /// フォーカス変更時の処理（Cursor-based）
    func handleFocusChange(to cursor: ListenNowCursor) async
    
    /// カルーセル内移動時の軽量処理
    func handleCarouselFocusChange(to cursor: ListenNowCursor) async
    
    /// キャッシュされたアイテムを取得
    func getCachedItem(for appleMusicID: String) -> StoredCacheItem?
    
    /// キャッシュ状態をチェック
    func isCached(_ appleMusicID: String) -> Bool
    
    /// 現在キャッシュされているキー一覧
    var cachedKeys: Set<String> { get }
    
    /// 現在のフォーカス位置
    var currentCursor: ListenNowCursor { get }
}

// MARK: - Legacy Protocol Support

/// 既存コードとの互換性のための拡張
extension CacheControllerProtocol {
    
    /// 従来のListenLaterItem-based初期化（非推奨）
    @available(*, deprecated, message: "Use updateListenNowItems(_:) instead")
    func initializeCache(
        items: [ListenLaterItem],
        initialFocusIndex: Int
    ) async {
        let listenNowItems = items.compactMap { ListenNowItem.from($0) }
        await updateListenNowItems(listenNowItems)
        
        let cursor = ListenNowCursor(pageIndex: initialFocusIndex, trackIndex: 0)
        await handleFocusChange(to: cursor)
    }
    
    /// 従来のindex-basedフォーカス変更（非推奨）
    @available(*, deprecated, message: "Use handleFocusChange(to:) with ListenNowCursor instead")
    func handleFocusChange(
        items: [ListenLaterItem],
        newFocusIndex: Int
    ) async {
        let cursor = ListenNowCursor(pageIndex: newFocusIndex, trackIndex: 0)
        await handleFocusChange(to: cursor)
    }
}

// MARK: - Cache Controller Implementation

/// キャッシュコントローラー本体
@MainActor
class CacheController: CacheControllerProtocol, ObservableObject {
    
    // MARK: - Dependencies
    
    private let strategy: CacheStrategy
    private let dataSource: CacheDataSource
    private let storage: CacheStorage
    
    // MARK: - State
    
    private var currentItems: [ListenNowItem] = []
    private(set) var currentCursor = ListenNowCursor(pageIndex: 0, trackIndex: 0)
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
        storage.storedKeys
    }
    
    func getCachedItem(for appleMusicID: String) -> StoredCacheItem? {
        let item = storage.retrieve(for: appleMusicID)
        if item != nil {
            emitEvent(.cacheHit(appleMusicID: appleMusicID))
        } else {
            emitEvent(.cacheMiss(appleMusicID: appleMusicID))
        }
        return item
    }
    
    func isCached(_ appleMusicID: String) -> Bool {
        return storage.contains(appleMusicID)
    }
    
    // MARK: - ListenNow API
    
    func updateListenNowItems(_ items: [ListenNowItem]) async {
        print("[CacheController] Updating ListenNow items: \(items.count) items")
        
        self.currentItems = items
        
        // リストが更新された場合、現在のカーソル位置を正規化
        self.currentCursor = currentCursor.normalized(for: items)
        
        // 新しいリストに対する初期キャッシュ戦略を実行
        let operations = strategy.calculateInitialCacheOperations(
            for: items,
            initialCursor: currentCursor
        )
        
        print("[CacheController] List update operations: \(operations.count)")
        await executeOperations(operations)
    }
    
    func handleFocusChange(to cursor: ListenNowCursor) async {
        print("[CacheController] Focus changing from \(currentCursor) to \(cursor)")
        
        let oldCursor = currentCursor
        let normalizedCursor = cursor.normalized(for: currentItems)
        
        // カーソル位置が実際に変わっていない場合はスキップ
        if oldCursor == normalizedCursor {
            print("[CacheController] No actual cursor change detected, skipping")
            return
        }
        
        self.currentCursor = normalizedCursor
        
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
        print("[CacheController] Carousel focus changing from \(currentCursor) to \(cursor)")
        
        let normalizedCursor = cursor.normalized(for: currentItems)
        self.currentCursor = normalizedCursor
        
        await handleCarouselChange(to: normalizedCursor)
    }
    
    // MARK: - Private Movement Handlers
    
    private func handlePageChange(to cursor: ListenNowCursor) async {
        let operations = strategy.calculateCacheOperations(
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
        
        let operations = strategy.calculateCarouselCacheOperations(
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
            storage.remove(for: appleMusicID)
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
        // Skip if already pending or cached
        guard !pendingOperations.contains(appleMusicID) &&
              !storage.contains(appleMusicID) else {
            return
        }
        
        pendingOperations.insert(appleMusicID)
        emitEvent(.downloadStarted(appleMusicID: appleMusicID))
        
        defer {
            pendingOperations.remove(appleMusicID)
        }
        
        do {
            guard let item = await dataSource.fetchPreview(for: appleMusicID) else {
                emitEvent(.downloadFailed(appleMusicID: appleMusicID, error: "No data received"))
                return
            }
            
            try await storage.store(item, for: appleMusicID)
            emitEvent(.downloadCompleted(appleMusicID: appleMusicID))
            
        } catch {
            emitEvent(.downloadFailed(appleMusicID: appleMusicID, error: error.localizedDescription))
        }
    }
    
    private func emitEvent(_ event: CacheControllerEvent) {
        events.append(event)
        print("[CacheController] Event: \(event)")
    }
    
    // MARK: - Test Support
    
    /// イベント履歴をクリア（テスト用）
    func clearEvents() {
        events.removeAll()
    }
    
    /// 現在の状態をダンプ（デバッグ用）
    func dumpState() -> [String: Any] {
        return [
            "currentCursor": currentCursor.description,
            "currentItemsCount": currentItems.count,
            "cachedKeys": Array(storage.storedKeys),
            "pendingOperations": Array(pendingOperations),
            "eventsCount": events.count,
            "currentAppleMusicID": currentCursor.getCurrentAppleMusicID(from: currentItems) ?? "none"
        ]
    }
}