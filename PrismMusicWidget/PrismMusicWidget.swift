//
//  PrismMusicWidget.swift
//  PrismMusicWidget
//
//  Bulletproof WidgetKit extension for PrismMusic with Async Image Loading.
//  Shows current track info, live artwork from URL, and sync lyrics when playing.
//

import WidgetKit
import SwiftUI
import Security

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
    let progress: Double
    let duration: Double
    let lastUpdated: Double

    var hasTrack: Bool {
        !title.isEmpty && title != "idle" && title != "Не воспроизводится"
    }

    static let idle = PrismEntry(
        date: .now, title: "idle", artist: "", source: "",
        isPlaying: false, lyrics: [], artwork: nil,
        progress: 0, duration: 0, lastUpdated: Date.now.timeIntervalSince1970
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
        var title       = ""
        var artist      = ""
        var source      = ""
        var playing     = false
        var lyrics      = [String]()
        var artworkURL  = ""
        var progress    = 0.0
        var duration    = 0.0
        var lastUpdated = Date.now.timeIntervalSince1970
        var hasLoadedState = false
        
        // Try reading from Keychain first (works on free developer accounts where App Groups are blocked)
        if let jsonString = KeychainHelper.get("widget.track.state"),
           let jsonData = jsonString.data(using: .utf8),
           let state = try? JSONDecoder().decode(WidgetTrackState.self, from: jsonData) {
            
            title       = state.title
            artist      = state.artist
            source      = state.source
            playing     = state.isPlaying
            lyrics      = state.lyricsLines
            artworkURL  = state.artworkURL
            progress    = state.progress
            duration    = state.duration
            lastUpdated = state.lastUpdated
            hasLoadedState = true
        }
        
        // Fallback to UserDefaults if Keychain is empty or unavailable
        if !hasLoadedState {
            let defaults = UserDefaults.appGroup ?? .standard
            title       = defaults.string(forKey: "widget.track.title") ?? ""
            artist      = defaults.string(forKey: "widget.track.artist") ?? ""
            source      = defaults.string(forKey: "widget.track.source") ?? ""
            playing     = defaults.bool(forKey: "widget.track.isPlaying")
            lyrics      = defaults.stringArray(forKey: "widget.track.lyricsLines") ?? []
            artworkURL  = defaults.string(forKey: "widget.track.artworkURL") ?? ""
            progress    = defaults.double(forKey: "widget.track.progress")
            duration    = defaults.double(forKey: "widget.track.duration")
            lastUpdated = defaults.double(forKey: "widget.track.lastUpdated")
        }

        if title.isEmpty || title == "idle" || title == "Не воспроизводится" {
            return .idle
        }

        var image: UIImage? = nil
        if !artworkURL.isEmpty, let url = URL(string: artworkURL) {
            do {
                let config = URLSessionConfiguration.default
                config.timeoutIntervalForRequest = 3.0
                config.timeoutIntervalForResource = 3.0
                let session = URLSession(configuration: config)
                let (data, _) = try await session.data(from: url)
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
            artwork: image,
            progress: progress,
            duration: duration,
            lastUpdated: lastUpdated
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
        .unredacted()
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

// MARK: - Medium: Idle
struct MediumIdleView: View {
    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Prism.gradient)
                    .frame(width: 80, height: 80)
                    .shadow(color: Prism.purple.opacity(0.35), radius: 10)
                Image(systemName: "waveform")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("PrismMusic")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                
                Text("Добро пожаловать в мир звука")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                
                Text("Откройте приложение и включите любимый трек.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .unredacted()
    }
}

// MARK: - Medium: Now Playing
struct MediumNowPlayingView: View {
    let entry: PrismEntry

    var body: some View {
        HStack(spacing: 16) {
            // Left Side: Artwork
            if let artwork = entry.artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 108, height: 108)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.45), radius: 8, y: 4)
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Prism.gradient)
                    .frame(width: 108, height: 108)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 32))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: Prism.purple.opacity(0.3), radius: 8, y: 4)
            }
            
            // Right Side: Info & Controls representation
            VStack(alignment: .leading, spacing: 6) {
                // Pill Badge
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: entry.isPlaying ? "play.fill" : "pause.fill")
                            .font(.system(size: 8))
                        Text(entry.isPlaying ? "ВОСПРОИЗВЕДЕНИЕ" : "ПАУЗА")
                            .font(.system(size: 8, weight: .black))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
                    .foregroundStyle(.white.opacity(0.8))
                    
                    Spacer()
                    
                    if !entry.source.isEmpty {
                        Text(entry.source.uppercased())
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                
                Spacer(minLength: 2)
                
                // Title and Artist
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    Text(entry.artist.isEmpty ? "—" : entry.artist)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                
                Spacer(minLength: 4)
                
                // Live Progress bar
                let startDate = Date(timeIntervalSince1970: entry.lastUpdated - entry.progress)
                let endDate = Date(timeIntervalSince1970: entry.lastUpdated - entry.progress + entry.duration)
                let isProgressValid = entry.duration > 0 && entry.progress <= entry.duration
                
                if entry.isPlaying && isProgressValid {
                    ProgressView(timerInterval: startDate...endDate, countsDown: false, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                        .tint(Prism.gradient)
                        .scaleEffect(x: 1.0, y: 0.8, anchor: .center)
                } else {
                    ProgressView(value: min(entry.progress, entry.duration), total: max(entry.duration, 1))
                        .tint(.white.opacity(0.3))
                        .scaleEffect(x: 1.0, y: 0.8, anchor: .center)
                }
                
                // Time stamps
                HStack {
                    Text(formatTime(entry.progress))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                    Spacer()
                    Text(formatTime(entry.duration))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
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
        .description("Текущий трек, обложка и прогресс воспроизведения.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Keychain Helper for Sideloading
enum KeychainHelper {
    private static var accessGroup: String? {
        if let prefix = appIdentifierPrefix {
            return "\(prefix).com.prism.music"
        }
        return nil
    }

    private static var appIdentifierPrefix: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "bundleSeedID",
            kSecAttrService as String: "bundleSeedID",
            kSecReturnAttributes as String: true
        ]
        var result: CFTypeRef?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: "bundleSeedID",
                kSecAttrService as String: "bundleSeedID",
                kSecValueData as String: "dummy".data(using: .utf8)!
            ]
            SecItemAdd(addQuery as CFDictionary, nil)
            status = SecItemCopyMatching(query as CFDictionary, &result)
        }
        if status == errSecSuccess,
           let dict = result as? [String: Any],
           let accessGroup = dict[kSecAttrAccessGroup as String] as? String {
            let components = accessGroup.components(separatedBy: ".")
            if !components.isEmpty {
                return components[0]
            }
        }
        return nil
    }

    static func get(_ key: String) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.prism.music",
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let accessGroup = self.accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

struct WidgetTrackState: Codable {
    let title: String
    let artist: String
    let source: String
    let isPlaying: Bool
    let lyricsLines: [String]
    let artworkURL: String
    let progress: Double
    let duration: Double
    let lastUpdated: Double
}
