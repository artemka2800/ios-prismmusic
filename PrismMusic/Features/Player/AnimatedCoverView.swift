//
//  AnimatedCoverView.swift
//  PrismMusic
//
//  Apple Music-style animated album cover.
//
//  Three layered effects, all GPU-composited:
//   1. Slow looping zoom (1.0 → 1.04 → 1.0 over ~10s) — gives the cover a
//      "breathing" feel when playing. Stops on pause.
//   2. 3D parallax tied to device gyroscope via CoreMotion — the cover
//      tilts subtly as the phone moves.
//   3. Outer mesh-gradient glow tinted with the cover's dominant colour
//      (extracted by `ColorExtractor`).
//

import CoreMotion
import SwiftUI

struct AnimatedCoverView: View {
    let track: Track?
    let isPlaying: Bool
    /// Side length in points. Square aspect enforced.
    let size: CGFloat

    @State private var motion = MotionManager.shared
    @State private var dominantColor: Color = .white
    @State private var breathScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // 3 — radiant glow tinted with the cover's dominant colour
            RoundedRectangle(cornerRadius: size * 0.07, style: .continuous)
                .fill(dominantColor.opacity(0.55))
                .blur(radius: size * 0.18)
                .offset(y: size * 0.04)
                .scaleEffect(0.92)
                .opacity(isPlaying ? 0.85 : 0.4)
                .animation(.easeInOut(duration: 1.5), value: isPlaying)

            // 2 — actual artwork
            artwork
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.06, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.06, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.45), radius: 30, y: 16)
                // 1 — looping breath. Driven by `breathScale` which we
                // animate inside `.onAppear` so it survives view updates.
                .scaleEffect(breathScale)
                // 1b — gyroscope parallax. Tilt magnitude limited so the
                // effect feels alive but not distracting.
                .rotation3DEffect(
                    .degrees(motion.pitch * 4),
                    axis: (x: 1, y: 0, z: 0),
                    perspective: 0.6
                )
                .rotation3DEffect(
                    .degrees(motion.roll * 4),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.6
                )
        }
        .frame(width: size, height: size)
        .onAppear {
            startBreath()
            motion.start()
        }
        .onDisappear { motion.stop() }
        .onChange(of: isPlaying) { _, playing in
            playing ? startBreath() : stopBreath()
        }
        .task(id: track?.artworkURL) {
            // Re-extract dominant colour whenever the artwork changes.
            await refreshDominantColor()
        }
    }

    // MARK: - Artwork loader

    @ViewBuilder
    private var artwork: some View {
        if let url = track?.artworkURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    Color.black.opacity(0.6)
                case .success(let image):
                    image
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                case .failure:
                    fallback
                @unknown default:
                    fallback
                }
            }
        } else {
            fallback
        }
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [Color.white.opacity(0.08), Color.white.opacity(0.02)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: size * 0.3, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: - Breath animation

    private func startBreath() {
        guard isPlaying else { return }
        withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
            breathScale = 1.04
        }
    }

    private func stopBreath() {
        withAnimation(.easeInOut(duration: 0.6)) {
            breathScale = 1.0
        }
    }

    // MARK: - Colour extraction

    private func refreshDominantColor() async {
        guard let url = track?.artworkURL else {
            dominantColor = .white
            return
        }
        if let color = await ColorExtractor.dominantColor(from: url) {
            withAnimation(.easeInOut(duration: 0.6)) {
                dominantColor = color
            }
        }
    }
}

// MARK: - CoreMotion bridge

@MainActor
@Observable
final class MotionManager {
    static let shared = MotionManager()
    private let manager = CMMotionManager()

    /// Roll/pitch in radians, smoothed.
    private(set) var roll: Double = 0
    private(set) var pitch: Double = 0

    private var refCount = 0

    func start() {
        refCount += 1
        guard refCount == 1, manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        // Callback dispatches on the main queue, but Swift's strict
        // concurrency doesn't know that == main actor. Hop explicitly.
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let roll = motion.attitude.roll
            let pitch = motion.attitude.pitch
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Low-pass filter so the cover floats instead of vibrating.
                let alpha = 0.12
                self.roll = self.roll * (1 - alpha) + roll * alpha
                self.pitch = self.pitch * (1 - alpha) + pitch * alpha
            }
        }
    }

    func stop() {
        refCount -= 1
        if refCount <= 0 {
            refCount = 0
            manager.stopDeviceMotionUpdates()
        }
    }
}
