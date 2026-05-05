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
        self.cells = (0..<grid.rows).flatMap { grid.rowCells($0) }
        self.cursor = model.cursor
        self.dirtyRows = model.dirtyRows
    }
}
