//
//  PreviewCacheManager.swift
//  CratebitsDemo
//
//  Created by Claude on 2025/07/19.
//

import Foundation
import AVFoundation
import MusicKit

/// プレビュー音源の事前キャッシュ管理
@MainActor
class PreviewCacheManager: NSObject, ObservableObject {
    
    // MARK: - Properties
    
    /// キャッシュされたプレビュープレイヤー
    private var cachedPlayers: [String: CachedPreviewItem] = [:]
    
    /// プリロード用キュー
    private let preloadQueue = DispatchQueue(label: "preview.preload", qos: .background)
    
    /// 最大キャッシュ数（メモリ制限）
    private let maxCacheSize = 10
    
    /// キャッシュ使用順序（LRU管理用）
    private var accessOrder: [String] = []
    
    // MARK: - Cached Item Structure
    
    private struct CachedPreviewItem {
        let player: AVPlayer
        let url: URL
        let itemId: String
        let title: String
        var lastAccessed: Date
        var isReady: Bool
        
        init(player: AVPlayer, url: URL, itemId: String, title: String) {
            self.player = player
            self.url = url
            self.itemId = itemId
            self.title = title
            self.lastAccessed = Date()
            self.isReady = false
        }
    }
    
    // MARK: - Public Methods
    
    /// 効率的な隣接ページキャッシュ（現在+次ページのみ）
    /// - Parameters:
    ///   - items: 全アイテムリスト
    ///   - currentIndex: 現在のインデックス
    func preloadAdjacent(for items: [ListenLaterItem], currentIndex: Int) {
        guard currentIndex >= 0 && currentIndex < items.count else { return }
        
        print("[Cache Info] 🎯 Smart cache strategy: page \(currentIndex) + \(currentIndex + 1) (total items: \(items.count))")
        
        // 現在のページをフルキャッシュ
        let currentItem = items[currentIndex]
        preloadItemWithStrategy(currentItem, isCurrentPage: true)
        
        // 次のページをプリロードキャッシュ
        if currentIndex + 1 < items.count {
            let nextItem = items[currentIndex + 1]
            preloadItemWithStrategy(nextItem, isCurrentPage: false)
        }
        
        // 前ページと離れたページのキャッシュを削除
        cleanupDistantCache(for: items, currentIndex: currentIndex)
    }
    
    /// 指定アイテム周辺のプレビューを事前キャッシュ（レガシー方式）
    /// - Parameters:
    ///   - items: 全アイテムリスト
    ///   - currentIndex: 現在のインデックス
    ///   - range: キャッシュする範囲（前後何曲）
    func preloadPreviews(for items: [ListenLaterItem], around currentIndex: Int, range: Int = 3) {
        let startIndex = max(0, currentIndex - range)
        let endIndex = min(items.count - 1, currentIndex + range)
        
        print("[Cache Debug] Preloading previews for range: \(startIndex)-\(endIndex), current: \(currentIndex)")
        
        for index in startIndex...endIndex {
            let item = items[index]
            preloadPreview(for: item)
            
            // アルバム/アーティストの場合、pickedTracksもキャッシュ
            if let pickedTracks = item.pickedTracks {
                preloadPickedTracks(pickedTracks)
            }
        }
        
        // 範囲外のキャッシュを削除
        cleanupOutOfRangeCache(for: items, currentIndex: currentIndex, range: range)
    }
    
    /// キャッシュされたプレイヤーを取得
    /// - Parameter itemId: アイテムID
    /// - Returns: キャッシュされたプレイヤー、なければnil
    func getCachedPlayer(for itemId: String) -> AVPlayer? {
        guard var cachedItem = cachedPlayers[itemId] else {
            print("[Cache Debug] No cached player for item: \(itemId)")
            return nil
        }
        
        // アクセス時刻を更新
        cachedItem.lastAccessed = Date()
        cachedPlayers[itemId] = cachedItem
        
        // LRU順序を更新
        updateAccessOrder(for: itemId)
        
        print("[Cache Debug] Retrieved cached player for item: \(itemId), ready: \(cachedItem.isReady)")
        return cachedItem.player
    }
    
    /// 指定アイテムがキャッシュ済みかチェック
    /// - Parameter itemId: アイテムID
    /// - Returns: キャッシュ済みかつ準備完了かどうか
    func isCached(itemId: String) -> Bool {
        guard let cachedItem = cachedPlayers[itemId] else { return false }
        return cachedItem.isReady
    }
    
    /// ピックアップ楽曲群を一括キャッシュ
    /// - Parameter pickedTracks: ピックアップ楽曲リスト
    func preloadPickedTracks(_ pickedTracks: [ListenLaterItem]) {
        print("[Cache Debug] Preloading \(pickedTracks.count) picked tracks")
        
        for track in pickedTracks {
            preloadPreview(for: track)
        }
    }
    
    /// カルーセル周辺の楽曲を優先キャッシュ
    /// - Parameters:
    ///   - tracks: カルーセルの楽曲リスト
    ///   - currentIndex: 現在のインデックス
    ///   - range: キャッシュする範囲（前後何曲）
    func cacheCarouselTracks(_ tracks: [ListenLaterItem], around currentIndex: Int, range: Int = 2) {
        let startIndex = max(0, currentIndex - range)
        let endIndex = min(tracks.count - 1, currentIndex + range)
        
        print("[Cache Debug] Caching carousel tracks around index \(currentIndex), range: \(startIndex)-\(endIndex)")
        
        for index in startIndex...endIndex {
            preloadPreview(for: tracks[index])
        }
    }
    
    /// 全キャッシュをクリア
    func clearCache() {
        print("[Cache Info] 🧹 CACHE clear: clearing all (\(cachedPlayers.count) items)")
        
        for (itemId, item) in cachedPlayers {
            print("[Cache Info] 🗑️ CACHE deleted (clear): \(item.title) (ID: \(itemId))")
            item.player.pause()
            // オブザーバーを削除
            removePlayerObservers(item.player)
        }
        
        cachedPlayers.removeAll()
        accessOrder.removeAll()
    }
    
    /// キャッシュ状態をデバッグ出力
    func debugCacheStatus() {
        print("[Cache Debug] Current cache status:")
        print("[Cache Debug] Cached items: \(cachedPlayers.count)/\(maxCacheSize)")
        for (itemId, item) in cachedPlayers {
            print("[Cache Debug] - \(itemId): \(item.title) (ready: \(item.isReady))")
        }
    }
    
    // MARK: - Private Methods
    
    /// 指定アイテムのプレビューを非同期でプリロード
    private func preloadPreview(for item: ListenLaterItem) {
        let itemId = item.id
        
        // 既にキャッシュ済みの場合はスキップ（重複防止強化）
        if cachedPlayers[itemId] != nil {
            print("[Cache Info] 🔄 Already cached, skipping: \(item.name) (ID: \(itemId))")
            return
        }
        
        // トラック以外またはApple Music IDがない場合はスキップ
        guard item.type == .track, let appleMusicID = item.appleMusicID else {
            print("[Cache Info] ⏭️ Skipping non-track or no Apple Music ID: \(item.name) (type: \(item.type))")
            return
        }
        
        print("[Cache Info] 🚀 PRE-LOAD started: \(item.name) (ID: \(itemId))")
        
        // バックグラウンドでプレビューURL取得とプリロード
        Task {
            // 非同期処理中に既にキャッシュされた場合はスキップ
            if await MainActor.run(body: { cachedPlayers[itemId] != nil }) {
                print("[Cache Debug] Item cached during async processing, skipping: \(item.name)")
                return
            }
            
            do {
                let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(appleMusicID))
                let response = try await request.response()
                
                guard let song = response.items.first,
                      let previewAssets = song.previewAssets,
                      !previewAssets.isEmpty,
                      let previewURL = previewAssets.first?.url else {
                    print("[Cache Debug] No preview URL for item: \(item.name)")
                    return
                }
                
                await createCachedPlayer(url: previewURL, itemId: itemId, title: item.name)
                
            } catch {
                print("[Cache Error] Failed to preload preview for \(item.name): \(error)")
                
                // 429エラー（API制限）の場合は少し待ってからリトライ
                if let decodingError = error as? DecodingError,
                   case .dataCorrupted(_) = decodingError {
                    print("[Cache Debug] Possible API limit error for \(item.name), will retry later")
                    // 一時的なAPI制限エラーとして扱い、ログのみ出力
                }
            }
        }
    }
    
    /// キャッシュ用プレイヤーを作成
    private func createCachedPlayer(url: URL, itemId: String, title: String) async {
        print("[Cache Info] 💾 CACHE created: \(title) (ID: \(itemId))")
        
        // メインスレッドでプレイヤーを作成
        let player = AVPlayer(url: url)
        let cachedItem = CachedPreviewItem(player: player, url: url, itemId: itemId, title: title)
        
        // プレイヤーの状態を監視
        addPlayerObservers(player, itemId: itemId)
        
        // キャッシュに追加
        cachedPlayers[itemId] = cachedItem
        updateAccessOrder(for: itemId)
        
        // キャッシュサイズ制限をチェック
        enforceCacheLimit()
        
        // プレイヤーが準備完了になるまで待機
        await waitForPlayerReady(player: player, itemId: itemId)
    }
    
    /// プレイヤーの準備完了を待機
    private func waitForPlayerReady(player: AVPlayer, itemId: String) async {
        return await withCheckedContinuation { continuation in
            var observer: NSKeyValueObservation?
            
            observer = player.observe(\.status, options: [.new]) { [weak self] player, _ in
                Task { @MainActor [weak self] in
                    if player.status == .readyToPlay {
                        let title = self?.cachedPlayers[itemId]?.title ?? "Unknown"
                        print("[Cache Info] ✅ CACHE ready: \(title) (ID: \(itemId))")
                        
                        if var cachedItem = self?.cachedPlayers[itemId] {
                            cachedItem.isReady = true
                            self?.cachedPlayers[itemId] = cachedItem
                        }
                        
                        observer?.invalidate()
                        continuation.resume()
                    } else if player.status == .failed {
                        print("[Cache Error] Player failed for item: \(itemId)")
                        observer?.invalidate()
                        continuation.resume()
                    }
                }
            }
        }
    }
    
    /// プレイヤーオブザーバーを追加
    private func addPlayerObservers(_ player: AVPlayer, itemId: String) {
        // 状態変更の監視は waitForPlayerReady で行うため最小限に
        // エラー監視のみここで行う
    }
    
    /// プレイヤーオブザーバーを削除
    private func removePlayerObservers(_ player: AVPlayer) {
        // エラー監視を削除
    }
    
    /// LRU順序を更新
    private func updateAccessOrder(for itemId: String) {
        accessOrder.removeAll { $0 == itemId }
        accessOrder.append(itemId)
    }
    
    /// キャッシュサイズ制限を適用
    private func enforceCacheLimit() {
        while cachedPlayers.count > maxCacheSize {
            guard let oldestItemId = accessOrder.first else { break }
            
            let oldestTitle = cachedPlayers[oldestItemId]?.title ?? "Unknown"
            print("[Cache Info] 🗑️ CACHE deleted (LRU): \(oldestTitle) (ID: \(oldestItemId))")
            
            if let oldestItem = cachedPlayers[oldestItemId] {
                oldestItem.player.pause()
                removePlayerObservers(oldestItem.player)
            }
            
            cachedPlayers.removeValue(forKey: oldestItemId)
            accessOrder.removeFirst()
        }
    }
    
    /// 戦略的アイテムキャッシュ（表示状態に応じた楽曲数制御）
    private func preloadItemWithStrategy(_ item: ListenLaterItem, isCurrentPage: Bool) {
        switch item.type {
        case .track:
            // 楽曲は常に1曲
            preloadPreview(for: item)
            
        case .album, .artist:
            // アルバム/アーティストはピックアップ楽曲の先頭N曲
            guard let pickedTracks = item.pickedTracks, !pickedTracks.isEmpty else { return }
            
            let cacheCount = isCurrentPage ? min(3, pickedTracks.count) : min(2, pickedTracks.count)
            let tracksToCache = Array(pickedTracks.prefix(cacheCount))
            
            print("[Cache Info] 📋 Strategy: \(item.type.displayName) '\(item.name)' → \(cacheCount) tracks (current page: \(isCurrentPage))")
            
            for track in tracksToCache {
                preloadPreview(for: track)
            }
        }
    }
    
    /// 離れたページのキャッシュを削除（現在+次ページ以外）
    private func cleanupDistantCache(for items: [ListenLaterItem], currentIndex: Int) {
        // 現在ページと次ページの有効アイテムIDを収集
        var validItemIds = Set<String>()
        
        // 現在ページ
        if currentIndex >= 0 && currentIndex < items.count {
            let currentItem = items[currentIndex]
            validItemIds.insert(currentItem.id)
            
            // アルバム/アーティストの場合、ピックアップ楽曲も含める
            if let pickedTracks = currentItem.pickedTracks {
                let currentPageTracks = Array(pickedTracks.prefix(3))
                validItemIds.formUnion(currentPageTracks.map { $0.id })
            }
        }
        
        // 次ページ
        if currentIndex + 1 < items.count {
            let nextItem = items[currentIndex + 1]
            validItemIds.insert(nextItem.id)
            
            // アルバム/アーティストの場合、ピックアップ楽曲も含める
            if let pickedTracks = nextItem.pickedTracks {
                let nextPageTracks = Array(pickedTracks.prefix(2))
                validItemIds.formUnion(nextPageTracks.map { $0.id })
            }
        }
        
        // 有効範囲外のキャッシュを削除
        let itemsToRemove = cachedPlayers.keys.filter { !validItemIds.contains($0) }
        
        for itemId in itemsToRemove {
            let itemTitle = cachedPlayers[itemId]?.title ?? "Unknown"
            print("[Cache Info] 🗑️ CACHE deleted (distant): \(itemTitle) (ID: \(itemId))")
            
            if let item = cachedPlayers[itemId] {
                item.player.pause()
                removePlayerObservers(item.player)
            }
            
            cachedPlayers.removeValue(forKey: itemId)
            accessOrder.removeAll { $0 == itemId }
        }
    }
    
    /// 範囲外キャッシュを削除（レガシー方式）
    private func cleanupOutOfRangeCache(for items: [ListenLaterItem], currentIndex: Int, range: Int) {
        let validRange = max(0, currentIndex - range)...min(items.count - 1, currentIndex + range)
        let validItemIds = Set(validRange.map { items[$0].id })
        
        let itemsToRemove = cachedPlayers.keys.filter { !validItemIds.contains($0) }
        
        for itemId in itemsToRemove {
            let itemTitle = cachedPlayers[itemId]?.title ?? "Unknown"
            print("[Cache Info] 🗑️ CACHE deleted (out-of-range): \(itemTitle) (ID: \(itemId))")
            
            if let item = cachedPlayers[itemId] {
                item.player.pause()
                removePlayerObservers(item.player)
            }
            
            cachedPlayers.removeValue(forKey: itemId)
            accessOrder.removeAll { $0 == itemId }
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        // clearCacheは同期的に呼び出し、警告を回避
        for (_, item) in cachedPlayers {
            item.player.pause()
        }
        cachedPlayers.removeAll()
        accessOrder.removeAll()
    }
}