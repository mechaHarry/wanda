import AppKit
import Metal
import simd

public struct TerminalTheme: @unchecked Sendable {
    public var foreground: NSColor
    public var background: NSColor

    public init(foreground: NSColor, background: NSColor) {
        self.foreground = foreground
        self.background = background
    }

    public static let `default` = TerminalTheme(
        foreground: NSColor(calibratedRed: 0.92, green: 0.94, blue: 0.96, alpha: 1),
        background: NSColor(calibratedRed: 0.02, green: 0.02, blue: 0.025, alpha: 1)
    )

    @MainActor
    public func resolvedBackgroundNSColor(for view: NSView) -> NSColor {
        resolvedNSColor(background, for: view)
    }

    @MainActor
    public func resolvedForegroundSIMD(for view: NSView) -> SIMD4<Float> {
        resolvedSIMD(color: resolvedNSColor(foreground, for: view))
    }

    @MainActor
    public func resolvedBackgroundSIMD(for view: NSView) -> SIMD4<Float> {
        resolvedSIMD(color: resolvedBackgroundNSColor(for: view))
    }

    @MainActor
    public func resolvedClearColor(for view: NSView) -> MTLClearColor {
        let color = resolvedRGBA(color: resolvedBackgroundNSColor(for: view))
        return MTLClearColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }

    private func resolvedSIMD(color: NSColor) -> SIMD4<Float> {
        let rgba = resolvedRGBA(color: color)
        return SIMD4<Float>(
            Float(rgba.red),
            Float(rgba.green),
            Float(rgba.blue),
            Float(rgba.alpha)
        )
    }

    private func resolvedRGBA(color: NSColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        return (rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent)
    }

    @MainActor
    private func resolvedNSColor(_ color: NSColor, for view: NSView) -> NSColor {
        var resolved = color
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.deviceRGB) ?? color
        }
        return resolved
    }
}
