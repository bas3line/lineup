// End-to-end test: launches the built Lineup binary, tiles only the fixture
// app's windows, drives Lineup with the real global shortcuts, and checks real
// window frames through the Accessibility API. Run with scripts/e2e.sh; the
// terminal needs Accessibility access. Keep hands off the keyboard while it runs.
import AppKit
import ApplicationServices

let binary = CommandLine.arguments[1]
let fixturePath = CommandLine.arguments[2]
let fixtureID = "app.lineup.fixture"
let gap: CGFloat = 10
var failures = 0

func check(_ ok: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
    print(ok ? "PASS  \(name)" : "FAIL  \(name)  \(detail())")
    if !ok { failures += 1 }
}

func wait(_ seconds: Double = 0.6) { usleep(useconds_t(seconds * 1_000_000)) }

// MARK: Accessibility helpers

func attr(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
}

func fixture() -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: fixtureID).first
}

func windows() -> [String: AXUIElement] {
    guard let pid = fixture()?.processIdentifier,
          let list = attr(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement] else { return [:] }
    var result: [String: AXUIElement] = [:]
    for w in list {
        if let title = attr(w, kAXTitleAttribute) as? String { result[title] = w }
    }
    return result
}

func frame(_ title: String) -> CGRect {
    guard let w = windows()[title] else { return .null }
    var p = CGPoint.zero, s = CGSize.zero
    AXValueGetValue(attr(w, kAXPositionAttribute) as! AXValue, .cgPoint, &p)
    AXValueGetValue(attr(w, kAXSizeAttribute) as! AXValue, .cgSize, &s)
    return CGRect(origin: p, size: s)
}

/// Moves or resizes a window the way a user's drag would.
func drag(_ title: String, x: CGFloat? = nil, width: CGFloat? = nil) {
    guard let w = windows()[title] else { return }
    let f = frame(title)
    if let width {
        var s = CGSize(width: width, height: f.height)
        AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &s)!)
    }
    if let x {
        var p = CGPoint(x: x, y: f.minY)
        AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &p)!)
    }
}

func focusedTitle() -> String? {
    guard let pid = fixture()?.processIdentifier,
          let w = attr(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute) else { return nil }
    return attr(w as! AXUIElement, kAXTitleAttribute) as? String
}

/// Brings a window to the front the way a click or the Window menu would.
func raise(_ title: String) {
    guard let w = windows()[title] else { return }
    AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
    AXUIElementPerformAction(w, kAXRaiseAction as CFString)
    wait(0.8)
}

func open(_ title: String) {
    DistributedNotificationCenter.default().postNotificationName(.init("app.lineup.fixture.open"), object: title, userInfo: nil, deliverImmediately: true)
    wait(0.8)
}

func close(_ title: String) {
    guard let w = windows()[title], let button = attr(w, kAXCloseButtonAttribute) else { return }
    AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
    wait(0.8)
}

// MARK: Input

func press(_ key: CGKeyCode, shift: Bool = false) {
    var flags: CGEventFlags = [.maskControl, .maskAlternate]
    if shift { flags.insert(.maskShift) }
    // A real keyboard flags arrow keys as function and keypad keys.
    if (0x7B...0x7E).contains(key) { flags.formUnion([.maskSecondaryFn, .maskNumericPad]) }
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down)!
        e.flags = flags
        e.post(tap: .cghidEventTap)
        usleep(20_000)
    }
    wait()
}

/// Control + Option + a horizontal trackpad scroll of `points`.
func scroll(_ points: Int32) {
    let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: points, wheel3: 0)!
    e.flags = [.maskControl, .maskAlternate]
    e.post(tap: .cghidEventTap)
    wait()
}

let left: CGKeyCode = 0x7B, right: CGKeyCode = 0x7C, down: CGKeyCode = 0x7D, up: CGKeyCode = 0x7E
let keyR: CGKeyCode = 0x0F, keyF: CGKeyCode = 0x03, keyC: CGKeyCode = 0x08, keyS: CGKeyCode = 0x01, keyP: CGKeyCode = 0x23
let minus: CGKeyCode = 0x1B, equal: CGKeyCode = 0x18

// MARK: Geometry

let primary = NSScreen.screens[0]
func flip(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: primary.frame.height - r.maxY, width: r.width, height: r.height) }
let screen = flip(primary.frame)
let visible = flip(primary.visibleFrame)
let half = 0.5 * (visible.width - gap) - gap
let height = visible.height - 2 * gap

func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 2) -> Bool { abs(a - b) <= tolerance }
/// Share of the window that is on screen; a missing window counts as fully
/// visible so that "parked" checks can't pass by accident.
func onScreen(_ f: CGRect) -> CGFloat {
    guard !f.isNull else { return 1 }
    let i = f.intersection(screen)
    return i.isNull ? 0 : i.width * i.height / (f.width * f.height)
}
func describe(_ f: CGRect) -> String { f.isNull ? "missing" : "got \(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))" }

// MARK: Run

guard AXIsProcessTrusted() else { print("This terminal needs Accessibility access."); exit(2) }
guard fixture() == nil else { print("LineupFixture is already running; quit it first."); exit(2) }

let lineup = Process()
lineup.executableURL = URL(fileURLWithPath: binary)
lineup.arguments = ["-gap", "\(Int(gap))"]
lineup.environment = ProcessInfo.processInfo.environment.merging(["LINEUP_ONLY_APPS": fixtureID, "LINEUP_DEBUG": "1"]) { $1 }
let logPath = NSTemporaryDirectory() + "lineup-e2e.log"
FileManager.default.createFile(atPath: logPath, contents: nil)
lineup.standardError = FileHandle(forWritingAtPath: logPath)
lineup.standardOutput = FileHandle.nullDevice
try lineup.run()
wait(1)

// Run the executable inside the bundle directly; it still picks up the bundle's
// identifier, and skips LaunchServices' checks on an ad-hoc signed build.
let launcher = Process()
launcher.executableURL = URL(fileURLWithPath: fixturePath + "/Contents/MacOS/LineupFixture")
launcher.standardOutput = FileHandle.nullDevice
launcher.standardError = FileHandle.nullDevice
try launcher.run()
for _ in 0..<50 where fixture() == nil { wait(0.1) }
guard fixture() != nil else {
    lineup.terminate()
    print("LineupFixture did not start.")
    exit(2)
}
wait(1)

print("Screen \(Int(screen.width))x\(Int(screen.height)), usable \(describe(visible))")

open("W1")
let a = frame("W1")
check(near(a.minX, visible.minX + gap) && near(a.minY, visible.minY + gap) && near(a.width, half) && near(a.height, height),
      "first window takes the first half", describe(a))

open("W2")
let b = frame("W2")
check(near(b.minX, visible.minX + 2 * gap + half) && near(b.width, half), "second window lands next to it", describe(b))
check(frame("W1") == a, "first window keeps its size and place", describe(frame("W1")))

scroll(-200)
let slid = frame("W1").minX - a.minX
check(near(abs(slid), 200), "⌃⌥ + scroll slides the row", describe(frame("W1")))
scroll(200)
check(near(frame("W1").minX, a.minX), "scrolling back returns it", describe(frame("W1")))

open("W3")
let c = frame("W3")
check(near(c.maxX, visible.maxX - gap) && near(c.width, half), "third window slides the row and sits at the right edge", describe(c))
check(near(frame("W2").minX, visible.minX + gap), "second window moves to the left edge", describe(frame("W2")))
check(onScreen(frame("W1")) < 0.05, "first window is parked out of view", describe(frame("W1")))

raise("W1")
check(near(frame("W1").minX, visible.minX + gap), "focusing a parked window with the mouse slides it into view", describe(frame("W1")))
raise("W3")
check(near(frame("W3").maxX, visible.maxX - gap) && onScreen(frame("W1")) < 0.05, "and focusing the last one slides back", describe(frame("W3")))

press(left)
check(focusedTitle() == "W2", "⌃⌥← focuses the window on the left", focusedTitle() ?? "nil")
press(left)
check(focusedTitle() == "W1", "⌃⌥← again reaches the first window", focusedTitle() ?? "nil")
check(near(frame("W1").minX, visible.minX + gap), "first window scrolls back into view", describe(frame("W1")))
check(onScreen(frame("W3")) < 0.05, "third window is parked on the right", describe(frame("W3")))

press(keyR)
check(near(frame("W1").width, 2.0 / 3 * (visible.width - gap) - gap), "⌃⌥R widens to two thirds", describe(frame("W1")))
press(keyR)
check(near(frame("W1").width, 1.0 / 3 * (visible.width - gap) - gap), "⌃⌥R wraps to one third", describe(frame("W1")))
press(keyR)
check(near(frame("W1").width, half), "⌃⌥R returns to half", describe(frame("W1")))

press(equal)
check(near(frame("W1").width, 0.6 * (visible.width - gap) - gap), "⌃⌥= widens a step", describe(frame("W1")))
press(minus)
check(near(frame("W1").width, half), "⌃⌥− narrows a step", describe(frame("W1")))

press(keyF)
check(near(frame("W1").width, visible.width - 2 * gap), "⌃⌥F fills the screen", describe(frame("W1")))
press(keyF)
check(near(frame("W1").width, half), "⌃⌥F again restores the width", describe(frame("W1")))

press(right, shift: true)
check(near(frame("W2").minX, visible.minX + gap) && near(frame("W1").minX, visible.minX + 2 * gap + half),
      "⌃⌥⇧→ swaps the window with its right neighbour", "W1 \(describe(frame("W1"))), W2 \(describe(frame("W2")))")
check(focusedTitle() == "W1", "moved window keeps focus", focusedTitle() ?? "nil")

press(keyS)
let top = frame("W2"), bottom = frame("W1")
check(near(top.minX, bottom.minX) && near(top.height, bottom.height) && near(bottom.minY, top.maxY + gap)
      && near(top.height, (visible.height - 3 * gap) / 2),
      "⌃⌥S stacks the window under its left neighbour", "top \(describe(top)), bottom \(describe(bottom))")
press(up)
check(focusedTitle() == "W2", "⌃⌥↑ focuses the window above in the stack", focusedTitle() ?? "nil")
press(down)
check(focusedTitle() == "W1", "⌃⌥↓ focuses the window below", focusedTitle() ?? "nil")
press(keyS, shift: true)
check(near(frame("W1").height, height) && near(frame("W1").minX, visible.minX + 2 * gap + half),
      "⌃⌥⇧S unstacks it again", describe(frame("W1")))

press(keyC)
check(near(frame("W1").midX, visible.midX), "⌃⌥C centres the window", describe(frame("W1")))

close("W1")
check(windows()["W1"] == nil, "closing a window removes it")
let afterClose2 = frame("W2"), afterClose3 = frame("W3")
check(onScreen(afterClose2) > 0.99 && near(afterClose3.minX, afterClose2.maxX + gap),
      "the row closes the gap", "W2 \(describe(afterClose2)), W3 \(describe(afterClose3))")

press(left)
drag("W2", width: 700)
wait(0.8)
check(near(frame("W2").width, 700, 4) && near(frame("W3").minX, frame("W2").maxX + gap),
      "a window resized by hand keeps its width and pushes its neighbour",
      "W2 \(describe(frame("W2"))), W3 \(describe(frame("W3")))")

let before = frame("W2")
drag("W2", x: before.minX + 150)
wait(1)
check(near(frame("W2").minX, before.minX), "a window dragged by hand snaps back into the row", describe(frame("W2")))

press(keyF)
check(onScreen(frame("W3")) < 0.05, "filling the screen parks the neighbour", describe(frame("W3")))
press(keyP)
check(visible.contains(frame("W3").insetBy(dx: 1, dy: 1)), "⌃⌥P pause brings parked windows back on screen", describe(frame("W3")))
open("W4")
let untiled = frame("W4")
check(!untiled.isNull && !near(untiled.height, height), "while paused new windows are left alone", describe(untiled))
press(keyP)
check(near(frame("W4").height, height) && near(frame("W2").height, height) && near(frame("W3").height, height),
      "⌃⌥P again resumes and tiles every window, including ones opened while paused",
      "W2 \(describe(frame("W2"))), W3 \(describe(frame("W3"))), W4 \(describe(frame("W4")))")

DistributedNotificationCenter.default().postNotificationName(.init("app.lineup.fixture.quit"), object: nil, userInfo: nil, deliverImmediately: true)
lineup.terminate()
lineup.waitUntilExit()
wait(0.5)
fixture()?.forceTerminate()
print("Lineup log: \(logPath)")
print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
