import CoreGraphics

/// One column of the row. Usually holds a single window; stacked windows share
/// the column and split its height.
public struct Column<ID: Hashable>: Equatable {
    public var windows: [ID]
    /// Fraction of the usable screen width, in `Strip.minimumWidth...1`.
    public var width: CGFloat
    public var focusedRow = 0
    /// The width to return to when "fill" is toggled off.
    public var widthBeforeFill: CGFloat?

    public init(windows: [ID], width: CGFloat) {
        self.windows = windows
        self.width = width
    }
}

/// The row of windows on one display. Pure state: no AppKit, no Accessibility,
/// so every rule about where windows go is unit-testable.
public struct Strip<ID: Hashable>: Equatable {
    public static var minimumWidth: CGFloat { 0.1 }

    public private(set) var columns: [Column<ID>] = []
    public private(set) var focusedColumn = 0
    /// How far the viewport has slid along the row, in points.
    public var scroll: CGFloat = 0

    public init() {}

    public var isEmpty: Bool { columns.isEmpty }

    public var windows: [ID] { columns.flatMap(\.windows) }

    public var focusedWindow: ID? {
        guard !columns.isEmpty else { return nil }
        let column = columns[focusedColumn]
        return column.windows[column.focusedRow]
    }

    public func location(of id: ID) -> (column: Int, row: Int)? {
        for (c, column) in columns.enumerated() {
            if let r = column.windows.firstIndex(of: id) { return (c, r) }
        }
        return nil
    }

    public func contains(_ id: ID) -> Bool { location(of: id) != nil }

    // MARK: Adding and removing

    /// Puts a new window in its own column right after the focused one and focuses it.
    public mutating func insert(_ id: ID, width: CGFloat) {
        let index = columns.isEmpty ? 0 : focusedColumn + 1
        columns.insert(Column(windows: [id], width: Self.clamp(width)), at: index)
        focusedColumn = index
    }

    /// Adds a window at the end of the row without moving focus.
    public mutating func append(_ id: ID, width: CGFloat) {
        columns.append(Column(windows: [id], width: Self.clamp(width)))
    }

    /// Removes a window. Focus falls back to the column on the left, so closing
    /// a window returns you to the one you opened it from.
    @discardableResult
    public mutating func remove(_ id: ID) -> Bool {
        guard let (c, r) = location(of: id) else { return false }
        columns[c].windows.remove(at: r)
        if columns[c].windows.isEmpty {
            columns.remove(at: c)
            if focusedColumn > c || (focusedColumn == c && c > 0) {
                focusedColumn -= 1
            }
            focusedColumn = max(0, min(focusedColumn, columns.count - 1))
        } else if r < columns[c].focusedRow || columns[c].focusedRow >= columns[c].windows.count {
            columns[c].focusedRow -= 1
        }
        return true
    }

    // MARK: Focus

    @discardableResult
    public mutating func focus(_ id: ID) -> Bool {
        guard let (c, r) = location(of: id) else { return false }
        focusedColumn = c
        columns[c].focusedRow = r
        return true
    }

    public mutating func focusLeft() {
        if focusedColumn > 0 { focusedColumn -= 1 }
    }

    public mutating func focusRight() {
        if focusedColumn < columns.count - 1 { focusedColumn += 1 }
    }

    public mutating func focusUp() {
        guard !columns.isEmpty, columns[focusedColumn].focusedRow > 0 else { return }
        columns[focusedColumn].focusedRow -= 1
    }

    public mutating func focusDown() {
        guard !columns.isEmpty else { return }
        let column = columns[focusedColumn]
        if column.focusedRow < column.windows.count - 1 { columns[focusedColumn].focusedRow += 1 }
    }

    // MARK: Rearranging

    public mutating func moveLeft() {
        guard focusedColumn > 0 else { return }
        columns.swapAt(focusedColumn, focusedColumn - 1)
        focusedColumn -= 1
    }

    public mutating func moveRight() {
        guard focusedColumn < columns.count - 1 else { return }
        columns.swapAt(focusedColumn, focusedColumn + 1)
        focusedColumn += 1
    }

    /// Moves the focused window into the bottom of the column on its left.
    public mutating func stackLeft() {
        guard focusedColumn > 0, let id = focusedWindow else { return }
        let target = focusedColumn - 1
        remove(id)
        columns[target].windows.append(id)
        columns[target].focusedRow = columns[target].windows.count - 1
        focusedColumn = target
    }

    /// Takes the focused window out of its stack into its own column on the right.
    public mutating func unstack() {
        guard !columns.isEmpty, columns[focusedColumn].windows.count > 1, let id = focusedWindow else { return }
        let width = columns[focusedColumn].width
        let source = focusedColumn
        remove(id)
        columns.insert(Column(windows: [id], width: width), at: source + 1)
        focusedColumn = source + 1
    }

    // MARK: Widths

    /// Steps to the next preset wider than the current width, wrapping to the narrowest.
    public mutating func cycleWidth(presets: [CGFloat]) {
        guard !columns.isEmpty, let first = presets.first else { return }
        let current = columns[focusedColumn].width
        columns[focusedColumn].width = Self.clamp(presets.first { $0 > current + 0.01 } ?? first)
        columns[focusedColumn].widthBeforeFill = nil
    }

    public mutating func resize(by delta: CGFloat) {
        guard !columns.isEmpty else { return }
        columns[focusedColumn].width = Self.clamp(columns[focusedColumn].width + delta)
        columns[focusedColumn].widthBeforeFill = nil
    }

    /// Fills the screen with the focused column; doing it again restores the old width.
    public mutating func toggleFill() {
        guard !columns.isEmpty else { return }
        var column = columns[focusedColumn]
        if column.width >= 0.999, let previous = column.widthBeforeFill {
            column.width = previous
            column.widthBeforeFill = nil
        } else {
            column.widthBeforeFill = column.width
            column.width = 1
        }
        columns[focusedColumn] = column
    }

    public mutating func setWidth(of id: ID, to width: CGFloat) {
        guard let (c, _) = location(of: id) else { return }
        columns[c].width = Self.clamp(width)
        columns[c].widthBeforeFill = nil
    }

    static func clamp(_ width: CGFloat) -> CGFloat {
        min(1, max(minimumWidth, width))
    }
}
