import AppKit
import Metal
import MetalKit

public final class TerminalMetalView: MTKView {
    public let terminalRenderer: TerminalMetalRenderer
    private let theme: TerminalTheme

    public override var isOpaque: Bool {
        true
    }

    public init(
        frame frameRect: CGRect = .zero,
        theme: TerminalTheme = .default,
        framePresented: (@Sendable (UInt64) -> Void)? = nil
    ) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RendererError.metalDeviceUnavailable
        }

        let terminalRenderer = try TerminalMetalRenderer(device: device, framePresented: framePresented)
        self.terminalRenderer = terminalRenderer
        self.theme = theme

        super.init(frame: frameRect, device: device)

        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        enableSetNeedsDisplay = true
        isPaused = true
        delegate = terminalRenderer
        wantsLayer = true
        applyTheme()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(snapshot: TerminalRendererSnapshot) {
        terminalRenderer.update(snapshot: snapshot)
        setNeedsDisplay(bounds)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyTheme()
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTheme()
    }

    private func applyTheme() {
        clearColor = theme.resolvedClearColor(for: self)
        layer?.backgroundColor = theme.resolvedBackgroundNSColor(for: self).cgColor
        terminalRenderer.updateTheme(
            foregroundColor: theme.resolvedForegroundSIMD(for: self),
            backgroundColor: theme.resolvedBackgroundSIMD(for: self)
        )
    }
}
