import Foundation

/// User preferences, stored in UserDefaults (`defaults read app.lineup`). Any key
/// can be overridden for one run with a launch argument, e.g. `-gap 0`.
enum Settings {
    private static let defaults = UserDefaults.standard

    static let widthPresets: [CGFloat] = [1.0 / 3, 0.5, 2.0 / 3]
    static let gapChoices: [(name: String, points: CGFloat)] = [("None", 0), ("Small", 8), ("Medium", 16), ("Large", 24)]

    static var gap: CGFloat {
        get { defaults.object(forKey: "gap") == nil ? 8 : CGFloat(defaults.double(forKey: "gap")) }
        set { defaults.set(Double(newValue), forKey: "gap") }
    }

    /// Width of a newly opened window, as a fraction of the screen.
    static var newWindowWidth: CGFloat {
        defaults.object(forKey: "newWindowWidth") == nil ? 0.5 : CGFloat(defaults.double(forKey: "newWindowWidth"))
    }

    /// Apps whose windows float freely instead of joining the row.
    static var floatingApps: Set<String> {
        get { Set(defaults.stringArray(forKey: "floatingApps") ?? []) }
        set { defaults.set(newValue.sorted(), forKey: "floatingApps") }
    }

    /// When set, only these apps are tiled. Used by the end-to-end test so a run
    /// never rearranges anything but its own windows.
    static var onlyApps: Set<String>? {
        guard let list = ProcessInfo.processInfo.environment["LINEUP_ONLY_APPS"], !list.isEmpty else { return nil }
        return Set(list.split(separator: ",").map(String.init))
    }
}
