//
//  PrismMusicLiveActivityWidget.swift
//  PrismMusicLiveActivity
//
//  The single ActivityConfiguration that drives:
//   - lock-screen / banner Live Activity card
//   - Dynamic Island compact (small left/right slots)
//   - Dynamic Island minimal (single-icon when multiple activities are active)
//   - Dynamic Island expanded (full card when long-pressed)
//
//  We render four variants from one source of truth (`LiveActivityState`).
//

import ActivityKit
import SwiftUI
import WidgetKit

struct PrismMusicLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivityAttributes.self) { context in
            // Lock-screen + banner presentation.
            LockScreenLiveActivityView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded: rendered when the user long-presses the island.
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedLeading(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailing(state: context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    ExpandedCenter(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottom(state: context.state)
                }
            } compactLeading: {
                CompactLeading(state: context.state)
            } compactTrailing: {
                CompactTrailing(state: context.state)
            } minimal: {
                MinimalView(state: context.state)
            }
            .keylineTint(.white)
        }
    }
}

// MARK: - Lock-screen card

private struct LockScreenLiveActivityView: View {
    let state: LiveActivityState

    var body: some View {
        HStack(spacing: 12) {
            Artwork(url: state.artworkURL, size: 60)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(state.title.isEmpty ? "PrismMusic" : state.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(state.artist)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)

                ProgressBar(fraction: state.fraction)
                    .frame(height: 3)
                    .padding(.top, 4)
            }

            Spacer()

            Image(systemName: state.isPlaying ? "waveform" : "pause.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: state.isPlaying)
                .frame(width: 36, height: 36)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }
}

// MARK: - Dynamic Island — compact

private struct CompactLeading: View {
    let state: LiveActivityState

    var body: some View {
        Artwork(url: state.artworkURL, size: 22)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

private struct CompactTrailing: View {
    let state: LiveActivityState

    /// Two-character glyph that conveys playback state at a glance:
    /// playing → animated waveform; paused → pause glyph.
    var body: some View {
        Image(systemName: state.isPlaying ? "waveform" : "pause.fill")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: state.isPlaying)
    }
}

private struct MinimalView: View {
    let state: LiveActivityState

    var body: some View {
        Image(systemName: state.isPlaying ? "music.note" : "pause.fill")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
    }
}

// MARK: - Dynamic Island — expanded

private struct ExpandedLeading: View {
    let state: LiveActivityState

    var body: some View {
        Artwork(url: state.artworkURL, size: 50)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ExpandedTrailing: View {
    let state: LiveActivityState

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(state.remainingLabel)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
                .monospacedDigit()
            Image(systemName: state.isPlaying ? "waveform" : "pause.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: state.isPlaying)
        }
    }
}

private struct ExpandedCenter: View {
    let state: LiveActivityState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(state.title.isEmpty ? "PrismMusic" : state.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(state.artist)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ExpandedBottom: View {
    let state: LiveActivityState

    var body: some View {
        ProgressBar(fraction: state.fraction)
            .frame(height: 3)
            .padding(.top, 6)
    }
}

// MARK: - Shared subviews

private struct Artwork: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        ZStack {
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [.white.opacity(0.18), .white.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: size * 0.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

private struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(Color.white)
                    .frame(width: max(0, proxy.size.width * fraction))
            }
        }
    }
}
