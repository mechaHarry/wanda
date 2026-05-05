import AppKit
import CoreText

public struct GlyphAtlasEntry: Equatable, Sendable {
    public let character: Character
    public let advance: CGFloat
    public let bounds: CGRect
    public let textureRect: CGRect

    public init(character: Character, advance: CGFloat, bounds: CGRect, textureRect: CGRect) {
        self.character = character
        self.advance = advance
        self.bounds = bounds
        self.textureRect = textureRect
    }
}

public enum GlyphAtlasError: Error, Equatable {
    case missingFont(String)
    case bitmapCreationFailed
    case imageCreationFailed
}

public final class GlyphAtlas: @unchecked Sendable {
    public let font: CTFont
    public let cellSize: CGSize
    public let atlasSize: CGSize
    public let image: CGImage

    private let entries: [Character: GlyphAtlasEntry]

    public init(fontName: String, fontSize: CGFloat) throws {
        guard let nsFont = NSFont(name: fontName, size: fontSize) else {
            throw GlyphAtlasError.missingFont(fontName)
        }

        let font = CTFontCreateWithName(nsFont.fontName as CFString, fontSize, nil)
        let metrics = Self.buildMetrics(font: font)
        let cellSize = Self.computeCellSize(font: font, metrics: metrics)
        let atlasSize = Self.computeAtlasSize(cellSize: cellSize)
        let entries = Self.buildEntries(metrics: metrics, cellSize: cellSize)
        let image = try Self.buildImage(
            font: font,
            metrics: metrics,
            cellSize: cellSize,
            atlasSize: atlasSize
        )

        self.font = font
        self.cellSize = cellSize
        self.atlasSize = atlasSize
        self.image = image
        self.entries = entries
    }

    public func glyph(for character: Character) -> GlyphAtlasEntry? {
        entries[character]
    }

    private static let firstPrintableASCII = UInt32(32)
    private static let lastPrintableASCII = UInt32(126)
    private static let atlasColumns = 16
    private static let atlasRows = 6

    private struct GlyphMetric {
        let character: Character
        let glyph: CGGlyph
        let advance: CGFloat
        let bounds: CGRect
        let asciiIndex: Int
    }

    private static func buildMetrics(font: CTFont) -> [GlyphMetric] {
        var metrics: [GlyphMetric] = []
        metrics.reserveCapacity(Int(lastPrintableASCII - firstPrintableASCII + 1))

        for value in firstPrintableASCII...lastPrintableASCII {
            guard let scalar = UnicodeScalar(value) else {
                continue
            }

            var utf16 = UniChar(value)
            var glyph = CGGlyph()
            guard CTFontGetGlyphsForCharacters(font, &utf16, &glyph, 1), glyph != 0 else {
                continue
            }

            var advance = CGSize.zero
            var advanceGlyph = glyph
            CTFontGetAdvancesForGlyphs(font, .horizontal, &advanceGlyph, &advance, 1)

            var boundsGlyph = glyph
            let bounds = CTFontGetBoundingRectsForGlyphs(font, .horizontal, &boundsGlyph, nil, 1)
            metrics.append(
                GlyphMetric(
                    character: Character(scalar),
                    glyph: glyph,
                    advance: max(advance.width, 0),
                    bounds: bounds,
                    asciiIndex: Int(value - firstPrintableASCII)
                )
            )
        }

        return metrics
    }

    private static func buildEntries(metrics: [GlyphMetric], cellSize: CGSize) -> [Character: GlyphAtlasEntry] {
        var entries: [Character: GlyphAtlasEntry] = [:]
        entries.reserveCapacity(metrics.count)

        for metric in metrics {
            entries[metric.character] = GlyphAtlasEntry(
                character: metric.character,
                advance: metric.advance,
                bounds: metric.bounds,
                textureRect: textureRect(forASCIIIndex: metric.asciiIndex, cellSize: cellSize)
            )
        }

        return entries
    }

    private static func computeCellSize(font: CTFont, metrics: [GlyphMetric]) -> CGSize {
        let widestAdvance = metrics.map(\.advance).max() ?? CTFontGetSize(font)
        let height = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)

        return CGSize(
            width: max(ceil(widestAdvance), 1),
            height: max(ceil(height), 1)
        )
    }

    private static func computeAtlasSize(cellSize: CGSize) -> CGSize {
        CGSize(
            width: cellSize.width * CGFloat(atlasColumns),
            height: cellSize.height * CGFloat(atlasRows)
        )
    }

    private static func buildImage(
        font: CTFont,
        metrics: [GlyphMetric],
        cellSize: CGSize,
        atlasSize: CGSize
    ) throws -> CGImage {
        let width = Int(ceil(atlasSize.width))
        let height = Int(ceil(atlasSize.height))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw GlyphAtlasError.bitmapCreationFailed
        }

        context.clear(CGRect(origin: .zero, size: atlasSize))
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.textMatrix = .identity

        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let leading = CTFontGetLeading(font)
        let lineHeight = ascent + descent + leading
        let baselineInset = max((cellSize.height - lineHeight) / 2, 0) + descent + max(leading / 2, 0)

        for metric in metrics where metric.character != " " {
            let rect = textureRect(forASCIIIndex: metric.asciiIndex, cellSize: cellSize)
            var glyph = metric.glyph
            var position = CGPoint(
                x: rect.minX + max((cellSize.width - metric.advance) / 2, 0),
                y: rect.minY + baselineInset
            )

            CTFontDrawGlyphs(font, &glyph, &position, 1, context)
        }

        guard let image = context.makeImage() else {
            throw GlyphAtlasError.imageCreationFailed
        }

        return image
    }

    private static func textureRect(forASCIIIndex index: Int, cellSize: CGSize) -> CGRect {
        let column = index % atlasColumns
        let row = index / atlasColumns

        return CGRect(
            x: CGFloat(column) * cellSize.width,
            y: CGFloat(row) * cellSize.height,
            width: cellSize.width,
            height: cellSize.height
        )
    }
}
