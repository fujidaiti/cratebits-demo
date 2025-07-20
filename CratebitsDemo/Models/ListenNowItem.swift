//
//  ListenNowItem.swift
//  CratebitsDemo
//
//  Created by Claude on 2025/07/20.
//

import Foundation

/// ListenNow画面でのピックアップ楽曲
struct PickedTrack: Identifiable, Codable {
    let id: String
    let appleMusicID: String
    let name: String
    let artist: String
    
    init(appleMusicID: String, name: String, artist: String) {
        self.id = UUID().uuidString
        self.appleMusicID = appleMusicID
        self.name = name
        self.artist = artist
    }
}

/// ListenNow画面専用のアイテム構造
struct ListenNowItem: Identifiable, Codable {
    let id: String
    let type: ItemType
    let name: String
    let artist: String
    let appleMusicID: String?
    let pickedTracks: [PickedTrack] // 必須、常に1つ以上
    
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
    
    /// 指定されたインデックスのピックアップ楽曲を取得
    /// - Parameter index: トラックインデックス
    /// - Returns: ピックアップ楽曲（範囲外の場合は最初の楽曲）
    func getPickedTrack(at index: Int) -> PickedTrack {
        guard !pickedTracks.isEmpty else {
            fatalError("ListenNowItem must have at least one picked track")
        }
        
        if index >= 0 && index < pickedTracks.count {
            return pickedTracks[index]
        } else {
            return pickedTracks[0] // デフォルトは最初の楽曲
        }
    }
    
    /// 現在のトラック数
    var trackCount: Int {
        return pickedTracks.count
    }
}

// MARK: - Factory Methods

extension ListenNowItem {
    
    /// 単一トラック用のListenNowItemを作成
    /// - Parameters:
    ///   - appleMusicID: Apple Music ID
    ///   - name: 楽曲名
    ///   - artist: アーティスト名
    /// - Returns: ListenNowItem
    static func singleTrack(appleMusicID: String, name: String, artist: String) -> ListenNowItem {
        let pickedTrack = PickedTrack(appleMusicID: appleMusicID, name: name, artist: artist)
        
        return ListenNowItem(
            id: UUID().uuidString,
            type: .track,
            name: name,
            artist: artist,
            appleMusicID: appleMusicID,
            pickedTracks: [pickedTrack]
        )
    }
    
    /// アルバム用のListenNowItemを作成
    /// - Parameters:
    ///   - appleMusicID: Apple Music ID
    ///   - name: アルバム名
    ///   - artist: アーティスト名
    ///   - pickedTracks: ピックアップされた楽曲リスト
    /// - Returns: ListenNowItem
    static func album(appleMusicID: String, name: String, artist: String, pickedTracks: [PickedTrack]) -> ListenNowItem {
        precondition(!pickedTracks.isEmpty, "Album must have at least one picked track")
        
        return ListenNowItem(
            id: UUID().uuidString,
            type: .album,
            name: name,
            artist: artist,
            appleMusicID: appleMusicID,
            pickedTracks: pickedTracks
        )
    }
    
    /// アーティスト用のListenNowItemを作成
    /// - Parameters:
    ///   - appleMusicID: Apple Music ID
    ///   - name: アーティスト名
    ///   - pickedTracks: ピックアップされた楽曲リスト
    /// - Returns: ListenNowItem
    static func artist(appleMusicID: String, name: String, pickedTracks: [PickedTrack]) -> ListenNowItem {
        precondition(!pickedTracks.isEmpty, "Artist must have at least one picked track")
        
        return ListenNowItem(
            id: UUID().uuidString,
            type: .artist,
            name: name,
            artist: name,
            appleMusicID: appleMusicID,
            pickedTracks: pickedTracks
        )
    }
}

// MARK: - Conversion from ListenLaterItem

extension ListenNowItem {
    
    /// ListenLaterItemからListenNowItemを作成
    /// - Parameter laterItem: 変換元のListenLaterItem
    /// - Returns: ListenNowItem（ピックアップ楽曲が設定されていない場合はnil）
    static func from(_ laterItem: ListenLaterItem) -> ListenNowItem? {
        switch laterItem.type {
        case .track:
            guard let appleMusicID = laterItem.appleMusicID else { return nil }
            return singleTrack(appleMusicID: appleMusicID, name: laterItem.name, artist: laterItem.artist)
            
        case .album, .artist:
            guard let appleMusicID = laterItem.appleMusicID,
                  let pickedTracksData = laterItem.pickedTracks,
                  !pickedTracksData.isEmpty else { return nil }
            
            let pickedTracks = pickedTracksData.compactMap { track -> PickedTrack? in
                guard let trackAppleMusicID = track.appleMusicID else { return nil }
                return PickedTrack(appleMusicID: trackAppleMusicID, name: track.name, artist: track.artist)
            }
            
            guard !pickedTracks.isEmpty else { return nil }
            
            return ListenNowItem(
                id: laterItem.id,
                type: laterItem.type,
                name: laterItem.name,
                artist: laterItem.artist,
                appleMusicID: appleMusicID,
                pickedTracks: pickedTracks
            )
        }
    }
}