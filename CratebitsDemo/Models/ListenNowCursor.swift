//
//  ListenNowCursor.swift
//  CratebitsDemo
//
//  Created by Claude on 2025/07/20.
//

import Foundation

/// ListenNow画面での2次元フォーカス位置を表現
struct ListenNowCursor: Equatable, Codable {
    /// 縦方向の位置（ページインデックス）
    let pageIndex: Int
    
    /// 横方向の位置（カルーセル内のトラックインデックス）
    let trackIndex: Int
    
    init(pageIndex: Int, trackIndex: Int = 0) {
        self.pageIndex = pageIndex
        self.trackIndex = trackIndex
    }
    
    /// 現在の楽曲のApple Music IDを取得
    /// - Parameter items: ListenNowアイテムリスト
    /// - Returns: 現在フォーカス中の楽曲のApple Music ID
    func getCurrentAppleMusicID(from items: [ListenNowItem]) -> String? {
        guard pageIndex >= 0 && pageIndex < items.count else { return nil }
        
        let currentItem = items[pageIndex]
        let pickedTrack = currentItem.getPickedTrack(at: trackIndex)
        return pickedTrack.appleMusicID
    }
    
    /// 現在の楽曲情報を取得
    /// - Parameter items: ListenNowアイテムリスト
    /// - Returns: 現在フォーカス中の楽曲情報
    func getCurrentTrack(from items: [ListenNowItem]) -> PickedTrack? {
        guard pageIndex >= 0 && pageIndex < items.count else { return nil }
        
        let currentItem = items[pageIndex]
        return currentItem.getPickedTrack(at: trackIndex)
    }
    
    /// 現在のページアイテムを取得
    /// - Parameter items: ListenNowアイテムリスト
    /// - Returns: 現在フォーカス中のページアイテム
    func getCurrentPage(from items: [ListenNowItem]) -> ListenNowItem? {
        guard pageIndex >= 0 && pageIndex < items.count else { return nil }
        return items[pageIndex]
    }
    
    /// ページ移動かカルーセル移動かを判定
    /// - Parameter other: 比較対象のカーソル
    /// - Returns: ページ移動の場合true、カルーセル移動の場合false
    func isPageMovement(from other: ListenNowCursor) -> Bool {
        return pageIndex != other.pageIndex
    }
    
    /// カルーセル移動かどうかを判定
    /// - Parameter other: 比較対象のカーソル
    /// - Returns: カルーセル移動の場合true
    func isCarouselMovement(from other: ListenNowCursor) -> Bool {
        return pageIndex == other.pageIndex && trackIndex != other.trackIndex
    }
    
    /// 有効なカーソル位置かどうかを検証
    /// - Parameter items: ListenNowアイテムリスト
    /// - Returns: 有効な位置の場合true
    func isValid(for items: [ListenNowItem]) -> Bool {
        guard pageIndex >= 0 && pageIndex < items.count else { return false }
        
        let currentItem = items[pageIndex]
        return trackIndex >= 0 && trackIndex < currentItem.trackCount
    }
    
    /// カーソル位置を正規化（範囲外の場合は有効な範囲に調整）
    /// - Parameter items: ListenNowアイテムリスト
    /// - Returns: 正規化されたカーソル
    func normalized(for items: [ListenNowItem]) -> ListenNowCursor {
        guard !items.isEmpty else { return ListenNowCursor(pageIndex: 0, trackIndex: 0) }
        
        let validPageIndex = max(0, min(pageIndex, items.count - 1))
        let currentItem = items[validPageIndex]
        let validTrackIndex = max(0, min(trackIndex, currentItem.trackCount - 1))
        
        return ListenNowCursor(pageIndex: validPageIndex, trackIndex: validTrackIndex)
    }
}

// MARK: - Navigation Helpers

extension ListenNowCursor {
    
    /// 次のページに移動
    /// - Parameter items: ListenNowアイテムリスト
    /// - Returns: 次のページのカーソル（最後のページの場合はそのまま）
    func nextPage(in items: [ListenNowItem]) -> ListenNowCursor {
        let newPageIndex = min(pageIndex + 1, items.count - 1)
        return ListenNowCursor(pageIndex: newPageIndex, trackIndex: 0)
    }
    
    /// 前のページに移動
    /// - Parameter items: ListenNowアイテムリスト
    /// - Returns: 前のページのカーソル（最初のページの場合はそのまま）
    func previousPage(in items: [ListenNowItem]) -> ListenNowCursor {
        let newPageIndex = max(pageIndex - 1, 0)
        return ListenNowCursor(pageIndex: newPageIndex, trackIndex: 0)
    }
    
    /// カルーセル内で次のトラックに移動
    /// - Parameter items: ListenNowアイテムリスト
    /// - Returns: 次のトラックのカーソル（最後のトラックの場合はそのまま）
    func nextTrack(in items: [ListenNowItem]) -> ListenNowCursor {
        guard pageIndex >= 0 && pageIndex < items.count else { return self }
        
        let currentItem = items[pageIndex]
        let newTrackIndex = min(trackIndex + 1, currentItem.trackCount - 1)
        return ListenNowCursor(pageIndex: pageIndex, trackIndex: newTrackIndex)
    }
    
    /// カルーセル内で前のトラックに移動
    /// - Parameter items: ListenNowアイテムリスト
    /// - Returns: 前のトラックのカーソル（最初のトラックの場合はそのまま）
    func previousTrack(in items: [ListenNowItem]) -> ListenNowCursor {
        let newTrackIndex = max(trackIndex - 1, 0)
        return ListenNowCursor(pageIndex: pageIndex, trackIndex: newTrackIndex)
    }
    
    /// 指定されたページの最初のトラックに移動
    /// - Parameter pageIndex: 移動先のページインデックス
    /// - Returns: 指定ページの最初のトラックのカーソル
    func toPage(_ pageIndex: Int) -> ListenNowCursor {
        return ListenNowCursor(pageIndex: pageIndex, trackIndex: 0)
    }
    
    /// 現在のページ内の指定されたトラックに移動
    /// - Parameter trackIndex: 移動先のトラックインデックス
    /// - Returns: 指定トラックのカーソル
    func toTrack(_ trackIndex: Int) -> ListenNowCursor {
        return ListenNowCursor(pageIndex: pageIndex, trackIndex: trackIndex)
    }
}

// MARK: - Debug Description

extension ListenNowCursor: CustomStringConvertible {
    var description: String {
        return "Cursor(page: \(pageIndex), track: \(trackIndex))"
    }
}