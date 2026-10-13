import AppKit
import ApplicationServices

/// A window seen through the Accessibility API. Two handles to the same window
/// compare equal (`CFEqual`), so it can key dictionaries and live in a `Strip`.
struct AXWindow: Hashable {
    let element: AXUIElement
    let pid: pid_t

    init(_ element: AXUIElement) {
        self.element = element
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        self.pid = pid
    }

    static func == (lhs: AXWindow, rhs: AXWindow) -> Bool { CFEqual(lhs.element, rhs.element) }
    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }

    var bundleID: String? { NSRunningApplication(processIdentifier: pid)?.bundleIdentifier }

    /// Ordinary resizable document windows only: no sheets, panels, popovers,
    /// minimised or full-screen windows.
    var isManageable: Bool {
        guard element.string(kAXRoleAttribute) == kAXWindowRole,
              element.string(kAXSubroleAttribute) == kAXStandardWindowSubrole,
              element.bool(kAXMinimizedAttribute) != true,
              element.bool("AXFullScreen") != true
        else { return false }
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &settable)
        return settable.boolValue
    }

    /// False once the window has been closed.
    var isAlive: Bool {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) != .invalidUIElement
    }

    var frame: CGRect? {
        guard let origin = element.point(kAXPositionAttribute), let size = element.size(kAXSizeAttribute) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    func setFrame(_ frame: CGRect) {
        // Electron and Chromium apps animate every frame change while
        // AXEnhancedUserInterface is on, which makes tiling crawl.
        let app = AXUIElementCreateApplication(pid)
        let enhanced = app.bool("AXEnhancedUserInterface") == true
        if enhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }
        // Position, size, position: apps clamp a new size against the old origin.
        element.set(kAXPositionAttribute, point: frame.origin)
        element.set(kAXSizeAttribute, size: frame.size)
        element.set(kAXPositionAttribute, point: frame.origin)
        if enhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) }
    }

    func focus() {
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        if #available(macOS 14, *) {
            app.activate()
        } else {
            app.activate(options: .activateIgnoringOtherApps)
        }
    }

    static func windows(of pid: pid_t) -> [AXWindow] {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let elements = value as? [AXUIElement]
        else { return [] }
        return elements.map(AXWindow.init)
    }

    static func focused(of pid: pid_t) -> AXWindow? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return AXWindow(value as! AXUIElement)
    }
}

extension AXUIElement {
    func string(_ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    func bool(_ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    func point(_ attribute: String) -> CGPoint? {
        var point = CGPoint.zero
        guard let value = axValue(attribute), AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    func size(_ attribute: String) -> CGSize? {
        var size = CGSize.zero
        guard let value = axValue(attribute), AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    private func axValue(_ attribute: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        return (value as! AXValue)
    }

    func set(_ attribute: String, point: CGPoint) {
        var point = point
        if let value = AXValueCreate(.cgPoint, &point) {
            AXUIElementSetAttributeValue(self, attribute as CFString, value)
        }
    }

    func set(_ attribute: String, size: CGSize) {
        var size = size
        if let value = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(self, attribute as CFString, value)
        }
    }
}
