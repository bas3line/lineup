import AppKit
import LineupCore

enum Command {
    case focusLeft, focusRight, focusUp, focusDown
    case moveLeft, moveRight
    case cycleWidth, narrower, wider, fill, center
    case stack, unstack, nextDisplay
}

/// Keeps one `Strip` per display in sync with the real windows: adopts windows
/// as they open, drops them as they close, follows focus, and moves every window
/// to the frame its strip says it should have.
final class WindowManager {
    private(set) var isRunning = false
    private var displays: [Display] = []
    private var strips: [CGDirectDisplayID: Strip<AXWindow>] = [:]
    /// The last frame we set on each window, to tell our own moves from the user's.
    private var applied: [AXWindow: CGRect] = [:]
    private var observers: [pid_t: AXObserver] = [:]
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    private var scrollMonitor: Any?
    private var resnap: DispatchWorkItem?
    private var screenChange: DispatchWorkItem?

    // MARK: Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        displays = Display.all()
        strips = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, Strip()) })

        // Adopt what is already open, keeping today's left-to-right order.
        var found: [(window: AXWindow, frame: CGRect)] = []
        for app in NSWorkspace.shared.runningApplications where shouldTile(app) {
            observe(app.processIdentifier)
            for window in AXWindow.windows(of: app.processIdentifier) where window.isManageable {
                if let frame = window.frame { found.append((window, frame)) }
            }
        }
        for (window, frame) in found.sorted(by: { $0.frame.minX < $1.frame.minX }) {
            guard let id = display(containing: frame)?.id else { continue }
            strips[id]?.append(window, width: Settings.newWindowWidth)
            watch(window)
        }
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           let window = AXWindow.focused(of: pid), let id = stripID(of: window) {
            strips[id]?.focus(window)
        }

        let workspace = NSWorkspace.shared.notificationCenter
        func on(_ center: NotificationCenter, _ name: Notification.Name, _ body: @escaping (Notification) -> Void) {
            tokens.append((center, center.addObserver(forName: name, object: nil, queue: .main, using: body)))
        }
        on(workspace, NSWorkspace.didLaunchApplicationNotification) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication { self?.appLaunched(app) }
        }
        on(workspace, NSWorkspace.didTerminateApplicationNotification) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication { self?.appTerminated(app.processIdentifier) }
        }
        on(workspace, NSWorkspace.didActivateApplicationNotification) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication { self?.syncFocus(app.processIdentifier) }
        }
        on(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { [weak self] _ in
            self?.screensChanged()
        }
        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in self?.scrolled(event) }

        for id in strips.keys { reveal(id); layout(id) }
    }

    /// Stops tiling. Windows stay where they are, except ones scrolled out of
    /// view, which are pulled back onto the screen so nothing is left hidden.
    func stop() {
        guard isRunning else { return }
        for (id, strip) in strips {
            guard let visible = display(id)?.visibleFrame else { continue }
            for window in strip.windows {
                guard let frame = window.frame, !visible.contains(frame) else { continue }
                let x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
                let y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
                window.element.set(kAXPositionAttribute, point: CGPoint(x: max(x, visible.minX), y: max(y, visible.minY)))
            }
        }
        isRunning = false
        for observer in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observers.removeAll()
        tokens.forEach { center, token in center.removeObserver(token) }
        tokens.removeAll()
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
        resnap?.cancel()
        screenChange?.cancel()
        strips.removeAll()
        applied.removeAll()
    }

    // MARK: Commands

    func perform(_ command: Command) {
        guard isRunning, let id = activeDisplayID(), let display = display(id), var strip = strips[id] else { return }
        if command == .nextDisplay { return sendToNextDisplay(from: id) }
        let width = display.visibleFrame.width
        let gap = Settings.gap
        switch command {
        case .focusLeft: strip.focusLeft()
        case .focusRight: strip.focusRight()
        case .focusUp: strip.focusUp()
        case .focusDown: strip.focusDown()
        case .moveLeft: strip.moveLeft()
        case .moveRight: strip.moveRight()
        case .cycleWidth: strip.cycleWidth(presets: Settings.widthPresets)
        case .narrower: strip.resize(by: -0.1)
        case .wider: strip.resize(by: 0.1)
        case .fill: strip.toggleFill()
        case .center: break
        case .stack: strip.stackLeft()
        case .unstack: strip.unstack()
        case .nextDisplay: break
        }
        if command == .center {
            strip.centerFocused(viewportWidth: width, gap: gap)
        } else {
            strip.revealFocused(viewportWidth: width, gap: gap)
        }
        strips[id] = strip
        debug("command \(command): \(strip.summary)")
        layout(id)
        strip.focusedWindow?.focus()
    }

    /// Re-applies every frame, e.g. after the gap changes.
    func relayout() {
        guard isRunning else { return }
        applied.removeAll()
        for id in strips.keys { reveal(id); layout(id) }
    }

    func setFloating(_ bundleID: String, _ floating: Bool) {
        var apps = Settings.floatingApps
        if floating { apps.insert(bundleID) } else { apps.remove(bundleID) }
        Settings.floatingApps = apps
        guard isRunning else { return }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            if floating {
                AXWindow.windows(of: app.processIdentifier).forEach(release)
            } else {
                if observers[app.processIdentifier] == nil { observe(app.processIdentifier) }
                AXWindow.windows(of: app.processIdentifier).forEach(adopt)
            }
        }
    }

    // MARK: Events

    fileprivate func handle(_ notification: String, _ window: AXWindow) {
        guard isRunning else { return }
        debug("event \(notification) \(window.element.string(kAXTitleAttribute) ?? "?")")
        switch notification {
        case kAXWindowCreatedNotification:
            // Some apps finish configuring a window just after announcing it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.adopt(window) }
        case kAXFocusedWindowChangedNotification:
            syncFocus(window.pid)
        case kAXUIElementDestroyedNotification:
            windowsClosed(in: window.pid)
        case kAXWindowMiniaturizedNotification:
            release(window)
        case kAXWindowDeminiaturizedNotification:
            adopt(window)
        case kAXWindowResizedNotification:
            resized(window)
        case kAXWindowMovedNotification:
            moved(window)
        default:
            break
        }
    }

    private func appLaunched(_ app: NSRunningApplication) {
        guard shouldTile(app) else { return }
        // A launching app may not answer Accessibility calls yet, and may open its
        // first window before we are listening, so look a few times.
        for delay in [0.1, 0.5, 1.5, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.isRunning, !app.isTerminated else { return }
                if self.observers[app.processIdentifier] == nil { self.observe(app.processIdentifier) }
                AXWindow.windows(of: app.processIdentifier).forEach(self.adopt)
            }
        }
    }

    private func appTerminated(_ pid: pid_t) {
        if let observer = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        for id in strips.keys {
            let gone = strips[id]!.windows.filter { $0.pid == pid }
            guard !gone.isEmpty else { continue }
            gone.forEach { strips[id]!.remove($0); applied[$0] = nil }
            reveal(id); layout(id)
        }
    }

    /// A closed window's handle doesn't always compare equal to the one we hold,
    /// so sweep the app's windows for any that no longer exist.
    private func windowsClosed(in pid: pid_t) {
        for id in strips.keys {
            let gone = strips[id]!.windows.filter { $0.pid == pid && !$0.isAlive }
            guard !gone.isEmpty else { continue }
            gone.forEach { strips[id]!.remove($0); applied[$0] = nil }
            debug("closed \(gone.count): \(strips[id]!.summary)")
            reveal(id); layout(id)
        }
    }

    private func syncFocus(_ pid: pid_t) {
        guard isRunning, let window = AXWindow.focused(of: pid) else { return }
        guard let id = stripID(of: window) else { return adopt(window) }
        guard strips[id]?.focusedWindow != window else { return }
        strips[id]?.focus(window)
        debug("focus followed: \(strips[id]!.summary)")
        reveal(id)
        layout(id)
    }

    /// The user dragged a window edge: keep the new width and make room for it.
    private func resized(_ window: AXWindow) {
        guard let id = stripID(of: window) else { return adopt(window) }
        guard let display = display(id), let frame = window.frame, let target = applied[window],
              abs(frame.width - target.width) > 2
        else { return }
        if window.element.bool("AXFullScreen") == true { return release(window) }
        let fraction = Strip<AXWindow>.fraction(of: frame.width, viewportWidth: display.visibleFrame.width, gap: Settings.gap)
        strips[id]?.setWidth(of: window, to: fraction)
        applied[window] = CGRect(origin: target.origin, size: CGSize(width: frame.width, height: target.height))
        reveal(id)
        layout(id)
    }

    /// The user dragged a window: once they let go, put it back in the row, on
    /// whichever display they dropped it.
    private func moved(_ window: AXWindow) {
        guard stripID(of: window) != nil, let target = applied[window], let frame = window.frame,
              abs(frame.minX - target.minX) > 2 || abs(frame.minY - target.minY) > 2
        else { return }
        scheduleResnap(window)
    }

    private func scheduleResnap(_ window: AXWindow) {
        resnap?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning, let from = self.stripID(of: window) else { return }
            if NSEvent.pressedMouseButtons & 1 != 0 { return self.scheduleResnap(window) }
            if let frame = window.frame, let to = self.display(containing: frame)?.id, to != from {
                self.strips[from]?.remove(window)
                self.strips[to]?.insert(window, width: Settings.newWindowWidth)
                self.reveal(from); self.layout(from)
                self.reveal(to)
            }
            self.applied[window] = nil
            self.layout(self.stripID(of: window) ?? from)
        }
        resnap = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// Control + Option + scroll (or a two-finger swipe) slides the row under the pointer.
    private func scrolled(_ event: NSEvent) {
        guard isRunning, event.modifierFlags.contains([.control, .option]),
              let display = Display.underMouse(in: displays) else { return }
        var delta = event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.scrollingDeltaY
        if !event.hasPreciseScrollingDeltas { delta *= 10 }
        strips[display.id]?.scroll(by: -delta, viewportWidth: display.visibleFrame.width, gap: Settings.gap)
        layout(display.id)
    }

    private func screensChanged() {
        screenChange?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning else { return }
            let old = self.strips
            self.displays = Display.all()
            guard let first = self.displays.first else { return }
            var strips = Dictionary(uniqueKeysWithValues: self.displays.map { ($0.id, old[$0.id] ?? Strip()) })
            for (id, strip) in old where strips[id] == nil {
                strip.windows.forEach { strips[first.id]?.append($0, width: Settings.newWindowWidth) }
            }
            self.strips = strips
            self.relayout()
        }
        screenChange = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    // MARK: Windows

    private func adopt(_ window: AXWindow) {
        guard isRunning, stripID(of: window) == nil, window.isManageable,
              let app = NSRunningApplication(processIdentifier: window.pid), shouldTile(app),
              let frame = window.frame, let id = display(containing: frame)?.id
        else { return }
        strips[id]?.insert(window, width: Settings.newWindowWidth)
        debug("adopted \(window.element.string(kAXTitleAttribute) ?? "?"): \(strips[id]!.summary)")
        watch(window)
        reveal(id)
        layout(id)
    }

    private func release(_ window: AXWindow) {
        guard let id = stripID(of: window) else { return }
        strips[id]?.remove(window)
        applied[window] = nil
        reveal(id)
        layout(id)
    }

    private func sendToNextDisplay(from id: CGDirectDisplayID) {
        guard displays.count > 1, let window = strips[id]?.focusedWindow,
              let index = displays.firstIndex(where: { $0.id == id }) else { return }
        let next = displays[(index + 1) % displays.count].id
        strips[id]?.remove(window)
        strips[next]?.insert(window, width: Settings.newWindowWidth)
        applied[window] = nil
        reveal(id); layout(id)
        reveal(next); layout(next)
        window.focus()
    }

    private func reveal(_ id: CGDirectDisplayID) {
        guard let display = display(id) else { return }
        strips[id]?.revealFocused(viewportWidth: display.visibleFrame.width, gap: Settings.gap)
    }

    private func layout(_ id: CGDirectDisplayID) {
        guard isRunning, let strip = strips[id], let display = display(id) else { return }
        let frames = strip.frames(viewport: display.visibleFrame, screen: display.frame, gap: Settings.gap)
        for (window, frame) in frames {
            if let last = applied[window], last.isClose(to: frame) { continue }
            window.setFrame(frame)
            applied[window] = frame
        }
    }

    // MARK: Lookup

    private func shouldTile(_ app: NSRunningApplication) -> Bool {
        guard app.activationPolicy == .regular, app.processIdentifier != getpid(),
              let bundleID = app.bundleIdentifier else { return false }
        if let only = Settings.onlyApps { return only.contains(bundleID) }
        return !Settings.floatingApps.contains(bundleID)
    }

    private func stripID(of window: AXWindow) -> CGDirectDisplayID? {
        strips.first { $0.value.contains(window) }?.key
    }

    private func display(_ id: CGDirectDisplayID) -> Display? {
        displays.first { $0.id == id }
    }

    private func display(containing frame: CGRect) -> Display? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return displays.first { $0.frame.contains(center) }
            ?? displays.max { $0.frame.intersection(frame).area < $1.frame.intersection(frame).area }
    }

    /// The display holding the focused window, or else the one under the pointer.
    private func activeDisplayID() -> CGDirectDisplayID? {
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           let window = AXWindow.focused(of: pid), let id = stripID(of: window) {
            return id
        }
        return Display.underMouse(in: displays)?.id
    }

    private func observe(_ pid: pid_t) {
        var observer: AXObserver?
        guard AXObserverCreate(pid, axCallback, &observer) == .success, let observer else { return }
        let app = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverAddNotification(observer, app, kAXWindowCreatedNotification as CFString, refcon) == .success else { return }
        AXObserverAddNotification(observer, app, kAXFocusedWindowChangedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func watch(_ window: AXWindow) {
        guard let observer = observers[window.pid] else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
                     kAXWindowResizedNotification, kAXWindowMovedNotification] {
            AXObserverAddNotification(observer, window.element, name as CFString, refcon)
        }
    }
}

private let debugging = ProcessInfo.processInfo.environment["LINEUP_DEBUG"] != nil

/// Set LINEUP_DEBUG=1 to trace every decision on stderr.
func debug(_ message: @autoclosure () -> String) {
    guard debugging else { return }
    FileHandle.standardError.write(Data((message() + "\n").utf8))
}

extension Strip where ID == AXWindow {
    var summary: String {
        columns.enumerated().map { index, column in
            let titles = column.windows.map { $0.element.string(kAXTitleAttribute) ?? "?" }.joined(separator: "+")
            return (index == focusedColumn ? "*" : "") + titles
        }.joined(separator: " | ")
    }
}

private func axCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    Unmanaged<WindowManager>.fromOpaque(refcon).takeUnretainedValue().handle(notification as String, AXWindow(element))
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }

    func isClose(to other: CGRect) -> Bool {
        abs(minX - other.minX) < 1 && abs(minY - other.minY) < 1 && abs(width - other.width) < 1 && abs(height - other.height) < 1
    }
}
