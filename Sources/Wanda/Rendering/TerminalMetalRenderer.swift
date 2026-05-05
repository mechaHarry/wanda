import Foundation
import Metal
import MetalKit

public enum RendererError: Error, Equatable {
    case commandQueueUnavailable
    case metalDeviceUnavailable
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
    private let stateLock = NSLock()
    private var storedLastSnapshot: TerminalRendererSnapshot?
    private var storedFramePresented: (@Sendable (UInt64) -> Void)?

    public init(device: MTLDevice, framePresented: (@Sendable (UInt64) -> Void)? = nil) throws {
        guard let commandQueue = device.makeCommandQueue() else {
            throw RendererError.commandQueueUnavailable
        }

        self.device = device
        self.commandQueue = commandQueue
        self.storedFramePresented = framePresented
        super.init()
    }

    public func update(snapshot: TerminalRendererSnapshot) {
        lastSnapshot = snapshot
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        guard let renderPassDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
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
}
