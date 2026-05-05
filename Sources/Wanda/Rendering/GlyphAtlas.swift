import AppKit
import CoreText

public struct GlyphAtlasEntry: Equatable, Sendable {
    public let character: Character
    public let advance: CGFloat
    public let bounds: CGRect

    public init(character: Character, advance: CGFloat, bounds: CGRect) {
        self.character = character
        self.advance = advance
        self.bounds = bounds
    }
}

public enum GlyphAtlasError: Error, Equatable {
    case missingFont(String)
}

public final class GlyphAtlas: @unchecked Sendable {
    public let font: CTFont
    public let cellSize: CGSize

    private let entries: [Character: GlyphAtlasEntry]

    public init(fontName: String, fontSize: CGFloat) throws {
        guard let nsFont = NSFont(name: fontName, size: fontSize) else {
            throw GlyphAtlasError.missingFont(fontName)
        }

        let font = CTFontCreateWithName(nsFont.fontName as CFString, fontSize, nil)
        let entries = Self.buildEntries(font: font)

        self.font = font
        self.cellSize = Self.computeCellSize(font: font, entries: entries)
        self.entries = entries
    }

    public func glyph(for character: Character) -> GlyphAtlasEntry? {
        entries[character]
    }

    private static func buildEntries(font: CTFont) -> [Character: GlyphAtlasEntry] {
        var entries: [Character: GlyphAtlasEntry] = [:]
        entries.reserveCapacity(95)

        for value in UInt32(32)...UInt32(126) {
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
            let character = Character(scalar)
            entries[character] = GlyphAtlasEntry(
                character: character,
                advance: max(advance.width, 0),
                bounds: bounds
            )
        }

        return entries
    }

    private static func computeCellSize(font: CTFont, entries: [Character: GlyphAtlasEntry]) -> CGSize {
        let widestAdvance = entries.values.map(\.advance).max() ?? CTFontGetSize(font)
        let height = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)

        return CGSize(
            width: max(ceil(widestAdvance), 1),
            height: max(ceil(height), 1)
        )
    }
}
