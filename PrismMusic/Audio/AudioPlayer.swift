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
import UIKit

@Observable
@MainActor
final class AudioPlayer {
    // MARK: - Observable state

    private(set) var currentTrack: Track?
    private(set) var queue: [Track] = []
    private(set) var currentIndex: Int = 0
    private(set) var isPlaying: Bool = false
    private(set) var progress: Double = 0
    private(set) var duration: Double = 0
    private(set) var isBuffering: Bool = false

    var volume: Float {
        get { player.volume }
        set { player.volume = max(0, min(1, newValue)) }
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
    private let player = AVPlayer()
    private let session = AudioSessionManager()
    private let nowPlaying = NowPlayingManager()
    private let liveActivity = LiveActivityManager()
    private let lyricsCache = LyricsCache()

    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var bufferObserver: NSKeyValueObservation?
    private var endNotificationObserver: NSObjectProtocol?

    init(api: APIClient, library: LibraryStore) {
        self.api = api
        self.library = library
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
    }

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
        liveActivity.update(state: liveActivityState)
    }

    func next() {
        guard !queue.isEmpty else { return }
        let nextIndex: Int
        if isShuffled {
            nextIndex = Int.random(in: 0..<queue.count)
        } else if currentIndex + 1 >= queue.count {
            guard repeatMode == .all else {
                // End of queue, no repeat — stop playback gracefully.
                player.pause()
                isPlaying = false
                liveActivity.end()
                return
            }
            nextIndex = 0
        } else {
            nextIndex = currentIndex + 1
        }
        currentIndex = nextIndex
        load(track: queue[nextIndex], autoplay: true)
    }

    func previous() {
        guard !queue.isEmpty else { return }
        // If more than 3s in, restart current track instead of jumping back.
        if progress > 3 {
            seek(to: 0)
            return
        }
        let prevIndex = currentIndex == 0 ? queue.count - 1 : currentIndex - 1
        currentIndex = prevIndex
        load(track: queue[prevIndex], autoplay: true)
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

    private func load(track: Track, autoplay: Bool) {
        currentTrack = track
        progress = 0
        duration = track.durationSeconds ?? 0
        isBuffering = true
        lyrics = nil

        // Build the proxied stream URL — this is what AVPlayer fetches.
        guard let url = api.streamURL(for: track) else {
            isBuffering = false
            return
        }

        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetOutOfBandMIMETypeKey": "audio/mpeg",
        ])
        let item = AVPlayerItem(asset: asset)
        observePlayerItem(item)
        player.replaceCurrentItem(with: item)

        if autoplay {
            player.play()
            isPlaying = true
        }

        // Kick off lyrics fetch in parallel — pre-populates the cache so
        // the Now Playing view doesn't show a spinner when opened.
        Task { await fetchLyrics(for: track) }

        updateNowPlaying()
        liveActivity.start(track: track, state: liveActivityState)
    }

    private func observePlayerItem(_ item: AVPlayerItem) {
        statusObserver?.invalidate()
        bufferObserver?.invalidate()

        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                if item.status == .readyToPlay {
                    let d = item.duration.seconds
                    if d.isFinite, d > 0 { self.duration = d }
                    self.isBuffering = false
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

    private func attachTimeObserver() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        // Tick every 250ms — enough granularity for the lyrics RAF
        // interpolator without overloading the main thread.
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.progress = time.seconds
                // Refresh Live Activity occasionally — every ~1s is enough.
                if Int(time.seconds * 4) % 4 == 0 {
                    self.liveActivity.update(state: self.liveActivityState)
                    self.updateNowPlaying()
                }
            }
        }
    }

    private func attachEndNotification() {
        endNotificationObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                switch self.repeatMode {
                case .one:
                    self.seek(to: 0)
                    self.player.play()
                default:
                    self.next()
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

    // MARK: - Lyrics

    private func fetchLyrics(for track: Track) async {
        if let cached = lyricsCache.value(for: track) {
            self.lyrics = cached
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
            }
        } catch {
            // Soft-fail — leave lyrics nil; UI shows "no lyrics" placeholder.
        }
    }

    // MARK: - Live Activity payload

    private var liveActivityState: LiveActivityState {
        LiveActivityState(
            title: currentTrack?.title ?? "",
            artist: currentTrack?.artist ?? "",
            artworkURL: currentTrack?.artworkURL,
            isPlaying: isPlaying,
            progress: progress,
            duration: duration
        )
    }
}
