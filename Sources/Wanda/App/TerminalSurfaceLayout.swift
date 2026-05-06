import Foundation

struct TerminalSurfaceLayout: Equatable {
    var resizeColumns: Int
    var resizeRows: Int
    var inputLayout: TerminalInputLayout

    init(
        viewSize: CGSize,
        displayedColumns: Int?,
        displayedRows: Int?,
        preferredCellSize: CGSize
    ) {
        let targetColumns = Self.cellCount(for: viewSize.width, preferredExtent: preferredCellSize.width)
        let targetRows = Self.cellCount(for: viewSize.height, preferredExtent: preferredCellSize.height)
        let inputColumns = max(displayedColumns ?? targetColumns, 1)
        let inputRows = max(displayedRows ?? targetRows, 1)

        self.resizeColumns = targetColumns
        self.resizeRows = targetRows
        self.inputLayout = TerminalInputLayout(
            columns: inputColumns,
            rows: inputRows,
            viewSize: viewSize
        )
    }

    init(
        viewSize: CGSize,
        displayedColumns: Int,
        displayedRows: Int,
        preferredCellSize: CGSize
    ) {
        self.init(
            viewSize: viewSize,
            displayedColumns: Optional(displayedColumns),
            displayedRows: Optional(displayedRows),
            preferredCellSize: preferredCellSize
        )
    }

    private static func cellCount(for length: CGFloat, preferredExtent: CGFloat) -> Int {
        guard preferredExtent > 0 else {
            return 1
        }

        return max(1, Int(length / preferredExtent))
    }
}
