//
//  AppleMusicLibraryService.swift
//  CratebitsDemo
//
//  Created by Claude on 2025/07/19.
//

import Foundation
import MusicKit

/// Apple Music ライブラリ操作サービス
@MainActor
class AppleMusicLibraryService: ObservableObject {
    
    /// アイテムをApple Musicライブラリに追加
    /// - Parameter item: 追加するListenLaterItem
    /// - Returns: 成功した場合true、失敗した場合false
    func addToLibrary(_ item: ListenLaterItem) async -> Bool {
        guard let appleMusicID = item.appleMusicID else {
            print("[Library] No Apple Music ID for item: \(item.name)")
            return false
        }
        
        // MusicKit認証状態を確認
        let status = await MusicAuthorization.request()
        guard status == .authorized else {
            print("[Library] Music authorization denied")
            return false
        }
        
        // アイテムタイプに応じてライブラリに追加
        switch item.type {
        case .track:
            return await addSongToLibrary(appleMusicID: appleMusicID, title: item.name)
            
        case .album:
            return await addAlbumToLibrary(appleMusicID: appleMusicID, title: item.name)
            
        case .artist:
            // アーティストは直接ライブラリに追加できないため、
            // pickedTracksがある場合はそれらを追加
            if let pickedTracks = item.pickedTracks {
                return await addPickedTracksToLibrary(pickedTracks)
            } else {
                print("[Library] Cannot add artist without picked tracks: \(item.name)")
                return false
            }
        }
    }
    
    /// 楽曲をライブラリに追加
    private func addSongToLibrary(appleMusicID: String, title: String) async -> Bool {
        #if os(iOS)
        do {
            let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(appleMusicID))
            let response = try await request.response()
            
            guard let song = response.items.first else {
                print("[Library] Song not found for ID: \(appleMusicID)")
                return false
            }
            
            // ライブラリに追加
            try await MusicLibrary.shared.add(song)
            print("[Library] Successfully added song to library: \(title)")
            return true
            
        } catch {
            print("[Library] Failed to add song to library: \(error)")
            return false
        }
        #else
        print("[Library] Adding to library is not supported on macOS")
        return false
        #endif
    }
    
    /// アルバムをライブラリに追加
    private func addAlbumToLibrary(appleMusicID: String, title: String) async -> Bool {
        #if os(iOS)
        do {
            let request = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: MusicItemID(appleMusicID))
            let response = try await request.response()
            
            guard let album = response.items.first else {
                print("[Library] Album not found for ID: \(appleMusicID)")
                return false
            }

            // Debug logs for album artwork URL verification
            print("[ARTWORK-DEBUG] Album: \(album.title) by \(album.artistName)")
            print("[ARTWORK-DEBUG] Album ID: \(album.id.rawValue)")
            print("[ARTWORK-DEBUG] Artwork available: \(album.artwork != nil)")

            if let artwork = album.artwork {
                // Test different artwork sizes
                let sizes = [(100, 100), (300, 300), (600, 600)]
                for (width, height) in sizes {
                    let artworkURL = artwork.url(width: width, height: height)
                    print("[ARTWORK-DEBUG] Artwork URL (\(width)x\(height)): \(artworkURL?.absoluteString ?? "nil")")
                }
            } else {
                print("[ARTWORK-DEBUG] No artwork property available for album")
            }
            
            // ライブラリに追加
            try await MusicLibrary.shared.add(album)
            print("[Library] Successfully added album to library: \(title)")
            return true
            
        } catch {
            print("[Library] Failed to add album to library: \(error)")
            return false
        }
        #else
        print("[Library] Adding to library is not supported on macOS")
        return false
        #endif
    }
    
    /// ピックアップ楽曲群をライブラリに追加
    private func addPickedTracksToLibrary(_ pickedTracks: [ListenLaterItem]) async -> Bool {
        var successCount = 0
        
        for track in pickedTracks {
            if await addToLibrary(track) {
                successCount += 1
            }
        }
        
        let allSuccessful = successCount == pickedTracks.count
        print("[Library] Added \(successCount)/\(pickedTracks.count) picked tracks to library")
        return allSuccessful
    }
    
    
    /// アイテムがライブラリに存在するかチェック
    /// - Parameter item: チェックするListenLaterItem
    /// - Returns: ライブラリに存在する場合true、存在しない場合false
    func isInLibrary(_ item: ListenLaterItem) async -> Bool {
        #if os(iOS)
        guard let appleMusicID = item.appleMusicID else {
            return false
        }
        
        do {
            let status = await MusicAuthorization.request()
            guard status == .authorized else {
                return false
            }
            
            switch item.type {
            case .track:
                let libraryRequest = MusicLibraryRequest<Song>()
                let libraryResponse = try await libraryRequest.response()
                return libraryResponse.items.contains { $0.id.rawValue == appleMusicID }
                
            case .album:
                let libraryRequest = MusicLibraryRequest<Album>()
                let libraryResponse = try await libraryRequest.response()
                return libraryResponse.items.contains { $0.id.rawValue == appleMusicID }
                
            case .artist:
                return false // アーティストはライブラリチェック不可
            }
        } catch {
            print("[Library] Error checking library status: \(error)")
            return false
        }
        #else
        print("[Library] Library checking is not supported on macOS")
        return false
        #endif
    }
}