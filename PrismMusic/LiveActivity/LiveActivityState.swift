//
//  LiveActivityState.swift
//  PrismMusic
//
//  ActivityKit attributes shared between the main app and the Live Activity
//  widget extension. Both targets compile this file via `project.yml`.
//
//  Anatomy:
//    - `LiveActivityAttributes` is the FIXED part of an Activity — set once
//      when the activity starts. We don't really need fixed fields (track
//      info changes when the user skips), so this is just an empty marker
//      keeping the API contract.
//    - `LiveActivityState` (nested ContentState) is the MUTABLE part. We
//      push it on every play/pause/seek/track-change.
//

import ActivityKit
import Foundation

struct LiveActivityAttributes: ActivityAttributes {
    public typealias PrismLiveState = ContentState

    public struct ContentState: Codable, Hashable {
        var title: String
        var artist: String
        var artworkURL: URL?
        var isPlaying: Bool
        /// Current playback position (seconds).
        var progress: Double
        /// Total track duration (seconds).
        var duration: Double

        /// Convenience: progress as a 0...1 fraction, clamped.
        var fraction: Double {
            guard duration.isFinite, progress.isFinite, duration > 0 else { return 0 }
            return max(0, min(1, progress / duration))
        }

        /// Convenience: m:ss remaining.
        var remainingLabel: String {
            guard duration.isFinite, progress.isFinite, duration > 0 else { return "—" }
            let remaining = max(0, duration - progress)
            guard remaining.isFinite else { return "—" }
            let m = Int(remaining) / 60
            let s = Int(remaining) % 60
            return String(format: "-%d:%02d", m, s)
        }
    }
}

/// Typealias kept for readability in app code.
typealias LiveActivityState = LiveActivityAttributes.ContentState
