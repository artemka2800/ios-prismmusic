//
//  NowPlayingView.swift
//  PrismMusic
//
//  Full-screen player. Same composition as the web `FullScreenPlayer`:
//   - top bar (close + "Сейчас играет" label)
//   - animated cover in the centre
//   - track info (source / title / artist) with smooth crossfade on track change
//   - progress slider + time labels
//   - playback controls (shuffle / prev / play-pause / next / repeat)
//   - secondary actions (like, lyrics, queue, volume, share, more)
//   - lyrics panel that slides out from behind the cover when lyrics enabled
//

import SwiftUI

struct NowPlayingView: View {
    @Environment(AppState.self) private var app
    @Binding var isPresented: Bool

    enum Panel: Equatable { case none, lyrics, queue }
    @State private var panel: Panel = .none

    var body: some View {
        ZStack {
            // Cover-tinted backdrop fills the whole screen.
            Backdrop()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 8)

                Spacer(minLength: 12)

                GeometryReader { proxy in
                    let coverSize = min(proxy.size.width, proxy.size.height) * 0.85
                    HStack(alignment: .center, spacing: 16) {
                        AnimatedCoverView(
                            track: app.audio.currentTrack,
                            isPlaying: app.audio.isPlaying,
                            size: coverSize
                        )
                        .id(app.audio.currentTrack?.id)   // forces motion reset on change

                        if panel == .lyrics {
                            SyncedLyricsView(
                                lyrics: app.audio.lyrics,
                                progress: app.audio.progress,
                                duration: app.audio.duration,
                                isPlaying: app.audio.isPlaying,
                                onSeek: { app.audio.seek(to: $0) }
                            )
                            .frame(width: coverSize)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(Theme.Motion.appleLong, value: panel)
                }
                .frame(maxHeight: .infinity)

                trackInfo
                    .padding(.horizontal, Theme.Layout.screenInset)
                    .padding(.top, 16)

                progress
                    .padding(.horizontal, Theme.Layout.screenInset)
                    .padding(.top, 18)

                playbackControls
                    .padding(.top, 14)

                actionRow
                    .padding(.top, 18)
                    .padding(.horizontal, Theme.Layout.screenInset)
                    .padding(.bottom, 28)
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button {
                isPresented = false
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(GlassCircleButtonStyle())

            Spacer()

            VStack(spacing: 2) {
                Text("Сейчас играет")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(Theme.Palette.textTertiary)
                Text(app.audio.currentTrack?.album ?? app.audio.currentTrack?.title ?? "—")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                    .id(app.audio.currentTrack?.id)
                    .transition(.opacity)
            }
            .animation(Theme.Motion.apple, value: app.audio.currentTrack?.id)

            Spacer()

            Button {} label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(GlassCircleButtonStyle())
        }
        .padding(.horizontal, Theme.Layout.screenInset)
    }

    // MARK: - Track info

    private var trackInfo: some View {
        VStack(spacing: 4) {
            if let source = app.audio.currentTrack?.source {
                Text(source.label)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .padding(.bottom, 4)
            }
            Text(app.audio.currentTrack?.title ?? "Ничего не выбрано")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)

            Text(app.audio.currentTrack?.artist ?? "Выбери трек из библиотеки")
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textSecondary)
                .lineLimit(1)
        }
        .id(app.audio.currentTrack?.id)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .animation(Theme.Motion.apple, value: app.audio.currentTrack?.id)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Progress

    private var progress: some View {
        VStack(spacing: 6) {
            ProgressSlider(
                value: app.audio.progress,
                duration: app.audio.duration,
                onSeek: { app.audio.seek(to: $0) }
            )
            HStack {
                Text(formatTime(app.audio.progress))
                Spacer()
                Text(formatTime(app.audio.duration))
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.Palette.textTertiary)
            .monospacedDigit()
        }
    }

    // MARK: - Playback controls

    private var playbackControls: some View {
        HStack(spacing: 28) {
            iconButton(
                "shuffle",
                tinted: app.audio.isShuffled,
                action: app.audio.toggleShuffle
            )

            iconButton("backward.fill", size: 28, action: app.audio.previous)

            Button(action: app.audio.togglePlay) {
                Image(systemName: app.audio.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .bold))
                    .frame(width: 76, height: 76)
                    .foregroundStyle(.black)
                    .background(
                        Circle()
                            .fill(.white)
                            .shadow(color: .white.opacity(0.25), radius: 22)
                    )
            }
            .buttonStyle(.plain)
            .scaleEffect(app.audio.isPlaying ? 1 : 0.94)
            .animation(Theme.Motion.snap, value: app.audio.isPlaying)

            iconButton("forward.fill", size: 28, action: app.audio.next)

            iconButton(
                repeatIcon,
                tinted: app.audio.repeatMode != .off,
                action: app.audio.toggleRepeat
            )
        }
    }

    private var repeatIcon: String {
        switch app.audio.repeatMode {
        case .off, .all: "repeat"
        case .one: "repeat.1"
        }
    }

    private func iconButton(_ symbol: String, size: CGFloat = 22, tinted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 50, height: 50)
                .foregroundStyle(tinted ? Color.white : Theme.Palette.textSecondary)
        }
        .buttonStyle(.plain)
        .contentTransition(.symbolEffect(.replace))
    }

    // MARK: - Secondary actions

    private var actionRow: some View {
        HStack {
            ForEach(actionButtons, id: \.symbol) { item in
                Spacer()
                Button(action: item.action) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(item.tinted ? Color.white : Theme.Palette.textSecondary)
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
    }

    private var actionButtons: [ActionItem] {
        let liked = app.audio.currentTrack.map(app.library.isLiked) ?? false
        return [
            ActionItem(symbol: liked ? "heart.fill" : "heart", tinted: liked, action: app.audio.toggleLike),
            ActionItem(symbol: "text.alignleft", tinted: panel == .lyrics, action: { togglePanel(.lyrics) }),
            ActionItem(symbol: "list.bullet", tinted: panel == .queue, action: { togglePanel(.queue) }),
            ActionItem(symbol: app.audio.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", action: app.audio.toggleMute),
            ActionItem(symbol: "moon.zzz", action: {}),
            ActionItem(symbol: "square.and.arrow.up", action: {}),
        ]
    }

    private struct ActionItem {
        let symbol: String
        var tinted: Bool = false
        let action: () -> Void
    }

    private func togglePanel(_ target: Panel) {
        withAnimation(Theme.Motion.appleLong) {
            panel = (panel == target) ? .none : target
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Cover-tinted backdrop

private struct Backdrop: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ZStack {
            Theme.Palette.background

            if let url = app.audio.currentTrack?.artworkURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .blur(radius: 80, opaque: true)
                            .saturation(1.4)
                            .opacity(0.7)
                            .scaleEffect(1.4)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipped()
            }

            LinearGradient(
                colors: [.black.opacity(0.45), .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

// MARK: - Glass circle button style

struct GlassCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .prismGlassCircle()
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(Theme.Motion.snap, value: configuration.isPressed)
    }
}

// MARK: - Custom progress slider with rounded thumb

private struct ProgressSlider: View {
    let value: Double
    let duration: Double
    let onSeek: (Double) -> Void

    @State private var dragValue: Double?

    var body: some View {
        GeometryReader { proxy in
            let frac: Double = {
                let v = dragValue ?? value
                guard duration > 0 else { return 0 }
                return max(0, min(1, v / duration))
            }()
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: 4)

                Capsule()
                    .fill(Color.white)
                    .frame(width: max(0, proxy.size.width * frac), height: 4)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard duration > 0 else { return }
                        let frac = max(0, min(1, gesture.location.x / proxy.size.width))
                        dragValue = frac * duration
                    }
                    .onEnded { _ in
                        if let dragValue { onSeek(dragValue) }
                        dragValue = nil
                    }
            )
        }
        .frame(height: 18)
    }
}
