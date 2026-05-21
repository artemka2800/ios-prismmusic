//
//  LiveActivityManager.swift
//  PrismMusic
//
//  Owns the lifecycle of the Live Activity that powers Dynamic Island and
//  the lock-screen Now Playing card. The widget UI lives in
//  `PrismMusicLiveActivity/LiveActivityViews.swift`.
//

import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager {
    /// Single in-flight activity at a time (one track playing = one activity).
    private var activity: Activity<LiveActivityAttributes>?

    /// Start a fresh Live Activity for the given track. If one is already
    /// running we replace its content state instead of spawning a new one
    /// (a stale activity would otherwise linger in the Dynamic Island).
    func start(track: Track, state: LiveActivityState) {
        // Activities are only available on iOS 16.1+, and the user must have
        // them enabled in Settings → Notifications.
        guard #available(iOS 16.1, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        if activity != nil {
            update(state: state)
            return
        }

        let attributes = LiveActivityAttributes()
        do {
            let content: ActivityContent<LiveActivityAttributes.ContentState>
            content = ActivityContent(state: state, staleDate: nil)
            activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil   // we update locally; no APNs required
            )
        } catch {
            print("[LiveActivity] failed to start: \(error)")
        }
    }

    /// Push a new content state to the existing activity.
    func update(state: LiveActivityState) {
        guard #available(iOS 16.1, *) else { return }
        guard let activity else { return }
        Task {
            await activity.update(
                ActivityContent(state: state, staleDate: nil)
            )
        }
    }

    /// Terminate the activity (called when the queue ends or the user
    /// dismisses Now Playing).
    func end() {
        guard #available(iOS 16.1, *) else { return }
        guard let activity else { return }
        Task {
            await activity.end(
                ActivityContent(
                    state: activity.content.state,
                    staleDate: .now
                ),
                dismissalPolicy: .immediate
            )
            self.activity = nil
        }
    }
}
