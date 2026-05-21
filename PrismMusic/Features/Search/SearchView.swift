//
//  SearchView.swift
//  PrismMusic
//
//  Debounced search across all sources (Yandex + SoundCloud). Empty state
//  shows recent queries (TODO) and suggestions; results render as a flat
//  list of tracks plus an albums carousel when present.
//

import SwiftUI

struct SearchView: View {
    @Environment(AppState.self) private var app
    @State private var query: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField

                Divider()
                    .background(Color.white.opacity(0.06))
                    .padding(.top, 4)

                content
            }
            .background(Color.clear)
            .navigationBarHidden(true)
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Palette.textTertiary)

            TextField("Поиск треков, альбомов, артистов", text: $query)
                .textFieldStyle(.plain)
                .focused($fieldFocused)
                .submitLabel(.search)
                .foregroundStyle(.white)
                .tint(.white)
                .onChange(of: query) { _, newValue in
                    app.search.update(query: newValue, client: app.api)
                }

            if !query.isEmpty {
                Button {
                    query = ""
                    app.search.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .prismGlass(cornerRadius: 12)
        .padding(.horizontal, Theme.Layout.screenInset)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        switch app.search.state {
        case .idle:
            idleState
        case .searching:
            VStack(spacing: 12) {
                ProgressView().tint(.white)
                Text("Ищем «\(app.search.query)»...")
                    .font(Theme.Typography.secondary)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .results(let tracks, let albums):
            if tracks.isEmpty && albums.isEmpty {
                emptyState
            } else {
                resultsList(tracks: tracks, albums: albums)
            }

        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(Theme.Typography.secondary)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var idleState: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Theme.Palette.textTertiary)
            Text("Найди свои треки")
                .font(Theme.Typography.title)
                .foregroundStyle(.white)
            Text("Поиск работает по Я.Музыке и SoundCloud")
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.Palette.textTertiary)
            Text("Ничего не найдено по запросу «\(app.search.query)»")
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resultsList(tracks: [Track], albums: [Album]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !albums.isEmpty {
                    Text("Альбомы")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .padding(.horizontal, Theme.Layout.screenInset)
                        .padding(.top, 8)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 14) {
                            ForEach(albums) { album in
                                AlbumCardView(album: album) {
                                    if let first = album.tracks?.first {
                                        app.audio.play(queue: album.tracks ?? [first], startAt: 0)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, Theme.Layout.screenInset)
                    }
                }

                if !tracks.isEmpty {
                    Text("Треки")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .padding(.horizontal, Theme.Layout.screenInset)
                        .padding(.top, albums.isEmpty ? 8 : 4)

                    LazyVStack(spacing: 0) {
                        ForEach(tracks) { track in
                            TrackRowView(
                                track: track,
                                isPlaying: app.audio.currentTrack?.id == track.id && app.audio.isPlaying,
                                onTap: {
                                    if let idx = tracks.firstIndex(of: track) {
                                        app.audio.play(queue: tracks, startAt: idx)
                                    }
                                },
                                onLikeToggle: { app.library.toggleLike(track) },
                                liked: app.library.isLiked(track)
                            )
                        }
                    }
                    .padding(.horizontal, Theme.Layout.screenInset)
                }
            }
            .padding(.bottom, 140)
        }
        .scrollIndicators(.hidden)
    }
}
