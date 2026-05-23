//
//  PrismMusicWidget.swift
//  PrismMusicWidget
//
//  Bulletproof WidgetKit extension for PrismMusic with Async Image Loading.
//  Shows current track info, live artwork from URL, and sync lyrics when playing.
//

import WidgetKit
import SwiftUI

// MARK: - App Group UserDefaults Helper
extension UserDefaults {
    static var appGroup: UserDefaults? {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.prism.music"
        var components = bundleId.components(separatedBy: ".")
        if let last = components.last, last.lowercased().contains("widget") || last.lowercased().contains("activity") {
            components.removeLast()
        }
        let baseId = components.joined(separator: ".")
        let groupName = "group.\(baseId)"
        return UserDefaults(suiteName: groupName)
    }
}

// MARK: - Timeline Entry
struct PrismEntry: TimelineEntry {
    let date: Date
    let title: String
    let artist: String
    let source: String
    let isPlaying: Bool
    let lyrics: [String]
    let artwork: UIImage? // Prefetched artwork image

    var hasTrack: Bool {
        !title.isEmpty && title != "idle" && title != "Не воспроизводится"
    }

    static let idle = PrismEntry(
        date: .now, title: "idle", artist: "", source: "",
        isPlaying: false, lyrics: [], artwork: nil
    )
}

// MARK: - Timeline Provider
struct PrismProvider: TimelineProvider {

    func placeholder(in context: Context) -> PrismEntry {
        .idle
    }

    func getSnapshot(in context: Context,
                     completion: @escaping @Sendable (PrismEntry) -> Void) {
        Task {
            let entry = await fetchEntry()
            completion(entry)
        }
    }

    func getTimeline(in context: Context,
                     completion: @escaping @Sendable (Timeline<PrismEntry>) -> Void) {
        Task {
            let entry = await fetchEntry()
            // Widgets update when app notifies via WidgetCenter, but we refresh every 15 min as a fallback.
            let next = Calendar.current.date(byAdding: .minute, value: 15, to: entry.date)!
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    // Fetches widget data + downloads artwork image asynchronously
    private func fetchEntry() async -> PrismEntry {
        let defaults = UserDefaults.appGroup ?? .standard

        let title      = defaults.string(forKey: "widget.track.title") ?? ""
        let artist     = defaults.string(forKey: "widget.track.artist") ?? ""
        let source     = defaults.string(forKey: "widget.track.source") ?? ""
        let playing    = defaults.bool(forKey: "widget.track.isPlaying")
        let lyrics     = defaults.stringArray(forKey: "widget.track.lyricsLines") ?? []
        let artworkURL = defaults.string(forKey: "widget.track.artworkURL") ?? ""

        if title.isEmpty || title == "idle" || title == "Не воспроизводится" {
            return .idle
        }

        var image: UIImage? = nil
        if !artworkURL.isEmpty, let url = URL(string: artworkURL) {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                image = UIImage(data: data)
            } catch {
                print("[PrismWidget] Failed to load artwork from \(artworkURL): \(error)")
            }
        }

        return PrismEntry(
            date: .now,
            title: title,
            artist: artist,
            source: source,
            isPlaying: playing,
            lyrics: lyrics,
            artwork: image
        )
    }
}

// MARK: - Colors & Gradients
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

// MARK: - Widget Background
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
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Prism.gradient)
                    .frame(width: 40, height: 40)
                    .shadow(color: Prism.purple.opacity(0.4), radius: 8)
                Image(systemName: "music.note")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.top, 4)

            VStack(spacing: 4) {
                Text("PrismMusic")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                
                Text("Открой меня и окунись в мир музыки")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .lineSpacing(1.5)
            }
            
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Small: Now Playing
struct SmallNowPlayingView: View {
    let entry: PrismEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                if let artwork = entry.artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Prism.gradient)
                        .frame(width: 52, height: 52)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.system(size: 18))
                                .foregroundStyle(.white)
                        }
                }
                
                Spacer()
                
                // Play / Pause status badge
                Image(systemName: entry.isPlaying ? "waveform" : "pause.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(entry.isPlaying ? Prism.purple : .white.opacity(0.4))
                    .padding(6)
                    .background(Circle().fill(.white.opacity(0.06)))
            }
            
            Spacer()
            
            Text(entry.title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
            
            Text(entry.artist.isEmpty ? "—" : entry.artist)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Medium: Idle
struct MediumIdleView: View {
    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Prism.gradient)
                    .frame(width: 68, height: 68)
                    .shadow(color: Prism.purple.opacity(0.35), radius: 10)
                Image(systemName: "waveform")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("PrismMusic")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
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
        HStack(spacing: 16) {
            // Left: metadata & cover
            VStack(alignment: .leading, spacing: 6) {
                if let artwork = entry.artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Prism.gradient)
                        .frame(width: 60, height: 60)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.system(size: 20))
                                .foregroundStyle(.white)
                        }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    Text(entry.artist.isEmpty ? "—" : entry.artist)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                
                if !entry.source.isEmpty {
                    Text(sourceLabel(entry.source))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3.5)
                        .background(Capsule().fill(.white.opacity(0.08)))
                }
            }
            .frame(width: 110, alignment: .leading)
            
            // Vertical Divider
            RoundedRectangle(cornerRadius: 1)
                .fill(.white.opacity(0.08))
                .frame(width: 1)
                .padding(.vertical, 6)
            
            // Right: lyrics
            VStack(alignment: .leading, spacing: 6) {
                if !entry.lyrics.isEmpty {
                    ForEach(0..<min(3, entry.lyrics.count), id: \.self) { idx in
                        let line = entry.lyrics[idx]
                        Text(line)
                            .font(.system(size: 11, weight: idx == 0 ? .semibold : .regular))
                            .foregroundStyle(.white.opacity(idx == 0 ? 1.0 : (idx == 1 ? 0.6 : 0.35)))
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
        .description("Текущий трек, обложка и текст песни.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
