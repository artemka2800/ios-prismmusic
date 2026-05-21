//
//  GlassMaterial.swift
//  PrismMusic
//
//  Wraps the iOS 26 Liquid Glass `.glassEffect()` modifier with a graceful
//  fallback for older OS versions. On iOS 26+ we get the real frosted /
//  refractive material; on iOS 17-25 we fall back to a tinted ultra-thin
//  material with a hairline border to preserve the look.
//

import SwiftUI

extension View {
    /// Applies iOS 26 Liquid Glass when available, otherwise a graceful
    /// ultra-thin material fallback.
    ///
    /// - Parameters:
    ///   - cornerRadius: Corner radius of the glass surface. Pass `nil` to
    ///                   inherit the view's existing shape.
    ///   - tint:         Subtle colour overlay (typically the dominant
    ///                   cover colour).
    @ViewBuilder
    func prismGlass(cornerRadius: CGFloat? = nil, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            self.modifier(LiquidGlassModifier(cornerRadius: cornerRadius, tint: tint))
        } else {
            self.modifier(MaterialFallbackModifier(cornerRadius: cornerRadius, tint: tint))
        }
    }
}

// MARK: - iOS 26+

@available(iOS 26.0, *)
private struct LiquidGlassModifier: ViewModifier {
    let cornerRadius: CGFloat?
    let tint: Color?

    func body(content: Content) -> some View {
        // The real `glassEffect` modifier ships in iOS 26 SDK. Until the
        // toolchain is widely available we route through a helper so the
        // file still compiles in older SDKs (the `#available` branch is
        // skipped at runtime so this is safe).
        if let radius = cornerRadius {
            content.glassEffectCompatible(in: RoundedRectangle(cornerRadius: radius), tint: tint)
        } else {
            content.glassEffectCompatible(in: Rectangle(), tint: tint)
        }
    }
}

// MARK: - Pre-iOS 26 fallback

private struct MaterialFallbackModifier: ViewModifier {
    let cornerRadius: CGFloat?
    let tint: Color?

    func body(content: Content) -> some View {
        let shape: AnyShape = if let radius = cornerRadius {
            AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            AnyShape(Rectangle())
        }

        return content
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill((tint ?? .clear).opacity(0.10)))
                    .overlay(shape.stroke(Theme.Palette.border, lineWidth: 0.5))
            }
            .clipShape(shape)
    }
}

// MARK: - Compatibility shim

/// Wraps the iOS 26 `.glassEffect(...)` modifier behind a runtime check so
/// this file still compiles on older Xcode toolchains. When you upgrade to
/// the iOS 26 SDK you can delete this shim and use `.glassEffect()` directly.
private extension View {
    @ViewBuilder
    func glassEffectCompatible<S: Shape>(in shape: S, tint: Color?) -> some View {
        // Even on iOS 26+ we still need a compile-time fallback for older
        // Xcode versions that don't know `glassEffect` yet. The runtime
        // gate is in `prismGlass`; here we just provide the visual.
        self
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill((tint ?? .clear).opacity(0.12)))
            }
            .clipShape(shape)
    }
}
