//
//  PrismMusicWidget.swift
//  PrismMusicWidget
//
//  Minimal, bulletproof WidgetKit extension for PrismMusic.
//  Shows current track info when playing, or a branded placeholder when idle.
//

import WidgetKit
import SwiftUI

// MARK: - Shared Constants

private let kGroupID = "group.com.prism.music"
private let kTitle    = "widget.track.title"
private let kArtist   = "widget.track.artist"
private let kSource   = "widget.track.source"
private let kPlaying  = "widget.track.isPlaying"
private let kLyrics   = "widget.track.lyricsLines"

// MARK: - Timeline Entry

struct PrismEntry: TimelineEntry {
    let date: Date
    let title: String
    let artist: String
    let source: String
    let isPlaying: Bool
    let lyrics: [String]

    var hasTrack: Bool {
        !title.isEmpty && title != "idle"
    }

    static let idle = PrismEntry(
        date: .now, title: "idle", artist: "", source: "",
        isPlaying: false, lyrics: []
    )
}

// MARK: - Timeline Provider

struct PrismProvider: TimelineProvider {

    func placeholder(in context: Context) -> PrismEntry {
        .idle
    }

    func getSnapshot(in context: Context,
                     completion: @escaping @Sendable (PrismEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context,
                     completion: @escaping @Sendable (Timeline<PrismEntry>) -> Void) {
        let entry = readEntry()
        // Refresh every 15 min at most; the app calls reloadAllTimelines() on track change anyway.
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: entry.date)!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    // Pure synchronous read — no networking, no semaphores, no async.
    private func readEntry() -> PrismEntry {
        // Try the official App Group first, then fall back to standard defaults.
        let defaults = UserDefaults(suiteName: kGroupID) ?? .standard

        let title    = defaults.string(forKey: kTitle) ?? ""
        let artist   = defaults.string(forKey: kArtist) ?? ""
        let source   = defaults.string(forKey: kSource) ?? ""
        let playing  = defaults.bool(forKey: kPlaying)
        let lyrics   = defaults.stringArray(forKey: kLyrics) ?? []

        if title.isEmpty {
            return .idle
        }

        return PrismEntry(
            date: .now,
            title: title,
            artist: artist,
            source: source,
            isPlaying: playing,
            lyrics: lyrics
        )
    }
}

// MARK: - Prism Colors

private enum Prism {
    static let purple  = Color(red: 0.65, green: 0.35, blue: 0.95)
    static let blue    = Color(red: 0.25, green: 0.55, blue: 1.0)
    static let magenta = Color(red: 0.95, green: 0.25, blue: 0.65)

    static let gradient = LinearGradient(
        colors: [purple, blue, magenta],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let bgDark = Color(red: 0.08, green: 0.08, blue: 0.09)
}

// MARK: - Background

struct PrismBackground: View {
    var body: some View {
        ZStack {
            Prism.bgDark
            RadialGradient(
                colors: [
                    Prism.purple.opacity(0.18),
                    Prism.blue.opacity(0.10),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 5,
                endRadius: 160
            )
        }
    }
}

// MARK: - Small: Idle

struct SmallIdleView: View {
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Prism.gradient)
                    .frame(width: 42, height: 42)
                    .shadow(color: Prism.purple.opacity(0.4), radius: 8)
                Image(systemName: "music.note")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.top, 6)

            Text("Открой меня и\nокунись в мир музыки")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Small: Now Playing

struct SmallNowPlayingView: View {
    let entry: PrismEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Source badge
            HStack {
                Spacer()
                if !entry.source.isEmpty {
                    Text(sourceLabel(entry.source))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.white.opacity(0.08)))
                }
            }

            Spacer()

            // Music icon
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Prism.gradient.opacity(0.6))
                Image(systemName: entry.isPlaying ? "waveform" : "pause.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)
            .padding(.bottom, 8)

            // Title
            Text(entry.title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)

            // Artist
            Text(entry.artist.isEmpty ? "—" : entry.artist)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func sourceLabel(_ s: String) -> String {
        switch s.lowercased() {
        case "yandex":     return "Я.Музыка"
        case "soundcloud": return "SoundCloud"
        case "spotify":    return "Spotify"
        default:           return s.capitalized
        }
    }
}

// MARK: - Medium: Idle

struct MediumIdleView: View {
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Prism.gradient)
                    .frame(width: 62, height: 62)
                    .shadow(color: Prism.purple.opacity(0.35), radius: 10)
                Image(systemName: "waveform")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("PrismMusic")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Открой меня и окунись в мир музыки")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
                    .lineSpacing(2)
                Text("Треки, плейлисты и тексты песен — всегда под рукой")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Medium: Now Playing

struct MediumNowPlayingView: View {
    let entry: PrismEntry

    var body: some View {
        HStack(spacing: 14) {
            // Left: artwork placeholder + metadata
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Prism.gradient.opacity(0.6))
                    Image(systemName: entry.isPlaying ? "waveform" : "pause.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 56, height: 56)

                Text(entry.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(entry.artist.isEmpty ? "—" : entry.artist)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)

                if !entry.source.isEmpty {
                    Text(sourceLabel(entry.source))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .frame(width: 110, alignment: .leading)

            // Divider
            RoundedRectangle(cornerRadius: 1)
                .fill(.white.opacity(0.08))
                .frame(width: 1)
                .padding(.vertical, 6)

            // Right: lyrics
            VStack(alignment: .leading, spacing: 5) {
                if !entry.lyrics.isEmpty {
                    ForEach(Array(entry.lyrics.prefix(3).enumerated()), id: \.offset) { idx, line in
                        Text(line)
                            .font(.system(size: 11, weight: idx == 0 ? .semibold : .regular))
                            .foregroundStyle(.white.opacity(idx == 0 ? 1.0 : (idx == 1 ? 0.55 : 0.3)))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Spacer(minLength: 0)
                } else {
                    Spacer()
                    Text("Текст песни отсутствует")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Включите трек с текстом.")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sourceLabel(_ s: String) -> String {
        switch s.lowercased() {
        case "yandex":     return "Я.Музыка"
        case "soundcloud": return "SoundCloud"
        case "spotify":    return "Spotify"
        default:           return s.capitalized
        }
    }
}

// MARK: - Root Widget View

struct PrismWidgetView: View {
    let entry: PrismEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                if entry.hasTrack { SmallNowPlayingView(entry: entry) }
                else              { SmallIdleView() }
            case .systemMedium:
                if entry.hasTrack { MediumNowPlayingView(entry: entry) }
                else              { MediumIdleView() }
            default:
                if entry.hasTrack { SmallNowPlayingView(entry: entry) }
                else              { SmallIdleView() }
            }
        }
    }
}

// MARK: - Widget Entry Point

@main
struct PrismMusicWidget: Widget {
    let kind = "PrismMusicWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PrismProvider()) { entry in
            PrismWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    PrismBackground()
                }
        }
        .configurationDisplayName("PrismMusic")
        .description("Текущий трек и текст песни.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
