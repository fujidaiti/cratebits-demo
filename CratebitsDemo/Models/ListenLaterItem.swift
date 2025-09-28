//
//  ListenLaterItem.swift
//  CratebitsDemo
//
//  Created by Claude on 2025/07/16.
//

import Foundation
import MusicKit

/// Listen Laterアイテムの種類
enum ItemType: String, CaseIterable, Codable {
    case track = "track"
    case album = "album"
    case artist = "artist"
    
    var displayName: String {
        switch self {
        case .track: return "Track"
        case .album: return "Album"
        case .artist: return "Artist"
        }
    }
}

/// Listen Laterに保存されるアイテム
struct ListenLaterItem: Identifiable, Codable {
    let id: String
    let type: ItemType
    let name: String
    let artist: String
    let dateAdded: Date
    let appleMusicID: String?
    let artworkURL: URL? // アートワーク画像URL
    var pickedTracks: [ListenLaterItem]? // アルバム/アーティストの場合のピックアップ楽曲
    
    /// 表示用のテキスト
    var displayText: String {
        switch type {
        case .track:
            return "\(name) - \(artist)"
        case .album:
            return "\(name) (\(artist))"
        case .artist:
            return artist
        }
    }
    
    /// トラック用のイニシャライザ
    static func track(name: String, artist: String, appleMusicID: String? = nil, artworkURL: URL? = nil) -> ListenLaterItem {
        return ListenLaterItem(
            id: UUID().uuidString,
            type: .track,
            name: name,
            artist: artist,
            dateAdded: Date(),
            appleMusicID: appleMusicID,
            artworkURL: artworkURL,
            pickedTracks: nil
        )
    }
    
    /// アルバム用のイニシャライザ
    static func album(name: String, artist: String, appleMusicID: String? = nil, artworkURL: URL? = nil) -> ListenLaterItem {
        return ListenLaterItem(
            id: UUID().uuidString,
            type: .album,
            name: name,
            artist: artist,
            dateAdded: Date(),
            appleMusicID: appleMusicID,
            artworkURL: artworkURL,
            pickedTracks: nil
        )
    }
    
    /// アーティスト用のイニシャライザ
    static func artist(name: String, appleMusicID: String? = nil, artworkURL: URL? = nil) -> ListenLaterItem {
        return ListenLaterItem(
            id: UUID().uuidString,
            type: .artist,
            name: name,
            artist: name,
            dateAdded: Date(),
            appleMusicID: appleMusicID,
            artworkURL: artworkURL,
            pickedTracks: nil
        )
    }
}

/// MusicKitのTrackからListenLaterItemを作成するための拡張
extension ListenLaterItem {
    init(from track: Track) {
        self.id = UUID().uuidString
        self.type = .track
        self.name = track.title
        self.artist = track.artistName
        self.dateAdded = Date()
        self.appleMusicID = track.id.rawValue
        self.artworkURL = track.artwork?.url(width: 300, height: 300)
        self.pickedTracks = nil
    }
    
    init(from song: Song) {
        self.id = UUID().uuidString
        self.type = .track
        self.name = song.title
        self.artist = song.artistName
        self.dateAdded = Date()
        self.appleMusicID = song.id.rawValue
        self.artworkURL = song.artwork?.url(width: 300, height: 300)
        self.pickedTracks = nil
    }
    
    init(from album: Album) {
        // Debug logs for album initializer artwork URL verification
        print("[ARTWORK-DEBUG] Creating ListenLaterItem from Album: \(album.title) by \(album.artistName)")
        print("[ARTWORK-DEBUG] Album ID: \(album.id.rawValue)")
        print("[ARTWORK-DEBUG] Artwork property available: \(album.artwork != nil)")

        var finalArtworkURL: URL?
        if let artwork = album.artwork {
            finalArtworkURL = artwork.url(width: 300, height: 300)
            print("[ARTWORK-DEBUG] Generated artwork URL (300x300): \(finalArtworkURL?.absoluteString ?? "nil")")

            // Test other sizes for verification
            let smallURL = artwork.url(width: 100, height: 100)
            let largeURL = artwork.url(width: 600, height: 600)
            print("[ARTWORK-DEBUG] Small artwork URL (100x100): \(smallURL?.absoluteString ?? "nil")")
            print("[ARTWORK-DEBUG] Large artwork URL (600x600): \(largeURL?.absoluteString ?? "nil")")
        } else {
            print("[ARTWORK-DEBUG] No artwork available for album")
        }

        self.id = UUID().uuidString
        self.type = .album
        self.name = album.title
        self.artist = album.artistName
        self.dateAdded = Date()
        self.appleMusicID = album.id.rawValue
        self.artworkURL = album.artwork?.url(width: 300, height: 300)
        self.pickedTracks = nil
    }
    
    init(from artist: Artist) {
        self.id = UUID().uuidString
        self.type = .artist
        self.name = artist.name
        self.artist = artist.name
        self.dateAdded = Date()
        self.appleMusicID = artist.id.rawValue
        self.artworkURL = artist.artwork?.url(width: 300, height: 300)
        self.pickedTracks = nil
    }
}
