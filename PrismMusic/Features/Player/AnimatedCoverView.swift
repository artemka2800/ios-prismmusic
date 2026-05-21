//
//  AnimatedCoverView.swift
//  PrismMusic
//
//  Two display modes for the album cover, both GPU-composited:
//
//  1. **Standard mode** (centered square cover with effects):
//     - Slow breathing zoom (1.0→1.04→1.0)
//     - 3D gyroscope parallax via CoreMotion
//     - Dominant-colour glow with pulse
//     - Subtle random drift ±5pt
//
//  2. **Full-screen mode** (Apple Music lock screen style):
//     - Cover art fills the entire screen (scaledToFill)
//     - Slow zoom/drift animation
//     - Gyroscope parallax on the full image
//     - Strong gradient overlay for control readability
//     - Toggleable via Settings → "Анимированная обложка"
//

import CoreMotion
import SwiftUI

// MARK: - Standard centered cover (used when fullscreen mode is OFF)

struct AnimatedCoverView: View {
    let track: Track?
    let isPlaying: Bool
    /// Side length in points. Square aspect enforced.
    let size: CGFloat
    /// Whether animated effects (drift, breath, parallax) are enabled.
    var animatedCoverEnabled: Bool = true

    @State private var motion = MotionManager.shared
    @State private var dominantColor: Color = .white
    @State private var breathScale: CGFloat = 1.0
    @State private var driftOffset: CGSize = .zero
    @State private var glowPulse: Double = 0.55

    var body: some View {
        ZStack {
            // Radiant glow tinted with the cover's dominant colour
            RoundedRectangle(cornerRadius: size * 0.07, style: .continuous)
                .fill(dominantColor.opacity(glowPulse))
                .blur(radius: size * 0.20)
                .offset(y: size * 0.04)
                .scaleEffect(0.92)
                .animation(.easeInOut(duration: 1.5), value: isPlaying)

            // Actual artwork
            artwork
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.06, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.06, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(
                    color: .black.opacity(isPlaying ? 0.45 : 0.15),
                    radius: isPlaying ? 30 : 15,
                    y: isPlaying ? 16 : 8
                )
                .scaleEffect(breathScale * (isPlaying ? 1.0 : 0.82))
                .animation(.spring(response: 0.6, dampingFraction: 0.7), value: isPlaying)
                .offset(driftOffset)
                .rotation3DEffect(
                    .degrees(animatedCoverEnabled ? motion.pitch * 4 : 0),
                    axis: (x: 1, y: 0, z: 0),
                    perspective: 0.6
                )
                .rotation3DEffect(
                    .degrees(animatedCoverEnabled ? motion.roll * 4 : 0),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.6
                )
        }
        .frame(width: size, height: size)
        .onAppear {
            if animatedCoverEnabled {
                startBreath()
                startDrift()
                startGlowPulse()
                motion.start()
            }
        }
        .onDisappear {
            if animatedCoverEnabled { motion.stop() }
        }
        .onChange(of: isPlaying) { _, playing in
            guard animatedCoverEnabled else { return }
            playing ? startBreath() : stopBreath()
            playing ? startGlowPulse() : stopGlowPulse()
        }
        .onChange(of: animatedCoverEnabled) { _, enabled in
            if enabled {
                startBreath(); startDrift(); startGlowPulse(); motion.start()
            } else {
                stopBreath(); stopDrift(); stopGlowPulse(); motion.stop()
            }
        }
        .task(id: track?.artworkURL) {
            await refreshDominantColor()
        }
    }

    // MARK: - Artwork loader

    @ViewBuilder
    private var artwork: some View {
        if let url = track?.artworkURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty: Color.black.opacity(0.6)
                case .success(let image):
                    image.resizable().interpolation(.high).scaledToFill()
                case .failure: fallback
                @unknown default: fallback
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
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: size * 0.3, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: - Animations

    private func startBreath() {
        guard isPlaying, animatedCoverEnabled else { return }
        withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
            breathScale = 1.04
        }
    }
    private func stopBreath() {
        withAnimation(.easeInOut(duration: 0.6)) { breathScale = 1.0 }
    }

    private func startDrift() {
        guard animatedCoverEnabled else { return }
        driftToRandomPoint()
    }
    private func stopDrift() {
        withAnimation(.easeInOut(duration: 1.0)) { driftOffset = .zero }
    }
    private func driftToRandomPoint() {
        guard animatedCoverEnabled else { return }
        let maxDrift: CGFloat = 5.0
        withAnimation(.easeInOut(duration: CGFloat.random(in: 6...9))) {
            driftOffset = CGSize(
                width: CGFloat.random(in: -maxDrift...maxDrift),
                height: CGFloat.random(in: -maxDrift...maxDrift)
            )
        }
        Task {
            try? await Task.sleep(nanoseconds: UInt64.random(in: 6_000_000_000...9_000_000_000))
            guard !Task.isCancelled else { return }
            driftToRandomPoint()
        }
    }

    private func startGlowPulse() {
        guard isPlaying, animatedCoverEnabled else { return }
        withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
            glowPulse = 0.85
        }
    }
    private func stopGlowPulse() {
        withAnimation(.easeInOut(duration: 0.8)) { glowPulse = 0.4 }
    }

    private func refreshDominantColor() async {
        guard let url = track?.artworkURL else { dominantColor = .white; return }
        if let color = await ColorExtractor.dominantColor(from: url) {
            withAnimation(.easeInOut(duration: 0.6)) { dominantColor = color }
        }
    }
}

// MARK: - Full-screen animated cover (Apple Music lock screen style)

struct FullScreenAnimatedCover: View {
    let track: Track?
    let isPlaying: Bool

    @State private var motion = MotionManager.shared
    @State private var breathScale: CGFloat = 1.0
    @State private var driftOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Full-screen cover image
                if let url = track?.artworkURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            Theme.Palette.background
                        case .success(let image):
                            image
                                .resizable()
                                .interpolation(.high)
                                .scaledToFill()
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .clipped()
                        case .failure:
                            Theme.Palette.background
                        @unknown default:
                            Theme.Palette.background
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(breathScale * 1.15) // slight over-scale to hide edges during drift
                    .offset(driftOffset)
                    .rotation3DEffect(
                        .degrees(motion.pitch * 3),
                        axis: (x: 1, y: 0, z: 0),
                        perspective: 0.4
                    )
                    .rotation3DEffect(
                        .degrees(motion.roll * 3),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.4
                    )
                } else {
                    Theme.Palette.background
                }

                // Gradient overlays for readability
                VStack(spacing: 0) {
                    // Top gradient — darker at very top for status bar
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.65), location: 0),
                            .init(color: .black.opacity(0.25), location: 0.5),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: proxy.size.height * 0.3)

                    Spacer()

                    // Bottom gradient — stronger for controls
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.4), location: 0.25),
                            .init(color: .black.opacity(0.85), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: proxy.size.height * 0.55)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            startBreath()
            startDrift()
            motion.start()
        }
        .onDisappear {
            motion.stop()
        }
        .onChange(of: isPlaying) { _, playing in
            playing ? startBreath() : stopBreath()
        }
    }

    // MARK: - Animations

    private func startBreath() {
        guard isPlaying else { return }
        withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
            breathScale = 1.06
        }
    }
    private func stopBreath() {
        withAnimation(.easeInOut(duration: 1.0)) { breathScale = 1.0 }
    }

    private func startDrift() {
        driftToRandomPoint()
    }
    private func driftToRandomPoint() {
        let maxDrift: CGFloat = 12.0
        withAnimation(.easeInOut(duration: CGFloat.random(in: 8...14))) {
            driftOffset = CGSize(
                width: CGFloat.random(in: -maxDrift...maxDrift),
                height: CGFloat.random(in: -maxDrift...maxDrift)
            )
        }
        Task {
            try? await Task.sleep(nanoseconds: UInt64.random(in: 8_000_000_000...14_000_000_000))
            guard !Task.isCancelled else { return }
            driftToRandomPoint()
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
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let roll = motion.attitude.roll
            let pitch = motion.attitude.pitch
            Task { @MainActor [weak self] in
                guard let self else { return }
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
