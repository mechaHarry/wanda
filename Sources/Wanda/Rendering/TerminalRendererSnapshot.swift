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

    public init(model: TerminalModel) {
        let grid = model.visibleGrid
        self.init(
            columns: grid.columns,
            rows: grid.rows,
            cells: (0..<grid.rows).flatMap { grid.rowCells($0) },
            cursor: model.cursor,
            dirtyRows: model.dirtyRows
        )
    }
}
