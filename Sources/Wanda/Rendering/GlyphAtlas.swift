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

struct GlyphAtlasTextureUpdate: Sendable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let bytes: Data
}

public final class GlyphAtlas: @unchecked Sendable {
    public let font: CTFont
    public let cellSize: CGSize
    public let atlasSize: CGSize
    public let image: CGImage
    let pixelWidth: Int
    let pixelHeight: Int
    let bytesPerRow: Int

    private let lock = NSLock()
    private let bitmapData: UnsafeMutableRawPointer
    private let context: CGContext
    private var entries: [Character: GlyphAtlasEntry]
    private var nextSlotIndex: Int
    private var pendingTextureUpdates: [GlyphAtlasTextureUpdate] = []

    public init(fontName: String, fontSize: CGFloat) throws {
        guard let nsFont = NSFont(name: fontName, size: fontSize) else {
            throw GlyphAtlasError.missingFont(fontName)
        }

        let font = CTFontCreateWithName(nsFont.fontName as CFString, fontSize, nil)
        let metrics = Self.buildMetrics(font: font, characters: Self.prewarmedCharacters)
        let cellSize = Self.computeCellSize(font: font, metrics: metrics)
        let atlasSize = Self.computeAtlasSize(cellSize: cellSize)
        let pixelWidth = Int(ceil(atlasSize.width))
        let pixelHeight = Int(ceil(atlasSize.height))
        let bytesPerRow = pixelWidth * Self.bytesPerPixel
        let byteCount = bytesPerRow * pixelHeight
        let bitmapData = UnsafeMutableRawPointer.allocate(
            byteCount: byteCount,
            alignment: MemoryLayout<UInt32>.alignment
        )
        bitmapData.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGImageByteOrderInfo.order32Big.rawValue
        guard let context = CGContext(
            data: bitmapData,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            bitmapData.deallocate()
            throw GlyphAtlasError.bitmapCreationFailed
        }

        Self.configure(context: context)

        let entries = Self.buildEntries(metrics: metrics, cellSize: cellSize)
        for metric in metrics {
            Self.drawGlyph(metric: metric, font: font, cellSize: cellSize, context: context)
        }

        guard let image = context.makeImage() else {
            bitmapData.deallocate()
            throw GlyphAtlasError.imageCreationFailed
        }

        self.font = font
        self.cellSize = cellSize
        self.atlasSize = atlasSize
        self.image = image
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.bytesPerRow = bytesPerRow
        self.bitmapData = bitmapData
        self.context = context
        self.entries = entries
        self.nextSlotIndex = metrics.count
    }

    deinit {
        bitmapData.deallocate()
    }

    public func glyph(for character: Character) -> GlyphAtlasEntry? {
        lock.withLock {
            if let entry = entries[character] {
                return entry
            }

            return cacheGlyphLocked(character)
        }
    }

    var pendingTextureUpdateCount: Int {
        lock.withLock {
            pendingTextureUpdates.count
        }
    }

    func takeTextureUpdates(maximumCount: Int) -> [GlyphAtlasTextureUpdate] {
        lock.withLock {
            let count = min(max(maximumCount, 0), pendingTextureUpdates.count)
            guard count > 0 else {
                return []
            }

            let updates = Array(pendingTextureUpdates.prefix(count))
            pendingTextureUpdates.removeFirst(count)
            return updates
        }
    }

    func fullTextureUpdate() -> GlyphAtlasTextureUpdate {
        lock.withLock {
            textureUpdateLocked(
                x: 0,
                y: 0,
                width: pixelWidth,
                height: pixelHeight
            )
        }
    }

    private static let firstPrintableASCII = UInt32(32)
    private static let lastPrintableASCII = UInt32(126)
    private static let atlasColumns = 64
    private static let atlasRows = 64
    private static let bytesPerPixel = 4
    private static let maximumGlyphCount = atlasColumns * atlasRows

    private static var prewarmedCharacters: [Character] {
        (firstPrintableASCII...lastPrintableASCII).compactMap { value in
            UnicodeScalar(value).map(Character.init)
        }
    }

    private struct GlyphMetric {
        let character: Character
        let font: CTFont
        let glyph: CGGlyph
        let advance: CGFloat
        let bounds: CGRect
        let slotIndex: Int
    }

    private static func buildMetrics(font: CTFont, characters: [Character]) -> [GlyphMetric] {
        var metrics: [GlyphMetric] = []
        metrics.reserveCapacity(characters.count)

        for (slotIndex, character) in characters.enumerated() {
            guard let metric = measure(character: character, font: font, slotIndex: slotIndex) else {
                continue
            }
            metrics.append(metric)
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
                textureRect: textureRect(forSlotIndex: metric.slotIndex, cellSize: cellSize)
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

    private static func configure(context: CGContext) {
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.textMatrix = .identity
    }

    private static func measure(character: Character, font: CTFont, slotIndex: Int) -> GlyphMetric? {
        let string = String(character)
        let utf16 = Array(string.utf16)
        guard utf16.count == 1 else {
            return nil
        }

        let glyphFont = CTFontCreateForString(
            font,
            string as CFString,
            CFRange(location: 0, length: utf16.count)
        )
        var codeUnit = UniChar(utf16[0])
        var glyph = CGGlyph()
        guard CTFontGetGlyphsForCharacters(glyphFont, &codeUnit, &glyph, 1), glyph != 0 else {
            return nil
        }

        var advance = CGSize.zero
        var advanceGlyph = glyph
        CTFontGetAdvancesForGlyphs(glyphFont, .horizontal, &advanceGlyph, &advance, 1)

        var boundsGlyph = glyph
        let bounds = CTFontGetBoundingRectsForGlyphs(glyphFont, .horizontal, &boundsGlyph, nil, 1)

        return GlyphMetric(
            character: character,
            font: glyphFont,
            glyph: glyph,
            advance: max(advance.width, 0),
            bounds: bounds,
            slotIndex: slotIndex
        )
    }

    private static func drawGlyph(
        metric: GlyphMetric,
        font: CTFont,
        cellSize: CGSize,
        context: CGContext
    ) {
        guard metric.character != " " else {
            return
        }

        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let leading = CTFontGetLeading(font)
        let lineHeight = ascent + descent + leading
        let baselineInset = max((cellSize.height - lineHeight) / 2, 0) + descent + max(leading / 2, 0)
        let rect = textureRect(forSlotIndex: metric.slotIndex, cellSize: cellSize)
        var glyph = metric.glyph
        var position = CGPoint(
            x: rect.minX + max((cellSize.width - metric.advance) / 2, 0),
            y: rect.minY + baselineInset
        )

        context.saveGState()
        context.clip(to: rect)
        CTFontDrawGlyphs(metric.font, &glyph, &position, 1, context)
        context.restoreGState()
    }

    private func cacheGlyphLocked(_ character: Character) -> GlyphAtlasEntry? {
        guard nextSlotIndex < Self.maximumGlyphCount,
              let metric = Self.measure(character: character, font: font, slotIndex: nextSlotIndex) else {
            return nil
        }

        Self.drawGlyph(metric: metric, font: font, cellSize: cellSize, context: context)
        let entry = GlyphAtlasEntry(
            character: metric.character,
            advance: metric.advance,
            bounds: metric.bounds,
            textureRect: Self.textureRect(forSlotIndex: metric.slotIndex, cellSize: cellSize)
        )
        entries[character] = entry
        nextSlotIndex += 1

        pendingTextureUpdates.append(
            textureUpdateLocked(
                x: Int(entry.textureRect.minX),
                y: Int(entry.textureRect.minY),
                width: Int(entry.textureRect.width),
                height: Int(entry.textureRect.height)
            )
        )

        return entry
    }

    private func textureUpdateLocked(x: Int, y: Int, width: Int, height: Int) -> GlyphAtlasTextureUpdate {
        let textureY = max(pixelHeight - y - height, 0)
        var data = Data(count: width * height * Self.bytesPerPixel)

        data.withUnsafeMutableBytes { destination in
            guard let destinationBaseAddress = destination.baseAddress else {
                return
            }

            for row in 0..<height {
                let source = bitmapData.advanced(
                    by: ((textureY + row) * bytesPerRow) + (x * Self.bytesPerPixel)
                )
                let target = destinationBaseAddress.advanced(by: row * width * Self.bytesPerPixel)
                memcpy(target, source, width * Self.bytesPerPixel)
            }
        }

        return GlyphAtlasTextureUpdate(
            x: x,
            y: textureY,
            width: width,
            height: height,
            bytesPerRow: width * Self.bytesPerPixel,
            bytes: data
        )
    }

    private static func textureRect(forSlotIndex index: Int, cellSize: CGSize) -> CGRect {
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
