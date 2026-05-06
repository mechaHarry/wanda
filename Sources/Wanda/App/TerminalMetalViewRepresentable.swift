import AppKit
import SwiftUI

struct TerminalMetalViewRepresentable: NSViewRepresentable {
    var snapshot: TerminalRendererSnapshot?
    var theme: TerminalTheme = .default
    var onFramePresented: @Sendable (UInt64) -> Void

    func makeNSView(context: Context) -> NSView {
        do {
            return try TerminalMetalView(theme: theme, framePresented: onFramePresented)
        } catch {
            let placeholder = NSTextField(labelWithString: "Metal renderer unavailable")
            placeholder.alignment = .center
            placeholder.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
            placeholder.textColor = .secondaryLabelColor
            placeholder.wantsLayer = true
            placeholder.layer?.backgroundColor = theme.background.cgColor
            return placeholder
        }
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let terminalView = nsView as? TerminalMetalView else {
            return
        }

        terminalView.terminalRenderer.framePresented = onFramePresented

        if let snapshot {
            terminalView.update(snapshot: snapshot)
        }
    }
}
