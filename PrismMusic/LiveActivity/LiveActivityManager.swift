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

    /// Defer creation of ActivityAuthorizationInfo until we actually need it.
    /// Creating it synchronously during app launch (before applicationDidFinishLaunching)
    /// causes a severe crash on iOS because activityd rejects the XPC connection.
    private var authorizationInfo: ActivityAuthorizationInfo?

    /// Safety switch to completely disable Live Activities.
    /// Default to false on Simulator to avoid system environment crashes.
    #if targetEnvironment(simulator)
    public static var isEnabled = false
    #else
    public static var isEnabled = true
    #endif

    init() {
        guard Self.isEnabled else { return }
        // Clean up any dangling activities from previous app sessions immediately.
        // Failing to do this causes ActivityKit to hit the 5-activity limit
        // and throw a fatal exception when `Activity.request` is called.
        Task {
            for existing in Activity<LiveActivityAttributes>.activities {
                await existing.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private var canUseLiveActivities: Bool {
        guard Self.isEnabled else { return false }
        if authorizationInfo == nil {
            authorizationInfo = ActivityAuthorizationInfo()
        }
        return authorizationInfo?.areActivitiesEnabled ?? false
    }

    /// Start a fresh Live Activity for the given track. If one is already
    /// running we replace its content state instead of spawning a new one
    /// (a stale activity would otherwise linger in the Dynamic Island).
    func start(track: Track, state: LiveActivityState) {
        guard canUseLiveActivities else { return }

        if activity != nil {
            update(state: state)
            return
        }

        let attributes = LiveActivityAttributes()
        do {
            let content = ActivityContent(state: state, staleDate: nil)
            activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil   // we update locally; no APNs required
            )
        } catch {
            print("[LiveActivity] failed to start: \(error)")
            // Soft-fail: if the system still rejects the request, we just catch
            // and log it instead of letting the app crash.
        }
    }

    /// Push a new content state to the existing activity.
    func update(state: LiveActivityState) {
        guard canUseLiveActivities, let activity else { return }
        Task {
            await activity.update(
                ActivityContent(state: state, staleDate: nil)
            )
        }
    }

    /// Terminate the activity (called when the queue ends or the user
    /// dismisses Now Playing).
    func end() {
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
