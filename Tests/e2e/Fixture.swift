// A stand-in app for the end-to-end test: opens an empty, titled, resizable
// window each time it receives `app.lineup.fixture.open` with the title as the
// object. No documents, no text input, nothing saved, so a test run can never
// touch real files.
import AppKit

final class FixtureDelegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: .init("app.lineup.fixture.open"), object: nil, queue: .main) { [weak self] note in
            self?.open(note.object as? String ?? "Window")
        }
        center.addObserver(forName: .init("app.lineup.fixture.quit"), object: nil, queue: .main) { _ in
            NSApp.terminate(nil)
        }
    }

    private func open(_ title: String) {
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 500, height: 400),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 100, height: 100)
        windows.append(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

let app = NSApplication.shared
let delegate = FixtureDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
