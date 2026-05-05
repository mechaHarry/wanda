import AppKit
import SwiftUI

struct TerminalInputView: NSViewRepresentable {
    var layout: TerminalInputLayout
    var onKey: (TerminalKeyEvent) -> Void
    var onSelectionBegan: (TerminalPoint) -> Void
    var onSelectionChanged: (TerminalPoint) -> Void
    var onTokenSelection: (TerminalPoint) -> Void
    var onCopy: () -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.layout = layout
        view.onKey = onKey
        view.onSelectionBegan = onSelectionBegan
        view.onSelectionChanged = onSelectionChanged
        view.onTokenSelection = onTokenSelection
        view.onCopy = onCopy
        view.requestFirstResponderOnNextMainActorTurn()
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.layout = layout
        nsView.onKey = onKey
        nsView.onSelectionBegan = onSelectionBegan
        nsView.onSelectionChanged = onSelectionChanged
        nsView.onTokenSelection = onTokenSelection
        nsView.onCopy = onCopy
    }
}

final class KeyCaptureView: NSView {
    var layout = TerminalInputLayout(columns: 1, rows: 1, cellSize: CGSize(width: 1, height: 1))
    var onKey: ((TerminalKeyEvent) -> Void)?
    var onSelectionBegan: ((TerminalPoint) -> Void)?
    var onSelectionChanged: ((TerminalPoint) -> Void)?
    var onTokenSelection: ((TerminalPoint) -> Void)?
    var onCopy: (() -> Void)?
    private var dragStart: TerminalPoint?

    override var acceptsFirstResponder: Bool {
        true
    }

    override var isFlipped: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        requestFirstResponderOnNextMainActorTurn()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = terminalPoint(for: event)

        if event.clickCount >= 2 {
            dragStart = nil
            onTokenSelection?(point)
            return
        }

        dragStart = point
        onSelectionBegan?(point)
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragStart != nil else {
            return
        }

        onSelectionChanged?(terminalPoint(for: event))
    }

    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else {
            return
        }

        onSelectionChanged?(terminalPoint(for: event))
        dragStart = nil
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "c" {
            onCopy?()
            return
        }

        guard let terminalKeyEvent = TerminalInputEventMapper.map(
            keyCode: event.keyCode,
            characters: event.characters,
            modifierFlags: event.modifierFlags
        ) else {
            super.keyDown(with: event)
            return
        }

        onKey?(terminalKeyEvent)
    }

    func requestFirstResponderOnNextMainActorTurn() {
        Task { @MainActor [weak self] in
            guard let self, let window else {
                return
            }

            window.makeFirstResponder(self)
        }
    }

    private func terminalPoint(for event: NSEvent) -> TerminalPoint {
        let location = convert(event.locationInWindow, from: nil)
        return layout.point(for: location)
    }
}

struct TerminalInputLayout: Equatable {
    var columns: Int
    var rows: Int
    var cellSize: CGSize

    func point(for location: CGPoint) -> TerminalPoint {
        TerminalPoint(
            column: clampedCellIndex(location.x, cellExtent: cellSize.width, upperBound: columns),
            row: clampedCellIndex(location.y, cellExtent: cellSize.height, upperBound: rows)
        )
    }

    private func clampedCellIndex(_ value: CGFloat, cellExtent: CGFloat, upperBound: Int) -> Int {
        guard upperBound > 1, cellExtent > 0 else {
            return 0
        }

        return min(max(Int(value / cellExtent), 0), upperBound - 1)
    }
}

struct TerminalSelectionClipboard {
    static func copy(_ text: String?, to pasteboard: NSPasteboard = .general) -> Bool {
        guard let text, !text.isEmpty else {
            return false
        }

        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}

struct TerminalInputEventMapper {
    static func map(
        keyCode: UInt16,
        characters: String?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> TerminalKeyEvent? {
        let modifiers = terminalModifiers(from: modifierFlags)

        switch keyCode {
        case 123:
            return .special(.leftArrow, modifiers: modifiers)
        case 124:
            return .special(.rightArrow, modifiers: modifiers)
        case 125:
            return .special(.downArrow, modifiers: modifiers)
        case 126:
            return .special(.upArrow, modifiers: modifiers)
        case 36:
            return .special(.returnKey, modifiers: modifiers)
        case 51:
            return .special(.delete, modifiers: modifiers)
        case 48:
            return .special(.tab, modifiers: modifiers)
        default:
            guard let characters, !characters.isEmpty else {
                return nil
            }

            return .printable(characters)
        }
    }

    private static func terminalModifiers(from modifierFlags: NSEvent.ModifierFlags) -> TerminalKeyModifiers {
        var modifiers: TerminalKeyModifiers = []

        if modifierFlags.contains(.option) {
            modifiers.insert(.option)
        }
        if modifierFlags.contains(.command) {
            modifiers.insert(.command)
        }
        if modifierFlags.contains(.control) {
            modifiers.insert(.control)
        }
        if modifierFlags.contains(.shift) {
            modifiers.insert(.shift)
        }

        return modifiers
    }
}
