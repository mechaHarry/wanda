import AppKit
import SwiftUI

struct TerminalSelectionOverlayRepresentable: NSViewRepresentable {
    var selection: TerminalSelection?
    var snapshot: TerminalRendererSnapshot?

    func makeNSView(context: Context) -> TerminalSelectionOverlayView {
        TerminalSelectionOverlayView()
    }

    func updateNSView(_ nsView: TerminalSelectionOverlayView, context: Context) {
        nsView.update(selection: selection, snapshot: snapshot)
    }
}

final class TerminalSelectionOverlayView: NSView {
    private var selection: TerminalSelection?
    private var snapshot: TerminalRendererSnapshot?

    override var isFlipped: Bool {
        true
    }

    override var isOpaque: Bool {
        false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    func update(selection: TerminalSelection?, snapshot: TerminalRendererSnapshot?) {
        self.selection = selection
        self.snapshot = snapshot
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.controlAccentColor.withAlphaComponent(0.32).setFill()
        for rect in selectionRects(in: bounds.size) {
            rect.fill()
        }
    }

    func selectionRects(in size: CGSize) -> [CGRect] {
        guard let selection, let snapshot, snapshot.columns > 0, snapshot.rows > 0 else {
            return []
        }

        let cellSize = CGSize(
            width: size.width / CGFloat(snapshot.columns),
            height: size.height / CGFloat(snapshot.rows)
        )

        return selection.rowRanges(columns: snapshot.columns, rows: snapshot.rows).map { range in
            CGRect(
                x: CGFloat(range.startColumn) * cellSize.width,
                y: CGFloat(range.row) * cellSize.height,
                width: CGFloat(range.endColumn - range.startColumn + 1) * cellSize.width,
                height: cellSize.height
            )
        }
    }
}
