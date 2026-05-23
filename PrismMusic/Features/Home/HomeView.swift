//
//  HomeView.swift
//  PrismMusic
//
//  Recommendations feed matching the web main-content.tsx design:
//   - Hero banner with blurred cover crossfade + gradient
//   - 2-column grid of playlist cards with tap → fetch tracks → play
//   - Pull-to-refresh
//   - Loading states for playlist fetches
//

import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        NavigationStack {
            ZStack {
                ImmersiveBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Hero banner
                        heroBanner

                        // Content
                        switch app.recommendations.state {
                        case .idle, .loading:
                            loadingState
                        case .failed(let message):
                            errorState(message)
                        case .loaded:
                            albumGrid
                        }
                    }
                    .padding(.bottom, 140) // mini-player + tab bar room
                }
                .ignoresSafeArea(edges: .top)
                .scrollIndicators(.hidden)
                .refreshable {
                    await app.recommendations.refresh(client: app.api)
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: Album.self) { album in
                PlaylistDetailView(album: album)
            }
        }
    }

    // MARK: - Hero banner

    private var heroBanner: some View {
        ZStack(alignment: .bottomLeading) {
            // Blurred cover background
            GeometryReader { _ in
                heroCoverBackground
            }

            // Gradient overlay
            LinearGradient(
                colors: [
                    .clear,
                    app.settings.immersiveMode ? .black.opacity(0.2) : Theme.Palette.background.opacity(0.7),
                    app.settings.immersiveMode ? .black.opacity(0.5) : Theme.Palette.background
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Text content — no background, no substrate
            VStack(alignment: .leading, spacing: 6) {
                Text("PrismMusic")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Слушай подборки и любимые треки")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .padding(.horizontal, Theme.Layout.screenInset + 4)
            .padding(.bottom, 20)
        }
        .frame(height: 240)
        .clipped()
    }

    @ViewBuilder
    private var heroCoverBackground: some View {
        let coverURL = app.audio.currentTrack?.artworkURL
            ?? app.recommendations.albums.first?.cover

        if let url = coverURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 40, opaque: true)
                        .saturation(1.4)
                        .brightness(-0.15)
                        .scaleEffect(1.15)
                } else {
                    defaultHeroGradient
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .clipped()
        } else {
            defaultHeroGradient
        }
    }

    private var defaultHeroGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.15, green: 0.08, blue: 0.25),
                Theme.Palette.background
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
            Text("Загружаем подборки...")
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textSecondary)
            Button("Повторить") {
                Task { await app.recommendations.refresh(client: app.api) }
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Album grid

    private var albumGrid: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section title — no background
            Text("Подборки для вас")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Layout.screenInset)

            if app.recommendations.albums.isEmpty {
                Text("Нет подборок")
                    .font(Theme.Typography.secondary)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                // 2-column grid matching web design
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14)
                    ],
                    spacing: 18
                ) {
                    ForEach(app.recommendations.albums) { album in
                        AlbumCardView(album: album)
                    }
                }
                .padding(.horizontal, Theme.Layout.screenInset)
            }
        }
        .padding(.top, 8)
    }


}

// MARK: - Album card (matches web album-card.tsx)

struct AlbumCardView: View {
    let album: Album
    @State private var isPressed = false

    var body: some View {
        NavigationLink(value: album) {
            VStack(alignment: .leading, spacing: 8) {
                // Square cover with play overlay
                ZStack {
                    coverImage
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()

                    if isPressed {
                        Color.black.opacity(0.4)
                            .overlay {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(.white)
                                    .shadow(radius: 8)
                            }
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )

                // Title + subtitle — no background, clean text
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                    Text(album.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .buttonStyle(CardPressStyle(isPressed: $isPressed))
    }

    @ViewBuilder
    private var coverImage: some View {
        AsyncImage(url: album.artworkURL) { phase in
            if let image = phase.image {
                image.resizable()
                    .scaledToFill()
            } else if phase.error != nil {
                fallbackCover
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.04))
                    .overlay {
                        ProgressView()
                            .tint(Theme.Palette.textTertiary)
                    }
            }
        }
    }

    private var fallbackCover: some View {
        ZStack {
            LinearGradient(
                colors: [Color.white.opacity(0.08), Color.white.opacity(0.02)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}

/// Button style that tracks press state for the play overlay.
private struct CardPressStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.Motion.snap, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                isPressed = pressed
            }
    }
}
