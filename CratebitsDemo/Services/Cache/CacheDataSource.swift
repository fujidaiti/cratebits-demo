//
//  CacheDataSource.swift
//  CratebitsDemo
//
//  Created by Claude on 2025/07/20.
//

import Foundation
import MusicKit
import AVFoundation

// MARK: - Cacheable Item

/// キャッシュ可能なアイテム
struct CacheableItem: Equatable {
    let appleMusicID: String
    let previewURL: URL
    let title: String
    let artist: String
    
    static func == (lhs: CacheableItem, rhs: CacheableItem) -> Bool {
        lhs.appleMusicID == rhs.appleMusicID
    }
}

// MARK: - Data Source Protocol

/// データ取得の抽象化
protocol CacheDataSource {
    /// プレビューデータを取得
    /// - Parameter appleMusicID: Apple Music ID
    /// - Returns: キャッシュ可能なアイテム（取得失敗時はnil）
    func fetchPreview(for appleMusicID: String) async -> CacheableItem?
}

// MARK: - MusicKit Implementation

/// MusicKitを使用した本番用データソース
@MainActor
class MusicKitCacheDataSource: CacheDataSource {
    
    func fetchPreview(for appleMusicID: String) async -> CacheableItem? {
        do {
            print("[CacheDataSource] Fetching from MusicKit: \(appleMusicID)")
            
            let request = MusicCatalogResourceRequest<Song>(
                matching: \.id, 
                equalTo: MusicItemID(appleMusicID)
            )
            let response = try await request.response()
            
            guard let song = response.items.first,
                  let previewURL = song.previewAssets?.first?.url else {
                print("[CacheDataSource] No preview URL found for: \(appleMusicID)")
                return nil
            }
            
            let item = CacheableItem(
                appleMusicID: appleMusicID,
                previewURL: previewURL,
                title: song.title,
                artist: song.artistName
            )
            
            print("[CacheDataSource] Successfully fetched: \(item.title) by \(item.artist)")
            return item
            
        } catch {
            print("[CacheDataSource] Failed to fetch \(appleMusicID): \(error)")
            return nil
        }
    }
}

// MARK: - Mock Implementation

/// テスト用モックデータソース
class MockCacheDataSource: CacheDataSource {
    
    /// モックレスポンス設定
    private var mockResponses: [String: CacheableItem] = [:]
    private var simulatedDelays: [String: TimeInterval] = [:]
    private var failureIDs: Set<String> = []
    
    /// 呼び出し履歴
    private(set) var fetchCalls: [String] = []
    
    /// モックレスポンスを設定
    func setMockResponse(for appleMusicID: String, item: CacheableItem) {
        mockResponses[appleMusicID] = item
    }
    
    /// レスポンス遅延を設定
    func setSimulatedDelay(for appleMusicID: String, delay: TimeInterval) {
        simulatedDelays[appleMusicID] = delay
    }
    
    /// 失敗するIDを設定
    func setFailure(for appleMusicID: String) {
        failureIDs.insert(appleMusicID)
    }
    
    /// 呼び出し履歴をクリア
    func clearFetchCalls() {
        fetchCalls.removeAll()
    }
    
    func fetchPreview(for appleMusicID: String) async -> CacheableItem? {
        fetchCalls.append(appleMusicID)
        
        print("[MockCacheDataSource] Fetch request for: \(appleMusicID)")
        
        // 失敗シミュレーション
        if failureIDs.contains(appleMusicID) {
            print("[MockCacheDataSource] Simulated failure for: \(appleMusicID)")
            return nil
        }
        
        // モックレスポンス返却
        if let response = mockResponses[appleMusicID] {
            print("[MockCacheDataSource] Returning mock response: \(response.title)")
            return response
        }
        
        // デフォルトレスポンス
        let defaultItem = CacheableItem(
            appleMusicID: appleMusicID,
            previewURL: URL(string: "https://example.com/preview/\(appleMusicID).m4a")!,
            title: "Mock Song \(appleMusicID)",
            artist: "Mock Artist"
        )
        
        print("[MockCacheDataSource] Returning default mock: \(defaultItem.title)")
        return defaultItem
    }
}

// MARK: - Test Helpers

extension MockCacheDataSource {
    
    /// 複数のテストデータを一括設定
    func setupTestData() {
        // テスト用の楽曲データ
        let testItems = [
            CacheableItem(
                appleMusicID: "1787556305",
                previewURL: URL(string: "https://example.com/preview/matter-of-time.m4a")!,
                title: "Matter of Time",
                artist: "Vulfpeck"
            ),
            CacheableItem(
                appleMusicID: "1787556307",
                previewURL: URL(string: "https://example.com/preview/can-you-tell.m4a")!,
                title: "Can You Tell (feat. Joey Dosik)",
                artist: "Vulfpeck"
            ),
            CacheableItem(
                appleMusicID: "1160119691",
                previewURL: URL(string: "https://example.com/preview/el-chepe.m4a")!,
                title: "El Chepe",
                artist: "Vulfpeck"
            ),
            CacheableItem(
                appleMusicID: "1160119422",
                previewURL: URL(string: "https://example.com/preview/dean-town.m4a")!,
                title: "Dean Town",
                artist: "Vulfpeck"
            )
        ]
        
        for item in testItems {
            setMockResponse(for: item.appleMusicID, item: item)
        }
    }
}