import Metal
import MetalKit

public enum RendererError: Error, Equatable {
    case commandQueueUnavailable
    case metalDeviceUnavailable
}

public final class TerminalMetalRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {
    public let device: MTLDevice
    public private(set) var lastSnapshot: TerminalRendererSnapshot?
    public var framePresented: (@Sendable (UInt64) -> Void)?

    private let commandQueue: MTLCommandQueue

    public init(device: MTLDevice, framePresented: (@Sendable (UInt64) -> Void)? = nil) throws {
        guard let commandQueue = device.makeCommandQueue() else {
            throw RendererError.commandQueueUnavailable
        }

        self.device = device
        self.framePresented = framePresented
        self.commandQueue = commandQueue
        super.init()
    }

    public func update(snapshot: TerminalRendererSnapshot) {
        lastSnapshot = snapshot
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        let framePresented = framePresented
        commandBuffer.addCompletedHandler { _ in
            framePresented?(DispatchTime.now().uptimeNanoseconds)
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
