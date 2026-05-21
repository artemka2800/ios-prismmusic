//
//  APIModels.swift
//  PrismMusic
//
//  Response DTOs for the PrismMusic backend. Shapes mirror what the
//  Next.js routes return in `app/api/music/*`.
//

import Foundation

/// `GET /api/music/search` — returns tracks + albums + artists.
struct SearchResponse: Decodable, Sendable {
    let tracks: [Track]
    let albums: [Album]?

    /// The backend sometimes omits optional sections; default them to empty.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.tracks = (try? container.decode([Track].self, forKey: .tracks)) ?? []
        self.albums = try? container.decode([Album].self, forKey: .albums)
    }

    enum CodingKeys: String, CodingKey {
        case tracks, albums
    }
}

/// `GET /api/music/recommendations` — returns playlists from SoundCloud.
///
/// Backend shape:
/// ```json
/// {
///   "title": "Подборки для вас",
///   "playlists": [
///     { "id": "...", "name": "...", "coverUrl": "...", "description": "...", "source": "soundcloud", "tracks": [] }
///   ]
/// }
/// ```
///
/// We map `playlists` → `[Album]` for display in the home grid.
struct RecommendationsResponse: Decodable, Sendable {
    let title: String?
    let albums: [Album]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try? container.decode(String.self, forKey: .title)

        // The backend returns `playlists`, each with { id, name, coverUrl, description, source, tracks }
        if let playlists = try? container.decode([PlaylistDTO].self, forKey: .playlists) {
            self.albums = playlists.map { playlist in
                Album(
                    id: playlist.id,
                    title: playlist.name,
                    artist: playlist.description ?? playlist.source ?? "SoundCloud",
                    year: nil,
                    cover: playlist.coverUrl.flatMap { URL(string: $0) },
                    source: TrackSource(rawValue: playlist.source ?? "soundcloud") ?? .soundcloud,
                    tracks: nil
                )
            }
        } else {
            // Fallback: try parsing as { tracks, albums } for forward-compat
            self.albums = (try? container.decode([Album].self, forKey: .albums)) ?? []
        }
    }

    enum CodingKeys: String, CodingKey {
        case title, playlists, albums
    }
}

/// Internal DTO matching the backend's playlist shape.
private struct PlaylistDTO: Decodable, Sendable {
    let id: String
    let name: String
    let coverUrl: String?
    let description: String?
    let source: String?
    let isSystem: Bool?
    let tracks: [Track]?
}

/// `GET /api/music/lyrics` — raw LRC blob.
struct LyricsResponse: Decodable, Sendable {
    let lyrics: String?
    let source: String?
}
