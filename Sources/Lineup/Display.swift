import AppKit

/// A screen in Accessibility coordinates: origin at the top-left of the primary
/// display, y growing downwards. AppKit's `NSScreen` uses bottom-left, so every
/// rectangle is flipped once here and nowhere else.
struct Display: Equatable {
    let id: CGDirectDisplayID
    /// The whole screen.
    let frame: CGRect
    /// The screen minus the menu bar and the Dock.
    let visibleFrame: CGRect

    static func all() -> [Display] {
        guard let primary = NSScreen.screens.first else { return [] }
        let height = primary.frame.height
        func flip(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: height - r.maxY, width: r.width, height: r.height) }
        return NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
            return Display(id: id, frame: flip(screen.frame), visibleFrame: flip(screen.visibleFrame))
        }
    }

    /// The display under the mouse pointer, in the same coordinates.
    static func underMouse(in displays: [Display]) -> Display? {
        guard let height = NSScreen.screens.first?.frame.height else { return displays.first }
        let mouse = NSEvent.mouseLocation
        let point = CGPoint(x: mouse.x, y: height - mouse.y)
        return displays.first { $0.frame.contains(point) } ?? displays.first
    }
}
