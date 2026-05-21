//
//  Track.swift
//  PrismMusic
//
//  Core music models, mirroring the TS types in the web app
//  (`components/music/album-card.tsx`). `Codable` for direct JSON
//  decoding from the backend.
//

import Foundation

/// One playable music track.
struct Track: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    let artist: String
    let album: String?
    let durationSeconds: Double?
    /// Cover artwork URL. Optional because some sources don't return one.
    let cover: URL?
    /// Original stream URL — passed through `/api/music/stream` for actual playback.
    let streamURL: URL?
    /// Provider tag used by the backend (`yandex`, `soundcloud`, etc).
    let source: TrackSource?

    var artworkURL: URL? { cover }

    /// Convenience: human-readable duration string (`m:ss`).
    var durationLabel: String {
        guard let d = durationSeconds, d.isFinite, d > 0 else { return "—" }
        let minutes = Int(d) / 60
        let seconds = Int(d) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    enum CodingKeys: String, CodingKey {
        case id, title, artist, album
        case durationSeconds = "duration"
        case cover
        case streamURL = "url"
        case source
    }
}

enum TrackSource: String, Codable, Sendable, CaseIterable {
    case yandex
    case soundcloud
    case spotify
    case other

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self).lowercased()
        self = TrackSource(rawValue: raw) ?? .other
    }

    /// Display label (`Я.Музыка`, `SoundCloud`, ...).
    var label: String {
        switch self {
        case .yandex: "Я.Музыка"
        case .soundcloud: "SoundCloud"
        case .spotify: "Spotify"
        case .other: "Другое"
        }
    }
}

/// An album / playlist / track-group as returned by search & recommendations.
struct Album: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    let artist: String
    let year: Int?
    let cover: URL?
    let source: TrackSource?
    let tracks: [Track]?
}
