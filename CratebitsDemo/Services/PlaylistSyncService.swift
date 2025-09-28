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
        // Extract songs from the listen now items using minimal JSON approach
        let songs = extractSongsFromJSON(from: items)

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

    /// Extract Song objects from ListenLaterItem array using minimal JSON approach
    /// No API calls needed - creates Songs from minimal JSON using Apple Music IDs
    private func extractSongsFromJSON(from items: [ListenLaterItem]) -> [Song] {
        var appleMusicIDs: [String] = []

        // Collect all Apple Music IDs from the items
        for item in items {
            switch item.type {
            case .track:
                if let appleMusicID = item.appleMusicID {
                    appleMusicIDs.append(appleMusicID)
                }

            case .album, .artist:
                // For albums and artists, get Apple Music IDs from picked tracks
                if let pickedTracks = item.pickedTracks {
                    for pickedTrack in pickedTracks {
                        if let appleMusicID = pickedTrack.appleMusicID {
                            appleMusicIDs.append(appleMusicID)
                        }
                    }
                }
            }
        }

        // Create Song objects from the collected IDs using minimal JSON
        return createSongsFromIDs(appleMusicIDs)
    }


    /// Create minimal JSON for a Song object using Apple Music API format
    /// Based on actual Song JSON structure - only includes absolutely required fields
    private func createMinimalSongJSON(appleMusicID: String) -> Data? {
        let minimalSongJSON = """
        {
            "id": "\(appleMusicID)",
            "type": "songs",
            "attributes": {
                "name": "",
                "artistName": "",
                "genreNames": []
            }
        }
        """
        return minimalSongJSON.data(using: .utf8)
    }

    /// Create multiple Song objects from Apple Music IDs using minimal JSON
    private func createSongsFromIDs(_ appleMusicIDs: [String]) -> [Song] {
        let decoder = JSONDecoder()
        var songs: [Song] = []

        for appleMusicID in appleMusicIDs {
            guard let jsonData = createMinimalSongJSON(appleMusicID: appleMusicID) else {
                print("[PlaylistSync] Failed to create JSON for ID: \(appleMusicID)")
                continue
            }

            do {
                let song = try decoder.decode(Song.self, from: jsonData)
                songs.append(song)
                print("[PlaylistSync] Created Song from minimal JSON: \(appleMusicID)")
            } catch {
                print("[PlaylistSync] Failed to decode Song from JSON for ID \(appleMusicID): \(error)")
            }
        }

        return songs
    }

    /// Debug method to examine Song JSON structure
    private func debugSongStructure(_ song: Song) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let jsonData = try encoder.encode(song)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "Failed to convert to string"
            print("[DEBUG] Song JSON Structure:")
            print(jsonString)
            print("[DEBUG] ==========================================")
        } catch {
            print("[DEBUG] Failed to encode Song: \(error)")
        }
    }

    /// Clear any previous sync errors
    func clearError() {
        lastSyncError = nil
    }
}
