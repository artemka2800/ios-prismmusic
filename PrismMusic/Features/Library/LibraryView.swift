//
//  LibraryView.swift
//  PrismMusic
//
//  Liked tracks and user custom playlists with grid presentation.
//
import SwiftUI

struct LibraryView: View {
    @Environment(AppState.self) private var app

    enum LibraryTab: String, CaseIterable, Identifiable {
        case favorites = "Избранное"
        case playlists = "Плейлисты"
        var id: String { self.rawValue }
    }

    @State private var activeTab: LibraryTab = .favorites
    @State private var isShowingCreateDialog = false
    @State private var newPlaylistName = ""
    @State private var newPlaylistDescription = ""

    private var tracksToDisplay: [Track] {
        if !app.networkMonitor.isConnected {
            return app.library.likedTracks.filter { app.downloadStore.isDownloaded($0.id) }
        } else {
            return app.library.likedTracks
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ImmersiveBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headerSection
                        
                        pickerSection
                        
                        if activeTab == .favorites {
                            favoritesSection
                        } else {
                            playlistsSection
                        }
                    }
                    .padding(.bottom, 140)
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    await app.library.syncWithServer()
                }
            }
            .navigationBarHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .alert("Новый плейлист", isPresented: $isShowingCreateDialog) {
                TextField("Название", text: $newPlaylistName)
                TextField("Описание (необязательно)", text: $newPlaylistDescription)
                Button("Создать") {
                    let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let desc = newPlaylistDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        Task {
                            _ = await app.library.createPlaylist(name: name, description: desc)
                        }
                    }
                    newPlaylistName = ""
                    newPlaylistDescription = ""
                }
                Button("Отмена", role: .cancel) {
                    newPlaylistName = ""
                    newPlaylistDescription = ""
                }
            }
        }
    }

    private var headerSection: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Медиатека")
                    .font(Theme.Typography.largeTitle)
                    .foregroundStyle(.white)
                
                if activeTab == .favorites {
                    if !app.networkMonitor.isConnected {
                        Text("Скачано \(tracksToDisplay.count) треков (офлайн)")
                            .font(Theme.Typography.secondary)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    } else {
                        Text("\(app.library.likedTracks.count) понравившихся")
                            .font(Theme.Typography.secondary)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                } else {
                    Text(app.settings.isLoggedIn ? "\(app.library.playlists.count) плейлистов" : "Личные плейлисты")
                        .font(Theme.Typography.secondary)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            
            Spacer()
            
            if activeTab == .playlists && app.settings.isLoggedIn {
                Button {
                    isShowingCreateDialog = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 38, height: 38)
                        .foregroundStyle(.white)
                        .background(.white.opacity(0.08), in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Layout.screenInset)
        .padding(.top, 56)
    }

    private var pickerSection: some View {
        HStack(spacing: 12) {
            ForEach(LibraryTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                        activeTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .foregroundStyle(activeTab == tab ? .black : .white)
                        .background(
                            activeTab == tab ? Color.white : Color.white.opacity(0.06),
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .stroke(activeTab == tab ? Color.clear : Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Layout.screenInset)
    }

    private var favoritesSection: some View {
        Group {
            if tracksToDisplay.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(tracksToDisplay) { track in
                        TrackRowView(
                            track: track,
                            isPlaying: app.audio.currentTrack?.id == track.id && app.audio.isPlaying,
                            onTap: {
                                if let idx = tracksToDisplay.firstIndex(of: track) {
                                    app.audio.play(queue: tracksToDisplay, startAt: idx)
                                }
                            },
                            onLikeToggle: { app.library.toggleLike(track) },
                            liked: true
                        )
                    }
                }
                .padding(.horizontal, Theme.Layout.screenInset)
            }
        }
    }

    private var playlistsSection: some View {
        Group {
            if !app.settings.isLoggedIn {
                guestPlaylistsView
            } else if app.library.playlists.isEmpty {
                emptyPlaylistsState
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    ForEach(app.library.playlists) { playlist in
                        NavigationLink {
                            PlaylistDetailView(album: playlist)
                        } label: {
                            PlaylistGridCard(playlist: playlist)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                Task {
                                    await app.library.deletePlaylist(playlist)
                                }
                            } label: {
                                Label("Удалить плейлист", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Layout.screenInset)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: !app.networkMonitor.isConnected ? "wifi.slash" : "heart.slash")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Theme.Palette.textTertiary)
            Text(!app.networkMonitor.isConnected ? "Нет скачанных треков" : "Пока пусто")
                .font(Theme.Typography.title)
                .foregroundStyle(.white)
            Text(!app.networkMonitor.isConnected ? "Скачайте треки в настройках, чтобы слушать их офлайн" : "Лайкни треки, и они появятся здесь")
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 36)
        .padding(.top, 60)
    }

    private var guestPlaylistsView: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Theme.Palette.textTertiary)
            Text("Вход не выполнен")
                .font(Theme.Typography.title)
                .foregroundStyle(.white)
            Text("Войдите в аккаунт, чтобы создавать персональные плейлисты и синхронизировать их между вашими устройствами")
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 36)
        .padding(.top, 60)
    }

    private var emptyPlaylistsState: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Theme.Palette.textTertiary)
            Text("Нет плейлистов")
                .font(Theme.Typography.title)
                .foregroundStyle(.white)
            Text("У вас пока нет созданных плейлистов. Нажмите «+» вверху, чтобы создать свой первый плейлист")
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 36)
        .padding(.top, 60)
    }
}

struct PlaylistGridCard: View {
    let playlist: Album

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Artwork cover
            ZStack {
                AsyncImage(url: playlist.artworkURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            LinearGradient(
                                colors: [Color.white.opacity(0.08), Color.white.opacity(0.02)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: "music.note.list")
                                .font(.system(size: 32, weight: .light))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                }
                .frame(width: (UIScreen.main.bounds.width - 48 - 16) / 2, height: (UIScreen.main.bounds.width - 48 - 16) / 2)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                Text(playlist.artist) // Displays description
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
        }
        .padding(8)
        .prismGlass(cornerRadius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }
}
