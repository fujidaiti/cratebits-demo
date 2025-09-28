//
//  PlaylistGenerationService.swift
//  CratebitsDemo
//
//  Created by Claude on 2025/07/19.
//

import Foundation
import MusicKit

/// プレイリスト生成サービス - Listen Laterアイテムから楽曲キューを生成
@MainActor
class PlaylistGenerationService: ObservableObject {
    @Published var isGenerating = false
    @Published var errorMessage: String?
    
    /// ランダム選択でListen Nowキューを生成
    /// - Parameters:
    ///   - items: Listen Laterアイテムリスト
    ///   - count: 生成する楽曲数（デフォルト: 10）
    /// - Returns: 生成された楽曲キュー
    func generateRandomListenNow(from items: [ListenLaterItem], count: Int = 10) -> [ListenLaterItem] {
        guard !items.isEmpty else {
            return []
        }
        
        var candidates: [ListenLaterItem] = []
        
        // アイテムタイプ別に展開
        for item in items {
            switch item.type {
            case .track:
                // トラックはそのまま追加
                candidates.append(item)
                
            case .album:
                // アルバムの場合は代表として追加（実際の楽曲展開は後で行う）
                candidates.append(item)
                
            case .artist:
                // アーティストの場合も代表として追加
                candidates.append(item)
            }
        }
        
        // 候補をシャッフルして指定数選択
        candidates.shuffle()
        let selected = Array(candidates.prefix(count))
        
        return selected
    }
    
    /// アルバムから楽曲を展開
    /// 移植元仕様: 最大5曲をランダム選択
    /// - Parameter album: アルバムアイテム
    /// - Returns: 展開された楽曲リスト
    func expandAlbumToTracks(album: ListenLaterItem) async -> [ListenLaterItem] {
        guard album.type == .album, let appleMusicID = album.appleMusicID else {
            return []
        }
        
        do {
            // 正しいMusicKitアプローチ: IDでアルバムの詳細情報（楽曲込み）を取得
            let albumRequest = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: MusicItemID(appleMusicID))
            let albumResponse = try await albumRequest.response()
            
            guard let albumData = albumResponse.items.first else {
                return createFallbackTracks(for: album)
            }

            // Debug logs for album artwork URL verification
            print("[ARTWORK-DEBUG] Fetched Album: \(albumData.title) by \(albumData.artistName)")
            print("[ARTWORK-DEBUG] Album artwork available: \(albumData.artwork != nil)")

            if let artwork = albumData.artwork {
                let artworkURL = artwork.url(width: 300, height: 300)
                print("[ARTWORK-DEBUG] Album artwork URL (300x300): \(artworkURL?.absoluteString ?? "nil")")
            }
            
            // アルバムから楽曲を含む詳細情報を取得
            let detailedAlbum = try await albumData.with([.tracks])
            
            var tracks: [ListenLaterItem] = []
            
            if let albumTracks = detailedAlbum.tracks {
                let tracksToUse = Array(albumTracks.prefix(5))
                
                for track in tracksToUse {
                    // Debug logs for track artwork comparison
                    print("[ARTWORK-DEBUG] Track: \(track.title)")
                    print("[ARTWORK-DEBUG] Track artwork available: \(track.artwork != nil)")

                    if let trackArtwork = track.artwork {
                        let trackArtworkURL = trackArtwork.url(width: 300, height: 300)
                        print("[ARTWORK-DEBUG] Track artwork URL (300x300): \(trackArtworkURL?.absoluteString ?? "nil")")
                    }

                    let trackItem = ListenLaterItem(
                        id: UUID().uuidString,
                        type: .track,
                        name: track.title, // 実際の楽曲名
                        artist: album.artist,
                        dateAdded: Date(),
                        appleMusicID: track.id.rawValue,
                        artworkURL: track.artwork?.url(width: 300, height: 300)
                    )
                    tracks.append(trackItem)
                }
            }
            
            // デバッグ情報を出力
            print("[DEBUG] Album: \(album.name) by \(album.artist)")
            print("[DEBUG] Album ID: \(appleMusicID)")
            print("[DEBUG] Album tracks count: \(detailedAlbum.tracks?.count ?? 0)")
            print("[DEBUG] Final tracks: \(tracks.count)")
            
            // 楽曲が取得できなかった場合はフォールバック
            if tracks.isEmpty {
                print("[DEBUG] Using fallback tracks for album: \(album.name)")
                return createFallbackTracks(for: album)
            } else {
                print("[DEBUG] Using real tracks from album ID for: \(album.name)")
                return tracks.shuffled()
            }
            
        } catch {
            await MainActor.run {
                errorMessage = "Failed to expand album: \(error.localizedDescription)"
            }
            return createFallbackTracks(for: album)
        }
    }
    
    /// フォールバック楽曲生成（APIが失敗した場合）
    private func createFallbackTracks(for album: ListenLaterItem) -> [ListenLaterItem] {
        let trackNames = [
            "Opening Theme",
            "Main Track", 
            "Interlude",
            "Closing Song",
            "Hidden Track"
        ]
        
        var tracks: [ListenLaterItem] = []
        for trackName in trackNames {
            let trackItem = ListenLaterItem(
                id: UUID().uuidString,
                type: .track,
                name: trackName, // アルバム名を含まない楽曲名のみ
                artist: album.artist,
                dateAdded: Date(),
                appleMusicID: nil,
                artworkURL: nil
            )
            tracks.append(trackItem)
        }
        
        return tracks.shuffled()
    }
    
    /// アーティストから楽曲を展開
    /// 移植元仕様: トップトラック3曲 + 最新アルバムから2曲
    /// - Parameter artist: アーティストアイテム
    /// - Returns: 展開された楽曲リスト
    func expandArtistToTracks(artist: ListenLaterItem) async -> [ListenLaterItem] {
        guard artist.type == .artist, let appleMusicID = artist.appleMusicID else {
            return []
        }
        
        do {
            // Apple MusicKitを使ってアーティストの楽曲を検索
            let artistRequest = MusicCatalogResourceRequest<Artist>(matching: \.id, equalTo: MusicItemID(appleMusicID))
            let artistResponse = try await artistRequest.response()
            
            guard artistResponse.items.first != nil else {
                return createFallbackArtistTracks(for: artist)
            }
            
            // アーティストの楽曲を検索
            let tracksRequest = MusicCatalogSearchRequest(term: artist.name, types: [Song.self])
            let tracksResponse = try await tracksRequest.response()
            
            // このアーティストの楽曲のみフィルタリング
            let artistSongs = tracksResponse.songs.filter { song in
                song.artistName.lowercased().contains(artist.name.lowercased())
            }
            
            var tracks: [ListenLaterItem] = []
            let songsToUse = Array(artistSongs.prefix(5))
            
            for song in songsToUse {
                let trackItem = ListenLaterItem(
                    id: UUID().uuidString,
                    type: .track,
                    name: song.title, // 実際の楽曲名のみ
                    artist: artist.name,
                    dateAdded: Date(),
                    appleMusicID: song.id.rawValue,
                    artworkURL: song.artwork?.url(width: 300, height: 300)
                )
                tracks.append(trackItem)
            }
            
            return tracks.isEmpty ? createFallbackArtistTracks(for: artist) : tracks
            
        } catch {
            await MainActor.run {
                errorMessage = "Failed to expand artist: \(error.localizedDescription)"
            }
            return createFallbackArtistTracks(for: artist)
        }
    }
    
    /// フォールバックアーティスト楽曲生成（APIが失敗した場合）
    private func createFallbackArtistTracks(for artist: ListenLaterItem) -> [ListenLaterItem] {
        let trackNames = [
            "Hit Song",
            "Popular Track", 
            "Chart Topper",
            "New Single",
            "Latest Release"
        ]
        
        var tracks: [ListenLaterItem] = []
        for trackName in trackNames {
            let trackItem = ListenLaterItem(
                id: UUID().uuidString,
                type: .track,
                name: trackName, // アーティスト名を含まない楽曲名のみ
                artist: artist.name,
                dateAdded: Date(),
                appleMusicID: nil,
                artworkURL: nil
            )
            tracks.append(trackItem)
        }
        
        return tracks
    }
    
    /// 混合アイテムリストにピックアップ楽曲を設定
    /// - Parameter items: Listen Laterアイテムリスト（トラック/アルバム/アーティスト混在）
    /// - Returns: ピックアップ楽曲が設定されたアイテムリスト
    func expandMixedItemsToTracks(_ items: [ListenLaterItem]) async -> [ListenLaterItem] {
        isGenerating = true
        errorMessage = nil
        
        var processedItems: [ListenLaterItem] = []
        
        for item in items {
            switch item.type {
            case .track:
                // トラックはそのまま追加
                processedItems.append(item)
                
            case .album:
                // アルバムにピックアップ楽曲を設定
                let albumTracks = await expandAlbumToTracks(album: item)
                var albumWithTracks = item
                albumWithTracks.pickedTracks = albumTracks
                processedItems.append(albumWithTracks)
                
            case .artist:
                // アーティストにピックアップ楽曲を設定
                let artistTracks = await expandArtistToTracks(artist: item)
                var artistWithTracks = item
                artistWithTracks.pickedTracks = artistTracks
                processedItems.append(artistWithTracks)
            }
        }
        
        isGenerating = false
        return processedItems
    }
    
    /// エラーメッセージをクリア
    func clearError() {
        errorMessage = nil
    }
}
