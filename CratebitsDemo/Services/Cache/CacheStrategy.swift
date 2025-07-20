//
//  CacheStrategy.swift
//  CratebitsDemo
//
//  Created by Claude on 2025/07/20.
//

import Foundation

// MARK: - Cache Operations

/// キャッシュ操作の種類
enum CacheOperation: Equatable {
    case load(appleMusicID: String, priority: CachePriority)
    case remove(appleMusicID: String)
}

/// キャッシュ優先度
enum CachePriority: Int, Comparable {
    case immediate = 0    // 即座に必要（現在フォーカス中）
    case adjacent = 1     // 隣接アイテム（すぐに必要になる可能性高）
    case prefetch = 2     // 予測的キャッシュ（将来的に必要になる可能性）
    
    static func < (lhs: CachePriority, rhs: CachePriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Cache Strategy

/// キャッシュ戦略アルゴリズム（純粋関数）
struct CacheStrategy {
    
    /// 最大キャッシュ数
    private let maxCacheSize: Int
    
    init(maxCacheSize: Int = 10) {
        self.maxCacheSize = maxCacheSize
    }
    
    
    
}

// MARK: - ListenNow Extensions

extension CacheStrategy {
    
    /// Cursor-based フォーカス変更時のキャッシュ操作を計算
    /// - Parameters:
    ///   - items: 全ListenNowアイテム
    ///   - cursor: 現在のフォーカス位置
    ///   - currentlyCached: 現在キャッシュ済みのAppleMusicIDセット
    /// - Returns: 実行すべきキャッシュ操作のリスト
    func calculateCacheOperations(
        for items: [ListenNowItem],
        cursor: ListenNowCursor,
        currentlyCached: Set<String>
    ) -> [CacheOperation] {
        
        let normalizedCursor = cursor.normalized(for: items)
        guard normalizedCursor.isValid(for: items) else {
            return []
        }
        
        // 必要なAppleMusicIDを優先度付きで収集
        let requiredIDs = gatherRequiredIDs(for: items, cursor: normalizedCursor)
        
        // 現在必要なIDのセット
        let requiredIDSet = Set(requiredIDs.keys)
        
        var operations: [CacheOperation] = []
        
        // 1. 不要になったアイテムを削除
        let toRemove = currentlyCached.subtracting(requiredIDSet)
        operations += toRemove.map { .remove(appleMusicID: $0) }
        
        // 2. 新たにキャッシュが必要なアイテムを追加
        let toAdd = requiredIDSet.subtracting(currentlyCached)
        let sortedToAdd = toAdd.compactMap { id in
            requiredIDs[id].map { (id, $0) }
        }.sorted { $0.1 < $1.1 }
        
        // キャッシュサイズ制限を考慮
        let remainingSlots = maxCacheSize - (currentlyCached.count - toRemove.count)
        let addOperations = sortedToAdd.prefix(remainingSlots).map { 
            CacheOperation.load(appleMusicID: $0.0, priority: $0.1) 
        }
        operations += addOperations
        
        return operations
    }
    
    /// カルーセル内移動用の軽量キャッシュ戦略
    /// - Parameters:
    ///   - item: 現在のページアイテム
    ///   - trackIndex: 移動先のトラックインデックス
    ///   - currentlyCached: 現在キャッシュ済みのAppleMusicIDセット
    /// - Returns: 実行すべきキャッシュ操作のリスト
    func calculateCarouselCacheOperations(
        for item: ListenNowItem,
        trackIndex: Int,
        currentlyCached: Set<String>
    ) -> [CacheOperation] {
        
        var requiredIDs: [String: CachePriority] = [:]
        
        // 現在のトラック（最高優先度）
        let currentTrack = item.getPickedTrack(at: trackIndex)
        requiredIDs[currentTrack.appleMusicID] = .immediate
        
        // 隣接トラック（adjacent優先度）
        let adjacentIndices = [trackIndex - 1, trackIndex + 1]
        for adjacentIndex in adjacentIndices {
            if adjacentIndex >= 0 && adjacentIndex < item.trackCount {
                let adjacentTrack = item.getPickedTrack(at: adjacentIndex)
                requiredIDs[adjacentTrack.appleMusicID] = .adjacent
            }
        }
        
        // 新たにキャッシュが必要なアイテムのみを追加
        let requiredIDSet = Set(requiredIDs.keys)
        let toAdd = requiredIDSet.subtracting(currentlyCached)
        
        let operations = toAdd.compactMap { id in
            requiredIDs[id].map { CacheOperation.load(appleMusicID: id, priority: $0) }
        }.sorted { 
            if case .load(_, let priority1) = $0,
               case .load(_, let priority2) = $1 {
                return priority1 < priority2
            }
            return false
        }
        
        return operations
    }
    
    /// Cursor-based 初期キャッシュ操作を計算
    /// - Parameters:
    ///   - items: 全ListenNowアイテム
    ///   - initialCursor: 初期フォーカス位置
    /// - Returns: 初期ロード用のキャッシュ操作リスト
    func calculateInitialCacheOperations(
        for items: [ListenNowItem],
        initialCursor: ListenNowCursor = ListenNowCursor(pageIndex: 0, trackIndex: 0)
    ) -> [CacheOperation] {
        
        let normalizedCursor = initialCursor.normalized(for: items)
        guard normalizedCursor.isValid(for: items) else {
            return []
        }
        
        let requiredIDs = gatherRequiredIDs(for: items, cursor: normalizedCursor)
        
        let sortedOperations = requiredIDs.sorted { $0.value < $1.value }
            .prefix(maxCacheSize)
            .map { CacheOperation.load(appleMusicID: $0.key, priority: $0.value) }
        
        return Array(sortedOperations)
    }
    
    // MARK: - Private Methods (ListenNow)
    
    /// Cursor位置に基づいて必要なAppleMusicIDを優先度付きで収集
    private func gatherRequiredIDs(
        for items: [ListenNowItem],
        cursor: ListenNowCursor
    ) -> [String: CachePriority] {
        
        var requiredIDs: [String: CachePriority] = [:]
        
        guard cursor.pageIndex >= 0 && cursor.pageIndex < items.count else {
            return requiredIDs
        }
        
        let currentItem = items[cursor.pageIndex]
        
        // 1. 現在フォーカス中の楽曲（最高優先度）
        let currentTrack = currentItem.getPickedTrack(at: cursor.trackIndex)
        requiredIDs[currentTrack.appleMusicID] = .immediate
        
        // 2. 現在のページ内の隣接楽曲（adjacent優先度）
        addAdjacentTracksInPage(currentItem, focusTrackIndex: cursor.trackIndex, to: &requiredIDs)
        
        // 3. 隣接ページの楽曲（prefetch優先度）
        addAdjacentPageTracks(items: items, focusPageIndex: cursor.pageIndex, to: &requiredIDs)
        
        return requiredIDs
    }
    
    /// ページ内の隣接楽曲を追加
    private func addAdjacentTracksInPage(
        _ item: ListenNowItem,
        focusTrackIndex: Int,
        to dict: inout [String: CachePriority]
    ) {
        // カルーセル内の前後の楽曲
        let adjacentIndices = [focusTrackIndex - 1, focusTrackIndex + 1]
        for adjacentIndex in adjacentIndices {
            if adjacentIndex >= 0 && adjacentIndex < item.trackCount {
                let adjacentTrack = item.getPickedTrack(at: adjacentIndex)
                if dict[adjacentTrack.appleMusicID] == nil {
                    dict[adjacentTrack.appleMusicID] = .adjacent
                }
            }
        }
    }
    
    /// 隣接ページの楽曲を追加
    private func addAdjacentPageTracks(
        items: [ListenNowItem],
        focusPageIndex: Int,
        to dict: inout [String: CachePriority]
    ) {
        // 次のページのみ予測キャッシュ（仕様に従い前ページはキャッシュしない）
        if focusPageIndex + 1 < items.count {
            let nextItem = items[focusPageIndex + 1]
            addPredictiveTracksFromPage(nextItem, to: &dict)
        }
    }
    
    /// ページから予測的楽曲を追加
    private func addPredictiveTracksFromPage(
        _ item: ListenNowItem,
        to dict: inout [String: CachePriority]
    ) {
        // 仕様に従い最初の1曲のみを予測キャッシュ
        if item.trackCount > 0 {
            let track = item.getPickedTrack(at: 0)
            if dict[track.appleMusicID] == nil {
                dict[track.appleMusicID] = .prefetch
            }
        }
    }
}