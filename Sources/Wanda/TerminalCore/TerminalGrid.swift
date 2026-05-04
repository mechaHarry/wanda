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
