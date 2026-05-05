import AppKit
import SwiftUI

struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowAccessView {
        WindowAccessView(onWindow: onWindow)
    }

    func updateNSView(_ nsView: WindowAccessView, context: Context) {
        nsView.update(onWindow: onWindow)
    }
}

final class WindowAccessView: NSView {
    private var onWindow: (NSWindow) -> Void
    private var deliveredWindowID: ObjectIdentifier?

    init(onWindow: @escaping (NSWindow) -> Void) {
        self.onWindow = onWindow
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("WindowAccessView does not support decoding")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard let window else {
            return
        }

        let windowID = ObjectIdentifier(window)
        guard deliveredWindowID != windowID else {
            return
        }

        deliveredWindowID = windowID
        onWindow(window)
    }

    func update(onWindow: @escaping (NSWindow) -> Void) {
        self.onWindow = onWindow
    }
}
