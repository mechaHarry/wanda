# Terminal Core MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first Wanda MVP: a macOS 15+ single-window SwiftUI terminal app with a PTY-backed shell, Swift terminal model, replaceable parser boundary, bounded scrollback, basic selection, Metal text rendering, geometry persistence, tests, and latency instrumentation.

**Architecture:** Use a SwiftPM macOS executable with SwiftUI at the app boundary, AppKit bridges for key events and `MTKView`, a pure Swift terminal core, a POSIX PTY adapter, and a Metal renderer that consumes terminal model snapshots. Parser, model, PTY, UI, persistence, and renderer code stay isolated behind small interfaces so later parser or renderer experiments do not leak across the app.

**Tech Stack:** Swift 6, SwiftPM, XCTest, SwiftUI, AppKit, MetalKit, CoreText, POSIX PTY APIs, os.signpost.

---

## Spec Reference

Implement from `docs/superpowers/specs/2026-05-04-terminal-core-mvp-design.md`.

## File Map

- `Package.swift`: SwiftPM executable and test target definition.
- `Sources/Wanda/App/WandaApp.swift`: SwiftUI app entry point.
- `Sources/Wanda/App/TerminalWindowView.swift`: Native SwiftUI window content and status surfaces.
- `Sources/Wanda/App/TerminalViewModel.swift`: Main actor coordinator between UI, PTY, terminal model, and renderer snapshots.
- `Sources/Wanda/App/GeometryStore.swift`: Window size and position persistence.
- `Sources/Wanda/App/TerminalMetalViewRepresentable.swift`: SwiftUI-to-AppKit bridge for `TerminalMetalView`.
- `Sources/Wanda/Input/TerminalKeyMapper.swift`: macOS key event to terminal byte mapping.
- `Sources/Wanda/Input/TerminalKeyEvent.swift`: Testable key event value type.
- `Sources/Wanda/PTY/PseudoTerminal.swift`: Protocol and concrete POSIX PTY implementation.
- `Sources/Wanda/PTY/PseudoTerminalTypes.swift`: PTY lifecycle and resize types.
- `Sources/Wanda/TerminalCore/TerminalCell.swift`: Cell, color, style, and attribute types.
- `Sources/Wanda/TerminalCore/TerminalGrid.swift`: Fixed-size grid storage and cell operations.
- `Sources/Wanda/TerminalCore/TerminalModel.swift`: Cursor, screen, alternate screen, scrollback, dirty ranges, and event application.
- `Sources/Wanda/TerminalCore/TerminalParser.swift`: Replaceable parser protocol and Swift-native parser.
- `Sources/Wanda/TerminalCore/TerminalEvent.swift`: Typed parser events.
- `Sources/Wanda/TerminalCore/TerminalSelection.swift`: Cell-aware selection and token rules.
- `Sources/Wanda/Rendering/TerminalRendererSnapshot.swift`: Immutable render snapshot shared with Metal renderer.
- `Sources/Wanda/Rendering/GlyphAtlas.swift`: CoreText-backed monospace glyph atlas.
- `Sources/Wanda/Rendering/TerminalMetalView.swift`: AppKit `MTKView` host and renderer lifecycle.
- `Sources/Wanda/Rendering/TerminalMetalRenderer.swift`: Metal pipeline, cell upload, drawing, and frame timing hooks.
- `Sources/Wanda/Instrumentation/LatencyProbe.swift`: Keystroke-to-present measurements and summaries.
- `Tests/WandaTests/TerminalCoreTests.swift`: Grid, model, parser, scrollback, alternate screen tests.
- `Tests/WandaTests/TerminalSelectionTests.swift`: Selection and double-click token tests.
- `Tests/WandaTests/TerminalKeyMapperTests.swift`: Option/Cmd arrow and printable key tests.
- `Tests/WandaTests/GeometryStoreTests.swift`: Geometry persistence tests.
- `Tests/WandaTests/PseudoTerminalTests.swift`: PTY launch, echo, resize, and cleanup tests.
- `Tests/WandaTests/RenderingTests.swift`: Snapshot, glyph atlas, and renderer metadata tests.
- `Tests/WandaTests/LatencyProbeTests.swift`: Latency summary tests.
- `README.md`: Build, test, and MVP scope notes.

## Task 1: Scaffold The SwiftPM macOS App

**Files:**
- Create: `Package.swift`
- Create: `Sources/Wanda/App/WandaApp.swift`
- Create: `Sources/Wanda/App/TerminalWindowView.swift`
- Create: `Tests/WandaTests/SmokeTests.swift`
- Create: `README.md`

- [ ] **Step 1: Write the package manifest**

Create `Package.swift`:

```swift
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Wanda",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Wanda", targets: ["Wanda"])
    ],
    targets: [
        .executableTarget(
            name: "Wanda",
            path: "Sources/Wanda",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "WandaTests",
            dependencies: ["Wanda"],
            path: "Tests/WandaTests"
        )
    ]
)
```

- [ ] **Step 2: Add the SwiftUI app entry point**

Create `Sources/Wanda/App/WandaApp.swift`:

```swift
import SwiftUI

@main
struct WandaApp: App {
    var body: some Scene {
        WindowGroup("Wanda") {
            TerminalWindowView()
        }
        .windowResizability(.contentSize)
    }
}
```

- [ ] **Step 3: Add a native shell view with an honest startup state**

Create `Sources/Wanda/App/TerminalWindowView.swift`:

```swift
import SwiftUI

struct TerminalWindowView: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("Wanda")
                .font(.system(.title2, design: .monospaced))
            Text("Terminal core is not connected yet.")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 720, minHeight: 420)
        .padding(24)
    }
}
```

- [ ] **Step 4: Add a smoke test for the package**

Create `Tests/WandaTests/SmokeTests.swift`:

```swift
import XCTest
@testable import Wanda

final class SmokeTests: XCTestCase {
    func testPackageLoads() {
        XCTAssertEqual("Wanda".count, 5)
    }
}
```

- [ ] **Step 5: Add build notes**

Create `README.md`:

```markdown
# Wanda

Wanda is a macOS 15+ terminal emulator MVP focused on a low-latency PTY-to-Metal rendering path.

## Build

```bash
swift build
```

## Test

```bash
swift test
```

## MVP Scope

The first milestone is a single native macOS terminal window with a local shell, Swift terminal model, bounded in-memory scrollback, basic selection, Metal text rendering, window geometry restore, and latency instrumentation.
```

- [ ] **Step 6: Run the initial tests**

Run: `swift test`

Expected: PASS with `SmokeTests.testPackageLoads`.

- [ ] **Step 7: Build the app executable**

Run: `swift build`

Expected: PASS and a `Wanda` executable product.

- [ ] **Step 8: Commit**

```bash
git add Package.swift Sources/Wanda/App/WandaApp.swift Sources/Wanda/App/TerminalWindowView.swift Tests/WandaTests/SmokeTests.swift README.md
git commit -m "feat: scaffold macOS Swift package"
```

## Task 2: Add Terminal Cell And Grid Core

**Files:**
- Create: `Sources/Wanda/TerminalCore/TerminalCell.swift`
- Create: `Sources/Wanda/TerminalCore/TerminalGrid.swift`
- Create: `Tests/WandaTests/TerminalCoreTests.swift`

- [ ] **Step 1: Write failing grid tests**

Create `Tests/WandaTests/TerminalCoreTests.swift`:

```swift
import XCTest
@testable import Wanda

final class TerminalCoreTests: XCTestCase {
    func testGridStartsBlankWithRequestedSize() {
        let grid = TerminalGrid(columns: 4, rows: 2)

        XCTAssertEqual(grid.columns, 4)
        XCTAssertEqual(grid.rows, 2)
        XCTAssertEqual(grid.cell(at: TerminalPoint(column: 0, row: 0)).character, " ")
        XCTAssertEqual(grid.cell(at: TerminalPoint(column: 3, row: 1)).character, " ")
    }

    func testSetCellStoresCharacterAndAttributes() {
        var grid = TerminalGrid(columns: 3, rows: 1)
        let attrs = TerminalAttributes(foreground: .ansi(index: 2), background: .ansi(index: 0), isBold: true)

        grid.setCell(TerminalCell(character: "A", attributes: attrs), at: TerminalPoint(column: 1, row: 0))

        XCTAssertEqual(grid.cell(at: TerminalPoint(column: 1, row: 0)).character, "A")
        XCTAssertEqual(grid.cell(at: TerminalPoint(column: 1, row: 0)).attributes, attrs)
    }

    func testClearLineResetsEveryCellOnRow() {
        var grid = TerminalGrid(columns: 3, rows: 2)
        grid.setCell(TerminalCell(character: "X"), at: TerminalPoint(column: 0, row: 1))
        grid.setCell(TerminalCell(character: "Y"), at: TerminalPoint(column: 2, row: 1))

        grid.clearLine(row: 1)

        XCTAssertEqual(grid.cell(at: TerminalPoint(column: 0, row: 1)), .blank)
        XCTAssertEqual(grid.cell(at: TerminalPoint(column: 2, row: 1)), .blank)
    }
}
```

- [ ] **Step 2: Run the failing grid tests**

Run: `swift test --filter TerminalCoreTests`

Expected: FAIL because `TerminalGrid`, `TerminalCell`, and related types do not exist.

- [ ] **Step 3: Add cell and attribute types**

Create `Sources/Wanda/TerminalCore/TerminalCell.swift`:

```swift
import Foundation

public struct TerminalPoint: Equatable, Hashable, Sendable {
    public var column: Int
    public var row: Int

    public init(column: Int, row: Int) {
        self.column = column
        self.row = row
    }
}

public enum TerminalColor: Equatable, Sendable {
    case `default`
    case ansi(index: UInt8)
    case rgb(red: UInt8, green: UInt8, blue: UInt8)
}

public struct TerminalAttributes: Equatable, Sendable {
    public var foreground: TerminalColor
    public var background: TerminalColor
    public var isBold: Bool
    public var isItalic: Bool
    public var isUnderline: Bool
    public var isInverse: Bool

    public init(
        foreground: TerminalColor = .default,
        background: TerminalColor = .default,
        isBold: Bool = false,
        isItalic: Bool = false,
        isUnderline: Bool = false,
        isInverse: Bool = false
    ) {
        self.foreground = foreground
        self.background = background
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderline = isUnderline
        self.isInverse = isInverse
    }
}

public struct TerminalCell: Equatable, Sendable {
    public var character: Character
    public var attributes: TerminalAttributes

    public init(character: Character = " ", attributes: TerminalAttributes = TerminalAttributes()) {
        self.character = character
        self.attributes = attributes
    }

    public static let blank = TerminalCell()
}
```

- [ ] **Step 4: Add fixed-size grid storage**

Create `Sources/Wanda/TerminalCore/TerminalGrid.swift`:

```swift
import Foundation

public struct TerminalGrid: Equatable, Sendable {
    public private(set) var columns: Int
    public private(set) var rows: Int
    private var cells: [TerminalCell]

    public init(columns: Int, rows: Int, fill: TerminalCell = .blank) {
        precondition(columns > 0, "TerminalGrid columns must be positive")
        precondition(rows > 0, "TerminalGrid rows must be positive")
        self.columns = columns
        self.rows = rows
        self.cells = Array(repeating: fill, count: columns * rows)
    }

    public func cell(at point: TerminalPoint) -> TerminalCell {
        cells[index(for: point)]
    }

    public mutating func setCell(_ cell: TerminalCell, at point: TerminalPoint) {
        cells[index(for: point)] = cell
    }

    public mutating func clearLine(row: Int) {
        precondition(row >= 0 && row < rows, "Row out of bounds")
        for column in 0..<columns {
            setCell(.blank, at: TerminalPoint(column: column, row: row))
        }
    }

    public mutating func clearAll() {
        cells = Array(repeating: .blank, count: columns * rows)
    }

    public func rowCells(_ row: Int) -> [TerminalCell] {
        precondition(row >= 0 && row < rows, "Row out of bounds")
        let start = row * columns
        return Array(cells[start..<(start + columns)])
    }

    private func index(for point: TerminalPoint) -> Int {
        precondition(point.column >= 0 && point.column < columns, "Column out of bounds")
        precondition(point.row >= 0 && point.row < rows, "Row out of bounds")
        return point.row * columns + point.column
    }
}
```

- [ ] **Step 5: Run grid tests**

Run: `swift test --filter TerminalCoreTests`

Expected: PASS for the three grid tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/Wanda/TerminalCore/TerminalCell.swift Sources/Wanda/TerminalCore/TerminalGrid.swift Tests/WandaTests/TerminalCoreTests.swift
git commit -m "feat: add terminal grid core"
```

## Task 3: Add Parser Events And Swift Parser Boundary

**Files:**
- Create: `Sources/Wanda/TerminalCore/TerminalEvent.swift`
- Create: `Sources/Wanda/TerminalCore/TerminalParser.swift`
- Modify: `Tests/WandaTests/TerminalCoreTests.swift`

- [ ] **Step 1: Add failing parser tests**

Append to `TerminalCoreTests`:

```swift
extension TerminalCoreTests {
    func testParserEmitsPrintableText() {
        var parser = SwiftTerminalParser()

        let events = parser.parse(Array("abc".utf8))

        XCTAssertEqual(events, [.print("a"), .print("b"), .print("c")])
    }

    func testParserEmitsCursorMoveForCSIH() {
        var parser = SwiftTerminalParser()

        let events = parser.parse(Array("\u{001B}[3;5H".utf8))

        XCTAssertEqual(events, [.moveCursor(row: 2, column: 4)])
    }

    func testParserBoundsOversizedCSIParameters() {
        var parser = SwiftTerminalParser(maxParameterDigits: 4)

        let events = parser.parse(Array("\u{001B}[12345;1H".utf8))

        XCTAssertEqual(events, [.malformedSequence])
    }
}
```

- [ ] **Step 2: Run parser tests to verify failure**

Run: `swift test --filter TerminalCoreTests/testParser`

Expected: FAIL because parser types do not exist.

- [ ] **Step 3: Add terminal event definitions**

Create `Sources/Wanda/TerminalCore/TerminalEvent.swift`:

```swift
import Foundation

public enum TerminalEvent: Equatable, Sendable {
    case print(Character)
    case moveCursor(row: Int, column: Int)
    case cursorUp(Int)
    case cursorDown(Int)
    case cursorForward(Int)
    case cursorBackward(Int)
    case carriageReturn
    case lineFeed
    case backspace
    case clearScreen
    case clearLine
    case setGraphicRendition([Int])
    case useAlternateScreen(Bool)
    case malformedSequence
}
```

- [ ] **Step 4: Add replaceable parser protocol and Swift parser**

Create `Sources/Wanda/TerminalCore/TerminalParser.swift`:

```swift
import Foundation

public protocol TerminalParser: Sendable {
    mutating func parse(_ bytes: [UInt8]) -> [TerminalEvent]
}

public struct SwiftTerminalParser: TerminalParser {
    private enum State {
        case ground
        case escape
        case csi(String)
    }

    private var state: State = .ground
    private let maxParameterDigits: Int

    public init(maxParameterDigits: Int = 8) {
        self.maxParameterDigits = maxParameterDigits
    }

    public mutating func parse(_ bytes: [UInt8]) -> [TerminalEvent] {
        var events: [TerminalEvent] = []

        for byte in bytes {
            switch state {
            case .ground:
                parseGround(byte, events: &events)
            case .escape:
                parseEscape(byte, events: &events)
            case .csi(let buffer):
                parseCSI(byte, buffer: buffer, events: &events)
            }
        }

        return events
    }

    private mutating func parseGround(_ byte: UInt8, events: inout [TerminalEvent]) {
        switch byte {
        case 0x08:
            events.append(.backspace)
        case 0x0A:
            events.append(.lineFeed)
        case 0x0D:
            events.append(.carriageReturn)
        case 0x1B:
            state = .escape
        case 0x20...0x7E:
            if let scalar = UnicodeScalar(Int(byte)) {
                events.append(.print(Character(scalar)))
            }
        default:
            break
        }
    }

    private mutating func parseEscape(_ byte: UInt8, events: inout [TerminalEvent]) {
        if byte == UInt8(ascii: "[") {
            state = .csi("")
        } else {
            events.append(.malformedSequence)
            state = .ground
        }
    }

    private mutating func parseCSI(_ byte: UInt8, buffer: String, events: inout [TerminalEvent]) {
        guard let scalar = UnicodeScalar(Int(byte)) else {
            events.append(.malformedSequence)
            state = .ground
            return
        }
        let character = Character(scalar)

        if byte >= 0x30 && byte <= 0x3F {
            let digitCount = buffer.reduce(0) { partial, char in
                char.isNumber ? partial + 1 : partial
            } + (character.isNumber ? 1 : 0)

            if digitCount > maxParameterDigits {
                events.append(.malformedSequence)
                state = .ground
                return
            }

            state = .csi(buffer + String(character))
            return
        }

        let parameters = buffer.split(separator: ";").map { Int($0) ?? 0 }
        switch byte {
        case UInt8(ascii: "H"), UInt8(ascii: "f"):
            let row = max((parameters.first ?? 1) - 1, 0)
            let column = max((parameters.dropFirst().first ?? 1) - 1, 0)
            events.append(.moveCursor(row: row, column: column))
        case UInt8(ascii: "A"):
            events.append(.cursorUp(max(parameters.first ?? 1, 1)))
        case UInt8(ascii: "B"):
            events.append(.cursorDown(max(parameters.first ?? 1, 1)))
        case UInt8(ascii: "C"):
            events.append(.cursorForward(max(parameters.first ?? 1, 1)))
        case UInt8(ascii: "D"):
            events.append(.cursorBackward(max(parameters.first ?? 1, 1)))
        case UInt8(ascii: "J"):
            events.append(.clearScreen)
        case UInt8(ascii: "K"):
            events.append(.clearLine)
        case UInt8(ascii: "m"):
            events.append(.setGraphicRendition(parameters.isEmpty ? [0] : parameters))
        case UInt8(ascii: "h") where buffer == "?1049":
            events.append(.useAlternateScreen(true))
        case UInt8(ascii: "l") where buffer == "?1049":
            events.append(.useAlternateScreen(false))
        default:
            events.append(.malformedSequence)
        }
        state = .ground
    }
}
```

- [ ] **Step 5: Run parser tests**

Run: `swift test --filter TerminalCoreTests/testParser`

Expected: PASS.

- [ ] **Step 6: Run all tests**

Run: `swift test`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/Wanda/TerminalCore/TerminalEvent.swift Sources/Wanda/TerminalCore/TerminalParser.swift Tests/WandaTests/TerminalCoreTests.swift
git commit -m "feat: add replaceable terminal parser"
```

## Task 4: Add Terminal Model, Cursor, Dirty Ranges, And Alternate Screen

**Files:**
- Create: `Sources/Wanda/TerminalCore/TerminalModel.swift`
- Modify: `Sources/Wanda/TerminalCore/TerminalGrid.swift`
- Modify: `Tests/WandaTests/TerminalCoreTests.swift`

- [ ] **Step 1: Add failing model tests**

Append to `TerminalCoreTests`:

```swift
extension TerminalCoreTests {
    func testModelPrintsAndAdvancesCursor() {
        var model = TerminalModel(columns: 4, rows: 2, scrollbackLimit: 10)

        model.apply(.print("A"))
        model.apply(.print("B"))

        XCTAssertEqual(model.visibleGrid.cell(at: TerminalPoint(column: 0, row: 0)).character, "A")
        XCTAssertEqual(model.visibleGrid.cell(at: TerminalPoint(column: 1, row: 0)).character, "B")
        XCTAssertEqual(model.cursor, TerminalPoint(column: 2, row: 0))
        XCTAssertEqual(model.dirtyRows, Set([0]))
    }

    func testModelScrollsIntoBoundedScrollback() {
        var model = TerminalModel(columns: 2, rows: 2, scrollbackLimit: 1)

        for character in "abcdefgh" {
            model.apply(.print(character))
        }

        XCTAssertEqual(model.scrollback.count, 1)
        XCTAssertEqual(String(model.scrollback[0].map(\.character)), "cd")
        XCTAssertEqual(String(model.visibleGrid.rowCells(0).map(\.character)), "ef")
    }

    func testAlternateScreenDoesNotMutateScrollback() {
        var model = TerminalModel(columns: 3, rows: 2, scrollbackLimit: 5)
        model.apply(.print("A"))

        model.apply(.useAlternateScreen(true))
        model.apply(.print("B"))
        model.apply(.useAlternateScreen(false))

        XCTAssertEqual(model.visibleGrid.cell(at: TerminalPoint(column: 0, row: 0)).character, "A")
        XCTAssertEqual(model.scrollback.count, 0)
    }
}
```

- [ ] **Step 2: Run model tests to verify failure**

Run: `swift test --filter TerminalCoreTests/testModel`

Expected: FAIL because `TerminalModel` does not exist.

- [ ] **Step 3: Add row replacement support to the grid**

Modify `Sources/Wanda/TerminalCore/TerminalGrid.swift`:

```swift
import Foundation

public struct TerminalGrid: Equatable, Sendable {
    public private(set) var columns: Int
    public private(set) var rows: Int
    private var cells: [TerminalCell]

    public init(columns: Int, rows: Int, fill: TerminalCell = .blank) {
        precondition(columns > 0, "TerminalGrid columns must be positive")
        precondition(rows > 0, "TerminalGrid rows must be positive")
        self.columns = columns
        self.rows = rows
        self.cells = Array(repeating: fill, count: columns * rows)
    }

    public func cell(at point: TerminalPoint) -> TerminalCell {
        cells[index(for: point)]
    }

    public mutating func setCell(_ cell: TerminalCell, at point: TerminalPoint) {
        cells[index(for: point)] = cell
    }

    public mutating func clearLine(row: Int) {
        precondition(row >= 0 && row < rows, "Row out of bounds")
        for column in 0..<columns {
            setCell(.blank, at: TerminalPoint(column: column, row: row))
        }
    }

    public mutating func clearAll() {
        cells = Array(repeating: .blank, count: columns * rows)
    }

    public func rowCells(_ row: Int) -> [TerminalCell] {
        precondition(row >= 0 && row < rows, "Row out of bounds")
        let start = row * columns
        return Array(cells[start..<(start + columns)])
    }

    public mutating func replaceRow(_ row: Int, with newCells: [TerminalCell]) {
        precondition(row >= 0 && row < rows, "Row out of bounds")
        precondition(newCells.count == columns, "Replacement row must match grid width")
        let start = row * columns
        cells.replaceSubrange(start..<(start + columns), with: newCells)
    }

    public mutating func scrollUpOneLine() -> [TerminalCell] {
        let removed = rowCells(0)
        for row in 1..<rows {
            replaceRow(row - 1, with: rowCells(row))
        }
        replaceRow(rows - 1, with: Array(repeating: .blank, count: columns))
        return removed
    }

    private func index(for point: TerminalPoint) -> Int {
        precondition(point.column >= 0 && point.column < columns, "Column out of bounds")
        precondition(point.row >= 0 && point.row < rows, "Row out of bounds")
        return point.row * columns + point.column
    }
}
```

- [ ] **Step 4: Add terminal model**

Create `Sources/Wanda/TerminalCore/TerminalModel.swift`:

```swift
import Foundation

public struct TerminalModel: Sendable {
    public private(set) var primaryGrid: TerminalGrid
    private var alternateGrid: TerminalGrid
    public private(set) var cursor: TerminalPoint
    private var primaryCursor: TerminalPoint
    private var alternateCursor: TerminalPoint
    public private(set) var scrollback: [[TerminalCell]]
    public private(set) var dirtyRows: Set<Int>
    public private(set) var isUsingAlternateScreen: Bool
    private let scrollbackLimit: Int
    private var attributes: TerminalAttributes

    public init(columns: Int, rows: Int, scrollbackLimit: Int) {
        self.primaryGrid = TerminalGrid(columns: columns, rows: rows)
        self.alternateGrid = TerminalGrid(columns: columns, rows: rows)
        self.cursor = TerminalPoint(column: 0, row: 0)
        self.primaryCursor = cursor
        self.alternateCursor = cursor
        self.scrollback = []
        self.dirtyRows = []
        self.isUsingAlternateScreen = false
        self.scrollbackLimit = max(scrollbackLimit, 0)
        self.attributes = TerminalAttributes()
    }

    public var visibleGrid: TerminalGrid {
        isUsingAlternateScreen ? alternateGrid : primaryGrid
    }

    public mutating func apply(_ event: TerminalEvent) {
        switch event {
        case .print(let character):
            print(character)
        case .moveCursor(let row, let column):
            setCursor(row: row, column: column)
        case .cursorUp(let amount):
            setCursor(row: cursor.row - amount, column: cursor.column)
        case .cursorDown(let amount):
            setCursor(row: cursor.row + amount, column: cursor.column)
        case .cursorForward(let amount):
            setCursor(row: cursor.row, column: cursor.column + amount)
        case .cursorBackward(let amount):
            setCursor(row: cursor.row, column: cursor.column - amount)
        case .carriageReturn:
            setCursor(row: cursor.row, column: 0)
        case .lineFeed:
            lineFeed()
        case .backspace:
            setCursor(row: cursor.row, column: cursor.column - 1)
        case .clearScreen:
            mutateVisibleGrid { $0.clearAll() }
            dirtyRows.formUnion(0..<visibleGrid.rows)
            setCursor(row: 0, column: 0)
        case .clearLine:
            mutateVisibleGrid { $0.clearLine(row: cursor.row) }
            dirtyRows.insert(cursor.row)
        case .setGraphicRendition(let values):
            applySGR(values)
        case .useAlternateScreen(let enabled):
            useAlternateScreen(enabled)
        case .malformedSequence:
            break
        }
    }

    public mutating func drainDirtyRows() -> Set<Int> {
        let rows = dirtyRows
        dirtyRows.removeAll()
        return rows
    }

    private mutating func print(_ character: Character) {
        if cursor.column >= visibleGrid.columns {
            lineFeed()
            setCursor(row: cursor.row, column: 0)
        }

        mutateVisibleGrid {
            $0.setCell(TerminalCell(character: character, attributes: attributes), at: cursor)
        }
        dirtyRows.insert(cursor.row)
        setCursor(row: cursor.row, column: cursor.column + 1)
    }

    private mutating func lineFeed() {
        if cursor.row == visibleGrid.rows - 1 {
            let removed = mutateVisibleGridReturningRemovedRow()
            if !isUsingAlternateScreen && scrollbackLimit > 0 {
                scrollback.append(removed)
                if scrollback.count > scrollbackLimit {
                    scrollback.removeFirst(scrollback.count - scrollbackLimit)
                }
            }
            dirtyRows.formUnion(0..<visibleGrid.rows)
        } else {
            setCursor(row: cursor.row + 1, column: cursor.column)
        }
    }

    private mutating func setCursor(row: Int, column: Int) {
        let boundedRow = min(max(row, 0), visibleGrid.rows - 1)
        let boundedColumn = min(max(column, 0), visibleGrid.columns)
        cursor = TerminalPoint(column: boundedColumn, row: boundedRow)
        if isUsingAlternateScreen {
            alternateCursor = cursor
        } else {
            primaryCursor = cursor
        }
    }

    private mutating func mutateVisibleGrid(_ body: (inout TerminalGrid) -> Void) {
        if isUsingAlternateScreen {
            body(&alternateGrid)
        } else {
            body(&primaryGrid)
        }
    }

    private mutating func mutateVisibleGridReturningRemovedRow() -> [TerminalCell] {
        if isUsingAlternateScreen {
            return alternateGrid.scrollUpOneLine()
        }
        return primaryGrid.scrollUpOneLine()
    }

    private mutating func useAlternateScreen(_ enabled: Bool) {
        guard enabled != isUsingAlternateScreen else { return }
        if enabled {
            primaryCursor = cursor
            alternateGrid.clearAll()
            alternateCursor = TerminalPoint(column: 0, row: 0)
            cursor = alternateCursor
            isUsingAlternateScreen = true
        } else {
            alternateCursor = cursor
            cursor = primaryCursor
            isUsingAlternateScreen = false
        }
        dirtyRows.formUnion(0..<visibleGrid.rows)
    }

    private mutating func applySGR(_ values: [Int]) {
        if values.isEmpty || values.contains(0) {
            attributes = TerminalAttributes()
            return
        }

        for value in values {
            switch value {
            case 1:
                attributes.isBold = true
            case 3:
                attributes.isItalic = true
            case 4:
                attributes.isUnderline = true
            case 7:
                attributes.isInverse = true
            case 30...37:
                attributes.foreground = .ansi(index: UInt8(value - 30))
            case 40...47:
                attributes.background = .ansi(index: UInt8(value - 40))
            default:
                break
            }
        }
    }
}
```

- [ ] **Step 5: Run model tests**

Run: `swift test --filter TerminalCoreTests/testModel`

Expected: PASS.

- [ ] **Step 6: Run all terminal core tests**

Run: `swift test --filter TerminalCoreTests`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/Wanda/TerminalCore/TerminalGrid.swift Sources/Wanda/TerminalCore/TerminalModel.swift Tests/WandaTests/TerminalCoreTests.swift
git commit -m "feat: add terminal model state"
```

## Task 5: Add Cell-Aware Selection And Double-Click Token Rules

**Files:**
- Create: `Sources/Wanda/TerminalCore/TerminalSelection.swift`
- Create: `Tests/WandaTests/TerminalSelectionTests.swift`

- [ ] **Step 1: Write failing selection tests**

Create `Tests/WandaTests/TerminalSelectionTests.swift`:

```swift
import XCTest
@testable import Wanda

final class TerminalSelectionTests: XCTestCase {
    func testLinearSelectionCopiesAcrossCells() {
        var grid = TerminalGrid(columns: 5, rows: 2)
        for (index, character) in Array("hello").enumerated() {
            grid.setCell(TerminalCell(character: character), at: TerminalPoint(column: index, row: 0))
        }
        for (index, character) in Array("world").enumerated() {
            grid.setCell(TerminalCell(character: character), at: TerminalPoint(column: index, row: 1))
        }

        let selection = TerminalSelection(start: TerminalPoint(column: 1, row: 0), end: TerminalPoint(column: 2, row: 1))

        XCTAssertEqual(selection.string(in: grid), "ello\nwor")
    }

    func testDoubleClickTokenKeepsURLCharacters() {
        var grid = TerminalGrid(columns: 40, rows: 1)
        let text = "open https://example.com/a-b?q=1 now"
        for (index, character) in Array(text).enumerated() {
            grid.setCell(TerminalCell(character: character), at: TerminalPoint(column: index, row: 0))
        }

        let token = TerminalSelection.token(at: TerminalPoint(column: 14, row: 0), in: grid)

        XCTAssertEqual(token.string(in: grid), "https://example.com/a-b?q=1")
    }

    func testDoubleClickTokenStopsAtWhitespace() {
        var grid = TerminalGrid(columns: 20, rows: 1)
        for (index, character) in Array("alpha beta").enumerated() {
            grid.setCell(TerminalCell(character: character), at: TerminalPoint(column: index, row: 0))
        }

        let token = TerminalSelection.token(at: TerminalPoint(column: 7, row: 0), in: grid)

        XCTAssertEqual(token.string(in: grid), "beta")
    }
}
```

- [ ] **Step 2: Run selection tests to verify failure**

Run: `swift test --filter TerminalSelectionTests`

Expected: FAIL because `TerminalSelection` does not exist.

- [ ] **Step 3: Add selection implementation**

Create `Sources/Wanda/TerminalCore/TerminalSelection.swift`:

```swift
import Foundation

public struct TerminalSelection: Equatable, Sendable {
    public var start: TerminalPoint
    public var end: TerminalPoint

    public init(start: TerminalPoint, end: TerminalPoint) {
        self.start = start
        self.end = end
    }

    public func string(in grid: TerminalGrid) -> String {
        let ordered = orderedEndpoints()
        var rows: [String] = []

        for row in ordered.start.row...ordered.end.row {
            let startColumn = row == ordered.start.row ? ordered.start.column : 0
            let endColumn = row == ordered.end.row ? ordered.end.column : grid.columns - 1
            let characters = (startColumn...endColumn).map {
                grid.cell(at: TerminalPoint(column: $0, row: row)).character
            }
            rows.append(String(characters).trimmedTrailingSpaces())
        }

        return rows.joined(separator: "\n")
    }

    public static func token(at point: TerminalPoint, in grid: TerminalGrid) -> TerminalSelection {
        let row = point.row
        var left = point.column
        var right = point.column

        while left > 0 && isTokenCharacter(grid.cell(at: TerminalPoint(column: left - 1, row: row)).character) {
            left -= 1
        }

        while right < grid.columns - 1 && isTokenCharacter(grid.cell(at: TerminalPoint(column: right + 1, row: row)).character) {
            right += 1
        }

        return TerminalSelection(start: TerminalPoint(column: left, row: row), end: TerminalPoint(column: right, row: row))
    }

    private func orderedEndpoints() -> (start: TerminalPoint, end: TerminalPoint) {
        if start.row < end.row || (start.row == end.row && start.column <= end.column) {
            return (start, end)
        }
        return (end, start)
    }

    private static func isTokenCharacter(_ character: Character) -> Bool {
        if character.isWhitespace {
            return false
        }
        let delimiters = CharacterSet(charactersIn: "\"'`()[]{}<>")
        return String(character).unicodeScalars.allSatisfy { !delimiters.contains($0) }
    }
}

private extension String {
    func trimmedTrailingSpaces() -> String {
        var copy = self
        while copy.last == " " {
            copy.removeLast()
        }
        return copy
    }
}
```

- [ ] **Step 4: Run selection tests**

Run: `swift test --filter TerminalSelectionTests`

Expected: PASS.

- [ ] **Step 5: Run all tests**

Run: `swift test`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/Wanda/TerminalCore/TerminalSelection.swift Tests/WandaTests/TerminalSelectionTests.swift
git commit -m "feat: add terminal selection rules"
```

## Task 6: Add Key Mapping Boundary

**Files:**
- Create: `Sources/Wanda/Input/TerminalKeyEvent.swift`
- Create: `Sources/Wanda/Input/TerminalKeyMapper.swift`
- Create: `Tests/WandaTests/TerminalKeyMapperTests.swift`

- [ ] **Step 1: Write failing key mapping tests**

Create `Tests/WandaTests/TerminalKeyMapperTests.swift`:

```swift
import XCTest
@testable import Wanda

final class TerminalKeyMapperTests: XCTestCase {
    func testPrintableCharacterMapsToUTF8Bytes() {
        let mapper = TerminalKeyMapper()

        XCTAssertEqual(mapper.bytes(for: .printable("a")), Array("a".utf8))
    }

    func testOptionLeftMapsToEscapeB() {
        let mapper = TerminalKeyMapper()

        XCTAssertEqual(mapper.bytes(for: .special(.leftArrow, modifiers: [.option])), [0x1B, UInt8(ascii: "b")])
    }

    func testOptionRightMapsToEscapeF() {
        let mapper = TerminalKeyMapper()

        XCTAssertEqual(mapper.bytes(for: .special(.rightArrow, modifiers: [.option])), [0x1B, UInt8(ascii: "f")])
    }

    func testCommandLeftAndRightMapToLineBoundaries() {
        let mapper = TerminalKeyMapper()

        XCTAssertEqual(mapper.bytes(for: .special(.leftArrow, modifiers: [.command])), [0x01])
        XCTAssertEqual(mapper.bytes(for: .special(.rightArrow, modifiers: [.command])), [0x05])
    }
}
```

- [ ] **Step 2: Run key mapping tests to verify failure**

Run: `swift test --filter TerminalKeyMapperTests`

Expected: FAIL because input types do not exist.

- [ ] **Step 3: Add testable key event values**

Create `Sources/Wanda/Input/TerminalKeyEvent.swift`:

```swift
import Foundation

public enum TerminalKeyEvent: Equatable, Sendable {
    case printable(String)
    case special(TerminalSpecialKey, modifiers: TerminalKeyModifiers)
}

public enum TerminalSpecialKey: Equatable, Sendable {
    case leftArrow
    case rightArrow
    case upArrow
    case downArrow
    case returnKey
    case delete
    case tab
}

public struct TerminalKeyModifiers: OptionSet, Equatable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let option = TerminalKeyModifiers(rawValue: 1 << 0)
    public static let command = TerminalKeyModifiers(rawValue: 1 << 1)
    public static let control = TerminalKeyModifiers(rawValue: 1 << 2)
    public static let shift = TerminalKeyModifiers(rawValue: 1 << 3)
}
```

- [ ] **Step 4: Add key mapper**

Create `Sources/Wanda/Input/TerminalKeyMapper.swift`:

```swift
import Foundation

public struct TerminalKeyMapper: Sendable {
    public init() {}

    public func bytes(for event: TerminalKeyEvent) -> [UInt8] {
        switch event {
        case .printable(let string):
            return Array(string.utf8)
        case .special(let key, let modifiers):
            return bytes(for: key, modifiers: modifiers)
        }
    }

    private func bytes(for key: TerminalSpecialKey, modifiers: TerminalKeyModifiers) -> [UInt8] {
        if key == .leftArrow && modifiers.contains(.option) {
            return [0x1B, UInt8(ascii: "b")]
        }
        if key == .rightArrow && modifiers.contains(.option) {
            return [0x1B, UInt8(ascii: "f")]
        }
        if key == .leftArrow && modifiers.contains(.command) {
            return [0x01]
        }
        if key == .rightArrow && modifiers.contains(.command) {
            return [0x05]
        }

        switch key {
        case .leftArrow:
            return Array("\u{001B}[D".utf8)
        case .rightArrow:
            return Array("\u{001B}[C".utf8)
        case .upArrow:
            return Array("\u{001B}[A".utf8)
        case .downArrow:
            return Array("\u{001B}[B".utf8)
        case .returnKey:
            return [0x0D]
        case .delete:
            return [0x7F]
        case .tab:
            return [0x09]
        }
    }
}
```

- [ ] **Step 5: Run key mapping tests**

Run: `swift test --filter TerminalKeyMapperTests`

Expected: PASS.

- [ ] **Step 6: Run all tests**

Run: `swift test`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/Wanda/Input/TerminalKeyEvent.swift Sources/Wanda/Input/TerminalKeyMapper.swift Tests/WandaTests/TerminalKeyMapperTests.swift
git commit -m "feat: add terminal key mapping"
```

## Task 7: Add Geometry Persistence

**Files:**
- Create: `Sources/Wanda/App/GeometryStore.swift`
- Create: `Tests/WandaTests/GeometryStoreTests.swift`

- [ ] **Step 1: Write failing geometry tests**

Create `Tests/WandaTests/GeometryStoreTests.swift`:

```swift
import CoreGraphics
import XCTest
@testable import Wanda

final class GeometryStoreTests: XCTestCase {
    func testSavesAndLoadsWindowFrame() throws {
        let defaults = UserDefaults(suiteName: "wanda.geometry.test.\(UUID().uuidString)")!
        let store = GeometryStore(defaults: defaults)
        let frame = CGRect(x: 10, y: 20, width: 800, height: 500)

        store.save(frame: frame)

        XCTAssertEqual(store.load(validatingAgainst: CGRect(x: 0, y: 0, width: 1600, height: 1000)), frame)
    }

    func testInvalidOffscreenFrameFallsBackToDefault() {
        let defaults = UserDefaults(suiteName: "wanda.geometry.test.\(UUID().uuidString)")!
        let store = GeometryStore(defaults: defaults)

        store.save(frame: CGRect(x: 9000, y: 9000, width: 800, height: 500))

        XCTAssertEqual(
            store.load(validatingAgainst: CGRect(x: 0, y: 0, width: 1600, height: 1000)),
            GeometryStore.defaultFrame
        )
    }
}
```

- [ ] **Step 2: Run geometry tests to verify failure**

Run: `swift test --filter GeometryStoreTests`

Expected: FAIL because `GeometryStore` does not exist.

- [ ] **Step 3: Add geometry store**

Create `Sources/Wanda/App/GeometryStore.swift`:

```swift
import CoreGraphics
import Foundation

public struct GeometryStore {
    public static let defaultFrame = CGRect(x: 100, y: 100, width: 900, height: 560)

    private let defaults: UserDefaults
    private let key = "wanda.window.frame"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func save(frame: CGRect) {
        defaults.set(NSStringFromRect(NSRectFromCGRect(frame)), forKey: key)
    }

    public func load(validatingAgainst visibleFrame: CGRect) -> CGRect {
        guard
            let string = defaults.string(forKey: key),
            !string.isEmpty
        else {
            return Self.defaultFrame
        }

        let frame = NSRectFromString(string)
        guard frame.width >= 320, frame.height >= 200, visibleFrame.intersects(frame) else {
            return Self.defaultFrame
        }

        return frame
    }
}
```

- [ ] **Step 4: Run geometry tests**

Run: `swift test --filter GeometryStoreTests`

Expected: PASS.

- [ ] **Step 5: Run all tests**

Run: `swift test`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/Wanda/App/GeometryStore.swift Tests/WandaTests/GeometryStoreTests.swift
git commit -m "feat: add window geometry persistence"
```

## Task 8: Add PTY Protocol And POSIX PTY Adapter

**Files:**
- Create: `Sources/Wanda/PTY/PseudoTerminalTypes.swift`
- Create: `Sources/Wanda/PTY/PseudoTerminal.swift`
- Create: `Tests/WandaTests/PseudoTerminalTests.swift`

- [ ] **Step 1: Write failing PTY integration tests**

Create `Tests/WandaTests/PseudoTerminalTests.swift`:

```swift
import XCTest
@testable import Wanda

final class PseudoTerminalTests: XCTestCase {
    func testLaunchesShellAndEchoesInput() async throws {
        let pty = try PosixPseudoTerminal(
            executablePath: "/bin/sh",
            arguments: ["sh"],
            environment: ["TERM": "xterm-256color", "PS1": ""],
            size: TerminalSize(columns: 80, rows: 24)
        )
        defer { pty.terminate() }

        try pty.write(Array("printf wanda\n".utf8))
        let output = try await pty.readUntilString("wanda", timeoutNanoseconds: 2_000_000_000)

        XCTAssertTrue(output.contains("wanda"))
    }

    func testResizeUpdatesStoredSize() throws {
        let pty = try PosixPseudoTerminal(
            executablePath: "/bin/sh",
            arguments: ["sh"],
            environment: ["TERM": "xterm-256color", "PS1": ""],
            size: TerminalSize(columns: 80, rows: 24)
        )
        defer { pty.terminate() }

        try pty.resize(TerminalSize(columns: 100, rows: 40))

        XCTAssertEqual(pty.currentSize, TerminalSize(columns: 100, rows: 40))
    }
}
```

- [ ] **Step 2: Run PTY tests to verify failure**

Run: `swift test --filter PseudoTerminalTests`

Expected: FAIL because PTY types do not exist.

- [ ] **Step 3: Add PTY types**

Create `Sources/Wanda/PTY/PseudoTerminalTypes.swift`:

```swift
import Foundation

public struct TerminalSize: Equatable, Sendable {
    public var columns: Int
    public var rows: Int

    public init(columns: Int, rows: Int) {
        precondition(columns > 0, "columns must be positive")
        precondition(rows > 0, "rows must be positive")
        self.columns = columns
        self.rows = rows
    }
}

public enum PseudoTerminalState: Equatable, Sendable {
    case running
    case terminating
    case exited(Int32)
    case failed(String)
}

public enum PseudoTerminalError: Error, Equatable {
    case openFailed
    case forkFailed
    case execFailed
    case writeFailed(Int32)
    case readFailed(Int32)
    case resizeFailed(Int32)
    case timedOut
}
```

- [ ] **Step 4: Add POSIX PTY implementation**

Create `Sources/Wanda/PTY/PseudoTerminal.swift`:

```swift
import Darwin
import Foundation

public protocol PseudoTerminal: AnyObject, Sendable {
    var state: PseudoTerminalState { get }
    var currentSize: TerminalSize { get }
    func write(_ bytes: [UInt8]) throws
    func resize(_ size: TerminalSize) throws
    func terminate()
}

public final class PosixPseudoTerminal: PseudoTerminal, @unchecked Sendable {
    private let masterFileDescriptor: Int32
    private let childPID: pid_t
    private let lock = NSLock()
    private var storedState: PseudoTerminalState = .running
    private var storedSize: TerminalSize

    public var state: PseudoTerminalState {
        lock.withLock { storedState }
    }

    public var currentSize: TerminalSize {
        lock.withLock { storedSize }
    }

    public init(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        size: TerminalSize
    ) throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        guard openpty(&master, &slave, nil, nil, nil) == 0 else {
            throw PseudoTerminalError.openFailed
        }

        var windowSize = winsize(ws_row: UInt16(size.rows), ws_col: UInt16(size.columns), ws_xpixel: 0, ws_ypixel: 0)
        ioctl(slave, TIOCSWINSZ, &windowSize)

        let pid = fork()
        if pid < 0 {
            close(master)
            close(slave)
            throw PseudoTerminalError.forkFailed
        }

        if pid == 0 {
            close(master)
            setsid()
            ioctl(slave, TIOCSCTTY, 0)
            dup2(slave, STDIN_FILENO)
            dup2(slave, STDOUT_FILENO)
            dup2(slave, STDERR_FILENO)
            if slave > STDERR_FILENO {
                close(slave)
            }

            let argv = arguments.isEmpty ? [executablePath] : arguments
            let cArguments = argv.map { strdup($0) } + [nil]
            let cEnvironment = environment.map { "\($0.key)=\($0.value)" }.map { strdup($0) } + [nil]
            execve(executablePath, cArguments, cEnvironment)
            _exit(127)
        }

        close(slave)
        self.masterFileDescriptor = master
        self.childPID = pid
        self.storedSize = size
        try setNonBlocking(master)
    }

    deinit {
        terminate()
        close(masterFileDescriptor)
    }

    public func write(_ bytes: [UInt8]) throws {
        try bytes.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var written = 0
            while written < rawBuffer.count {
                let result = Darwin.write(masterFileDescriptor, baseAddress.advanced(by: written), rawBuffer.count - written)
                if result < 0 {
                    if errno == EAGAIN || errno == EWOULDBLOCK {
                        continue
                    }
                    throw PseudoTerminalError.writeFailed(errno)
                }
                written += result
            }
        }
    }

    public func resize(_ size: TerminalSize) throws {
        var windowSize = winsize(ws_row: UInt16(size.rows), ws_col: UInt16(size.columns), ws_xpixel: 0, ws_ypixel: 0)
        guard ioctl(masterFileDescriptor, TIOCSWINSZ, &windowSize) == 0 else {
            throw PseudoTerminalError.resizeFailed(errno)
        }
        lock.withLock {
            storedSize = size
        }
    }

    public func terminate() {
        lock.withLock {
            if case .running = storedState {
                storedState = .terminating
                kill(childPID, SIGTERM)
            }
        }
    }

    public func readAvailableBytes(maxBytes: Int = 4096) throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: maxBytes)
        let result = Darwin.read(masterFileDescriptor, &buffer, maxBytes)
        if result > 0 {
            return Array(buffer.prefix(result))
        }
        if result == 0 || errno == EAGAIN || errno == EWOULDBLOCK {
            return []
        }
        throw PseudoTerminalError.readFailed(errno)
    }

    public func readUntilString(_ expected: String, timeoutNanoseconds: UInt64) async throws -> String {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        var output = ""

        while DispatchTime.now().uptimeNanoseconds < deadline {
            let bytes = try readAvailableBytes()
            if !bytes.isEmpty {
                output += String(decoding: bytes, as: UTF8.self)
                if output.contains(expected) {
                    return output
                }
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        throw PseudoTerminalError.timedOut
    }

    private func setNonBlocking(_ fd: Int32) throws {
        let flags = fcntl(fd, F_GETFL, 0)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else {
            throw PseudoTerminalError.readFailed(errno)
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
```

- [ ] **Step 5: Run PTY tests**

Run: `swift test --filter PseudoTerminalTests`

Expected: PASS.

- [ ] **Step 6: Run all tests**

Run: `swift test`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/Wanda/PTY/PseudoTerminalTypes.swift Sources/Wanda/PTY/PseudoTerminal.swift Tests/WandaTests/PseudoTerminalTests.swift
git commit -m "feat: add posix pseudo terminal"
```

## Task 9: Add Render Snapshots And Glyph Atlas

**Files:**
- Create: `Sources/Wanda/Rendering/TerminalRendererSnapshot.swift`
- Create: `Sources/Wanda/Rendering/GlyphAtlas.swift`
- Create: `Tests/WandaTests/RenderingTests.swift`

- [ ] **Step 1: Write failing rendering metadata tests**

Create `Tests/WandaTests/RenderingTests.swift`:

```swift
import XCTest
@testable import Wanda

final class RenderingTests: XCTestCase {
    func testSnapshotCapturesGridCursorAndDirtyRows() {
        var model = TerminalModel(columns: 3, rows: 2, scrollbackLimit: 10)
        model.apply(.print("A"))

        let snapshot = TerminalRendererSnapshot(model: model)

        XCTAssertEqual(snapshot.columns, 3)
        XCTAssertEqual(snapshot.rows, 2)
        XCTAssertEqual(snapshot.cells[0].character, "A")
        XCTAssertEqual(snapshot.cursor, TerminalPoint(column: 1, row: 0))
        XCTAssertEqual(snapshot.dirtyRows, Set([0]))
    }

    func testGlyphAtlasComputesStableCellMetrics() throws {
        let atlas = try GlyphAtlas(fontName: "Menlo", fontSize: 14)

        XCTAssertGreaterThan(atlas.cellSize.width, 0)
        XCTAssertGreaterThan(atlas.cellSize.height, 0)
        XCTAssertNotNil(atlas.glyph(for: "A"))
    }
}
```

- [ ] **Step 2: Run rendering tests to verify failure**

Run: `swift test --filter RenderingTests`

Expected: FAIL because rendering types do not exist.

- [ ] **Step 3: Add render snapshot**

Create `Sources/Wanda/Rendering/TerminalRendererSnapshot.swift`:

```swift
import Foundation

public struct TerminalRendererSnapshot: Sendable {
    public var columns: Int
    public var rows: Int
    public var cells: [TerminalCell]
    public var cursor: TerminalPoint
    public var dirtyRows: Set<Int>

    public init(model: TerminalModel) {
        let grid = model.visibleGrid
        self.columns = grid.columns
        self.rows = grid.rows
        self.cells = (0..<grid.rows).flatMap { row in
            grid.rowCells(row)
        }
        self.cursor = model.cursor
        self.dirtyRows = model.dirtyRows
    }
}
```

- [ ] **Step 4: Add CoreText glyph atlas metadata**

Create `Sources/Wanda/Rendering/GlyphAtlas.swift`:

```swift
import AppKit
import CoreGraphics
import CoreText
import Foundation

public struct GlyphAtlasEntry: Equatable, Sendable {
    public var character: Character
    public var advance: CGFloat
    public var bounds: CGRect
}

public enum GlyphAtlasError: Error, Equatable {
    case missingFont(String)
}

public final class GlyphAtlas: @unchecked Sendable {
    public let font: CTFont
    public let cellSize: CGSize
    private let entries: [Character: GlyphAtlasEntry]

    public init(fontName: String, fontSize: CGFloat) throws {
        guard let nsFont = NSFont(name: fontName, size: fontSize) else {
            throw GlyphAtlasError.missingFont(fontName)
        }

        self.font = nsFont as CTFont
        let width = ceil("W".size(withAttributes: [.font: nsFont]).width)
        let height = ceil(nsFont.ascender - nsFont.descender + nsFont.leading)
        self.cellSize = CGSize(width: max(width, 1), height: max(height, 1))

        var built: [Character: GlyphAtlasEntry] = [:]
        for scalar in UInt8(ascii: " ")...UInt8(ascii: "~") {
            let character = Character(UnicodeScalar(scalar))
            let string = String(character)
            built[character] = GlyphAtlasEntry(
                character: character,
                advance: ceil(string.size(withAttributes: [.font: nsFont]).width),
                bounds: CGRect(origin: .zero, size: cellSize)
            )
        }
        self.entries = built
    }

    public func glyph(for character: Character) -> GlyphAtlasEntry? {
        entries[character]
    }
}
```

- [ ] **Step 5: Run rendering metadata tests**

Run: `swift test --filter RenderingTests`

Expected: PASS.

- [ ] **Step 6: Run all tests**

Run: `swift test`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/Wanda/Rendering/TerminalRendererSnapshot.swift Sources/Wanda/Rendering/GlyphAtlas.swift Tests/WandaTests/RenderingTests.swift
git commit -m "feat: add renderer snapshots and glyph atlas"
```

## Task 10: Add Metal View And Renderer Skeleton

**Files:**
- Create: `Sources/Wanda/Rendering/TerminalMetalRenderer.swift`
- Create: `Sources/Wanda/Rendering/TerminalMetalView.swift`
- Create: `Sources/Wanda/App/TerminalMetalViewRepresentable.swift`
- Modify: `Tests/WandaTests/RenderingTests.swift`

- [ ] **Step 1: Add failing renderer lifecycle test**

Append to `RenderingTests`:

```swift
extension RenderingTests {
    func testMetalRendererAcceptsSnapshot() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable")
        }

        let renderer = try TerminalMetalRenderer(device: device)
        var model = TerminalModel(columns: 2, rows: 1, scrollbackLimit: 5)
        model.apply(.print("A"))

        renderer.update(snapshot: TerminalRendererSnapshot(model: model))

        XCTAssertEqual(renderer.lastSnapshot?.cells.first?.character, "A")
    }
}
```

- [ ] **Step 2: Run renderer lifecycle test to verify failure**

Run: `swift test --filter RenderingTests/testMetalRendererAcceptsSnapshot`

Expected: FAIL because `TerminalMetalRenderer` does not exist.

- [ ] **Step 3: Add Metal renderer skeleton**

Create `Sources/Wanda/Rendering/TerminalMetalRenderer.swift`:

```swift
import Metal
import MetalKit

public final class TerminalMetalRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {
    public let device: MTLDevice
    public private(set) var lastSnapshot: TerminalRendererSnapshot?
    private let commandQueue: MTLCommandQueue
    private var framePresented: ((UInt64) -> Void)?

    public init(device: MTLDevice, framePresented: ((UInt64) -> Void)? = nil) throws {
        guard let commandQueue = device.makeCommandQueue() else {
            throw RendererError.commandQueueUnavailable
        }
        self.device = device
        self.commandQueue = commandQueue
        self.framePresented = framePresented
        super.init()
    }

    public func update(snapshot: TerminalRendererSnapshot) {
        lastSnapshot = snapshot
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable else { return }
        let commandBuffer = commandQueue.makeCommandBuffer()
        commandBuffer?.addCompletedHandler { [framePresented] _ in
            framePresented?(DispatchTime.now().uptimeNanoseconds)
        }
        commandBuffer?.present(drawable)
        commandBuffer?.commit()
    }
}

public enum RendererError: Error, Equatable {
    case commandQueueUnavailable
    case metalDeviceUnavailable
}
```

- [ ] **Step 4: Add AppKit Metal view**

Create `Sources/Wanda/Rendering/TerminalMetalView.swift`:

```swift
import AppKit
import Metal
import MetalKit

public final class TerminalMetalView: MTKView {
    public let terminalRenderer: TerminalMetalRenderer

    public init(frame: CGRect = .zero, framePresented: ((UInt64) -> Void)? = nil) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RendererError.metalDeviceUnavailable
        }
        self.terminalRenderer = try TerminalMetalRenderer(device: device, framePresented: framePresented)
        super.init(frame: frame, device: device)
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.055, alpha: 1.0)
        framebufferOnly = true
        enableSetNeedsDisplay = false
        isPaused = false
        delegate = terminalRenderer
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    public func update(snapshot: TerminalRendererSnapshot) {
        terminalRenderer.update(snapshot: snapshot)
        setNeedsDisplay(bounds)
    }
}
```

- [ ] **Step 5: Add SwiftUI representable**

Create `Sources/Wanda/App/TerminalMetalViewRepresentable.swift`:

```swift
import AppKit
import SwiftUI

struct TerminalMetalViewRepresentable: NSViewRepresentable {
    var snapshot: TerminalRendererSnapshot?
    var onFramePresented: (UInt64) -> Void

    func makeNSView(context: Context) -> NSView {
        do {
            return try TerminalMetalView(framePresented: onFramePresented)
        } catch {
            let label = NSTextField(labelWithString: "Metal renderer unavailable: \(error)")
            label.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
            label.textColor = .secondaryLabelColor
            label.alignment = .center
            return label
        }
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let snapshot {
            (nsView as? TerminalMetalView)?.update(snapshot: snapshot)
        }
    }
}
```

- [ ] **Step 6: Run renderer tests**

Run: `swift test --filter RenderingTests`

Expected: PASS.

- [ ] **Step 7: Run full build**

Run: `swift build`

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/Wanda/Rendering/TerminalMetalRenderer.swift Sources/Wanda/Rendering/TerminalMetalView.swift Sources/Wanda/App/TerminalMetalViewRepresentable.swift Tests/WandaTests/RenderingTests.swift
git commit -m "feat: add metal terminal view skeleton"
```

## Task 10B: Draw Terminal Cells As Metal Glyph Quads

**Files:**
- Modify: `Sources/Wanda/Rendering/GlyphAtlas.swift`
- Modify: `Sources/Wanda/Rendering/TerminalMetalRenderer.swift`
- Modify: `Tests/WandaTests/RenderingTests.swift`

- [ ] **Step 1: Add failing glyph quad tests**

Append to `RenderingTests`:

```swift
extension RenderingTests {
    func testGlyphAtlasBuildsTextureCoordinates() throws {
        let atlas = try GlyphAtlas(fontName: "Menlo", fontSize: 14)

        let entry = try XCTUnwrap(atlas.glyph(for: "A"))

        XCTAssertGreaterThan(atlas.atlasSize.width, atlas.cellSize.width)
        XCTAssertGreaterThan(atlas.atlasSize.height, atlas.cellSize.height)
        XCTAssertGreaterThan(entry.textureRect.width, 0)
        XCTAssertGreaterThan(entry.textureRect.height, 0)
    }

    func testRendererBuildsVerticesForVisibleCells() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable")
        }

        let renderer = try TerminalMetalRenderer(device: device)
        var model = TerminalModel(columns: 2, rows: 1, scrollbackLimit: 5)
        model.apply(.print("A"))

        renderer.update(snapshot: TerminalRendererSnapshot(model: model))

        XCTAssertEqual(renderer.debugVertexCount, 6)
    }
}
```

- [ ] **Step 2: Run glyph quad tests to verify failure**

Run: `swift test --filter RenderingTests/testGlyphAtlasBuildsTextureCoordinates`

Expected: FAIL because `GlyphAtlasEntry.textureRect` and `GlyphAtlas.atlasSize` do not exist.

- [ ] **Step 3: Replace the glyph atlas with atlas image and texture coordinates**

Replace `Sources/Wanda/Rendering/GlyphAtlas.swift` with:

```swift
import AppKit
import CoreGraphics
import CoreText
import Foundation

public struct GlyphAtlasEntry: Equatable, Sendable {
    public var character: Character
    public var advance: CGFloat
    public var bounds: CGRect
    public var textureRect: CGRect
}

public enum GlyphAtlasError: Error, Equatable {
    case missingFont(String)
    case bitmapCreationFailed
    case imageCreationFailed
}

public final class GlyphAtlas: @unchecked Sendable {
    public let font: CTFont
    public let cellSize: CGSize
    public let atlasSize: CGSize
    public let image: CGImage
    private let entries: [Character: GlyphAtlasEntry]

    public init(fontName: String, fontSize: CGFloat) throws {
        guard let nsFont = NSFont(name: fontName, size: fontSize) else {
            throw GlyphAtlasError.missingFont(fontName)
        }

        self.font = nsFont as CTFont
        let width = ceil("W".size(withAttributes: [.font: nsFont]).width)
        let height = ceil(nsFont.ascender - nsFont.descender + nsFont.leading)
        self.cellSize = CGSize(width: max(width, 1), height: max(height, 1))

        let columns = 16
        let glyphCount = Int(UInt8(ascii: "~") - UInt8(ascii: " ") + 1)
        let rows = Int(ceil(Double(glyphCount) / Double(columns)))
        self.atlasSize = CGSize(width: CGFloat(columns) * cellSize.width, height: CGFloat(rows) * cellSize.height)

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(atlasSize.width),
            pixelsHigh: Int(atlasSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw GlyphAtlasError.bitmapCreationFailed
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: atlasSize).fill()

        var built: [Character: GlyphAtlasEntry] = [:]
        let attributes: [NSAttributedString.Key: Any] = [
            .font: nsFont,
            .foregroundColor: NSColor.white
        ]

        for (offset, scalar) in (UInt8(ascii: " ")...UInt8(ascii: "~")).enumerated() {
            guard let unicodeScalar = UnicodeScalar(Int(scalar)) else { continue }
            let character = Character(unicodeScalar)
            let column = offset % columns
            let row = offset / columns
            let origin = CGPoint(x: CGFloat(column) * cellSize.width, y: CGFloat(row) * cellSize.height)
            let drawPoint = CGPoint(x: origin.x, y: origin.y + max((cellSize.height - nsFont.ascender) / 2, 0))
            String(character).draw(at: drawPoint, withAttributes: attributes)

            let textureRect = CGRect(origin: origin, size: cellSize)
            built[character] = GlyphAtlasEntry(
                character: character,
                advance: ceil(String(character).size(withAttributes: attributes).width),
                bounds: CGRect(origin: .zero, size: cellSize),
                textureRect: textureRect
            )
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let image = bitmap.cgImage else {
            throw GlyphAtlasError.imageCreationFailed
        }

        self.image = image
        self.entries = built
    }

    public func glyph(for character: Character) -> GlyphAtlasEntry? {
        entries[character]
    }
}
```

- [ ] **Step 4: Replace the renderer with glyph quad generation and Metal draw setup**

Replace `Sources/Wanda/Rendering/TerminalMetalRenderer.swift` with:

```swift
import CoreGraphics
import Metal
import MetalKit

private struct GlyphVertex {
    var position: SIMD2<Float>
    var textureCoordinate: SIMD2<Float>
    var color: SIMD4<Float>
}

public final class TerminalMetalRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {
    public let device: MTLDevice
    public private(set) var lastSnapshot: TerminalRendererSnapshot?
    public private(set) var debugVertexCount: Int = 0

    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let atlas: GlyphAtlas
    private let atlasTexture: MTLTexture
    private var vertexBuffer: MTLBuffer?
    private var framePresented: ((UInt64) -> Void)?

    public init(device: MTLDevice, framePresented: ((UInt64) -> Void)? = nil) throws {
        guard let commandQueue = device.makeCommandQueue() else {
            throw RendererError.commandQueueUnavailable
        }

        self.device = device
        self.commandQueue = commandQueue
        self.atlas = try GlyphAtlas(fontName: "Menlo", fontSize: 14)
        self.atlasTexture = try Self.makeTexture(device: device, image: atlas.image)
        self.pipelineState = try Self.makePipeline(device: device)
        self.framePresented = framePresented
        super.init()
    }

    public func update(snapshot: TerminalRendererSnapshot) {
        lastSnapshot = snapshot
        let vertices = buildVertices(for: snapshot)
        debugVertexCount = vertices.count
        vertexBuffer = vertices.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress, !vertices.isEmpty else { return nil }
            return device.makeBuffer(bytes: baseAddress, length: bytes.count, options: .storageModeShared)
        }
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        guard
            let drawable = view.currentDrawable,
            let passDescriptor = view.currentRenderPassDescriptor,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            return
        }

        if let vertexBuffer, debugVertexCount > 0 {
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
            encoder?.setRenderPipelineState(pipelineState)
            encoder?.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder?.setFragmentTexture(atlasTexture, index: 0)
            encoder?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: debugVertexCount)
            encoder?.endEncoding()
        }

        commandBuffer.addCompletedHandler { [framePresented] _ in
            framePresented?(DispatchTime.now().uptimeNanoseconds)
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func buildVertices(for snapshot: TerminalRendererSnapshot) -> [GlyphVertex] {
        guard snapshot.columns > 0, snapshot.rows > 0 else { return [] }
        var vertices: [GlyphVertex] = []
        let cellWidth = Float(atlas.cellSize.width)
        let cellHeight = Float(atlas.cellSize.height)
        let totalWidth = Float(snapshot.columns) * cellWidth
        let totalHeight = Float(snapshot.rows) * cellHeight

        for row in 0..<snapshot.rows {
            for column in 0..<snapshot.columns {
                let cell = snapshot.cells[row * snapshot.columns + column]
                guard cell.character != " ", let glyph = atlas.glyph(for: cell.character) else { continue }

                let left = (Float(column) * cellWidth / totalWidth) * 2 - 1
                let right = (Float(column + 1) * cellWidth / totalWidth) * 2 - 1
                let top = 1 - (Float(row) * cellHeight / totalHeight) * 2
                let bottom = 1 - (Float(row + 1) * cellHeight / totalHeight) * 2
                let tex = normalizedTextureRect(glyph.textureRect)
                let color = colorVector(for: cell.attributes.foreground)

                vertices.append(contentsOf: [
                    GlyphVertex(position: SIMD2(left, top), textureCoordinate: SIMD2(Float(tex.minX), Float(tex.minY)), color: color),
                    GlyphVertex(position: SIMD2(left, bottom), textureCoordinate: SIMD2(Float(tex.minX), Float(tex.maxY)), color: color),
                    GlyphVertex(position: SIMD2(right, bottom), textureCoordinate: SIMD2(Float(tex.maxX), Float(tex.maxY)), color: color),
                    GlyphVertex(position: SIMD2(left, top), textureCoordinate: SIMD2(Float(tex.minX), Float(tex.minY)), color: color),
                    GlyphVertex(position: SIMD2(right, bottom), textureCoordinate: SIMD2(Float(tex.maxX), Float(tex.maxY)), color: color),
                    GlyphVertex(position: SIMD2(right, top), textureCoordinate: SIMD2(Float(tex.maxX), Float(tex.minY)), color: color)
                ])
            }
        }

        return vertices
    }

    private func normalizedTextureRect(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX / atlas.atlasSize.width,
            y: rect.minY / atlas.atlasSize.height,
            width: rect.width / atlas.atlasSize.width,
            height: rect.height / atlas.atlasSize.height
        )
    }

    private func colorVector(for color: TerminalColor) -> SIMD4<Float> {
        switch color {
        case .default:
            return SIMD4(0.92, 0.94, 0.96, 1.0)
        case .ansi(let index):
            let palette: [SIMD4<Float>] = [
                SIMD4(0.05, 0.05, 0.06, 1), SIMD4(0.86, 0.20, 0.18, 1),
                SIMD4(0.28, 0.68, 0.26, 1), SIMD4(0.86, 0.68, 0.22, 1),
                SIMD4(0.24, 0.45, 0.82, 1), SIMD4(0.68, 0.34, 0.76, 1),
                SIMD4(0.20, 0.68, 0.76, 1), SIMD4(0.90, 0.90, 0.88, 1)
            ]
            return palette[Int(index) % palette.count]
        case .rgb(let red, let green, let blue):
            return SIMD4(Float(red) / 255, Float(green) / 255, Float(blue) / 255, 1)
        }
    }

    private static func makeTexture(device: MTLDevice, image: CGImage) throws -> MTLTexture {
        let loader = MTKTextureLoader(device: device)
        return try loader.newTexture(cgImage: image, options: [.SRGB: false])
    }

    private static func makePipeline(device: MTLDevice) throws -> MTLRenderPipelineState {
        let source = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexIn {
            float2 position;
            float2 textureCoordinate;
            float4 color;
        };

        struct VertexOut {
            float4 position [[position]];
            float2 textureCoordinate;
            float4 color;
        };

        vertex VertexOut vertex_main(uint vertexID [[vertex_id]], const device VertexIn *vertices [[buffer(0)]]) {
            VertexIn input = vertices[vertexID];
            VertexOut output;
            output.position = float4(input.position, 0, 1);
            output.textureCoordinate = input.textureCoordinate;
            output.color = input.color;
            return output;
        }

        fragment float4 fragment_main(VertexOut input [[stage_in]], texture2d<float> atlas [[texture(0)]]) {
            constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
            float alpha = atlas.sample(textureSampler, input.textureCoordinate).a;
            return float4(input.color.rgb, input.color.a * alpha);
        }
        """
        let library = try device.makeLibrary(source: source, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "vertex_main")
        descriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }
}

public enum RendererError: Error, Equatable {
    case commandQueueUnavailable
    case metalDeviceUnavailable
}
```

- [ ] **Step 5: Run glyph quad renderer tests**

Run: `swift test --filter RenderingTests`

Expected: PASS, including the vertex count test.

- [ ] **Step 6: Run build verification**

Run: `swift build`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/Wanda/Rendering/GlyphAtlas.swift Sources/Wanda/Rendering/TerminalMetalRenderer.swift Tests/WandaTests/RenderingTests.swift
git commit -m "feat: draw terminal glyphs with metal"
```

## Task 11: Add Latency Probe

**Files:**
- Create: `Sources/Wanda/Instrumentation/LatencyProbe.swift`
- Create: `Tests/WandaTests/LatencyProbeTests.swift`

- [ ] **Step 1: Write failing latency tests**

Create `Tests/WandaTests/LatencyProbeTests.swift`:

```swift
import XCTest
@testable import Wanda

final class LatencyProbeTests: XCTestCase {
    func testRecordsCompleteKeystrokeMeasurement() {
        var probe = LatencyProbe()
        let id = probe.recordKeyReceived(at: 100)

        probe.recordPTYWrite(for: id, at: 120)
        probe.recordModelMutation(for: id, at: 150)
        probe.recordFramePresented(for: id, at: 180)

        XCTAssertEqual(probe.completedMeasurements.count, 1)
        XCTAssertEqual(probe.completedMeasurements[0].keystrokeToPresentNanoseconds, 80)
    }

    func testP95SummaryUsesSortedMeasurements() {
        var probe = LatencyProbe()
        for index in 1...20 {
            let id = probe.recordKeyReceived(at: UInt64(index * 100))
            probe.recordFramePresented(for: id, at: UInt64(index * 100 + index))
        }

        XCTAssertEqual(probe.summary().p95Nanoseconds, 19)
    }
}
```

- [ ] **Step 2: Run latency tests to verify failure**

Run: `swift test --filter LatencyProbeTests`

Expected: FAIL because `LatencyProbe` does not exist.

- [ ] **Step 3: Add latency probe**

Create `Sources/Wanda/Instrumentation/LatencyProbe.swift`:

```swift
import Foundation

public struct LatencyMeasurement: Equatable, Sendable {
    public var id: Int
    public var keyReceived: UInt64
    public var ptyWritten: UInt64?
    public var modelMutated: UInt64?
    public var framePresented: UInt64?

    public var keystrokeToPresentNanoseconds: UInt64? {
        guard let framePresented else { return nil }
        return framePresented - keyReceived
    }
}

public struct LatencySummary: Equatable, Sendable {
    public var count: Int
    public var p95Nanoseconds: UInt64?
}

public struct LatencyProbe: Sendable {
    private var nextID: Int = 0
    private var active: [Int: LatencyMeasurement] = [:]
    public private(set) var completedMeasurements: [LatencyMeasurement] = []

    public init() {}

    public mutating func recordKeyReceived(at timestamp: UInt64 = DispatchTime.now().uptimeNanoseconds) -> Int {
        nextID += 1
        active[nextID] = LatencyMeasurement(id: nextID, keyReceived: timestamp)
        return nextID
    }

    public mutating func recordPTYWrite(for id: Int, at timestamp: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        active[id]?.ptyWritten = timestamp
    }

    public mutating func recordModelMutation(for id: Int, at timestamp: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        active[id]?.modelMutated = timestamp
    }

    public mutating func recordFramePresented(for id: Int, at timestamp: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        guard var measurement = active.removeValue(forKey: id) else { return }
        measurement.framePresented = timestamp
        completedMeasurements.append(measurement)
    }

    public func summary() -> LatencySummary {
        let values = completedMeasurements.compactMap(\.keystrokeToPresentNanoseconds).sorted()
        guard !values.isEmpty else {
            return LatencySummary(count: 0, p95Nanoseconds: nil)
        }

        let index = max(Int(ceil(Double(values.count) * 0.95)) - 1, 0)
        return LatencySummary(count: values.count, p95Nanoseconds: values[index])
    }
}
```

- [ ] **Step 4: Run latency tests**

Run: `swift test --filter LatencyProbeTests`

Expected: PASS.

- [ ] **Step 5: Run all tests**

Run: `swift test`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/Wanda/Instrumentation/LatencyProbe.swift Tests/WandaTests/LatencyProbeTests.swift
git commit -m "feat: add latency instrumentation probe"
```

## Task 12: Wire View Model To Parser, Model, PTY, Renderer Snapshot, And Latency Probe

**Files:**
- Create: `Sources/Wanda/App/TerminalViewModel.swift`
- Modify: `Sources/Wanda/App/TerminalWindowView.swift`
- Modify: `Tests/WandaTests/SmokeTests.swift`

- [ ] **Step 1: Replace smoke test with view model processing test**

Modify `Tests/WandaTests/SmokeTests.swift`:

```swift
import XCTest
@testable import Wanda

@MainActor
final class SmokeTests: XCTestCase {
    func testViewModelAppliesOutputBytesToSnapshot() {
        let viewModel = TerminalViewModel(columns: 4, rows: 2, scrollbackLimit: 10)

        viewModel.processOutput(Array("ok".utf8))

        XCTAssertEqual(viewModel.snapshot?.cells[0].character, "o")
        XCTAssertEqual(viewModel.snapshot?.cells[1].character, "k")
    }
}
```

- [ ] **Step 2: Run view model test to verify failure**

Run: `swift test --filter SmokeTests`

Expected: FAIL because `TerminalViewModel` does not exist.

- [ ] **Step 3: Add terminal view model**

Create `Sources/Wanda/App/TerminalViewModel.swift`:

```swift
import Combine
import Foundation

@MainActor
public final class TerminalViewModel: ObservableObject {
    @Published public private(set) var snapshot: TerminalRendererSnapshot?
    @Published public private(set) var statusMessage: String?

    private var parser: any TerminalParser
    private var model: TerminalModel
    private var latencyProbe = LatencyProbe()
    private let keyMapper = TerminalKeyMapper()
    private var pendingLatencyID: Int?
    private var pty: PosixPseudoTerminal?

    public init(columns: Int = 80, rows: Int = 24, scrollbackLimit: Int = 2_000) {
        self.parser = SwiftTerminalParser()
        self.model = TerminalModel(columns: columns, rows: rows, scrollbackLimit: scrollbackLimit)
        self.snapshot = TerminalRendererSnapshot(model: model)
    }

    public func startDefaultShell() {
        guard pty == nil else { return }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        do {
            pty = try PosixPseudoTerminal(
                executablePath: shell,
                arguments: [shell],
                environment: ["TERM": "xterm-256color"],
                size: TerminalSize(columns: model.visibleGrid.columns, rows: model.visibleGrid.rows)
            )
            statusMessage = nil
        } catch {
            statusMessage = "Could not start shell: \(error)"
        }
    }

    public func processOutput(_ bytes: [UInt8]) {
        let events = parser.parse(bytes)
        for event in events {
            model.apply(event)
        }
        if let id = pendingLatencyID {
            latencyProbe.recordModelMutation(for: id)
        }
        snapshot = TerminalRendererSnapshot(model: model)
    }

    public func handleKey(_ event: TerminalKeyEvent) {
        let id = latencyProbe.recordKeyReceived()
        pendingLatencyID = id
        let bytes = keyMapper.bytes(for: event)

        do {
            try pty?.write(bytes)
            latencyProbe.recordPTYWrite(for: id)
        } catch {
            statusMessage = "Could not write to shell: \(error)"
        }
    }

    public func framePresented(at timestamp: UInt64) {
        guard let id = pendingLatencyID else { return }
        latencyProbe.recordFramePresented(for: id, at: timestamp)
        pendingLatencyID = nil
    }

    public func stop() {
        pty?.terminate()
        pty = nil
    }
}
```

- [ ] **Step 4: Render Metal view from SwiftUI**

Modify `Sources/Wanda/App/TerminalWindowView.swift`:

```swift
import SwiftUI

struct TerminalWindowView: View {
    @StateObject private var viewModel = TerminalViewModel()

    var body: some View {
        ZStack(alignment: .topLeading) {
            TerminalMetalViewRepresentable(
                snapshot: viewModel.snapshot,
                onFramePresented: { timestamp in
                    Task { @MainActor in
                        viewModel.framePresented(at: timestamp)
                    }
                }
            )

            if let statusMessage = viewModel.statusMessage {
                Text(statusMessage)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
        }
        .frame(minWidth: 720, minHeight: 420)
        .task {
            viewModel.startDefaultShell()
        }
        .onDisappear {
            viewModel.stop()
        }
    }
}
```

- [ ] **Step 5: Run view model tests**

Run: `swift test --filter SmokeTests`

Expected: PASS.

- [ ] **Step 6: Build app**

Run: `swift build`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/Wanda/App/TerminalViewModel.swift Sources/Wanda/App/TerminalWindowView.swift Tests/WandaTests/SmokeTests.swift
git commit -m "feat: wire terminal view model"
```

## Task 13: Bridge AppKit Key Events Into The View Model

**Files:**
- Create: `Sources/Wanda/App/TerminalInputView.swift`
- Modify: `Sources/Wanda/App/TerminalWindowView.swift`

- [ ] **Step 1: Add AppKit input bridge**

Create `Sources/Wanda/App/TerminalInputView.swift`:

```swift
import AppKit
import SwiftUI

struct TerminalInputView: NSViewRepresentable {
    var onKey: (TerminalKeyEvent) -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onKey = onKey
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.onKey = onKey
    }
}

final class KeyCaptureView: NSView {
    var onKey: ((TerminalKeyEvent) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if let mapped = TerminalKeyEvent(event: event) {
            onKey?(mapped)
        } else {
            super.keyDown(with: event)
        }
    }
}

private extension TerminalKeyEvent {
    init?(event: NSEvent) {
        let modifiers = TerminalKeyModifiers(event.modifierFlags)

        switch event.keyCode {
        case 123:
            self = .special(.leftArrow, modifiers: modifiers)
        case 124:
            self = .special(.rightArrow, modifiers: modifiers)
        case 125:
            self = .special(.downArrow, modifiers: modifiers)
        case 126:
            self = .special(.upArrow, modifiers: modifiers)
        case 36:
            self = .special(.returnKey, modifiers: modifiers)
        case 51:
            self = .special(.delete, modifiers: modifiers)
        case 48:
            self = .special(.tab, modifiers: modifiers)
        default:
            guard let characters = event.characters, !characters.isEmpty else {
                return nil
            }
            self = .printable(characters)
        }
    }
}

private extension TerminalKeyModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var result: TerminalKeyModifiers = []
        if flags.contains(.option) {
            result.insert(.option)
        }
        if flags.contains(.command) {
            result.insert(.command)
        }
        if flags.contains(.control) {
            result.insert(.control)
        }
        if flags.contains(.shift) {
            result.insert(.shift)
        }
        self = result
    }
}
```

- [ ] **Step 2: Layer key capture over Metal view**

Modify `Sources/Wanda/App/TerminalWindowView.swift`:

```swift
import SwiftUI

struct TerminalWindowView: View {
    @StateObject private var viewModel = TerminalViewModel()

    var body: some View {
        ZStack(alignment: .topLeading) {
            TerminalMetalViewRepresentable(
                snapshot: viewModel.snapshot,
                onFramePresented: { timestamp in
                    Task { @MainActor in
                        viewModel.framePresented(at: timestamp)
                    }
                }
            )

            TerminalInputView { event in
                viewModel.handleKey(event)
            }
            .allowsHitTesting(true)

            if let statusMessage = viewModel.statusMessage {
                Text(statusMessage)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
        }
        .frame(minWidth: 720, minHeight: 420)
        .task {
            viewModel.startDefaultShell()
        }
        .onDisappear {
            viewModel.stop()
        }
    }
}
```

- [ ] **Step 3: Run tests**

Run: `swift test`

Expected: PASS.

- [ ] **Step 4: Build app**

Run: `swift build`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Wanda/App/TerminalInputView.swift Sources/Wanda/App/TerminalWindowView.swift
git commit -m "feat: bridge terminal key input"
```

## Task 14: Add Manual PTY Output Pump And Resize Propagation

**Files:**
- Modify: `Sources/Wanda/App/TerminalViewModel.swift`
- Modify: `Sources/Wanda/App/TerminalWindowView.swift`

- [ ] **Step 1: Add polling output pump and resize API**

Modify `Sources/Wanda/App/TerminalViewModel.swift`:

```swift
import Combine
import Foundation

@MainActor
public final class TerminalViewModel: ObservableObject {
    @Published public private(set) var snapshot: TerminalRendererSnapshot?
    @Published public private(set) var statusMessage: String?

    private var parser: any TerminalParser
    private var model: TerminalModel
    private var latencyProbe = LatencyProbe()
    private let keyMapper = TerminalKeyMapper()
    private var pendingLatencyID: Int?
    private var pty: PosixPseudoTerminal?
    private var outputTask: Task<Void, Never>?

    public init(columns: Int = 80, rows: Int = 24, scrollbackLimit: Int = 2_000) {
        self.parser = SwiftTerminalParser()
        self.model = TerminalModel(columns: columns, rows: rows, scrollbackLimit: scrollbackLimit)
        self.snapshot = TerminalRendererSnapshot(model: model)
    }

    public func startDefaultShell() {
        guard pty == nil else { return }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        do {
            let terminal = try PosixPseudoTerminal(
                executablePath: shell,
                arguments: [shell],
                environment: ["TERM": "xterm-256color"],
                size: TerminalSize(columns: model.visibleGrid.columns, rows: model.visibleGrid.rows)
            )
            pty = terminal
            statusMessage = nil
            startOutputPump(for: terminal)
        } catch {
            statusMessage = "Could not start shell: \(error)"
        }
    }

    public func processOutput(_ bytes: [UInt8]) {
        let events = parser.parse(bytes)
        for event in events {
            model.apply(event)
        }
        if let id = pendingLatencyID {
            latencyProbe.recordModelMutation(for: id)
        }
        snapshot = TerminalRendererSnapshot(model: model)
    }

    public func handleKey(_ event: TerminalKeyEvent) {
        let id = latencyProbe.recordKeyReceived()
        pendingLatencyID = id
        let bytes = keyMapper.bytes(for: event)

        do {
            try pty?.write(bytes)
            latencyProbe.recordPTYWrite(for: id)
        } catch {
            statusMessage = "Could not write to shell: \(error)"
        }
    }

    public func resize(columns: Int, rows: Int) {
        guard columns > 0, rows > 0 else { return }
        do {
            try pty?.resize(TerminalSize(columns: columns, rows: rows))
        } catch {
            statusMessage = "Could not resize shell: \(error)"
        }
    }

    public func framePresented(at timestamp: UInt64) {
        guard let id = pendingLatencyID else { return }
        latencyProbe.recordFramePresented(for: id, at: timestamp)
        pendingLatencyID = nil
    }

    public func stop() {
        outputTask?.cancel()
        outputTask = nil
        pty?.terminate()
        pty = nil
    }

    private func startOutputPump(for terminal: PosixPseudoTerminal) {
        outputTask?.cancel()
        outputTask = Task { [weak self, weak terminal] in
            while !Task.isCancelled {
                guard let terminal else { return }
                do {
                    let bytes = try terminal.readAvailableBytes()
                    if !bytes.isEmpty {
                        await MainActor.run {
                            self?.processOutput(bytes)
                        }
                    }
                } catch {
                    await MainActor.run {
                        self?.statusMessage = "Could not read shell output: \(error)"
                    }
                    return
                }
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
        }
    }
}
```

- [ ] **Step 2: Add a geometry reader for approximate resize propagation**

Modify `Sources/Wanda/App/TerminalWindowView.swift`:

```swift
import SwiftUI

struct TerminalWindowView: View {
    @StateObject private var viewModel = TerminalViewModel()

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                TerminalMetalViewRepresentable(
                    snapshot: viewModel.snapshot,
                    onFramePresented: { timestamp in
                        Task { @MainActor in
                            viewModel.framePresented(at: timestamp)
                        }
                    }
                )

                TerminalInputView { event in
                    viewModel.handleKey(event)
                }
                .allowsHitTesting(true)

                if let statusMessage = viewModel.statusMessage {
                    Text(statusMessage)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(12)
                }
            }
            .onChange(of: proxy.size) { _, size in
                let columns = max(Int(size.width / 9), 1)
                let rows = max(Int(size.height / 18), 1)
                viewModel.resize(columns: columns, rows: rows)
            }
        }
        .frame(minWidth: 720, minHeight: 420)
        .task {
            viewModel.startDefaultShell()
        }
        .onDisappear {
            viewModel.stop()
        }
    }
}
```

- [ ] **Step 3: Run tests**

Run: `swift test`

Expected: PASS.

- [ ] **Step 4: Build app**

Run: `swift build`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Wanda/App/TerminalViewModel.swift Sources/Wanda/App/TerminalWindowView.swift
git commit -m "feat: pump pty output and resize"
```

## Task 15: Apply Window Geometry Restore In The App

**Files:**
- Create: `Sources/Wanda/App/WindowAccessor.swift`
- Modify: `Sources/Wanda/App/TerminalWindowView.swift`

- [ ] **Step 1: Add AppKit window accessor**

Create `Sources/Wanda/App/WindowAccessor.swift`:

```swift
import AppKit
import SwiftUI

struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onWindow(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onWindow(window)
            }
        }
    }
}
```

- [ ] **Step 2: Apply geometry store on window access**

Modify `Sources/Wanda/App/TerminalWindowView.swift`:

```swift
import AppKit
import SwiftUI

struct TerminalWindowView: View {
    @StateObject private var viewModel = TerminalViewModel()
    private let geometryStore = GeometryStore()

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                TerminalMetalViewRepresentable(
                    snapshot: viewModel.snapshot,
                    onFramePresented: { timestamp in
                        Task { @MainActor in
                            viewModel.framePresented(at: timestamp)
                        }
                    }
                )

                TerminalInputView { event in
                    viewModel.handleKey(event)
                }
                .allowsHitTesting(true)

                WindowAccessor { window in
                    let frame = geometryStore.load(validatingAgainst: window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero)
                    if window.frame != frame {
                        window.setFrame(frame, display: true)
                    }
                }
                .frame(width: 0, height: 0)

                if let statusMessage = viewModel.statusMessage {
                    Text(statusMessage)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(12)
                }
            }
            .onChange(of: proxy.size) { _, size in
                let columns = max(Int(size.width / 9), 1)
                let rows = max(Int(size.height / 18), 1)
                viewModel.resize(columns: columns, rows: rows)
            }
        }
        .frame(minWidth: 720, minHeight: 420)
        .task {
            viewModel.startDefaultShell()
        }
        .onDisappear {
            if let window = NSApplication.shared.keyWindow {
                geometryStore.save(frame: window.frame)
            }
            viewModel.stop()
        }
    }
}
```

- [ ] **Step 3: Run tests**

Run: `swift test`

Expected: PASS.

- [ ] **Step 4: Build app**

Run: `swift build`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Wanda/App/WindowAccessor.swift Sources/Wanda/App/TerminalWindowView.swift
git commit -m "feat: restore terminal window geometry"
```

## Task 16: Add Final Verification And Documentation Updates

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/plans/2026-05-04-terminal-core-mvp.md`

- [ ] **Step 1: Update README with MVP verification commands**

Modify `README.md`:

```markdown
# Wanda

Wanda is a macOS 15+ terminal emulator MVP focused on a low-latency PTY-to-Metal rendering path.

## Build

```bash
swift build
```

## Test

```bash
swift test
```

## Manual Run

```bash
swift run Wanda
```

## MVP Scope

The first milestone is a single native macOS terminal window with a local shell, Swift terminal model, bounded in-memory scrollback, basic selection, Metal text rendering, window geometry restore, and latency instrumentation.

## Verification Checklist

- `swift test` passes.
- `swift build` passes.
- `swift run Wanda` launches one native macOS window.
- Printable keys reach the shell.
- Option-Left sends `ESC b`.
- Option-Right sends `ESC f`.
- Command-Left sends `Ctrl-A`.
- Command-Right sends `Ctrl-E`.
- Window size and position restore after relaunch.
- Sustained shell output does not grow scrollback beyond the configured cap.
```

- [ ] **Step 2: Run full automated verification**

Run: `swift test`

Expected: PASS for all test targets.

- [ ] **Step 3: Run build verification**

Run: `swift build`

Expected: PASS.

- [ ] **Step 4: Run a local app smoke test**

Run: `swift run Wanda`

Expected: A native macOS window opens, starts the user's default shell, and accepts basic keyboard input. Close the app after the smoke test.

- [ ] **Step 5: Commit documentation**

```bash
git add README.md docs/superpowers/plans/2026-05-04-terminal-core-mvp.md
git commit -m "docs: add terminal mvp verification notes"
```

## Self-Review Checklist

- Spec coverage: this plan covers the SwiftUI shell, PTY adapter, replaceable parser boundary, terminal model, bounded scrollback, selection, key mapping, geometry persistence, atlas-backed Metal glyph rendering, latency probe, tests, and final verification.
- Scope control: this plan does not add splits, multiple windows, disk-backed history, indexed search, live session restore, ligatures, complex shaping, network calls, or AI features.
- Type consistency: shared types are named consistently across tasks: `TerminalPoint`, `TerminalCell`, `TerminalGrid`, `TerminalModel`, `TerminalEvent`, `SwiftTerminalParser`, `TerminalSelection`, `TerminalKeyMapper`, `TerminalSize`, `PosixPseudoTerminal`, `TerminalRendererSnapshot`, `GlyphAtlas`, `TerminalMetalRenderer`, and `LatencyProbe`.
- Test discipline: every feature task starts with a failing test or a build-verified bridge step, then requires `swift test` or `swift build` before commit.
