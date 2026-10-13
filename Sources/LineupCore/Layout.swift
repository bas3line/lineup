import CoreGraphics

extension Strip {
    /// Pixel width of a column. Chosen so that columns whose fractions add up to 1
    /// fill the viewport exactly, gaps included: two halves fit side by side.
    public static func pixelWidth(of fraction: CGFloat, viewportWidth: CGFloat, gap: CGFloat) -> CGFloat {
        max(1, fraction * (viewportWidth - gap) - gap)
    }

    /// Inverse of `pixelWidth`, for when the user drags a window to a new width.
    public static func fraction(of pixelWidth: CGFloat, viewportWidth: CGFloat, gap: CGFloat) -> CGFloat {
        (pixelWidth + gap) / max(1, viewportWidth - gap)
    }

    /// Left edge of every column, measured along the row from its start.
    func offsets(viewportWidth: CGFloat, gap: CGFloat) -> [CGFloat] {
        var x = gap
        return columns.map { column in
            defer { x += Self.pixelWidth(of: column.width, viewportWidth: viewportWidth, gap: gap) + gap }
            return x
        }
    }

    func span(of index: Int, viewportWidth: CGFloat, gap: CGFloat) -> (x: CGFloat, width: CGFloat) {
        let x = offsets(viewportWidth: viewportWidth, gap: gap)[index]
        return (x, Self.pixelWidth(of: columns[index].width, viewportWidth: viewportWidth, gap: gap))
    }

    /// The viewport may slide from centring the first column to centring the last,
    /// and always includes the resting position where the row starts at the left edge.
    public func scrollBounds(viewportWidth: CGFloat, gap: CGFloat) -> ClosedRange<CGFloat> {
        guard !columns.isEmpty else { return 0...0 }
        let first = span(of: 0, viewportWidth: viewportWidth, gap: gap)
        let last = span(of: columns.count - 1, viewportWidth: viewportWidth, gap: gap)
        let total = last.x + last.width + gap
        let lower = min(0, first.x + first.width / 2 - viewportWidth / 2)
        let upper = max(0, total - viewportWidth, last.x + last.width / 2 - viewportWidth / 2)
        return lower...upper
    }

    /// Slides the viewport the least amount needed to show the whole focused column.
    public mutating func revealFocused(viewportWidth: CGFloat, gap: CGFloat) {
        guard !columns.isEmpty else { scroll = 0; return }
        let (x, width) = span(of: focusedColumn, viewportWidth: viewportWidth, gap: gap)
        if x - gap < scroll {
            scroll = x - gap
        } else if x + width + gap > scroll + viewportWidth {
            scroll = x + width + gap - viewportWidth
        }
        clampScroll(viewportWidth: viewportWidth, gap: gap)
    }

    public mutating func centerFocused(viewportWidth: CGFloat, gap: CGFloat) {
        guard !columns.isEmpty else { return }
        let (x, width) = span(of: focusedColumn, viewportWidth: viewportWidth, gap: gap)
        scroll = x + width / 2 - viewportWidth / 2
    }

    public mutating func scroll(by delta: CGFloat, viewportWidth: CGFloat, gap: CGFloat) {
        scroll += delta
        clampScroll(viewportWidth: viewportWidth, gap: gap)
    }

    mutating func clampScroll(viewportWidth: CGFloat, gap: CGFloat) {
        let bounds = scrollBounds(viewportWidth: viewportWidth, gap: gap)
        scroll = min(bounds.upperBound, max(bounds.lowerBound, scroll))
    }

    /// Where every window goes. `viewport` is the usable area of the display (menu
    /// bar and Dock excluded); `screen` is the whole display, used to park windows
    /// that are scrolled out of view in its bottom corners with only `sliver`
    /// points showing, since macOS won't let a window leave the screen entirely.
    /// All rectangles use top-left-origin global coordinates, like Accessibility.
    public func frames(viewport: CGRect, screen: CGRect, gap: CGFloat, sliver: CGFloat = 1) -> [ID: CGRect] {
        var result: [ID: CGRect] = [:]
        let offsets = offsets(viewportWidth: viewport.width, gap: gap)
        for (c, column) in columns.enumerated() {
            let width = Self.pixelWidth(of: column.width, viewportWidth: viewport.width, gap: gap)
            let rows = CGFloat(column.windows.count)
            let height = max(1, (viewport.height - gap * (rows + 1)) / rows)
            let x = viewport.minX + offsets[c] - scroll
            for (r, id) in column.windows.enumerated() {
                var frame = CGRect(x: x, y: viewport.minY + gap + CGFloat(r) * (height + gap), width: width, height: height)
                if frame.maxX <= viewport.minX {
                    frame.origin = CGPoint(x: screen.minX - width + sliver, y: screen.maxY - sliver)
                } else if frame.minX >= viewport.maxX {
                    frame.origin = CGPoint(x: screen.maxX - sliver, y: screen.maxY - sliver)
                }
                result[id] = frame
            }
        }
        return result
    }
}
