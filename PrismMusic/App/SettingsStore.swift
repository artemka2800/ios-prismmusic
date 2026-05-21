//
//  SettingsStore.swift
//  PrismMusic
//
//  Lightweight persistence for user-configurable values: backend URL, Yandex
//  Music token, immersive mode toggle. Stored in `UserDefaults` (cheap, no
//  dependency on Core Data / SwiftData). The Yandex token is sensitive so
//  it lives in the Keychain — see `KeychainStore`.
//

import Foundation
import Observation

@Observable
@MainActor
final class SettingsStore {
    // MARK: - Backend

    /// URL of the PrismMusic Next.js backend. Edit `defaultBackendURL` in
    /// `APIConfig.swift` to ship a different default. The user can also
    /// override it from the Settings screen.
    var backendURL: String {
        didSet {
            UserDefaults.standard.set(backendURL, forKey: Keys.backendURL)
        }
    }

    // MARK: - Yandex token

    /// Yandex.Music OAuth token. Stored in Keychain, not UserDefaults.
    /// Required to play Yandex-sourced tracks; SoundCloud works without it.
    var yandexToken: String {
        didSet { KeychainStore.set(yandexToken, for: Keys.yandexToken) }
    }

    // MARK: - UI

    /// Whether the immersive (full-bleed, cover-tinted) background is on.
    var immersiveMode: Bool {
        didSet {
            UserDefaults.standard.set(immersiveMode, forKey: Keys.immersiveMode)
        }
    }

    // MARK: - Init

    init() {
        let storedURL = UserDefaults.standard.string(forKey: Keys.backendURL) ?? ""
        self.backendURL = storedURL.isEmpty ? APIConfig.defaultBackendURL : storedURL
        self.yandexToken = KeychainStore.get(Keys.yandexToken) ?? ""
        self.immersiveMode = UserDefaults.standard.object(forKey: Keys.immersiveMode) as? Bool ?? true
    }

    private enum Keys {
        static let backendURL = "prism.backendURL"
        static let yandexToken = "prism.yandexToken"
        static let immersiveMode = "prism.immersive"
    }
}
