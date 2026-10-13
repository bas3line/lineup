import AppKit
import Carbon.HIToolbox

struct Shortcut {
    let title: String
    let keyCode: Int
    let key: String
    var shift = false
    let command: Command

    var symbols: String { "⌃⌥" + (shift ? "⇧" : "") + key }
}

/// Every shortcut starts with Control + Option, a combination almost no app uses.
let shortcuts: [Shortcut] = [
    Shortcut(title: "Window on the left", keyCode: kVK_LeftArrow, key: "←", command: .focusLeft),
    Shortcut(title: "Window on the right", keyCode: kVK_RightArrow, key: "→", command: .focusRight),
    Shortcut(title: "Window above in stack", keyCode: kVK_UpArrow, key: "↑", command: .focusUp),
    Shortcut(title: "Window below in stack", keyCode: kVK_DownArrow, key: "↓", command: .focusDown),
    Shortcut(title: "Move left", keyCode: kVK_LeftArrow, key: "←", shift: true, command: .moveLeft),
    Shortcut(title: "Move right", keyCode: kVK_RightArrow, key: "→", shift: true, command: .moveRight),
    Shortcut(title: "Change width", keyCode: kVK_ANSI_R, key: "R", command: .cycleWidth),
    Shortcut(title: "Narrower", keyCode: kVK_ANSI_Minus, key: "−", command: .narrower),
    Shortcut(title: "Wider", keyCode: kVK_ANSI_Equal, key: "=", command: .wider),
    Shortcut(title: "Fill screen", keyCode: kVK_ANSI_F, key: "F", command: .fill),
    Shortcut(title: "Centre", keyCode: kVK_ANSI_C, key: "C", command: .center),
    Shortcut(title: "Stack onto the left", keyCode: kVK_ANSI_S, key: "S", command: .stack),
    Shortcut(title: "Unstack", keyCode: kVK_ANSI_S, key: "S", shift: true, command: .unstack),
    Shortcut(title: "Send to next display", keyCode: kVK_ANSI_D, key: "D", command: .nextDisplay),
]

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let manager = WindowManager()
    private let hotKeys = HotKeys()
    private var statusItem: NSStatusItem!
    private var paused = false
    private var permissionTimer: Timer?
    /// The app that was in front when the menu opened, for "Float".
    private var frontApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "Lineup")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        let modifiers = controlKey | optionKey
        for shortcut in shortcuts {
            let registered = hotKeys.register(keyCode: shortcut.keyCode, modifiers: modifiers | (shortcut.shift ? shiftKey : 0)) { [weak self] in
                self?.manager.perform(shortcut.command)
            }
            if !registered { debug("could not register \(shortcut.symbols); another app owns it") }
        }
        hotKeys.register(keyCode: kVK_ANSI_P, modifiers: modifiers) { [weak self] in self?.togglePause() }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            manager.start()
        } else {
            // macOS has shown its prompt; start as soon as access is granted.
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
                guard AXIsProcessTrusted() else { return }
                timer.invalidate()
                if self?.paused == false { self?.manager.start() }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager.stop()
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        frontApp = NSWorkspace.shared.frontmostApplication
        menu.removeAllItems()

        if !AXIsProcessTrusted() {
            menu.addItem(item("Allow Lineup in Accessibility settings…", #selector(openAccessibilitySettings)))
            menu.addItem(.separator())
        }
        menu.addItem(item(paused ? "Resume" : "Pause", #selector(togglePause), key: "⌃⌥P"))

        if let app = frontApp, app.processIdentifier != getpid(), let bundleID = app.bundleIdentifier {
            let floating = item("Float \(app.localizedName ?? bundleID)", #selector(toggleFloating))
            floating.state = Settings.floatingApps.contains(bundleID) ? .on : .off
            menu.addItem(floating)
        }

        let gaps = NSMenu()
        for (index, choice) in Settings.gapChoices.enumerated() {
            let gap = item(choice.name, #selector(setGap(_:)))
            gap.tag = index
            gap.state = Settings.gap == choice.points ? .on : .off
            gaps.addItem(gap)
        }
        let gapItem = NSMenuItem(title: "Spacing", action: nil, keyEquivalent: "")
        gapItem.submenu = gaps
        menu.addItem(gapItem)

        let list = NSMenu()
        for shortcut in shortcuts {
            let entry = NSMenuItem(title: "\(shortcut.symbols)    \(shortcut.title)", action: nil, keyEquivalent: "")
            entry.isEnabled = false
            list.addItem(entry)
        }
        let scroll = NSMenuItem(title: "⌃⌥ + scroll    Slide the row", action: nil, keyEquivalent: "")
        scroll.isEnabled = false
        list.addItem(scroll)
        let listItem = NSMenuItem(title: "Shortcuts", action: nil, keyEquivalent: "")
        listItem.submenu = list
        menu.addItem(listItem)

        menu.addItem(.separator())
        menu.addItem(item("Quit Lineup", #selector(quit)))
    }

    private func item(_ title: String, _ action: Selector, key: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: key.map { "\(title)    \($0)" } ?? title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func togglePause() {
        paused.toggle()
        if paused {
            manager.stop()
        } else if AXIsProcessTrusted() {
            manager.start()
        }
        statusItem.button?.appearsDisabled = paused
    }

    @objc private func toggleFloating() {
        guard let bundleID = frontApp?.bundleIdentifier else { return }
        manager.setFloating(bundleID, !Settings.floatingApps.contains(bundleID))
    }

    @objc private func setGap(_ sender: NSMenuItem) {
        Settings.gap = Settings.gapChoices[sender.tag].points
        manager.relayout()
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
