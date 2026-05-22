//
//  AudioPlayer.swift
//  PrismMusic
//
//  AVPlayer wrapper that owns the entire playback domain:
//   - current track + queue + index
//   - play/pause/seek + repeat/shuffle modes
//   - progress + duration broadcasting via @Observable
//   - audio session activation
//   - MPNowPlayingInfoCenter integration
//   - MPRemoteCommandCenter handlers (lock screen + headphones + Siri)
//   - Live Activity / Dynamic Island lifecycle
//
//  This is the single source of truth — the UI never instantiates an
//  AVPlayer of its own.
//

import AVFoundation
import Combine
import Foundation
import MediaPlayer
import Observation
import SwiftUI
import UIKit
import WidgetKit

@Observable
@MainActor
final class AudioPlayer {
    // MARK: - Observable state

    enum TrackChangeDirection { case forward, backward, none }

    private(set) var currentTrack: Track?
    private(set) var queue: [Track] = []
    private(set) var currentIndex: Int = 0
    private(set) var isPlaying: Bool = false
    private(set) var progress: Double = 0
    private(set) var duration: Double = 0
    private(set) var isBuffering: Bool = false
    /// Direction of the last track change — used by the UI to animate cover slides.
    private(set) var trackChangeDirection: TrackChangeDirection = .none
    private var transitionTask: Task<Void, Never>?

    // Cache properties for Widget Updates to prevent throttling
    private var lastWidgetTrackId: String? = nil
    private var lastWidgetIsPlaying: Bool? = nil
    private var lastWidgetLyricsLines: [String]? = nil
    private var lastWidgetLyricLineIndex: Int? = nil
    private var hasTriggeredAutoNext: Bool = false

    var errorMessage: String? = nil
    var showError: Bool = false

    var volume: Float {
        get { storedVolume }
        set {
            let val = max(0, min(1, newValue))
            storedVolume = val
            if !isMuted {
                player.volume = val
            }
        }
    }
    private(set) var isMuted: Bool = false {
        didSet { player.volume = isMuted ? 0 : storedVolume }
    }
    private var storedVolume: Float = 1.0

    enum RepeatMode: String, CaseIterable { case off, all, one }
    var repeatMode: RepeatMode = .off
    var isShuffled: Bool = false

    /// Lyrics parsed for the current track (nil while still loading / absent).
    private(set) var lyrics: ParsedLyrics?

    // MARK: - Internals

    private let api: APIClient
    private let library: LibraryStore
    private var player = AVPlayer()
    private let session = AudioSessionManager()
    private let nowPlaying = NowPlayingManager()
    private let lyricsCache = LyricsCache()

    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var bufferObserver: NSKeyValueObservation?
    private var endNotificationObserver: NSObjectProtocol?

    init(api: APIClient, library: LibraryStore) {
        self.api = api
        self.library = library
    }

    // No `deinit` cleanup is needed: AudioPlayer is owned by AppState for
    // the lifetime of the process, and ARC tears down both the AVPlayer
    // and its time observer atomically when the app exits. Touching
    // `@MainActor` state from `deinit` would also violate Swift 6's
    // strict-concurrency rules.

    // MARK: - Public API

    /// One-shot setup called once when the app boots.
    func bootstrap() {
        session.activate()
        setupRemoteCommands()
        attachTimeObserver()
        attachEndNotification()
        // Volume mirror for Now Playing.
        storedVolume = player.volume
    }

    /// Replace the queue and start playing the first track.
    func play(queue tracks: [Track], startAt index: Int = 0) {
        guard !tracks.isEmpty else { return }
        let clampedIndex = max(0, min(index, tracks.count - 1))
        self.queue = tracks
        self.currentIndex = clampedIndex
        self.trackChangeDirection = .none
        load(track: tracks[clampedIndex], autoplay: true)
    }

    func togglePlay() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
        updateNowPlaying()
        updateWidgetState()
    }

    func next(isAutomatic: Bool = false) {
        guard !queue.isEmpty else { return }
        let nextIndex: Int
        if isShuffled {
            nextIndex = Int.random(in: 0..<queue.count)
        } else if currentIndex + 1 >= queue.count {
            guard repeatMode == .all else {
                // End of queue, no repeat — stop playback gracefully.
                player.pause()
                isPlaying = false
                return
            }
            nextIndex = 0
        } else {
            nextIndex = currentIndex + 1
        }
        withAnimation(.spring(response: 0.52, dampingFraction: 0.85)) {
            trackChangeDirection = .forward
            currentIndex = nextIndex
            load(track: queue[nextIndex], autoplay: true, isAutomatic: isAutomatic)
        }
    }

    func previous() {
        guard !queue.isEmpty else { return }
        // If more than 3s in, restart current track instead of jumping back.
        if progress > 3 {
            seek(to: 0)
            return
        }
        withAnimation(.spring(response: 0.52, dampingFraction: 0.85)) {
            trackChangeDirection = .backward
            let prevIndex = currentIndex == 0 ? queue.count - 1 : currentIndex - 1
            currentIndex = prevIndex
            load(track: queue[prevIndex], autoplay: true)
        }
    }

    func moveTrack(from source: IndexSet, to destination: Int) {
        let offset = currentIndex + 1
        guard offset < queue.count else { return }
        
        var newQueue = queue
        
        // Map source offsets and destination to actual indices in queue
        let adjustedSource = IndexSet(source.map { $0 + offset })
        let adjustedDestination = destination + offset
        
        newQueue.move(fromOffsets: adjustedSource, toOffset: adjustedDestination)
        self.queue = newQueue
        updateNowPlaying()
    }

    func seek(to seconds: Double) {
        let target = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                self?.progress = seconds
                self?.updateNowPlaying()
            }
        }
    }

    func toggleMute() {
        if isMuted {
            isMuted = false
        } else {
            storedVolume = player.volume
            isMuted = true
        }
    }

    func toggleRepeat() {
        let all = RepeatMode.allCases
        let next = all[(all.firstIndex(of: repeatMode)! + 1) % all.count]
        repeatMode = next
    }

    func toggleShuffle() { isShuffled.toggle() }

    func toggleLike() {
        guard let track = currentTrack else { return }
        library.toggleLike(track)
        updateNowPlaying()
    }

    // MARK: - Load track

    private func load(track: Track, autoplay: Bool, isAutomatic: Bool = false) {
        currentTrack = track
        progress = 0
        duration = track.durationSeconds ?? 0
        isBuffering = true
        lyrics = nil
        lastWidgetLyricLineIndex = nil
        hasTriggeredAutoNext = false

        // Update widget metadata immediately
        updateWidgetState(force: true)

        // Build the proxied stream URL — this is what AVPlayer fetches.
        guard let url = api.streamURL(for: track) else {
            print("[AudioPlayer] ⚠️ streamURL returned nil for track: \(track.id)")
            self.errorMessage = "Не удалось получить URL для трека \(track.title)."
            self.showError = true
            self.isBuffering = false
            return
        }
        print("[AudioPlayer] ▶ Loading: \(track.title) — \(track.artist)")
        print("[AudioPlayer]   URL: \(url)")

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        
        let oldPlayer = self.player
        let newPlayer = AVPlayer()
        self.player = newPlayer
        
        // Remove old observers
        if let timeObserver {
            oldPlayer.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        statusObserver?.invalidate()
        bufferObserver?.invalidate()
        if let endNotificationObserver {
            NotificationCenter.default.removeObserver(endNotificationObserver)
            self.endNotificationObserver = nil
        }
        
        observePlayerItem(item)
        attachTimeObserver()
        newPlayer.replaceCurrentItem(with: item)
        attachEndNotification()
        
        let targetVolume = isMuted ? 0 : storedVolume
        
        if isAutomatic {
            newPlayer.volume = 0
            if autoplay {
                newPlayer.play()
                self.isPlaying = true
            }
            self.updateWidgetState(force: true)
            performCrossfade(oldPlayer: oldPlayer, newPlayer: newPlayer)
        } else {
            // Cancel transition first
            transitionTask?.cancel()
            
            // Instantly stop and unload old player to avoid sound overlap
            oldPlayer.pause()
            oldPlayer.replaceCurrentItem(with: nil)
            
            newPlayer.volume = targetVolume
            if autoplay {
                newPlayer.play()
                self.isPlaying = true
            }
            self.updateWidgetState(force: true)
        }

        Task { await fetchLyrics(for: track) }

        updateNowPlaying()
    }

    private func performCrossfade(oldPlayer: AVPlayer, newPlayer: AVPlayer) {
        transitionTask?.cancel()
        let targetVolume = isMuted ? 0 : storedVolume
        
        transitionTask = Task { [weak self] in
            guard self != nil else { return }
            
            let crossfadeDuration = 2.0 // 2 seconds crossfade
            let steps = 20
            let interval = crossfadeDuration / Double(steps)
            
            let startVolume = oldPlayer.volume
            
            for step in 1...steps {
                if Task.isCancelled { break }
                
                let progress = Float(step) / Float(steps)
                
                // Fade out old player
                oldPlayer.volume = startVolume * (1.0 - progress)
                
                // Fade in new player
                newPlayer.volume = targetVolume * progress
                
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
            
            // Clean up old player
            oldPlayer.pause()
            oldPlayer.replaceCurrentItem(with: nil)
            
            // Ensure new player has final target volume
            if !Task.isCancelled {
                newPlayer.volume = targetVolume
            }
        }
    }

    private func observePlayerItem(_ item: AVPlayerItem) {
        statusObserver?.invalidate()
        bufferObserver?.invalidate()

        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    let d = item.duration.seconds
                    if d.isFinite, d > 0 { self.duration = d }
                    self.isBuffering = false
                case .failed:
                    let msg = item.error?.localizedDescription ?? "Неизвестная ошибка"
                    print("[AudioPlayer] ❌ Failed to load: \(msg)")
                    self.errorMessage = "Ошибка воспроизведения: \(msg)"
                    self.showError = true
                    self.isBuffering = false
                    // Auto-skip to next track on failure
                    self.next()
                default:
                    break
                }
            }
        }

        bufferObserver = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                self?.isBuffering = !item.isPlaybackLikelyToKeepUp
            }
        }
    }

    // MARK: - Time observation

    private var hasNextTrack: Bool {
        guard !queue.isEmpty else { return false }
        if isShuffled { return true }
        if currentIndex + 1 < queue.count { return true }
        if repeatMode == .all { return true }
        return false
    }

    private func attachTimeObserver() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        // Tick every 250ms — enough granularity for the lyrics RAF
        // interpolator without overloading the main thread.
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let seconds = time.seconds
                guard seconds.isFinite else { return }
                self.progress = seconds
                
                // Trigger early transition for audio crossfade if there's a next track
                let remaining = self.duration - seconds
                if remaining > 0 && remaining <= 3.0 && !self.hasTriggeredAutoNext && self.repeatMode != .one && self.hasNextTrack && self.duration > 10 {
                    self.hasTriggeredAutoNext = true
                    self.next(isAutomatic: true)
                }
                
                // Only trigger widget updates in the time observer if the active lyric line changes
                if let lyrics = self.lyrics, lyrics.isSynced {
                    let activeIndex = lyrics.lines.lastIndex(where: { $0.time <= seconds }) ?? -1
                    if activeIndex != self.lastWidgetLyricLineIndex {
                        self.lastWidgetLyricLineIndex = activeIndex
                        self.updateWidgetState()
                    }
                }
                
                // Refresh Now Playing occasionally
                if Int(seconds * 4) % 4 == 0 {
                    self.updateNowPlaying()
                }
            }
        }
    }

    private func attachEndNotification() {
        if let endNotificationObserver {
            NotificationCenter.default.removeObserver(endNotificationObserver)
            self.endNotificationObserver = nil
        }
        guard let currentItem = player.currentItem else { return }
        endNotificationObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                switch self.repeatMode {
                case .one:
                    self.seek(to: 0)
                    self.player.play()
                default:
                    self.next(isAutomatic: true)
                }
            }
        }
    }

    // MARK: - Remote commands (lock screen + headphones)

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlay() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlay() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlay() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let track = currentTrack else {
            nowPlaying.clear()
            return
        }
        nowPlaying.update(
            track: track,
            isPlaying: isPlaying,
            progress: progress,
            duration: duration
        )
    }

    // MARK: - Widget State Sync

    func updateWidgetState(force: Bool = false) {
        let defaults = UserDefaults.appGroup
        
        let title = currentTrack?.title ?? "Не воспроизводится"
        let artist = currentTrack?.artist ?? ""
        let album = currentTrack?.album ?? ""
        let source = currentTrack?.source?.rawValue ?? ""
        let isPlaying = self.isPlaying
        let artworkURL = currentTrack?.artworkURL?.absoluteString ?? ""
        
        var lyricsLines: [String] = []
        if let lyrics = self.lyrics, lyrics.isSynced {
            let t = self.progress
            if let activeIndex = lyrics.lines.lastIndex(where: { $0.time <= t }) {
                for offset in 0..<3 {
                    let idx = activeIndex + offset
                    if idx < lyrics.lines.count {
                        lyricsLines.append(lyrics.lines[idx].text)
                    }
                }
            } else {
                for idx in 0..<min(3, lyrics.lines.count) {
                    lyricsLines.append(lyrics.lines[idx].text)
                }
            }
        } else if let lyrics = self.lyrics {
            for idx in 0..<min(3, lyrics.lines.count) {
                lyricsLines.append(lyrics.lines[idx].text)
            }
        }
        
        let trackId = currentTrack?.id
        if !force &&
            trackId == lastWidgetTrackId &&
            isPlaying == lastWidgetIsPlaying &&
            lyricsLines == lastWidgetLyricsLines {
            return
        }
        
        lastWidgetTrackId = trackId
        lastWidgetIsPlaying = isPlaying
        lastWidgetLyricsLines = lyricsLines
        
        defaults?.set(title, forKey: "widget.track.title")
        defaults?.set(artist, forKey: "widget.track.artist")
        defaults?.set(album, forKey: "widget.track.album")
        defaults?.set(source, forKey: "widget.track.source")
        defaults?.set(isPlaying, forKey: "widget.track.isPlaying")
        defaults?.set(lyricsLines, forKey: "widget.track.lyricsLines")
        defaults?.set(artworkURL, forKey: "widget.track.artworkURL")
        defaults?.synchronize()
        
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Lyrics

    private func fetchLyrics(for track: Track) async {
        if let cached = lyricsCache.value(for: track) {
            self.lyrics = cached
            self.updateWidgetState(force: true)
            return
        }
        do {
            let response = try await api.lyrics(
                artist: track.artist,
                title: track.title,
                id: track.id,
                duration: track.durationSeconds
            )
            guard let raw = response?.lyrics, !raw.isEmpty else {
                lyricsCache.set(nil, for: track)
                return
            }
            let parsed = LyricsParser.parse(raw)
            lyricsCache.set(parsed, for: track)
            // Only commit if the user hasn't already changed tracks while we waited.
            if currentTrack?.id == track.id {
                self.lyrics = parsed
                self.updateWidgetState(force: true)
            }
        } catch {
            // Soft-fail — leave lyrics nil; UI shows "no lyrics" placeholder.
        }
    }

}

extension UserDefaults {
    static var appGroup: UserDefaults? {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.prism.music.app"
        var components = bundleId.components(separatedBy: ".")
        
        // Robust filtering: Remove any component containing "widget", "extension", or "app",
        // and also any trailing numeric/hash component added by sideloading tools if it's after the widget.
        components = components.filter { component in
            let lower = component.lowercased()
            return !lower.contains("widget") && !lower.contains("extension") && lower != "app"
        }
        
        let appGroupId = "group." + components.joined(separator: ".")
        return UserDefaults(suiteName: appGroupId)
    }
}


