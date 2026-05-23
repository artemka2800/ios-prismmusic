//
//  APIConfig.swift
//  PrismMusic
//
//  ONE place to edit when you change the backend host. The user can also
//  override this at runtime from the Settings screen.
//

import Foundation

enum APIConfig {
    /// Default PrismMusic backend URL.
    ///
    /// Replace this with your deployed Next.js URL (e.g. `https://prism.example.com`).
    /// For local development on macOS while running `pnpm dev`, set this to
    /// `http://YOUR_MAC_LAN_IP:3000` (the simulator can't reach `localhost`
    /// from a physical device).
    static let defaultBackendURL = "https://prism-music-one.vercel.app"

    /// Request timeout for all API calls in seconds.
    static let timeoutSeconds: TimeInterval = 20

    /// Max bytes of body to log to console for failed requests.
    static let errorBodyLogLimit = 2_048
}
