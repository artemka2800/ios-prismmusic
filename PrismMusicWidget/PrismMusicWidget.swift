//
//  PrismMusicWidget.swift
//  PrismMusicWidget
//
//  Widget extension for PrismMusic. Displays the currently playing track
//  info (cover art, title, artist, source badge) in the small widget, and
//  adds synced lyrics lines in the medium widget. Uses a shared App Group
//  suite to read playback state from the main app.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct MusicWidgetEntry: TimelineEntry {
    let date: Date
    let title: String
    let artist: String
    let album: String
    let source: String
    let isPlaying: Bool
    let lyricsLines: [String]
    let artworkImage: UIImage?
}

// MARK: - Timeline Provider

struct Provider: TimelineProvider {
    typealias Entry = MusicWidgetEntry

    func placeholder(in context: Context) -> MusicWidgetEntry {
        MusicWidgetEntry(
            date: Date(),
            title: "Название трека",
            artist: "Исполнитель",
            album: "Альбом",
            source: "yandex",
            isPlaying: false,
            lyricsLines: ["Первая строка текста...", "Вторая строка песни...", "Третья строка..."],
            artworkImage: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (MusicWidgetEntry) -> ()) {
        let entry = readCurrentEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<Entry>) -> ()) {
        let entry = fetchCurrentEntrySync()
        let timeline = Timeline(entries: [entry], policy: .atEnd)
        completion(timeline)
    }
    
    private func readCurrentEntry() -> MusicWidgetEntry {
        let defaults = UserDefaults.appGroup
        let title = defaults?.string(forKey: "widget.track.title") ?? "Не воспроизводится"
        let artist = defaults?.string(forKey: "widget.track.artist") ?? ""
        let album = defaults?.string(forKey: "widget.track.album") ?? ""
        let source = defaults?.string(forKey: "widget.track.source") ?? ""
        let isPlaying = defaults?.bool(forKey: "widget.track.isPlaying") ?? false
        let lyricsLines = defaults?.stringArray(forKey: "widget.track.lyricsLines") ?? []
        
        return MusicWidgetEntry(
            date: Date(),
            title: title,
            artist: artist,
            album: album,
            source: source,
            isPlaying: isPlaying,
            lyricsLines: lyricsLines,
            artworkImage: nil
        )
    }
    
    private func fetchCurrentEntrySync() -> MusicWidgetEntry {
        let defaults = UserDefaults.appGroup
        let title = defaults?.string(forKey: "widget.track.title") ?? "Не воспроизводится"
        let artist = defaults?.string(forKey: "widget.track.artist") ?? ""
        let album = defaults?.string(forKey: "widget.track.album") ?? ""
        let source = defaults?.string(forKey: "widget.track.source") ?? ""
        let isPlaying = defaults?.bool(forKey: "widget.track.isPlaying") ?? false
        let lyricsLines = defaults?.stringArray(forKey: "widget.track.lyricsLines") ?? []
        let artworkURL = defaults?.string(forKey: "widget.track.artworkURL")
        
        var artworkImage: UIImage? = nil
        if let artworkURL = artworkURL, !artworkURL.isEmpty, let url = URL(string: artworkURL) {
            let semaphore = DispatchSemaphore(value: 0)
            let session = URLSession.shared
            var request = URLRequest(url: url)
            request.timeoutInterval = 2.0 // Short timeout to avoid blocking widget extension process
            
            final class ImageBox: @unchecked Sendable {
                var image: UIImage? = nil
            }
            let box = ImageBox()
            
            let task = session.dataTask(with: request) { data, response, error in
                if let data = data {
                    box.image = UIImage(data: data)
                }
                semaphore.signal()
            }
            task.resume()
            _ = semaphore.wait(timeout: .now() + 2.0)
            artworkImage = box.image
        }
        
        return MusicWidgetEntry(
            date: Date(),
            title: title,
            artist: artist,
            album: album,
            source: source,
            isPlaying: isPlaying,
            lyricsLines: lyricsLines,
            artworkImage: artworkImage
        )
    }
}

// MARK: - Widget Views

struct SmallWidgetView: View {
    let entry: MusicWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                if let image = entry.artworkImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    fallbackArtwork(size: 56)
                }
                
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
            
            Spacer(minLength: 0)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    if entry.isPlaying {
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                
                Text(entry.artist.isEmpty ? "—" : entry.artist)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
    
    private func sourceLabel(_ src: String) -> String {
        switch src.lowercased() {
        case "yandex": return "Я.Музыка"
        case "soundcloud": return "SoundCloud"
        case "spotify": return "Spotify"
        default: return src.capitalized
        }
    }
    
    private func fallbackArtwork(size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
            Image(systemName: "music.note")
                .font(.system(size: size * 0.4))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(width: size, height: size)
    }
}

struct MediumWidgetView: View {
    let entry: MusicWidgetEntry

    var body: some View {
        HStack(spacing: 16) {
            // Left Column (Artwork + metadata)
            VStack(alignment: .leading, spacing: 8) {
                if let image = entry.artworkImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    fallbackArtwork(size: 60)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(entry.title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        
                        if entry.isPlaying {
                            Image(systemName: "speaker.wave.3.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    
                    Text(entry.artist.isEmpty ? "—" : entry.artist)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                    
                    if !entry.source.isEmpty {
                        Text(sourceLabel(entry.source))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.top, 2)
                    }
                }
            }
            .frame(width: 105, alignment: .leading)
            
            // Divider line
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.white.opacity(0.1))
                .frame(width: 1)
                .padding(.vertical, 4)
            
            // Right Column (Lyrics lines)
            VStack(alignment: .leading, spacing: 6) {
                if !entry.lyricsLines.isEmpty {
                    ForEach(Array(entry.lyricsLines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(size: 11, weight: index == 0 ? .semibold : .regular))
                            .foregroundStyle(.white.opacity(index == 0 ? 1.0 : (index == 1 ? 0.6 : 0.3)))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if entry.lyricsLines.count < 3 {
                        Spacer(minLength: 0)
                    }
                } else {
                    Spacer()
                    Text("Текст песни отсутствует")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text("Включите трек с текстом в приложении.")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func sourceLabel(_ src: String) -> String {
        switch src.lowercased() {
        case "yandex": return "Я.Музыка"
        case "soundcloud": return "SoundCloud"
        case "spotify": return "Spotify"
        default: return src.capitalized
        }
    }
    
    private func fallbackArtwork(size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
            Image(systemName: "music.note")
                .font(.system(size: size * 0.4))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(width: size, height: size)
    }
}

struct WidgetBackdrop: View {
    let image: UIImage?

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.09)
            
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 26)
                    .opacity(0.35)
            } else {
                // A beautiful soft radial gradient glow for the placeholder state
                RadialGradient(
                    colors: [
                        Color(red: 0.45, green: 0.2, blue: 0.7).opacity(0.22),
                        Color(red: 0.15, green: 0.3, blue: 0.7).opacity(0.12),
                        .clear
                    ],
                    center: .topTrailing,
                    startRadius: 5,
                    endRadius: 140
                )
            }
            
            LinearGradient(
                colors: [.black.opacity(0.2), .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

struct SmallWidgetPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            // Glowing app logo/icon representation (Prism style!)
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.65, green: 0.35, blue: 0.95), // Purple
                                Color(red: 0.25, green: 0.55, blue: 1.0),  // Blue
                                Color(red: 0.95, green: 0.25, blue: 0.65)  // Pink/Magenta
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .shadow(color: Color(red: 0.65, green: 0.35, blue: 0.95).opacity(0.45), radius: 8)
                
                Image(systemName: "music.note")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.top, 8)
            
            Text("Открой меня и\nокунись в мир музыки")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 8)
            
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
    }
}

struct MediumWidgetPlaceholderView: View {
    var body: some View {
        HStack(spacing: 16) {
            // Left side: Glowing prism logo representation
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.65, green: 0.35, blue: 0.95),
                                Color(red: 0.25, green: 0.55, blue: 1.0),
                                Color(red: 0.95, green: 0.25, blue: 0.65)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                    .shadow(color: Color(red: 0.65, green: 0.35, blue: 0.95).opacity(0.4), radius: 10)
                
                Image(systemName: "waveform")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }
            
            // Right side: Welcoming text block
            VStack(alignment: .leading, spacing: 5) {
                Text("PrismMusic")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                
                Text("Открой меня и окунись в мир музыки")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(2)
                    .lineSpacing(2)
                
                Text("Ваши треки, плейлисты и тексты песен всегда под рукой.")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MusicWidgetView: View {
    let entry: MusicWidgetEntry
    @Environment(\.widgetFamily) var family

    private var isPlaceholder: Bool {
        entry.title.isEmpty || entry.title == "Не воспроизводится"
    }

    var body: some View {
        switch family {
        case .systemSmall:
            if isPlaceholder {
                SmallWidgetPlaceholderView()
            } else {
                SmallWidgetView(entry: entry)
            }
        case .systemMedium:
            if isPlaceholder {
                MediumWidgetPlaceholderView()
            } else {
                MediumWidgetView(entry: entry)
            }
        default:
            if isPlaceholder {
                SmallWidgetPlaceholderView()
            } else {
                SmallWidgetView(entry: entry)
            }
        }
    }
}

// MARK: - Widget Main entry point

@main
struct PrismMusicWidget: Widget {
    let kind: String = "PrismMusicWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            MusicWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetBackdrop(image: entry.artworkImage)
                }
        }
        .configurationDisplayName("PrismMusic")
        .description("Виджеты «В эфире» и «Текст песни» для PrismMusic.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

extension UserDefaults {
    static var appGroup: UserDefaults? {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.prism.music.app"
        var components = bundleId.components(separatedBy: ".")
        
        let suffixesToStrip: Set<String> = [
            "widget",
            "prismmusicwidget",
            "prismmusicwidgetextension",
            "extension",
            "app"
        ]
        
        while let lastComponent = components.last?.lowercased(), suffixesToStrip.contains(lastComponent) {
            components.removeLast()
        }
        
        let appGroupId = "group." + components.joined(separator: ".")
        return UserDefaults(suiteName: appGroupId)
    }
}


