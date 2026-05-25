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
        VStack(alignment: .leading, spacing: 8) {
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
            
            Spacer(minLength: 0)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                Text(entry.artist.isEmpty ? "—" : entry.artist)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Large: Idle
struct LargeIdleView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Prism.gradient)
                        .frame(width: 52, height: 52)
                        .shadow(color: Prism.purple.opacity(0.35), radius: 10)
                    Image(systemName: "waveform")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("PrismMusic")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Музыкальный плеер")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            
            RoundedRectangle(cornerRadius: 1)
                .fill(.white.opacity(0.08))
                .frame(height: 1)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Добро пожаловать в мир звука")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                
                Text("Откройте приложение PrismMusic, выберите любимый трек или плейлист и начните прослушивание.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineSpacing(4)
            }
            
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Large: Now Playing
struct LargeNowPlayingView: View {
    let entry: PrismEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Top section: cover, title, artist
            HStack(spacing: 16) {
                if let artwork = entry.artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 76, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Prism.gradient)
                        .frame(width: 76, height: 76)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.system(size: 24))
                                .foregroundStyle(.white)
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text(entry.artist.isEmpty ? "—" : entry.artist)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            // Elegant Divider
            RoundedRectangle(cornerRadius: 1)
                .fill(.white.opacity(0.08))
                .frame(height: 1)

            // Lyrics section
            VStack(alignment: .leading, spacing: 8) {
                if !entry.lyrics.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(0..<min(7, entry.lyrics.count), id: \.self) { idx in
                            Text(entry.lyrics[idx])
                                .font(.system(size: 12, weight: idx == 0 ? .semibold : .regular, design: .rounded))
                                .foregroundStyle(idx == 0 ? Color.white : Color.white.opacity(max(0.12, 0.8 - Double(idx) * 0.12)))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Текст песни отсутствует")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                        Text("Включите трек с текстом в приложении.")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .padding(.vertical, 8)
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
            case .systemLarge:
                if entry.hasTrack { LargeNowPlayingView(entry: entry) }
                else              { LargeIdleView() }
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
        .supportedFamilies([.systemSmall, .systemLarge])
    }
}
