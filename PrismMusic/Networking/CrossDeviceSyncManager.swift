//
//  CrossDeviceSyncManager.swift
//  PrismMusic
//
//  Coordinates cross-device playback and settings synchronization.
//  Listens to Next.js server SSE stream for remote events and sends POST broadcasts
//  on local changes (debounced for volume/track/play-pause to save bandwidth).
//

import Foundation
import Observation

@MainActor
final class CrossDeviceSyncManager {
    private let audio: AudioPlayer
    private let settings: SettingsStore
    private let api: APIClient
    
    private let clientId = UUID().uuidString
    private var isApplyingRemote = false
    private var lastSentState: String = ""
    
    private var sseTask: Task<Void, Never>? = nil
    private var debounceTask: Task<Void, Never>? = nil
    
    init(audio: AudioPlayer, settings: SettingsStore, api: APIClient) {
        self.audio = audio
        self.settings = settings
        self.api = api
    }
    
    func bootstrap() {
        // Observe login/logout session changes
        NotificationCenter.default.addObserver(
            forName: .prismUserSessionChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.handleSessionChange() }
        }
        
        // Observe player state changes (track, isPlaying, volume)
        NotificationCenter.default.addObserver(
            forName: .prismPlayerStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.queuePlayerBroadcast() }
        }
        
        // Observe immediate seek changes
        NotificationCenter.default.addObserver(
            forName: .prismPlayerSeekChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let currentTime = notification.userInfo?["currentTime"] as? Double
            Task { @MainActor in self.broadcastPlayerState(currentTimeOverride: currentTime, immediate: true) }
        }
        
        // Observe settings changes (immersive, yandex token)
        NotificationCenter.default.addObserver(
            forName: .prismSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.broadcastSettings() }
        }
        
        // Start connection if already logged in
        if settings.isLoggedIn {
            startSync()
        }
    }
    
    private func handleSessionChange() {
        if settings.isLoggedIn {
            startSync()
        } else {
            stopSync()
        }
    }
    
    private func startSync() {
        stopSync()
        let userId = settings.userId
        print("[Sync] Starting cross-device sync for user: \(userId)")
        
        sseTask = Task {
            while !Task.isCancelled {
                await connectSSE(userId: userId)
                if Task.isCancelled { break }
                // Wait 5 seconds before reconnecting on failure
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
    
    private func stopSync() {
        sseTask?.cancel()
        sseTask = nil
        debounceTask?.cancel()
        debounceTask = nil
        print("[Sync] Stopped cross-device sync.")
    }
    
    private func connectSSE(userId: String) async {
        let trimmed = settings.backendURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base = URL(string: trimmed),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            print("[Sync] Invalid backend URL: \(trimmed)")
            return
        }
        
        if components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        components.path += "/api/user/sync/stream"
        components.queryItems = [URLQueryItem(name: "userId", value: userId)]
        
        guard let url = components.url else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3600
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        
        do {
            print("[Sync] Connecting to SSE stream...")
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("[Sync] SSE connected but server returned non-200 status.")
                return
            }
            
            print("[Sync] SSE Stream connected.")
            for try await line in bytes.lines {
                if Task.isCancelled { break }
                
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedLine.hasPrefix("data: ") {
                    let jsonString = trimmedLine.dropFirst(6)
                    if let data = jsonString.data(using: .utf8) {
                        self.handleIncomingSync(data)
                    }
                }
            }
        } catch {
            print("[Sync] SSE connection error: \(error.localizedDescription)")
        }
    }
    
    private func handleIncomingSync(_ data: Data) {
        let decoder = JSONDecoder()
        do {
            let envelope = try decoder.decode(GenericEnvelope.self, from: data)
            if envelope.clientId == clientId { return }
            
            print("[Sync] Received remote update: \(envelope.type)")
            isApplyingRemote = true
            
            if envelope.type == "player" {
                let playerMsg = try decoder.decode(PlayerSyncEnvelope.self, from: data)
                let payload = playerMsg.payload
                
                // 1. Sync track
                let currentTrackId = audio.currentTrack?.id
                let remoteTrackId = payload.track?.id
                if remoteTrackId != currentTrackId {
                    if let track = payload.track {
                        audio.syncPlay(track: track, autoplay: payload.isPlaying ?? false)
                    } else {
                        audio.syncStop()
                    }
                }
                
                // 2. Sync volume
                if let volume = payload.volume, volume != audio.volume {
                    audio.volume = volume
                }
                
                // 3. Sync play/pause
                if let isPlaying = payload.isPlaying, isPlaying != audio.isPlaying {
                    audio.setPlaying(isPlaying)
                }
                
                // 4. Sync seek/currentTime (only seek if difference is more than 3 seconds)
                if let currentTime = payload.currentTime {
                    let timeDiff = abs(audio.progress - currentTime)
                    if timeDiff > 3 {
                        audio.seek(to: currentTime)
                    }
                }
            } else if envelope.type == "settings" {
                let settingsMsg = try decoder.decode(SettingsSyncEnvelope.self, from: data)
                let payload = settingsMsg.payload
                if let immersive = payload.immersive {
                    settings.immersiveMode = immersive
                }
                if let yandexToken = payload.yandexToken, !yandexToken.isEmpty {
                    settings.yandexToken = yandexToken
                }
            } else if envelope.type == "token" {
                let tokenMsg = try decoder.decode(TokenSyncEnvelope.self, from: data)
                settings.yandexToken = tokenMsg.payload
            }
            
            // Release lock after state has updated
            Task {
                try? await Task.sleep(for: .seconds(0.1))
                isApplyingRemote = false
            }
        } catch {
            print("[Sync] Failed to parse SSE message: \(error)")
            isApplyingRemote = false
        }
    }
    
    private func queuePlayerBroadcast() {
        debounceTask?.cancel()
        debounceTask = Task {
            // 500ms debounce
            try? await Task.sleep(for: .seconds(0.5))
            if Task.isCancelled { return }
            broadcastPlayerState()
        }
    }
    
    private func broadcastPlayerState(currentTimeOverride: Double? = nil, immediate: Bool = false) {
        if isApplyingRemote || !settings.isLoggedIn { return }
        
        if immediate {
            debounceTask?.cancel()
        }
        
        let payload = PlayerSyncPayload(
            track: audio.currentTrack,
            isPlaying: audio.isPlaying,
            volume: audio.volume,
            currentTime: currentTimeOverride ?? audio.progress,
            timestamp: Date().timeIntervalSince1970 * 1000
        )
        
        guard let dict = toDictionary(payload) else { return }
        
        // Prevent duplicate updates
        let serialized = String(describing: dict)
        if serialized == lastSentState { return }
        lastSentState = serialized
        
        sendBroadcast(type: "player", payload: dict)
    }
    
    private func broadcastSettings() {
        if isApplyingRemote || !settings.isLoggedIn { return }
        
        let payload = SettingsSyncPayload(
            theme: "dark",
            immersive: settings.immersiveMode,
            yandexToken: settings.yandexToken
        )
        
        guard let dict = toDictionary(payload) else { return }
        sendBroadcast(type: "settings", payload: dict)
    }
    
    private func sendBroadcast(type: String, payload: Any) {
        let uId = settings.userId
        let cId = clientId
        Task {
            do {
                try await api.syncState(userId: uId, clientId: cId, type: type, payload: payload)
            } catch {
                print("[Sync] Failed to broadcast sync state (\(type)): \(error.localizedDescription)")
            }
        }
    }
    
    private func toDictionary<T: Encodable>(_ value: T) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(value),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict
    }
}

// MARK: - Local Envelope Helpers

private struct GenericEnvelope: Decodable {
    let clientId: String
    let type: String
}

private struct PlayerSyncEnvelope: Decodable {
    let clientId: String
    let type: String
    let payload: PlayerSyncPayload
}

private struct SettingsSyncEnvelope: Decodable {
    let clientId: String
    let type: String
    let payload: SettingsSyncPayload
}

private struct TokenSyncEnvelope: Decodable {
    let clientId: String
    let type: String
    let payload: String
}
