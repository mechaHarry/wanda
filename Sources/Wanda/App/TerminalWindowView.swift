import AppKit
import SwiftUI

struct TerminalWindowView: View {
    @StateObject private var viewModel = TerminalViewModel()
    @StateObject private var windowGeometry = TerminalWindowGeometryController()

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                TerminalMetalViewRepresentable(
                    snapshot: viewModel.snapshot,
                    onFramePresented: viewModel.framePresented(at:)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                TerminalInputView { keyEvent in
                    viewModel.handleKey(keyEvent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())

                if let statusMessage = viewModel.statusMessage {
                    Text(statusMessage)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .padding(12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                resizeTerminal(to: geometry.size)
            }
            .onChange(of: geometry.size) { _, newSize in
                resizeTerminal(to: newSize)
            }
            .task {
                viewModel.startDefaultShell()
                resizeTerminal(to: geometry.size)
            }
            .onDisappear {
                windowGeometry.saveCurrentWindowFrame()
                viewModel.stop()
            }
        }
        .frame(minWidth: 720, minHeight: 420)
        .background {
            WindowAccessor { window in
                windowGeometry.observe(window: window)
            }
        }
    }

    private func resizeTerminal(to size: CGSize) {
        let columns = max(1, Int(size.width / 9))
        let rows = max(1, Int(size.height / 18))
        viewModel.resize(columns: columns, rows: rows)
    }
}

@MainActor
final class TerminalWindowGeometryController: ObservableObject {
    private let geometryStore: GeometryStore
    private weak var window: NSWindow?
    private var restoredWindowID: ObjectIdentifier?

    init(geometryStore: GeometryStore = GeometryStore()) {
        self.geometryStore = geometryStore
    }

    func observe(window: NSWindow) {
        self.window = window

        guard let frame = frameToApply(
            to: ObjectIdentifier(window),
            currentFrame: window.frame,
            visibleFrame: Self.visibleFrame(for: window)
        ) else {
            return
        }

        window.setFrame(frame, display: true)
    }

    func saveCurrentWindowFrame() {
        guard let frame = window?.frame else {
            return
        }

        save(frame: frame)
    }

    func frameToApply(to windowID: ObjectIdentifier, currentFrame: CGRect, visibleFrame: CGRect) -> CGRect? {
        guard restoredWindowID != windowID else {
            return nil
        }

        restoredWindowID = windowID
        let frame = geometryStore.load(validatingAgainst: visibleFrame)
        guard frame != currentFrame else {
            return nil
        }

        return frame
    }

    func save(frame: CGRect) {
        geometryStore.save(frame: frame)
    }

    private static func visibleFrame(for window: NSWindow) -> CGRect {
        window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
    }
}
