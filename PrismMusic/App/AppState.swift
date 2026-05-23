//
//  AppState.swift
//  PrismMusic
//
//  Root state container. Holds everything that has to outlive a single view:
//   - audio (AVPlayer + Now Playing + Live Activity orchestration)
//   - API client (single instance, reads backend URL from UserDefaults)
//   - library (liked tracks)
//   - recommendations cache (loaded once at app start)
//   - settings (backend URL, Yandex token, immersive mode)
//
//  Wired into the SwiftUI environment by `PrismMusicApp` so any view can
//  pull it via `@Environment(AppState.self)`.s
//

import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    let settings: SettingsStore
    let api: APIClient
    let audio: AudioPlayer
    let library: LibraryStore
    let recommendations: RecommendationsStore
    let search: SearchStore

    init() {
        let settings = SettingsStore()
        let api = APIClient(settings: settings)
        let library = LibraryStore(api: api, settings: settings)
        self.settings = settings
        self.api = api
        self.library = library
        self.recommendations = RecommendationsStore()
        self.search = SearchStore()
        self.audio = AudioPlayer(api: api, library: library)
    }
}
