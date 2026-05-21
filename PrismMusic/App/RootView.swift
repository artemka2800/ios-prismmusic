//
//  RootView.swift
//  PrismMusic
//
//  Top-level layout: tab navigation + persistent mini-player overlay +
//  fullscreen Now Playing presented modally. Same composition pattern as
//  the Next.js web app (`app/page.tsx`).
//

import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var app
    @State private var nowPlayingPresented = false

    var body: some View {
        ZStack {
            // Cover-tinted immersive background (web parity)
            ImmersiveBackground()
                .ignoresSafeArea()

            TabRoot()

            // Mini player docks above the tab bar. Tapping it opens the
            // full Now Playing modal.
            VStack {
                Spacer()
                if app.audio.currentTrack != nil {
                    MiniPlayerView(onExpand: { nowPlayingPresented = true })
                        .padding(.horizontal, 12)
                        .padding(.bottom, 56)   // sits above standard tab bar height
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(Theme.Motion.apple, value: app.audio.currentTrack?.id)
        }
        .fullScreenCover(isPresented: $nowPlayingPresented) {
            NowPlayingView(isPresented: $nowPlayingPresented)
                .environment(app)
        }
    }
}

/// Subtle blurred cover that fills the entire screen behind everything.
/// When immersive mode is off, falls back to a flat dark gradient.
private struct ImmersiveBackground: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ZStack {
            // Base canvas — always present so transitions don't flash.
            Theme.Palette.background

            if app.settings.immersiveMode, let url = app.audio.currentTrack?.artworkURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .blur(radius: 60, opaque: true)
                            .opacity(0.55)
                            .saturation(1.2)
                            // Subtle slow drift so the background feels alive.
                            .scaleEffect(1.15)
                            .animation(.easeInOut(duration: 0.8), value: url)
                    }
                }
                // Vignette + dark gradient overlay to keep foreground readable.
                LinearGradient(
                    colors: [.black.opacity(0.55), .black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                LinearGradient(
                    colors: [
                        Theme.Palette.background,
                        Color(red: 0.07, green: 0.07, blue: 0.10),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }
}
