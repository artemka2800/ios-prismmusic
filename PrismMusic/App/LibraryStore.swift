//
//  LibraryStore.swift
//  PrismMusic
//
//  Liked tracks + recently played history, persisted to UserDefaults.
//  Same shape as the web app's localStorage entries.
//

import Foundation
import Observation

@Observable
@MainActor
final class LibraryStore {
    /// Set of track ids the user has liked. Source of truth for the
    /// heart-button state across the app.
    private(set) var likedTrackIDs: Set<String>

    /// Cached track data so the Library tab can render liked tracks even
    /// when they're not in the current playlist.
    private(set) var likedTracks: [Track]

    /// Cached user playlists.
    private(set) var playlists: [Album] = []
    private(set) var isLoadingPlaylists = false

    private let api: APIClient?
    private let settings: SettingsStore?

    init(api: APIClient? = nil, settings: SettingsStore? = nil) {
        self.api = api
        self.settings = settings
        let defaults = UserDefaults.standard
        self.likedTrackIDs = Set(defaults.stringArray(forKey: Keys.likedIDs) ?? [])
        if let data = defaults.data(forKey: Keys.likedTracks),
           let cached = try? JSONDecoder().decode([Track].self, from: data) {
            self.likedTracks = cached
        } else {
            self.likedTracks = []
        }
    }

    func isLiked(_ track: Track) -> Bool {
        likedTrackIDs.contains(track.id)
    }

    func toggleLike(_ track: Track) {
        if likedTrackIDs.contains(track.id) {
            likedTrackIDs.remove(track.id)
            likedTracks.removeAll { $0.id == track.id }
        } else {
            likedTrackIDs.insert(track.id)
            // Pin newest at the top.
            likedTracks.insert(track, at: 0)
        }
        persist()

        if let api, let settings, settings.isLoggedIn {
            Task {
                do {
                    _ = try await api.toggleLikeOnServer(userId: settings.userId, track: track)
                } catch {
                    print("[LibraryStore] Failed to toggle like on server: \(error)")
                }
            }
        }
    }

    func syncWithServer() async {
        guard let api, let settings, settings.isLoggedIn else {
            self.playlists = []
            return
        }
        do {
            let serverLikes = try await api.fetchLikedTracks(userId: settings.userId)
            self.likedTracks = serverLikes
            self.likedTrackIDs = Set(serverLikes.map { $0.id })
            persist()
        } catch {
            print("[LibraryStore] Failed to sync likes with server: \(error)")
        }
        await fetchPlaylists()
    }

    func importYandexTracks(_ tracks: [Track]) -> Int {
        var addedCount = 0
        for track in tracks {
            if !likedTrackIDs.contains(track.id) {
                addedCount += 1
            }
        }
        
        // Remove existing yandex tracks so we can insert them in the correct order
        likedTracks.removeAll { $0.source == .yandex }
        likedTrackIDs = Set(likedTracks.map { $0.id })
        
        // Prepend imported tracks in reverse order so the newest from Yandex is at index 0 (top)
        for track in tracks.reversed() {
            likedTrackIDs.insert(track.id)
            likedTracks.insert(track, at: 0)
        }
        
        persist()
        return addedCount
    }

    func replaceTrack(_ oldTrack: Track, with newTrack: Track) {
        likedTrackIDs.remove(oldTrack.id)
        likedTrackIDs.insert(newTrack.id)
        
        if let idx = likedTracks.firstIndex(where: { $0.id == oldTrack.id }) {
            likedTracks[idx] = newTrack
        }
        persist()
        
        if let api, let settings, settings.isLoggedIn {
            Task {
                do {
                    _ = try await api.replaceLikedTrack(oldTrackId: oldTrack.id, newTrack: newTrack)
                } catch {
                    print("[LibraryStore] Failed to replace liked track on server: \(error)")
                }
            }
        }
    }

    func fetchPlaylists() async {
        guard let api, let settings, settings.isLoggedIn else { return }
        isLoadingPlaylists = true
        do {
            self.playlists = try await api.fetchUserPlaylists(userId: settings.userId)
        } catch {
            print("[LibraryStore] Failed to fetch playlists: \(error)")
        }
        isLoadingPlaylists = false
    }

    func createPlaylist(name: String, description: String) async -> Album? {
        guard let api, let settings, settings.isLoggedIn else { return nil }
        do {
            let newPlaylist = try await api.createPlaylist(userId: settings.userId, name: name, description: description)
            self.playlists.insert(newPlaylist, at: 0)
            return newPlaylist
        } catch {
            print("[LibraryStore] Failed to create playlist: \(error)")
            return nil
        }
    }

    func deletePlaylist(_ playlist: Album) async {
        guard let api, let settings, settings.isLoggedIn else { return }
        do {
            try await api.deletePlaylist(playlistId: playlist.id)
            self.playlists.removeAll { $0.id == playlist.id }
        } catch {
            print("[LibraryStore] Failed to delete playlist: \(error)")
        }
    }

    func addTrack(_ track: Track, to playlist: Album) async {
        guard let api, let settings, settings.isLoggedIn else { return }
        do {
            try await api.addTrackToPlaylist(playlistId: playlist.id, track: track)
        } catch {
            print("[LibraryStore] Failed to add track to playlist: \(error)")
        }
    }

    func removeTrack(_ track: Track, from playlist: Album) async {
        guard let api, let settings, settings.isLoggedIn else { return }
        do {
            try await api.removeTrackFromPlaylist(playlistId: playlist.id, trackId: track.id)
        } catch {
            print("[LibraryStore] Failed to remove track from playlist: \(error)")
        }
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(Array(likedTrackIDs), forKey: Keys.likedIDs)
        if let data = try? JSONEncoder().encode(likedTracks) {
            defaults.set(data, forKey: Keys.likedTracks)
        }
    }

    private enum Keys {
        static let likedIDs = "prism.likedTrackIDs"
        static let likedTracks = "prism.likedTracks"
    }
}
