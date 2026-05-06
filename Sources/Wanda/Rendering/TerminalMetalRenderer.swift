import Foundation
import Metal
import MetalKit
import simd

public enum RendererError: Error, Equatable {
    case commandQueueUnavailable
    case metalDeviceUnavailable
    case shaderFunctionUnavailable(String)
}

public final class TerminalMetalRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {
    public let device: MTLDevice
    public private(set) var lastSnapshot: TerminalRendererSnapshot? {
        get {
            stateLock.withLock {
                storedLastSnapshot
            }
        }
        set {
            stateLock.withLock {
                storedLastSnapshot = newValue
            }
        }
    }
    public private(set) var debugVertexCount: Int {
        get {
            stateLock.withLock {
                storedDebugVertexCount
            }
        }
        set {
            stateLock.withLock {
                storedDebugVertexCount = newValue
            }
        }
    }
    public private(set) var defaultBackgroundColor: SIMD4<Float> {
        get {
            stateLock.withLock {
                storedDefaultBackgroundColor
            }
        }
        set {
            stateLock.withLock {
                storedDefaultBackgroundColor = newValue
            }
        }
    }
    private(set) var debugPrimitiveKinds: [TerminalMetalPrimitiveKind] {
        get {
            stateLock.withLock {
                storedDebugPrimitiveKinds
            }
        }
        set {
            stateLock.withLock {
                storedDebugPrimitiveKinds = newValue
            }
        }
    }
    public var framePresented: (@Sendable (UInt64) -> Void)? {
        get {
            stateLock.withLock {
                storedFramePresented
            }
        }
        set {
            stateLock.withLock {
                storedFramePresented = newValue
            }
        }
    }

    private let commandQueue: MTLCommandQueue
    private let glyphAtlas: GlyphAtlas
    private let atlasTexture: MTLTexture
    private let pipelineState: MTLRenderPipelineState
    private let stateLock = NSLock()
    private var storedLastSnapshot: TerminalRendererSnapshot?
    private var storedDebugVertexCount = 0
    private var storedDebugPrimitiveKinds: [TerminalMetalPrimitiveKind] = []
    private var storedVertexBuffer: MTLBuffer?
    private var storedFramePresented: (@Sendable (UInt64) -> Void)?
    private var storedDefaultForegroundColor = SIMD4<Float>(0.92, 0.94, 0.96, 1)
    private var storedDefaultBackgroundColor = SIMD4<Float>(0.02, 0.02, 0.025, 1)

    public init(device: MTLDevice, framePresented: (@Sendable (UInt64) -> Void)? = nil) throws {
        guard let commandQueue = device.makeCommandQueue() else {
            throw RendererError.commandQueueUnavailable
        }

        let glyphAtlas = try GlyphAtlas(fontName: "Menlo", fontSize: 14)
        let atlasTexture = try Self.makeAtlasTexture(device: device, image: glyphAtlas.image)
        let pipelineState = try Self.makePipelineState(device: device)

        self.device = device
        self.commandQueue = commandQueue
        self.glyphAtlas = glyphAtlas
        self.atlasTexture = atlasTexture
        self.pipelineState = pipelineState
        self.storedFramePresented = framePresented
        super.init()
    }

    public func updateTheme(foregroundColor: SIMD4<Float>, backgroundColor: SIMD4<Float>) {
        stateLock.withLock {
            storedDefaultForegroundColor = foregroundColor
            storedDefaultBackgroundColor = backgroundColor
        }
    }

    public func update(snapshot: TerminalRendererSnapshot) {
        let buildResult = buildVertices(for: snapshot)
        let vertexBuffer = makeVertexBuffer(vertices: buildResult.vertices)

        stateLock.withLock {
            storedLastSnapshot = snapshot
            storedDebugVertexCount = buildResult.vertices.count
            storedDebugPrimitiveKinds = buildResult.primitiveKinds
            storedVertexBuffer = vertexBuffer
        }
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        guard let renderPassDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        let drawState = stateLock.withLock {
            (vertexCount: storedDebugVertexCount, vertexBuffer: storedVertexBuffer)
        }

        if drawState.vertexCount > 0, let vertexBuffer = drawState.vertexBuffer {
            encoder.setRenderPipelineState(pipelineState)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setFragmentTexture(atlasTexture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: drawState.vertexCount)
        }

        encoder.endEncoding()
        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.notifyFramePresented(timestamp: DispatchTime.now().uptimeNanoseconds)
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func notifyFramePresentedForTesting(timestamp: UInt64) {
        notifyFramePresented(timestamp: timestamp)
    }

    private func notifyFramePresented(timestamp: UInt64) {
        let framePresented = stateLock.withLock {
            storedFramePresented
        }

        guard let framePresented else {
            return
        }

        Task { @MainActor in
            framePresented(timestamp)
        }
    }

    private func buildVertices(for snapshot: TerminalRendererSnapshot) -> VertexBuildResult {
        guard snapshot.columns > 0, snapshot.rows > 0 else {
            return VertexBuildResult(vertices: [], primitiveKinds: [])
        }

        let cellSize = glyphAtlas.cellSize
        let viewportSize = CGSize(
            width: CGFloat(snapshot.columns) * cellSize.width,
            height: CGFloat(snapshot.rows) * cellSize.height
        )
        let defaultColors = stateLock.withLock {
            (foreground: storedDefaultForegroundColor, background: storedDefaultBackgroundColor)
        }
        var vertices: [GlyphVertex] = []
        var primitiveKinds: [TerminalMetalPrimitiveKind] = []
        vertices.reserveCapacity(snapshot.cells.count * 18)

        for row in 0..<snapshot.rows {
            for column in 0..<snapshot.columns {
                let cellIndex = row * snapshot.columns + column
                guard cellIndex < snapshot.cells.count else {
                    continue
                }

                let cell = snapshot.cells[cellIndex]
                let isCursor = snapshot.cursor == TerminalPoint(column: column, row: row)
                var foregroundColor = Self.rgba(for: cell.attributes.foreground, defaultColor: defaultColors.foreground)
                var backgroundColor = Self.rgba(for: cell.attributes.background, defaultColor: defaultColors.background)
                if cell.attributes.isInverse || isCursor {
                    swap(&foregroundColor, &backgroundColor)
                }

                if cell.attributes.background != .default || cell.attributes.isInverse || isCursor {
                    appendSolidQuad(
                        column: column,
                        row: row,
                        viewportSize: viewportSize,
                        color: backgroundColor,
                        to: &vertices
                    )
                    primitiveKinds.append(isCursor ? .cursor : .background)
                }

                if cell.attributes.isUnderline {
                    appendUnderlineQuad(
                        column: column,
                        row: row,
                        viewportSize: viewportSize,
                        color: foregroundColor,
                        to: &vertices
                    )
                    primitiveKinds.append(.underline)
                }

                if cell.character != " ", let glyph = glyphAtlas.glyph(for: cell.character) {
                    appendGlyphQuad(
                        column: column,
                        row: row,
                        viewportSize: viewportSize,
                        glyph: glyph,
                        foregroundColor: foregroundColor,
                        xOffset: 0,
                        italicSkew: cell.attributes.isItalic ? 1 : 0,
                        to: &vertices
                    )
                    primitiveKinds.append(.glyph)

                    if cell.attributes.isBold {
                        appendGlyphQuad(
                            column: column,
                            row: row,
                            viewportSize: viewportSize,
                            glyph: glyph,
                            foregroundColor: foregroundColor,
                            xOffset: 1,
                            italicSkew: cell.attributes.isItalic ? 1 : 0,
                            to: &vertices
                        )
                        primitiveKinds.append(.glyph)
                    }
                }
            }
        }

        return VertexBuildResult(vertices: vertices, primitiveKinds: primitiveKinds)
    }

    private func appendGlyphQuad(
        column: Int,
        row: Int,
        viewportSize: CGSize,
        glyph: GlyphAtlasEntry,
        foregroundColor: SIMD4<Float>,
        xOffset: CGFloat,
        italicSkew: CGFloat,
        to vertices: inout [GlyphVertex]
    ) {
        let cellSize = glyphAtlas.cellSize
        let x0 = CGFloat(column) * cellSize.width + xOffset
        let y0 = CGFloat(row) * cellSize.height
        let x1 = x0 + cellSize.width
        let y1 = y0 + cellSize.height

        let topLeft = GlyphVertex(
            position: clipPosition(x: x0 + italicSkew, y: y0, viewportSize: viewportSize),
            textureCoordinate: textureCoordinate(x: glyph.textureRect.minX, y: glyph.textureRect.maxY),
            color: foregroundColor
        )
        let bottomLeft = GlyphVertex(
            position: clipPosition(x: x0, y: y1, viewportSize: viewportSize),
            textureCoordinate: textureCoordinate(x: glyph.textureRect.minX, y: glyph.textureRect.minY),
            color: foregroundColor
        )
        let topRight = GlyphVertex(
            position: clipPosition(x: x1 + italicSkew, y: y0, viewportSize: viewportSize),
            textureCoordinate: textureCoordinate(x: glyph.textureRect.maxX, y: glyph.textureRect.maxY),
            color: foregroundColor
        )
        let bottomRight = GlyphVertex(
            position: clipPosition(x: x1, y: y1, viewportSize: viewportSize),
            textureCoordinate: textureCoordinate(x: glyph.textureRect.maxX, y: glyph.textureRect.minY),
            color: foregroundColor
        )

        vertices.append(contentsOf: [
            topLeft,
            bottomLeft,
            topRight,
            topRight,
            bottomLeft,
            bottomRight
        ])
    }

    private func appendSolidQuad(
        column: Int,
        row: Int,
        viewportSize: CGSize,
        color: SIMD4<Float>,
        to vertices: inout [GlyphVertex]
    ) {
        let cellSize = glyphAtlas.cellSize
        appendSolidQuad(
            x0: CGFloat(column) * cellSize.width,
            y0: CGFloat(row) * cellSize.height,
            x1: CGFloat(column + 1) * cellSize.width,
            y1: CGFloat(row + 1) * cellSize.height,
            viewportSize: viewportSize,
            color: color,
            to: &vertices
        )
    }

    private func appendUnderlineQuad(
        column: Int,
        row: Int,
        viewportSize: CGSize,
        color: SIMD4<Float>,
        to vertices: inout [GlyphVertex]
    ) {
        let cellSize = glyphAtlas.cellSize
        let lineHeight = max(CGFloat(1), ceil(cellSize.height * 0.08))
        let y1 = CGFloat(row + 1) * cellSize.height - 2
        appendSolidQuad(
            x0: CGFloat(column) * cellSize.width,
            y0: max(CGFloat(row) * cellSize.height, y1 - lineHeight),
            x1: CGFloat(column + 1) * cellSize.width,
            y1: y1,
            viewportSize: viewportSize,
            color: color,
            to: &vertices
        )
    }

    private func appendSolidQuad(
        x0: CGFloat,
        y0: CGFloat,
        x1: CGFloat,
        y1: CGFloat,
        viewportSize: CGSize,
        color: SIMD4<Float>,
        to vertices: inout [GlyphVertex]
    ) {
        let topLeft = GlyphVertex(
            position: clipPosition(x: x0, y: y0, viewportSize: viewportSize),
            textureCoordinate: Self.solidTextureCoordinate,
            color: color
        )
        let bottomLeft = GlyphVertex(
            position: clipPosition(x: x0, y: y1, viewportSize: viewportSize),
            textureCoordinate: Self.solidTextureCoordinate,
            color: color
        )
        let topRight = GlyphVertex(
            position: clipPosition(x: x1, y: y0, viewportSize: viewportSize),
            textureCoordinate: Self.solidTextureCoordinate,
            color: color
        )
        let bottomRight = GlyphVertex(
            position: clipPosition(x: x1, y: y1, viewportSize: viewportSize),
            textureCoordinate: Self.solidTextureCoordinate,
            color: color
        )

        vertices.append(contentsOf: [
            topLeft,
            bottomLeft,
            topRight,
            topRight,
            bottomLeft,
            bottomRight
        ])
    }

    private func clipPosition(x: CGFloat, y: CGFloat, viewportSize: CGSize) -> SIMD2<Float> {
        SIMD2<Float>(
            Float((x / viewportSize.width) * 2 - 1),
            Float(1 - (y / viewportSize.height) * 2)
        )
    }

    private func textureCoordinate(x: CGFloat, y: CGFloat) -> SIMD2<Float> {
        SIMD2<Float>(
            Float(x / glyphAtlas.atlasSize.width),
            Float(1 - (y / glyphAtlas.atlasSize.height))
        )
    }

    private func makeVertexBuffer(vertices: [GlyphVertex]) -> MTLBuffer? {
        guard !vertices.isEmpty else {
            return nil
        }

        return vertices.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return nil
            }

            return device.makeBuffer(
                bytes: baseAddress,
                length: rawBuffer.count,
                options: .storageModeShared
            )
        }
    }

    private static func makeAtlasTexture(device: MTLDevice, image: CGImage) throws -> MTLTexture {
        let textureLoader = MTKTextureLoader(device: device)
        return try textureLoader.newTexture(cgImage: image, options: [.SRGB: false])
    }

    private static func makePipelineState(device: MTLDevice) throws -> MTLRenderPipelineState {
        let library = try device.makeLibrary(source: shaderSource, options: nil)
        guard let vertexFunction = library.makeFunction(name: "terminalGlyphVertex") else {
            throw RendererError.shaderFunctionUnavailable("terminalGlyphVertex")
        }
        guard let fragmentFunction = library.makeFunction(name: "terminalGlyphFragment") else {
            throw RendererError.shaderFunctionUnavailable("terminalGlyphFragment")
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func rgba(for color: TerminalColor, defaultColor: SIMD4<Float>) -> SIMD4<Float> {
        switch color {
        case .default:
            return defaultColor
        case .ansi(let index):
            let paletteIndex = Int(index)
            guard paletteIndex < ansiPalette.count else {
                return defaultColor
            }

            return ansiPalette[paletteIndex]
        case .rgb(let red, let green, let blue):
            return SIMD4<Float>(
                Float(red) / 255,
                Float(green) / 255,
                Float(blue) / 255,
                1
            )
        }
    }

    private static let solidTextureCoordinate = SIMD2<Float>(-1, -1)

    private static let ansiPalette: [SIMD4<Float>] = [
        SIMD4<Float>(0.00, 0.00, 0.00, 1),
        SIMD4<Float>(0.80, 0.00, 0.00, 1),
        SIMD4<Float>(0.00, 0.80, 0.00, 1),
        SIMD4<Float>(0.80, 0.80, 0.00, 1),
        SIMD4<Float>(0.00, 0.00, 0.80, 1),
        SIMD4<Float>(0.80, 0.00, 0.80, 1),
        SIMD4<Float>(0.00, 0.80, 0.80, 1),
        SIMD4<Float>(0.86, 0.86, 0.86, 1),
        SIMD4<Float>(0.33, 0.33, 0.33, 1),
        SIMD4<Float>(1.00, 0.33, 0.33, 1),
        SIMD4<Float>(0.33, 1.00, 0.33, 1),
        SIMD4<Float>(1.00, 1.00, 0.33, 1),
        SIMD4<Float>(0.33, 0.33, 1.00, 1),
        SIMD4<Float>(1.00, 0.33, 1.00, 1),
        SIMD4<Float>(0.33, 1.00, 1.00, 1),
        SIMD4<Float>(1.00, 1.00, 1.00, 1)
    ]

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct TerminalGlyphVertex {
        float2 position;
        float2 textureCoordinate;
        float4 color;
    };

    struct TerminalGlyphVaryings {
        float4 position [[position]];
        float2 textureCoordinate;
        float4 color;
    };

    vertex TerminalGlyphVaryings terminalGlyphVertex(
        uint vertexID [[vertex_id]],
        const device TerminalGlyphVertex *vertices [[buffer(0)]]
    ) {
        TerminalGlyphVertex input = vertices[vertexID];
        TerminalGlyphVaryings output;
        output.position = float4(input.position, 0.0, 1.0);
        output.textureCoordinate = input.textureCoordinate;
        output.color = input.color;
        return output;
    }

    fragment float4 terminalGlyphFragment(
        TerminalGlyphVaryings input [[stage_in]],
        texture2d<float, access::sample> atlas [[texture(0)]]
    ) {
        constexpr sampler glyphSampler(
            coord::normalized,
            address::clamp_to_edge,
            filter::linear
        );
        float glyphAlpha = input.textureCoordinate.x < 0.0
            ? 1.0
            : atlas.sample(glyphSampler, input.textureCoordinate).a;
        return float4(input.color.rgb, input.color.a * glyphAlpha);
    }
    """
}

private struct GlyphVertex {
    let position: SIMD2<Float>
    let textureCoordinate: SIMD2<Float>
    let color: SIMD4<Float>
}

enum TerminalMetalPrimitiveKind: Equatable {
    case background
    case cursor
    case underline
    case glyph
}

private struct VertexBuildResult {
    var vertices: [GlyphVertex]
    var primitiveKinds: [TerminalMetalPrimitiveKind]
}
