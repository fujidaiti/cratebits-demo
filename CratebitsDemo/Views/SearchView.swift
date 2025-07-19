//
//  SearchView.swift
//  CratebitsDemo
//
//  Created by Claude on 2025/07/19.
//

import SwiftUI
import MusicKit

/// Apple Music検索機能のメインビュー
struct SearchView: View {
    @EnvironmentObject var storage: UserDefaultsStorage
    @State private var searchText = ""
    @State private var searchResults: MusicItemCollection<Song> = []
    @State private var albumSearchResults: MusicItemCollection<Album> = []
    @State private var artistSearchResults: MusicItemCollection<Artist> = []
    @State private var selectedSegment = 0
    @State private var isSearching = false
    
    private let segments = ["Tracks", "Albums", "Artists"]
    
    var body: some View {
        NavigationView {
            VStack {
                // 検索機能
                searchSection
                
                // セグメント選択
                if hasSearchResults {
                    segmentPicker
                }
                
                // 検索結果
                searchResultsList
            }
            .navigationTitle("Search")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
        }
    }
    
    /// 検索セクション
    private var searchSection: some View {
        HStack {
            TextField("Search Apple Music", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    searchMusic()
                }
            
            Button(action: searchMusic) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.blue)
            }
            .disabled(searchText.isEmpty || isSearching)
        }
        .padding(.horizontal)
    }
    
    /// セグメントピッカー
    private var segmentPicker: some View {
        Picker("Content Type", selection: $selectedSegment) {
            ForEach(0..<segments.count, id: \.self) { index in
                Text(segments[index]).tag(index)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }
    
    /// 検索結果があるかどうか
    private var hasSearchResults: Bool {
        !searchResults.isEmpty || !albumSearchResults.isEmpty || !artistSearchResults.isEmpty
    }
    
    /// 検索結果リスト
    private var searchResultsList: some View {
        Group {
            if isSearching {
                ProgressView("Searching...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if hasSearchResults {
                List {
                    switch selectedSegment {
                    case 0: // Tracks
                        ForEach(searchResults) { track in
                            SearchTrackRow(track: track)
                        }
                    case 1: // Albums
                        ForEach(albumSearchResults) { album in
                            SearchAlbumRow(album: album)
                        }
                    case 2: // Artists
                        ForEach(artistSearchResults) { artist in
                            SearchArtistRow(artist: artist)
                        }
                    default:
                        EmptyView()
                    }
                }
                .listStyle(PlainListStyle())
            } else {
                emptyStateView
            }
        }
    }
    
    /// 空状態のビュー
    private var emptyStateView: some View {
        VStack {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            Text("Search Apple Music")
                .font(.title2)
                .foregroundColor(.gray)
            Text("Find tracks, albums, and artists")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    /// 音楽検索
    private func searchMusic() {
        guard !searchText.isEmpty else { return }
        
        isSearching = true
        Task {
            do {
                // トラック検索
                var trackRequest = MusicCatalogSearchRequest(term: searchText, types: [Song.self])
                trackRequest.limit = 20
                let trackResponse = try await trackRequest.response()
                
                // アルバム検索
                var albumRequest = MusicCatalogSearchRequest(term: searchText, types: [Album.self])
                albumRequest.limit = 20
                let albumResponse = try await albumRequest.response()
                
                // アーティスト検索
                var artistRequest = MusicCatalogSearchRequest(term: searchText, types: [Artist.self])
                artistRequest.limit = 20
                let artistResponse = try await artistRequest.response()
                
                await MainActor.run {
                    self.searchResults = trackResponse.songs
                    self.albumSearchResults = albumResponse.albums
                    self.artistSearchResults = artistResponse.artists
                    self.isSearching = false
                }
            } catch {
                print("検索エラー: \(error)")
                await MainActor.run {
                    self.isSearching = false
                }
            }
        }
    }
}

/// 検索結果のトラック行
struct SearchTrackRow: View {
    let track: Song
    @EnvironmentObject var storage: UserDefaultsStorage
    
    private var listenLaterItem: ListenLaterItem {
        ListenLaterItem(from: track)
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(track.title)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(track.artistName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Listen Laterボタン
            Button(action: {
                storage.addItem(listenLaterItem)
            }) {
                Image(systemName: "plus.circle")
                    .foregroundColor(.blue)
                    .font(.title2)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }
}

/// 検索結果のアルバム行
struct SearchAlbumRow: View {
    let album: Album
    @EnvironmentObject var storage: UserDefaultsStorage
    
    private var listenLaterItem: ListenLaterItem {
        ListenLaterItem(from: album)
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(album.title)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(album.artistName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Listen Laterボタン
            Button(action: {
                storage.addItem(listenLaterItem)
            }) {
                Image(systemName: "plus.circle")
                    .foregroundColor(.green)
                    .font(.title2)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }
}

/// 検索結果のアーティスト行
struct SearchArtistRow: View {
    let artist: Artist
    @EnvironmentObject var storage: UserDefaultsStorage
    
    private var listenLaterItem: ListenLaterItem {
        ListenLaterItem(from: artist)
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(artist.name)
                    .font(.headline)
                    .lineLimit(1)
                
                Text("Artist")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Listen Laterボタン
            Button(action: {
                storage.addItem(listenLaterItem)
            }) {
                Image(systemName: "plus.circle")
                    .foregroundColor(.purple)
                    .font(.title2)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    SearchView()
        .environmentObject(UserDefaultsStorage())
}