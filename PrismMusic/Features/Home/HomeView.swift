//
//  HomeView.swift
//  PrismMusic
//
//  Recommendations feed. Hero album-card carousel up top, vertical track
//  list below. Mirrors the web `MainContent` layout.
//

import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Layout.sectionSpacing) {
                    header

                    switch app.recommendations.state {
                    case .idle, .loading:
                        loadingState
                    case .failed(let message):
                        errorState(message)
                    case .loaded:
                        loadedContent
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

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Главная")
                .font(Theme.Typography.largeTitle)
                .foregroundStyle(.white)
            Text("Подобрано для тебя")
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .padding(.horizontal, Theme.Layout.screenInset)
        .padding(.top, 12)
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
            Text("Загружаем рекомендации...")
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

    private var loadedContent: some View {
        VStack(alignment: .leading, spacing: Theme.Layout.sectionSpacing) {
            if !app.recommendations.albums.isEmpty {
                albumCarousel
            }
            tracksSection
        }
    }

    private var albumCarousel: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Новинки", subtitle: "Свежие релизы")

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(app.recommendations.albums) { album in
                        AlbumCardView(album: album) {
                            playAlbum(album)
                        }
                    }
                }
                .padding(.horizontal, Theme.Layout.screenInset)
            }
        }
    }

    private var tracksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Сейчас слушают", subtitle: "Подборка PrismMusic")

            LazyVStack(spacing: 0) {
                ForEach(app.recommendations.tracks) { track in
                    TrackRowView(
                        track: track,
                        isPlaying: app.audio.currentTrack?.id == track.id && app.audio.isPlaying,
                        onTap: { play(track) },
                        onLikeToggle: { app.library.toggleLike(track) },
                        liked: app.library.isLiked(track)
                    )
                }
            }
            .padding(.horizontal, Theme.Layout.screenInset)
        }
    }

    private func sectionTitle(_ title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Typography.title)
                .foregroundStyle(.white)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
        .padding(.horizontal, Theme.Layout.screenInset)
    }

    // MARK: - Actions

    private func play(_ track: Track) {
        // Build a queue of all visible recommendations starting from the tapped track.
        let tracks = app.recommendations.tracks
        guard let index = tracks.firstIndex(of: track) else {
            app.audio.play(queue: [track], startAt: 0)
            return
        }
        app.audio.play(queue: tracks, startAt: index)
    }

    private func playAlbum(_ album: Album) {
        if let tracks = album.tracks, !tracks.isEmpty {
            app.audio.play(queue: tracks, startAt: 0)
        }
    }
}

// MARK: - Album card

struct AlbumCardView: View {
    let album: Album
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                AsyncImage(url: album.cover) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        LinearGradient(
                            colors: [.white.opacity(0.08), .white.opacity(0.02)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
                .frame(width: 160, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 0.5)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(album.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(album.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(1)
                }
                .frame(width: 160, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}
