//
//  HomeView.swift
//  PrismMusic
//
//  Recommendations feed matching the web main-content.tsx design:
//   - Top tab bar: "Главная" / "Новое и горячее"
//   - Hero banner with blurred cover crossfade + gradient
//   - 2-column grid of album/playlist cards
//   - Pull-to-refresh
//

import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var app
    @State private var activeTab: HomeTab = .home

    enum HomeTab { case home, hot }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Tab bar
                    tabBar
                        .padding(.top, 8)

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
            .scrollIndicators(.hidden)
            .background(Color.clear)
            .refreshable {
                await app.recommendations.refresh(client: app.api)
            }
            .navigationBarHidden(true)
        }
    }

    // MARK: - Display albums

    private var displayedAlbums: [Album] {
        let all = app.recommendations.albums
        switch activeTab {
        case .home:
            return Array(all.prefix(12))
        case .hot:
            return all.count > 12 ? Array(all.dropFirst(12).prefix(12)) : Array(all.suffix(max(0, all.count - 6)))
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton("Главная", tab: .home)
            tabButton("Новое и горячее", tab: .hot)
            Spacer()
        }
        .padding(.horizontal, Theme.Layout.screenInset)
    }

    private func tabButton(_ title: String, tab: HomeTab) -> some View {
        Button {
            withAnimation(Theme.Motion.standard) {
                activeTab = tab
            }
        } label: {
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(activeTab == tab ? .white : Theme.Palette.textTertiary)

                Rectangle()
                    .fill(activeTab == tab ? Color.white : Color.clear)
                    .frame(height: 2)
            }
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
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
                colors: [.clear, Theme.Palette.background.opacity(0.6), Theme.Palette.background],
                startPoint: .top,
                endPoint: .bottom
            )

            // Text content
            VStack(alignment: .leading, spacing: 8) {
                Text("Добро пожаловать в PrismMusic")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Открывай новую музыку, слушай подборки и любимые треки")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, Theme.Layout.screenInset + 4)
            .padding(.bottom, 20)
        }
        .frame(height: 220)
        .clipped()
    }

    @ViewBuilder
    private var heroCoverBackground: some View {
        let coverURL = app.audio.currentTrack?.artworkURL
            ?? displayedAlbums.first?.cover

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
            // Section title
            Text(activeTab == .home ? "Выбор редакции" : "Сейчас в тренде")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Layout.screenInset)

            if displayedAlbums.isEmpty {
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
                    ForEach(displayedAlbums) { album in
                        AlbumCardView(album: album) {
                            playAlbum(album)
                        }
                    }
                }
                .padding(.horizontal, Theme.Layout.screenInset)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func playAlbum(_ album: Album) {
        if let tracks = album.tracks, !tracks.isEmpty {
            app.audio.play(queue: tracks, startAt: 0)
        }
    }
}

// MARK: - Album card (matches web album-card.tsx)

struct AlbumCardView: View {
    let album: Album
    let onTap: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Square cover with play overlay
                ZStack {
                    AsyncImage(url: album.cover) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else if phase.error != nil {
                            fallbackCover
                        } else {
                            // Loading
                            Rectangle()
                                .fill(Color.white.opacity(0.04))
                                .overlay {
                                    ProgressView()
                                        .tint(Theme.Palette.textTertiary)
                                }
                        }
                    }
                    .aspectRatio(1, contentMode: .fill)
                    .clipped()

                    // Play overlay on press
                    if isPressed {
                        Color.black.opacity(0.4)
                            .overlay {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 28, weight: .bold))
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

                // Title + artist — no background, clean text
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(album.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(CardPressStyle(isPressed: $isPressed))
    }

    private var fallbackCover: some View {
        ZStack {
            LinearGradient(
                colors: [Color.white.opacity(0.08), Color.white.opacity(0.02)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: 32, weight: .medium))
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
