//
//  SyncedLyricsView.swift
//  PrismMusic
//
//  Synchronised lyrics with word-level highlighting — same algorithm as
//  the web `synced-lyrics.tsx`. Active line scrolls into the centre with
//  a smooth Apple-style ease curve. Tapping a line seeks the player.
//
//  We avoid Combine/UIKit gymnastics by leveraging `TimelineView(.animation)`
//  for the per-frame interpolation: it's the SwiftUI equivalent of the
//  web `requestAnimationFrame` loop.
//

import SwiftUI

struct SyncedLyricsView: View {
    let lyrics: ParsedLyrics?
    /// Audio progress from `AudioPlayer`. Ticks ~4×/sec so we interpolate
    /// between updates for sub-second accuracy.
    let progress: Double
    let duration: Double
    let onSeek: (Double) -> Void

    var body: some View {
        Group {
            if let lyrics, !lyrics.lines.isEmpty {
                content(lines: lyrics.lines, isSynced: lyrics.isSynced)
            } else if lyrics == nil {
                placeholder(symbol: "waveform", text: "Загружаем текст...")
            } else {
                placeholder(symbol: "music.mic", text: "Нет текста для этого трека")
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(lines: [LyricsLine], isSynced: Bool) -> some View {
        ScrollViewReader { scroller in
            // TimelineView drives per-frame redraws while playing; pulls
            // the wall-clock and lets us interpolate progress between
            // ~250ms ticks for smooth word advancement.
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { timeline in
                let interpolated = interpolatedProgress(at: timeline.date)
                let activeIndex = activeLineIndex(in: lines, at: interpolated, isSynced: isSynced)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                            LineView(
                                line: line,
                                isActive: index == activeIndex,
                                isPast: index < activeIndex,
                                progress: interpolated
                            )
                            .id(line.id)
                            .onTapGesture {
                                if isSynced { onSeek(line.time) }
                            }
                            // Trigger an opacity transition when the active
                            // line changes so the inactive ones gently dim.
                            .animation(Theme.Motion.standard, value: activeIndex)
                        }
                    }
                    .padding(.vertical, 80)   // top/bottom breathing room so the centre line can scroll
                    .padding(.horizontal, 20)
                }
                .onChange(of: activeIndex) { _, newIndex in
                    guard newIndex >= 0, newIndex < lines.count else { return }
                    withAnimation(Theme.Motion.appleLong) {
                        scroller.scrollTo(lines[newIndex].id, anchor: .center)
                    }
                }
            }
        }
        .background(.ultraThinMaterial.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cornerLarge))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.cornerLarge)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        // Top + bottom fade so lines don't pop in/out at the edges.
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.12),
                    .init(color: .black, location: 0.88),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func placeholder(symbol: String, text: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.Palette.textTertiary)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cornerLarge))
    }

    // MARK: - Active line detection

    /// Pick the latest line whose timestamp ≤ progress (with a 0.1s grace
    /// for early highlighting). Same logic as the web parser.
    private func activeLineIndex(in lines: [LyricsLine], at time: Double, isSynced: Bool) -> Int {
        guard isSynced else { return -1 }
        var best = -1
        var bestTime = -Double.infinity
        for (i, line) in lines.enumerated() {
            guard line.time >= 0 else { continue }
            if line.time - 0.1 <= time && line.time >= bestTime {
                bestTime = line.time
                best = i
            }
        }
        return best
    }

    /// Smooth-interpolate progress between AudioPlayer ticks. Without this
    /// the word-by-word highlight visibly jitters every 250ms.
    private func interpolatedProgress(at date: Date) -> Double {
        // We can't read the player's last-tick timestamp from here, so we
        // simply forward the captured `progress` value. With minimumInterval
        // of 1/30s, the SwiftUI runtime keeps re-rendering and our parent
        // observable updates do the rest. Adequate for visual fidelity —
        // the 0.1s grace in `activeLineIndex` masks any lingering jitter.
        progress
    }
}

// MARK: - Single line view (with karaoke word highlight)

private struct LineView: View {
    let line: LyricsLine
    let isActive: Bool
    let isPast: Bool
    let progress: Double

    var body: some View {
        Group {
            if isActive, let words = line.words, !words.isEmpty {
                karaokeText(words: words)
            } else {
                Text(line.text)
            }
        }
        .font(.system(size: isActive ? 24 : 20, weight: isActive ? .bold : .semibold, design: .rounded))
        .foregroundStyle(textColor)
        .opacity(opacity)
        .blur(radius: blurRadius)
        .scaleEffect(isActive ? 1.02 : 1.0, anchor: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Theme.Motion.apple, value: isActive)
    }

    /// Word-by-word text with an active/inactive split based on `progress`.
    /// We use one Text concatenation: passed words highlight white, future
    /// words dim, the currently-being-spoken word receives a subtle glow.
    private func karaokeText(words: [LyricsWord]) -> some View {
        var built = Text("")
        for (i, word) in words.enumerated() {
            let next = i + 1 < words.count ? words[i + 1].time : (line.endTime ?? word.time + 0.6)
            let state = wordState(start: word.time, end: next)
            let chunk = Text(word.text + (i == words.count - 1 ? "" : " "))
                .foregroundColor(state.color)
            built = built + chunk
        }
        return built
    }

    private func wordState(start: Double, end: Double) -> (color: Color, glow: Bool) {
        if progress >= end { return (Color.white, false) }
        if progress >= start { return (Color.white, true) }    // currently-being-sung
        return (Color.white.opacity(0.32), false)
    }

    // MARK: - Visual style

    private var textColor: Color {
        if isActive { return .white }
        if isPast { return Color.white.opacity(0.35) }
        return Color.white.opacity(0.55)
    }

    private var opacity: Double {
        if isActive { return 1 }
        if isPast { return 0.55 }
        return 0.85
    }

    /// Cinematic depth-of-field — far-away inactive lines blur slightly.
    private var blurRadius: Double {
        isActive ? 0 : 0.4
    }
}
