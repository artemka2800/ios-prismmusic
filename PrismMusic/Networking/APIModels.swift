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

/// `GET /api/music/recommendations` — list of curated tracks.
struct RecommendationsResponse: Decodable, Sendable {
    let tracks: [Track]
    let albums: [Album]?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.tracks = (try? container.decode([Track].self, forKey: .tracks)) ?? []
        self.albums = try? container.decode([Album].self, forKey: .albums)
    }

    enum CodingKeys: String, CodingKey {
        case tracks, albums
    }
}

/// `GET /api/music/lyrics` — raw LRC blob.
struct LyricsResponse: Decodable, Sendable {
    let lyrics: String?
    let source: String?
}
