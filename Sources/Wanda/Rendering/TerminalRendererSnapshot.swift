import Foundation

public struct TerminalRendererSnapshot: Sendable {
    public var columns: Int
    public var rows: Int
    public var cells: [TerminalCell]
    public var cursor: TerminalPoint
    public var dirtyRows: Set<Int>

    public init(columns: Int, rows: Int, cells: [TerminalCell], cursor: TerminalPoint, dirtyRows: Set<Int>) {
        self.columns = columns
        self.rows = rows
        self.cells = cells
        self.cursor = cursor
        self.dirtyRows = dirtyRows
    }

    public init(model: TerminalModel, scrollbackOffsetRows: Int = 0) {
        let grid = model.visibleGrid
        let visibleRows = (0..<grid.rows).map { grid.rowCells($0) }
        let combinedRows = model.isUsingAlternateScreen ? visibleRows : model.scrollback + visibleRows
        let maximumOffset = max(combinedRows.count - grid.rows, 0)
        let offset = min(max(scrollbackOffsetRows, 0), maximumOffset)
        let startRow = max(combinedRows.count - grid.rows - offset, 0)
        let endRow = min(startRow + grid.rows, combinedRows.count)
        let viewportRows = Array(combinedRows[startRow..<endRow])
        let cursorCombinedRow = (model.isUsingAlternateScreen ? 0 : model.scrollback.count) + model.cursor.row
        let cursorViewportRow = cursorCombinedRow - startRow
        let cursor = (0..<grid.rows).contains(cursorViewportRow)
            ? TerminalPoint(column: model.cursor.column, row: cursorViewportRow)
            : TerminalPoint(column: model.cursor.column, row: grid.rows)

        self.init(
            columns: grid.columns,
            rows: grid.rows,
            cells: viewportRows.flatMap { Self.normalizedRow($0, columns: grid.columns) },
            cursor: cursor,
            dirtyRows: offset == 0 ? model.dirtyRows : Set(0..<grid.rows)
        )
    }

    private static func normalizedRow(_ row: [TerminalCell], columns: Int) -> [TerminalCell] {
        if row.count == columns {
            return row
        }

        if row.count > columns {
            return Array(row.prefix(columns))
        }

        return row + Array(repeating: .blank, count: columns - row.count)
    }
}
