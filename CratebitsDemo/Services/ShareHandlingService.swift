//
//  ShareHandlingService.swift
//  CratebitsDemo
//
//  Created by Claude on 2025/07/16.
//

import Foundation
import MusicKit

/// 共有機能を処理するサービス
class ShareHandlingService {
    
    /// Apple Music URLを解析してListenLaterItemを作成
    static func parseAppleMusicURL(_ url: URL) async -> ListenLaterItem? {
        // Apple Music URLのパターン例:
        // https://music.apple.com/jp/album/album-name/id123456789
        // https://music.apple.com/jp/song/song-name/id123456789
        // https://music.apple.com/jp/artist/artist-name/id123456789
        
        let urlString = url.absoluteString
        
        // URLからIDを抽出
        guard let id = extractAppleMusicID(from: urlString) else {
            return nil
        }
        
        // URLのタイプを判定
        if urlString.contains("/song/") {
            return await createTrackItem(appleMusicID: id, url: url)
        } else if urlString.contains("/album/") {
            return await createAlbumItem(appleMusicID: id, url: url)
        } else if urlString.contains("/artist/") {
            return await createArtistItem(appleMusicID: id, url: url)
        }
        
        return nil
    }
    
    /// Apple Music URLからIDを抽出
    private static func extractAppleMusicID(from urlString: String) -> String? {
        // URLの最後の数字部分（Apple Music ID）を抽出
        let components = urlString.components(separatedBy: "/")
        for component in components.reversed() {
            if component.hasPrefix("id"), component.count > 2 {
                return String(component.dropFirst(2)) // "id"を除去
            }
        }
        
        // パターンが見つからない場合、数字のみの部分を探す
        for component in components.reversed() {
            if component.allSatisfy({ $0.isNumber }) && !component.isEmpty {
                return component
            }
        }
        
        return nil
    }
    
    /// トラックアイテムを作成
    private static func createTrackItem(appleMusicID: String, url: URL) async -> ListenLaterItem? {
        do {
            let musicItemID = MusicItemID(appleMusicID)
            let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: musicItemID)
            let response = try await request.response()
            
            if let song = response.items.first {
                return ListenLaterItem.track(
                    name: song.title,
                    artist: song.artistName,
                    appleMusicID: appleMusicID
                )
            }
        } catch {
            print("トラック取得エラー: \(error)")
        }
        
        // MusicKitでの取得に失敗した場合、URLから名前を推測
        return createFallbackTrackItem(from: url, appleMusicID: appleMusicID)
    }
    
    /// アルバムアイテムを作成
    private static func createAlbumItem(appleMusicID: String, url: URL) async -> ListenLaterItem? {
        do {
            let musicItemID = MusicItemID(appleMusicID)
            let request = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: musicItemID)
            let response = try await request.response()
            
            if let album = response.items.first {
                return ListenLaterItem.album(
                    name: album.title,
                    artist: album.artistName,
                    appleMusicID: appleMusicID
                )
            }
        } catch {
            print("アルバム取得エラー: \(error)")
        }
        
        // MusicKitでの取得に失敗した場合、URLから名前を推測
        return createFallbackAlbumItem(from: url, appleMusicID: appleMusicID)
    }
    
    /// アーティストアイテムを作成
    private static func createArtistItem(appleMusicID: String, url: URL) async -> ListenLaterItem? {
        do {
            let musicItemID = MusicItemID(appleMusicID)
            let request = MusicCatalogResourceRequest<Artist>(matching: \.id, equalTo: musicItemID)
            let response = try await request.response()
            
            if let artist = response.items.first {
                return ListenLaterItem.artist(
                    name: artist.name,
                    appleMusicID: appleMusicID
                )
            }
        } catch {
            print("アーティスト取得エラー: \(error)")
        }
        
        // MusicKitでの取得に失敗した場合、URLから名前を推測
        return createFallbackArtistItem(from: url, appleMusicID: appleMusicID)
    }
    
    /// フォールバック用トラックアイテム
    private static func createFallbackTrackItem(from url: URL, appleMusicID: String) -> ListenLaterItem? {
        let components = url.pathComponents
        guard let songIndex = components.firstIndex(of: "song"),
              songIndex + 1 < components.count else {
            return nil
        }
        
        let name = components[songIndex + 1]
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
        
        return ListenLaterItem.track(
            name: name,
            artist: "Unknown Artist",
            appleMusicID: appleMusicID
        )
    }
    
    /// フォールバック用アルバムアイテム
    private static func createFallbackAlbumItem(from url: URL, appleMusicID: String) -> ListenLaterItem? {
        let components = url.pathComponents
        guard let albumIndex = components.firstIndex(of: "album"),
              albumIndex + 1 < components.count else {
            return nil
        }
        
        let name = components[albumIndex + 1]
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
        
        return ListenLaterItem.album(
            name: name,
            artist: "Unknown Artist",
            appleMusicID: appleMusicID
        )
    }
    
    /// フォールバック用アーティストアイテム
    private static func createFallbackArtistItem(from url: URL, appleMusicID: String) -> ListenLaterItem? {
        let components = url.pathComponents
        guard let artistIndex = components.firstIndex(of: "artist"),
              artistIndex + 1 < components.count else {
            return nil
        }
        
        let name = components[artistIndex + 1]
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
        
        return ListenLaterItem.artist(
            name: name,
            appleMusicID: appleMusicID
        )
    }
    
    /// App Groupを使用してメインアプリとデータを共有
    static func saveSharedItem(_ item: ListenLaterItem) {
        let userDefaults = UserDefaults(suiteName: "group.cratebits.shared") ?? UserDefaults.standard
        
        // 既存のアイテムを取得
        var items: [ListenLaterItem] = []
        if let data = userDefaults.data(forKey: "shared_listen_later_items"),
           let decoded = try? JSONDecoder().decode([ListenLaterItem].self, from: data) {
            items = decoded
        }
        
        // 重複チェック
        if !items.contains(where: { $0.appleMusicID == item.appleMusicID && $0.type == item.type }) {
            items.append(item)
            
            // 保存
            if let encoded = try? JSONEncoder().encode(items) {
                userDefaults.set(encoded, forKey: "shared_listen_later_items")
            }
        }
    }
    
    /// 共有されたアイテムを取得
    static func getSharedItems() -> [ListenLaterItem] {
        let userDefaults = UserDefaults(suiteName: "group.cratebits.shared") ?? UserDefaults.standard
        
        if let data = userDefaults.data(forKey: "shared_listen_later_items"),
           let items = try? JSONDecoder().decode([ListenLaterItem].self, from: data) {
            return items
        }
        
        return []
    }
    
    /// 共有されたアイテムをクリア
    static func clearSharedItems() {
        let userDefaults = UserDefaults(suiteName: "group.cratebits.shared") ?? UserDefaults.standard
        userDefaults.removeObject(forKey: "shared_listen_later_items")
    }
}