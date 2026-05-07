import Foundation

public struct TerminalModel: Equatable, Sendable {
    public private(set) var primaryGrid: TerminalGrid
    private var alternateGrid: TerminalGrid
    public private(set) var cursor: TerminalPoint
    public private(set) var scrollback: [[TerminalCell]]
    public private(set) var dirtyRows: Set<Int>
    public private(set) var isUsingAlternateScreen: Bool

    private var primaryCursor: TerminalPoint
    private var alternateCursor: TerminalPoint
    private var primaryPendingWrap: Bool
    private var alternatePendingWrap: Bool
    private var currentAttributes: TerminalAttributes
    private let scrollbackLimit: Int

    public init(columns: Int, rows: Int, scrollbackLimit: Int) {
        precondition(scrollbackLimit >= 0, "TerminalModel scrollback limit cannot be negative")
        let grid = TerminalGrid(columns: columns, rows: rows)
        self.primaryGrid = grid
        self.alternateGrid = grid
        self.cursor = TerminalPoint(column: 0, row: 0)
        self.scrollback = []
        self.dirtyRows = []
        self.isUsingAlternateScreen = false
        self.primaryCursor = TerminalPoint(column: 0, row: 0)
        self.alternateCursor = TerminalPoint(column: 0, row: 0)
        self.primaryPendingWrap = false
        self.alternatePendingWrap = false
        self.currentAttributes = TerminalAttributes()
        self.scrollbackLimit = scrollbackLimit
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
        case .cursorHorizontalAbsolute(let column):
            setCursor(row: cursor.row, column: column)
        case .carriageReturn:
            setCursor(row: cursor.row, column: 0)
        case .lineFeed:
            lineFeed()
        case .backspace:
            setCursor(row: cursor.row, column: cursor.column - 1)
        case .eraseScreen(let mode):
            eraseScreen(mode)
        case .eraseLine(let mode):
            eraseLine(mode)
        case .setGraphicRendition(let parameters):
            applySGR(parameters)
        case .useAlternateScreen(let enabled):
            useAlternateScreen(enabled)
        case .malformedSequence:
            break
        }
    }

    public mutating func drainDirtyRows() -> Set<Int> {
        let drainedRows = dirtyRows
        dirtyRows.removeAll()
        return drainedRows
    }

    public mutating func resize(columns: Int, rows: Int) {
        precondition(columns > 0, "TerminalModel columns must be positive")
        precondition(rows > 0, "TerminalModel rows must be positive")

        primaryGrid.resize(columns: columns, rows: rows)
        alternateGrid.resize(columns: columns, rows: rows)

        primaryCursor = clampedCursor(primaryCursor, columns: columns, rows: rows)
        alternateCursor = clampedCursor(alternateCursor, columns: columns, rows: rows)
        primaryPendingWrap = false
        alternatePendingWrap = false
        restoreCursor()
        dirtyRows = Set(0..<visibleGrid.rows)
    }

    private mutating func print(_ character: Character) {
        if pendingWrap {
            setPendingWrap(false)
            setCursor(row: cursor.row, column: 0)
            lineFeed()
        }

        let point = cursor
        let attributes = currentAttributes
        withVisibleGrid { grid in
            grid.setCell(TerminalCell(character: character, attributes: attributes), at: point)
        }
        markDirty(row: point.row)
        advanceCursorAfterPrint()
    }

    private mutating func advanceCursorAfterPrint() {
        if cursor.column + 1 < visibleGrid.columns {
            setCursor(row: cursor.row, column: cursor.column + 1)
            return
        }

        setPendingWrap(true)
    }

    private mutating func lineFeed() {
        if cursor.row + 1 < visibleGrid.rows {
            setCursor(row: cursor.row + 1, column: cursor.column)
            return
        }

        scrollUpOneLine()
        setCursor(row: visibleGrid.rows - 1, column: cursor.column)
    }

    private mutating func scrollUpOneLine() {
        var removedRow: [TerminalCell] = []
        withVisibleGrid { grid in
            removedRow = grid.scrollUpOneLine()
        }

        if !isUsingAlternateScreen {
            appendScrollbackRow(removedRow)
        }

        markAllRowsDirty()
    }

    private mutating func eraseScreen(_ mode: TerminalEraseMode) {
        switch mode {
        case .cursorToEnd:
            clearVisibleRow(cursor.row, from: cursor.column, through: visibleGrid.columns - 1)
            if cursor.row + 1 < visibleGrid.rows {
                for row in (cursor.row + 1)..<visibleGrid.rows {
                    clearVisibleRow(row, from: 0, through: visibleGrid.columns - 1)
                }
            }
        case .startToCursor:
            if cursor.row > 0 {
                for row in 0..<cursor.row {
                    clearVisibleRow(row, from: 0, through: visibleGrid.columns - 1)
                }
            }
            clearVisibleRow(cursor.row, from: 0, through: cursor.column)
        case .all:
            withVisibleGrid { grid in
                grid.clearAll()
            }
            markAllRowsDirty()
        }
        setPendingWrap(false)
    }

    private mutating func eraseLine(_ mode: TerminalEraseMode) {
        switch mode {
        case .cursorToEnd:
            clearVisibleRow(cursor.row, from: cursor.column, through: visibleGrid.columns - 1)
        case .startToCursor:
            clearVisibleRow(cursor.row, from: 0, through: cursor.column)
        case .all:
            clearVisibleRow(cursor.row, from: 0, through: visibleGrid.columns - 1)
        }
        setPendingWrap(false)
    }

    private mutating func clearVisibleRow(_ row: Int, from startColumn: Int, through endColumn: Int) {
        guard startColumn <= endColumn else {
            return
        }

        withVisibleGrid { grid in
            grid.clearCells(in: row, columns: startColumn...endColumn)
        }
        markDirty(row: row)
    }

    private mutating func appendScrollbackRow(_ row: [TerminalCell]) {
        guard scrollbackLimit > 0 else { return }

        scrollback.append(row)
        if scrollback.count > scrollbackLimit {
            scrollback.removeFirst(scrollback.count - scrollbackLimit)
        }
    }

    private mutating func useAlternateScreen(_ enabled: Bool) {
        guard enabled != isUsingAlternateScreen else { return }

        saveCursor()
        isUsingAlternateScreen = enabled
        restoreCursor()

        if enabled {
            alternateGrid.clearAll()
            alternateCursor = TerminalPoint(column: 0, row: 0)
            alternatePendingWrap = false
            cursor = alternateCursor
        }

        markAllRowsDirty()
    }

    private mutating func applySGR(_ parameters: [Int]) {
        let parameters = parameters.isEmpty ? [0] : parameters

        for parameter in parameters {
            switch parameter {
            case 0:
                currentAttributes = TerminalAttributes()
            case 1:
                currentAttributes.isBold = true
            case 3:
                currentAttributes.isItalic = true
            case 4:
                currentAttributes.isUnderline = true
            case 7:
                currentAttributes.isInverse = true
            case 22:
                currentAttributes.isBold = false
            case 23:
                currentAttributes.isItalic = false
            case 24:
                currentAttributes.isUnderline = false
            case 27:
                currentAttributes.isInverse = false
            case 30...37:
                currentAttributes.foreground = .ansi(index: UInt8(parameter - 30))
            case 39:
                currentAttributes.foreground = .default
            case 40...47:
                currentAttributes.background = .ansi(index: UInt8(parameter - 40))
            case 49:
                currentAttributes.background = .default
            default:
                break
            }
        }
    }

    private mutating func setCursor(row: Int, column: Int) {
        let oldCursor = cursor
        let hadPendingWrap = pendingWrap
        let clampedRow = min(max(row, 0), visibleGrid.rows - 1)
        let clampedColumn = min(max(column, 0), visibleGrid.columns - 1)
        cursor = TerminalPoint(column: clampedColumn, row: clampedRow)
        setPendingWrap(false)
        saveCursor()

        if oldCursor != cursor || hadPendingWrap {
            markDirty(row: oldCursor.row)
            markDirty(row: cursor.row)
        }
    }

    private mutating func saveCursor() {
        if isUsingAlternateScreen {
            alternateCursor = cursor
        } else {
            primaryCursor = cursor
        }
    }

    private mutating func restoreCursor() {
        cursor = isUsingAlternateScreen ? alternateCursor : primaryCursor
    }

    private func clampedCursor(_ point: TerminalPoint, columns: Int, rows: Int) -> TerminalPoint {
        TerminalPoint(
            column: min(max(point.column, 0), columns - 1),
            row: min(max(point.row, 0), rows - 1)
        )
    }

    private var pendingWrap: Bool {
        isUsingAlternateScreen ? alternatePendingWrap : primaryPendingWrap
    }

    private mutating func setPendingWrap(_ pendingWrap: Bool) {
        if isUsingAlternateScreen {
            alternatePendingWrap = pendingWrap
        } else {
            primaryPendingWrap = pendingWrap
        }
    }

    private mutating func withVisibleGrid(_ update: (inout TerminalGrid) -> Void) {
        if isUsingAlternateScreen {
            update(&alternateGrid)
        } else {
            update(&primaryGrid)
        }
    }

    private mutating func markDirty(row: Int) {
        dirtyRows.insert(row)
    }

    private mutating func markAllRowsDirty() {
        dirtyRows.formUnion(0..<visibleGrid.rows)
    }
}
