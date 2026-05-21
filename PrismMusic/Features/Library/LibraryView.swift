//
//  LibraryView.swift
//  PrismMusic
//
//  Liked tracks. Empty state when nothing is liked yet. Tapping a track
//  starts playback with the entire library as the queue.
//

import SwiftUI

struct LibraryView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        NavigationStack {
            Group {
                if app.library.likedTracks.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(Color.clear)
            .navigationBarHidden(true)
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                LazyVStack(spacing: 0) {
                    ForEach(app.library.likedTracks) { track in
                        TrackRowView(
                            track: track,
                            isPlaying: app.audio.currentTrack?.id == track.id && app.audio.isPlaying,
                            onTap: {
                                if let idx = app.library.likedTracks.firstIndex(of: track) {
                                    app.audio.play(queue: app.library.likedTracks, startAt: idx)
                                }
                            },
                            onLikeToggle: { app.library.toggleLike(track) },
                            liked: true
                        )
                    }
                }
                .padding(.horizontal, Theme.Layout.screenInset)
            }
            .padding(.bottom, 140)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Медиатека")
                .font(Theme.Typography.largeTitle)
                .foregroundStyle(.white)
            Text("\(app.library.likedTracks.count) понравившихся")
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .padding(.horizontal, Theme.Layout.screenInset)
        .padding(.top, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "heart.slash")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Theme.Palette.textTertiary)
            Text("Пока пусто")
                .font(Theme.Typography.title)
                .foregroundStyle(.white)
            Text("Лайкни треки, и они появятся здесь")
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
