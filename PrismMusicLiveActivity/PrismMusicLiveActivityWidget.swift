//
//  PrismMusicLiveActivityWidget.swift
//  PrismMusicLiveActivity
//
//  Standard music player Dynamic Island + lock-screen Live Activity.
//  Compact, clean design matching Apple Music / Spotify conventions:
//   - Compact: cover art (leading) + waveform/pause icon (trailing)
//   - Expanded: cover + title/artist + progress bar
//   - Lock screen: full now-playing card with cover, info, progress
//

import ActivityKit
import SwiftUI
import WidgetKit

struct PrismMusicLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivityAttributes.self) { context in
            // Lock-screen + banner presentation.
            LockScreenView(state: context.state)
                .activityBackgroundTint(.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded regions
                DynamicIslandExpandedRegion(.leading) {
                    CoverArt(url: context.state.artworkURL, size: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.title.isEmpty ? "PrismMusic" : context.state.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(context.state.artist)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.remainingLabel)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressStrip(fraction: context.state.fraction)
                        .frame(height: 3)
                        .padding(.top, 4)
                }
            } compactLeading: {
                // Small cover art
                CoverArt(url: context.state.artworkURL, size: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } compactTrailing: {
                // Waveform (playing) or pause icon
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: context.state.isPlaying)
            } minimal: {
                // Single icon when multiple activities
                Image(systemName: context.state.isPlaying ? "music.note" : "pause.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            .keylineTint(.white.opacity(0.3))
        }
    }
}

// MARK: - Lock-screen card

private struct LockScreenView: View {
    let state: LiveActivityState

    var body: some View {
        HStack(spacing: 12) {
            CoverArt(url: state.artworkURL, size: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(state.title.isEmpty ? "PrismMusic" : state.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(state.artist)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)

                ProgressStrip(fraction: state.fraction)
                    .frame(height: 3)
                    .padding(.top, 4)
            }

            Spacer(minLength: 4)

            Image(systemName: state.isPlaying ? "waveform" : "pause.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: state.isPlaying)
                .frame(width: 32, height: 32)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Shared components

private struct CoverArt: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [.white.opacity(0.15), .white.opacity(0.03)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: size * 0.45, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}

private struct ProgressStrip: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: max(0, proxy.size.width * fraction))
            }
        }
    }
}
