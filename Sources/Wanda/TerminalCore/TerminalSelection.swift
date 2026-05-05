import Foundation

public struct TerminalSelection: Equatable, Sendable {
    public var start: TerminalPoint
    public var end: TerminalPoint

    public init(start: TerminalPoint, end: TerminalPoint) {
        self.start = start
        self.end = end
    }

    public func string(in grid: TerminalGrid) -> String {
        rowRanges(columns: grid.columns, rows: grid.rows).map { range in
            let characters = (range.startColumn...range.endColumn).map {
                grid.cell(at: TerminalPoint(column: $0, row: range.row)).character
            }
            return String(characters).trimmedTrailingSpaces()
        }
        .joined(separator: "\n")
    }

    public func rowRanges(columns: Int, rows: Int) -> [TerminalSelectionRowRange] {
        guard columns > 0, rows > 0 else {
            return []
        }

        let ordered = orderedEndpoints()
        guard ordered.end.row >= 0, ordered.start.row < rows else {
            return []
        }

        let startRow = min(max(ordered.start.row, 0), rows - 1)
        let endRow = min(max(ordered.end.row, 0), rows - 1)
        guard startRow <= endRow else {
            return []
        }

        return (startRow...endRow).compactMap { row in
            let startColumn = row == ordered.start.row ? ordered.start.column : 0
            let endColumn = row == ordered.end.row ? ordered.end.column : columns - 1
            guard endColumn >= 0, startColumn < columns else {
                return nil
            }

            return TerminalSelectionRowRange(
                row: row,
                startColumn: min(max(startColumn, 0), columns - 1),
                endColumn: min(max(endColumn, 0), columns - 1)
            )
        }
    }

    public static func token(at point: TerminalPoint, in grid: TerminalGrid) -> TerminalSelection {
        let row = point.row
        let character = grid.cell(at: point).character
        guard isTokenCharacter(character) else {
            return TerminalSelection(start: point, end: point)
        }

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

public struct TerminalSelectionRowRange: Equatable, Sendable {
    public var row: Int
    public var startColumn: Int
    public var endColumn: Int

    public init(row: Int, startColumn: Int, endColumn: Int) {
        self.row = row
        self.startColumn = startColumn
        self.endColumn = endColumn
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
