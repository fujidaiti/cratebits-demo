//
//  PlaylistSyncService.swift
//  CratebitsDemo
//
//  Created by Claude on 2025/09/28.
//

import Foundation
import MusicKit

/// Service for synchronizing Listen Now queue with Apple Music playlists
@MainActor
class PlaylistSyncService: ObservableObject {
    @Published var isSyncing = false
    @Published var lastSyncError: String?

    private let playlistName = "Generated Test Playlist"
    private let authorDisplayName = "Cratebits Demo App"

    /// Sync the Listen Now queue to an Apple Music playlist
    /// - Parameters:
    ///   - items: The Listen Now queue items to sync
    ///   - storage: UserDefaultsStorage instance for playlist ID persistence
    /// - Returns: Success status
    func syncToPlaylist(_ items: [ListenLaterItem], storage: UserDefaultsStorage) async -> Bool {
        isSyncing = true
        lastSyncError = nil

        defer {
            isSyncing = false
        }

        // Check authorization
        let authStatus = await MusicAuthorization.request()
        guard authStatus == .authorized else {
            lastSyncError = "Apple Music authorization denied"
            return false
        }

        #if os(iOS)
        // Extract songs from the listen now items
        let songs = await extractSongs(from: items)

        if songs.isEmpty {
            lastSyncError = "No valid songs found to sync"
            return false
        }

        // Check if we have an existing playlist
        if let savedPlaylistID = storage.getPlaylistID() {
            // Try to update existing playlist
            return await updateExistingPlaylist(savedPlaylistID, with: songs, storage: storage)
        } else {
            // Create new playlist
            return await createNewPlaylist(with: songs, storage: storage)
        }
        #else
        lastSyncError = "Playlist sync is not supported on macOS"
        return false
        #endif
    }

    #if os(iOS)
    /// Create a new Apple Music playlist
    private func createNewPlaylist(with songs: [Song], storage: UserDefaultsStorage) async -> Bool {
        do {
            let playlist = try await MusicLibrary.shared.createPlaylist(
                name: playlistName,
                description: "Auto-generated playlist from Listen Now queue",
                authorDisplayName: authorDisplayName,
                items: songs
            )

            // Save the playlist ID for future updates
            storage.savePlaylistID(playlist.id.rawValue)
            print("[PlaylistSync] Created new playlist with ID: \(playlist.id.rawValue)")
            return true

        } catch {
            lastSyncError = "Failed to create playlist: \(error.localizedDescription)"
            print("[PlaylistSync] Error creating playlist: \(error)")
            return false
        }
    }

    /// Update an existing Apple Music playlist
    private func updateExistingPlaylist(_ playlistID: String, with songs: [Song], storage: UserDefaultsStorage) async -> Bool {
        do {
            // First, get the existing playlist
            let request = MusicLibraryRequest<Playlist>()
            let response = try await request.response()

            guard let existingPlaylist = response.items.first(where: { $0.id.rawValue == playlistID }) else {
                print("[PlaylistSync] Existing playlist not found, creating new one")
                // If playlist doesn't exist anymore, create a new one
                storage.clearPlaylistID()
                return await createNewPlaylist(with: songs, storage: storage)
            }

            // Update the existing playlist
            let updatedPlaylist = try await MusicLibrary.shared.edit(
                existingPlaylist,
                name: playlistName,
                description: "Auto-generated playlist from Listen Now queue (Updated: \(Date().formatted(date: .abbreviated, time: .shortened)))",
                authorDisplayName: authorDisplayName,
                items: songs
            )

            print("[PlaylistSync] Updated existing playlist: \(updatedPlaylist.name)")
            return true

        } catch {
            lastSyncError = "Failed to update playlist: \(error.localizedDescription)"
            print("[PlaylistSync] Error updating playlist: \(error)")

            // If update fails, try creating a new playlist
            storage.clearPlaylistID()
            return await createNewPlaylist(with: songs, storage: storage)
        }
    }
    #endif

    /// Extract Song objects from ListenLaterItem array
    private func extractSongs(from items: [ListenLaterItem]) async -> [Song] {
        var songs: [Song] = []

        for item in items {
            switch item.type {
            case .track:
                if let song = await getSong(from: item) {
                    songs.append(song)
                }

            case .album, .artist:
                // For albums and artists, get songs from picked tracks
                if let pickedTracks = item.pickedTracks {
                    for pickedTrack in pickedTracks {
                        if let song = await getSong(from: pickedTrack) {
                            songs.append(song)
                        }
                    }
                }
            }
        }

        return songs
    }

    /// Convert a ListenLaterItem to a Song object
    /// Includes a delay to prevent hitting API rate limits when called multiple times
    private func getSong(from item: ListenLaterItem) async -> Song? {
        guard let appleMusicID = item.appleMusicID else {
            print("[PlaylistSync] No Apple Music ID for item: \(item.name)")
            return nil
        }

        do {
            // Add a small delay to prevent rate limiting when making multiple concurrent requests
            // 100ms delay should be reasonable for most use cases while staying responsive
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms

            let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(appleMusicID))
            let response = try await request.response()
            return response.items.first
        } catch {
            print("[PlaylistSync] Error fetching song \(item.name): \(error)")
            return nil
        }
    }

    /// Clear any previous sync errors
    func clearError() {
        lastSyncError = nil
    }
}