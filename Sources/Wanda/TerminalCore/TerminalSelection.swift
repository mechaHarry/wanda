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
