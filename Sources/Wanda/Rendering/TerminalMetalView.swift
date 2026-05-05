import AppKit
import Metal
import MetalKit

public final class TerminalMetalView: MTKView {
    public let terminalRenderer: TerminalMetalRenderer

    public init(frame frameRect: CGRect = .zero, framePresented: (@Sendable (UInt64) -> Void)? = nil) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RendererError.metalDeviceUnavailable
        }

        let terminalRenderer = try TerminalMetalRenderer(device: device, framePresented: framePresented)
        self.terminalRenderer = terminalRenderer

        super.init(frame: frameRect, device: device)

        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0.02, green: 0.02, blue: 0.025, alpha: 1)
        framebufferOnly = true
        enableSetNeedsDisplay = false
        isPaused = false
        delegate = terminalRenderer
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(snapshot: TerminalRendererSnapshot) {
        terminalRenderer.update(snapshot: snapshot)
        setNeedsDisplay(bounds)
    }
}
