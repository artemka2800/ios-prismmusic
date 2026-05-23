//
//  APIClient.swift
//  PrismMusic
//
//  Networking layer talking to the PrismMusic Next.js backend. One class
//  exposes typed methods for search, recommendations, lyrics, and the
//  stream-proxy URL builder. Always pulls the current backend host and
//  Yandex token from `SettingsStore` so changes propagate immediately.
//

import Foundation
import Observation

@MainActor
final class APIClient {
    private let settings: SettingsStore
    private let session: URLSession
    private let decoder: JSONDecoder

    init(settings: SettingsStore) {
        self.settings = settings

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = APIConfig.timeoutSeconds
        config.timeoutIntervalForResource = APIConfig.timeoutSeconds * 2
        // Use the URL cache to dedupe identical recommendation / search requests
        // within a single session — saves a network round-trip on tab switches.
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 32 * 1024 * 1024)

        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }

    // MARK: - Endpoints

    /// `GET /api/music/search?q=...`
    func search(query: String) async throws -> SearchResponse {
        var components = try makeComponents(path: "/api/music/search")
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return try await request(components, as: SearchResponse.self)
    }

    /// `GET /api/music/recommendations`
    func recommendations() async throws -> RecommendationsResponse {
        let components = try makeComponents(path: "/api/music/recommendations")
        return try await request(components, as: RecommendationsResponse.self)
    }

    /// `GET /api/music/lyrics?artist=...&title=...&id=...&duration=...`
    func lyrics(artist: String, title: String, id: String? = nil, duration: Double? = nil)
        async throws -> LyricsResponse?
    {
        var components = try makeComponents(path: "/api/music/lyrics")
        var items: [URLQueryItem] = [
            URLQueryItem(name: "artist", value: artist),
            URLQueryItem(name: "title", value: title),
        ]
        if let id { items.append(URLQueryItem(name: "id", value: id)) }
        if let duration { items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
        components.queryItems = items

        // Lyrics endpoint returns 404 when no lyrics exist — treat that as nil.
        do {
            return try await request(components, as: LyricsResponse.self)
        } catch APIError.httpStatus(let code, _) where code == 404 {
            return nil
        }
    }

    /// Builds the proxied stream URL for a given track. AVPlayer hits this
    /// URL directly; we never download the bytes ourselves.
    ///
    /// The backend stream endpoint accepts `?id=<trackId>&source=<source>`
    /// and resolves the actual audio URL server-side. The iOS client never
    /// needs the raw audio URL.
    func streamURL(for track: Track) -> URL? {
        guard var components = try? makeComponents(path: "/api/music/stream") else { return nil }
        var items: [URLQueryItem] = [
            URLQueryItem(name: "id", value: track.id),
            URLQueryItem(name: "source", value: track.source?.rawValue ?? "soundcloud"),
        ]
        if track.source == .yandex, !settings.yandexToken.isEmpty {
            items.append(URLQueryItem(name: "token", value: settings.yandexToken))
        }
        components.queryItems = items
        return components.url
    }

    /// `GET /api/music/playlist?id=...&source=...` — fetches tracks for a playlist/album.
    func playlistTracks(id: String, source: String) async throws -> [Track] {
        var components = try makeComponents(path: "/api/music/playlist")
        components.queryItems = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "source", value: source),
        ]
        let response = try await request(components, as: PlaylistDetailResponse.self)
        return response.tracks
    }

    /// `POST /api/music/yandex/import` — imports Yandex Liked tracks.
    func importYandexLikes() async throws -> YandexImportResponse {
        let components = try makeComponents(path: "/api/music/yandex/import")
        guard let url = components.url else { throw APIError.invalidBackendURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.cachePolicy = .reloadRevalidatingCacheData
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !settings.yandexToken.isEmpty {
            req.setValue(settings.yandexToken, forHTTPHeaderField: "x-yandex-token")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: [:])
        
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let bodyPreview = String(data: data.prefix(APIConfig.errorBodyLogLimit), encoding: .utf8)
            throw APIError.httpStatus(http.statusCode, bodyPreview)
        }
        return try decoder.decode(YandexImportResponse.self, from: data)
    }

    /// `POST /api/auth/login`
    func login(username: String, password: String) async throws -> UserResponse {
        let components = try makeComponents(path: "/api/auth/login")
        guard let url = components.url else { throw APIError.invalidBackendURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = ["username": username, "password": password]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let bodyPreview = String(data: data.prefix(APIConfig.errorBodyLogLimit), encoding: .utf8)
            throw APIError.httpStatus(http.statusCode, bodyPreview)
        }
        return try decoder.decode(UserResponse.self, from: data)
    }

    /// `POST /api/auth/register`
    func register(username: String, password: String) async throws -> UserResponse {
        let components = try makeComponents(path: "/api/auth/register")
        guard let url = components.url else { throw APIError.invalidBackendURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = ["username": username, "password": password]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let bodyPreview = String(data: data.prefix(APIConfig.errorBodyLogLimit), encoding: .utf8)
            throw APIError.httpStatus(http.statusCode, bodyPreview)
        }
        return try decoder.decode(UserResponse.self, from: data)
    }

    /// `GET /api/library/likes`
    func fetchLikedTracks(userId: String) async throws -> [Track] {
        var components = try makeComponents(path: "/api/library/likes")
        components.queryItems = [URLQueryItem(name: "userId", value: userId)]
        return try await request(components, as: [Track].self)
    }

    /// `POST /api/library/likes`
    func toggleLikeOnServer(userId: String, track: Track) async throws -> Bool {
        let components = try makeComponents(path: "/api/library/likes")
        guard let url = components.url else { throw APIError.invalidBackendURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let trackDict: [String: Any] = [
            "id": track.id,
            "title": track.title,
            "artist": track.artist,
            "coverUrl": track.cover?.absoluteString ?? "",
            "duration": track.duration,
            "source": track.source?.rawValue ?? "unknown"
        ]
        let body: [String: Any] = [
            "userId": userId,
            "track": trackDict
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let bodyPreview = String(data: data.prefix(APIConfig.errorBodyLogLimit), encoding: .utf8)
            throw APIError.httpStatus(http.statusCode, bodyPreview)
        }
        
        struct LikeResponse: Decodable {
            let liked: Bool
        }
        let result = try decoder.decode(LikeResponse.self, from: data)
        return result.liked
    }


    // MARK: - Plumbing

    private func makeComponents(path: String) throws -> URLComponents {
        let trimmed = settings.backendURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base = URL(string: trimmed),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidBackendURL
        }
        // Make sure we don't double-slash.
        if components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        components.path += path
        return components
    }

    private func request<T: Decodable>(_ components: URLComponents, as: T.Type) async throws -> T {
        guard let url = components.url else { throw APIError.invalidBackendURL }
        var req = URLRequest(url: url)
        // Use reloadRevalidating so we don't serve stale cached JSON
        // from a previous app version with a different response schema.
        req.cachePolicy = .reloadRevalidatingCacheData
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if !settings.yandexToken.isEmpty {
            req.setValue(settings.yandexToken, forHTTPHeaderField: "x-yandex-token")
        }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let bodyPreview = String(data: data.prefix(APIConfig.errorBodyLogLimit), encoding: .utf8)
            throw APIError.httpStatus(http.statusCode, bodyPreview)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            // Log raw JSON on decode failure to aid debugging.
            let preview = String(data: data.prefix(512), encoding: .utf8) ?? "(binary)"
            print("[APIClient] JSON decode failed for \(T.self):")
            print("[APIClient]   error: \(error)")
            print("[APIClient]   body preview: \(preview)")
            throw error
        }
    }
}

// MARK: - Errors

enum APIError: LocalizedError {
    case invalidBackendURL
    case invalidResponse
    case httpStatus(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidBackendURL:
            return "Некорректный URL бэкенда. Проверь Settings."
        case .invalidResponse:
            return "Сервер вернул неожиданный ответ."
        case .httpStatus(let code, _):
            return "Ошибка сервера (\(code))."
        }
    }
}
