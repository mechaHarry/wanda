import AppKit
import SwiftUI

struct TerminalInputView: NSViewRepresentable {
    var onKey: (TerminalKeyEvent) -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onKey = onKey
        view.requestFirstResponderOnNextMainActorTurn()
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.onKey = onKey
    }
}

final class KeyCaptureView: NSView {
    var onKey: ((TerminalKeyEvent) -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        requestFirstResponderOnNextMainActorTurn()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
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
