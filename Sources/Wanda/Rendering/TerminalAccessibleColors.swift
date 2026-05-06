import Foundation
import simd

enum TerminalAccessibleColors {
    static let minimumTextContrastRatio = 4.5
    static let pureBlack = SIMD4<Float>(0.00, 0.00, 0.00, 1.00)
    static let defaultForeground = SIMD4<Float>(0.94, 0.94, 0.94, 1.00)

    static var ansiColorCount: Int {
        ansiForegroundPalette.count
    }

    static func foregroundColor(for color: TerminalColor, defaultColor: SIMD4<Float>) -> SIMD4<Float> {
        switch color {
        case .default:
            return accessibleForeground(defaultColor)
        case .ansi(let index):
            let paletteIndex = Int(index)
            guard paletteIndex < ansiForegroundPalette.count else {
                return accessibleForeground(defaultColor)
            }

            return ansiForegroundPalette[paletteIndex]
        case .rgb(let red, let green, let blue):
            return accessibleForeground(
                SIMD4<Float>(
                    Float(red) / 255,
                    Float(green) / 255,
                    Float(blue) / 255,
                    1
                )
            )
        }
    }

    static func backgroundColor(for color: TerminalColor, defaultColor: SIMD4<Float>) -> SIMD4<Float> {
        switch color {
        case .default:
            return defaultColor
        case .ansi(let index):
            let paletteIndex = Int(index)
            guard paletteIndex < ansiBackgroundPalette.count else {
                return defaultColor
            }

            return ansiBackgroundPalette[paletteIndex]
        case .rgb(let red, let green, let blue):
            return SIMD4<Float>(
                Float(red) / 255,
                Float(green) / 255,
                Float(blue) / 255,
                1
            )
        }
    }

    static func contrastRatio(foreground: SIMD4<Float>, background: SIMD4<Float>) -> Double {
        let foregroundLuminance = relativeLuminance(foreground)
        let backgroundLuminance = relativeLuminance(background)
        let lighter = max(foregroundLuminance, backgroundLuminance)
        let darker = min(foregroundLuminance, backgroundLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func accessibleForeground(
        _ color: SIMD4<Float>,
        background: SIMD4<Float> = pureBlack
    ) -> SIMD4<Float> {
        guard contrastRatio(foreground: color, background: background) < minimumTextContrastRatio else {
            return color
        }

        var lower: Float = 0
        var upper: Float = 1
        var lifted = color

        for _ in 0..<16 {
            let midpoint = (lower + upper) / 2
            lifted = mix(color, SIMD4<Float>(1, 1, 1, color.w), t: midpoint)

            if contrastRatio(foreground: lifted, background: background) >= minimumTextContrastRatio {
                upper = midpoint
            } else {
                lower = midpoint
            }
        }

        return mix(color, SIMD4<Float>(1, 1, 1, color.w), t: upper)
    }

    private static func mix(_ color: SIMD4<Float>, _ target: SIMD4<Float>, t: Float) -> SIMD4<Float> {
        SIMD4<Float>(
            color.x + (target.x - color.x) * t,
            color.y + (target.y - color.y) * t,
            color.z + (target.z - color.z) * t,
            color.w
        )
    }

    private static func relativeLuminance(_ color: SIMD4<Float>) -> Double {
        let red = linearComponent(Double(color.x))
        let green = linearComponent(Double(color.y))
        let blue = linearComponent(Double(color.z))
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    private static func linearComponent(_ component: Double) -> Double {
        let clamped = min(max(component, 0), 1)
        if clamped <= 0.03928 {
            return clamped / 12.92
        }

        return pow((clamped + 0.055) / 1.055, 2.4)
    }

    private static let ansiForegroundPalette: [SIMD4<Float>] = [
        SIMD4<Float>(0.48, 0.48, 0.48, 1.00),
        SIMD4<Float>(1.00, 0.37, 0.37, 1.00),
        SIMD4<Float>(0.00, 0.84, 0.37, 1.00),
        SIMD4<Float>(0.84, 0.84, 0.37, 1.00),
        SIMD4<Float>(0.37, 0.53, 1.00, 1.00),
        SIMD4<Float>(1.00, 0.37, 1.00, 1.00),
        SIMD4<Float>(0.00, 0.84, 0.84, 1.00),
        SIMD4<Float>(0.86, 0.86, 0.86, 1.00),
        SIMD4<Float>(0.54, 0.54, 0.54, 1.00),
        SIMD4<Float>(1.00, 0.53, 0.53, 1.00),
        SIMD4<Float>(0.37, 1.00, 0.53, 1.00),
        SIMD4<Float>(1.00, 1.00, 0.53, 1.00),
        SIMD4<Float>(0.53, 0.69, 1.00, 1.00),
        SIMD4<Float>(1.00, 0.53, 1.00, 1.00),
        SIMD4<Float>(0.37, 1.00, 1.00, 1.00),
        SIMD4<Float>(1.00, 1.00, 1.00, 1.00)
    ]

    private static let ansiBackgroundPalette: [SIMD4<Float>] = [
        SIMD4<Float>(0.00, 0.00, 0.00, 1.00),
        SIMD4<Float>(0.80, 0.00, 0.00, 1.00),
        SIMD4<Float>(0.00, 0.80, 0.00, 1.00),
        SIMD4<Float>(0.80, 0.80, 0.00, 1.00),
        SIMD4<Float>(0.00, 0.00, 0.80, 1.00),
        SIMD4<Float>(0.80, 0.00, 0.80, 1.00),
        SIMD4<Float>(0.00, 0.80, 0.80, 1.00),
        SIMD4<Float>(0.86, 0.86, 0.86, 1.00),
        SIMD4<Float>(0.33, 0.33, 0.33, 1.00),
        SIMD4<Float>(1.00, 0.33, 0.33, 1.00),
        SIMD4<Float>(0.33, 1.00, 0.33, 1.00),
        SIMD4<Float>(1.00, 1.00, 0.33, 1.00),
        SIMD4<Float>(0.33, 0.33, 1.00, 1.00),
        SIMD4<Float>(1.00, 0.33, 1.00, 1.00),
        SIMD4<Float>(0.33, 1.00, 1.00, 1.00),
        SIMD4<Float>(1.00, 1.00, 1.00, 1.00)
    ]
}
