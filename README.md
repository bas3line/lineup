# Lineup

A calm, scrolling window manager for macOS, written in Swift.

Lineup keeps your windows side by side in one tidy row. Open an app and its
window takes the spot right after the one you're using; everything else keeps
its size. When the row is wider than the screen, slide along it with a shortcut
or Control + Option + scroll. Nothing gets buried under anything else.

Free and open source under the MIT license. macOS 13 Ventura or later.

## Install

Build it with one command (you need Swift 6, from Xcode 16 or the Command Line
Tools):

```bash
git clone https://github.com/bas3line/lineup && cd lineup
./scripts/bundle.sh
mv dist/Lineup.app /Applications/
```

Prebuilt zips are attached to [Releases](https://github.com/bas3line/lineup/releases)
when one is published. They're signed ad hoc, not notarised, so the first time
macOS will say it can't check the app. Right-click `Lineup.app` and choose
**Open**, or run:

```bash
xattr -dr com.apple.quarantine /Applications/Lineup.app
```

On first launch macOS asks you to let Lineup control your computer (System
Settings → Privacy & Security → Accessibility). That's the only permission it
needs: it's how Lineup moves and resizes windows. Lineup starts tiling as soon
as you switch it on.

## Shortcuts

Every shortcut starts with **Control + Option** held together, a combination
almost no app uses.

| Shortcut | What it does |
| --- | --- |
| ⌃⌥ ← / → | Focus the window on the left / right |
| ⌃⌥⇧ ← / → | Move the window left / right in the row |
| ⌃⌥ R | Change width: ⅓ → ½ → ⅔ |
| ⌃⌥ − / = | Narrower / wider by a tenth of the screen |
| ⌃⌥ F | Fill the screen; press again to go back |
| ⌃⌥ C | Bring the window to the centre |
| ⌃⌥ S | Stack the window under the one on its left |
| ⌃⌥⇧ S | Take it back out of the stack |
| ⌃⌥ ↑ / ↓ | Focus the window above / below in a stack |
| ⌃⌥ D | Send the window to the next display |
| ⌃⌥ P | Pause or resume Lineup |
| ⌃⌥ + scroll | Slide the row (trackpad or mouse wheel) |

The menu bar icon lists them all too.

## How it behaves

- **New windows** land right after the focused window, at half the screen width.
- **Closing a window** closes the gap; focus goes back to the window on its left.
- **Clicking a window** that's partly off screen slides the row to show it.
- **Resizing by hand** works: drag a window's edge and Lineup keeps the new width,
  moving its neighbours to make room.
- **Dragging a window** away drops it back into the row when you let go. Drop it
  on another display and it joins that display's row.
- **Every display** gets a row of its own.
- **Windows out of view** wait in the bottom corner of the screen with one point
  showing, since macOS won't let a window leave the screen entirely.
- **Pausing or quitting** leaves windows where they are, and pulls any that were
  out of view back onto the screen. Nothing is closed.

From the menu bar icon you can pause, change the **spacing** between windows,
and **float** an app, so its windows are left alone (good for things like
calculators or video calls).

## Settings

Everything is in the menu, and stored in the `app.lineup` defaults domain:

| Key | Default | Meaning |
| --- | --- | --- |
| `gap` | `8` | Points of space around and between windows |
| `newWindowWidth` | `0.5` | Width of a new window, as a share of the screen |
| `floatingApps` | `[]` | Bundle IDs whose windows are never tiled |

```bash
defaults write app.lineup newWindowWidth -float 0.6667
```

## Known limits

- Only windows on the current Space are tiled.
- There's no four-finger swipe gesture; use Control + Option + scroll instead.
- Windows move instantly, without animation.
- Multiple displays are supported, but so far only tested on a single display.

## Build from source

You need Swift 6 (Xcode 16 or the Command Line Tools).

```bash
swift build                # debug build: .build/debug/Lineup
./scripts/bundle.sh        # release app: dist/Lineup.app and dist/Lineup.zip
```

Running `.build/debug/Lineup` straight from a terminal uses the terminal's
Accessibility permission, which is the quickest loop while developing. Set
`LINEUP_DEBUG=1` to log every decision to stderr.

## Tests

```bash
./scripts/test.sh          # unit tests for the layout engine
./scripts/e2e.sh           # end-to-end test with real windows
```

The layout engine (`Sources/LineupCore`) is pure Swift with no AppKit, so every
rule about where windows go is unit-tested.

The end-to-end test builds a tiny fixture app, starts Lineup tiling only that
app's windows, then presses the real shortcuts and checks the real window frames
through the Accessibility API. It needs your terminal to have Accessibility
access, takes about thirty seconds, and you should keep your hands off the
keyboard while it runs. Your other windows are never touched.

## How it's built

| Path | What's there |
| --- | --- |
| `Sources/LineupCore/Strip.swift` | The row: columns, focus, stacking, widths |
| `Sources/LineupCore/Layout.swift` | Turning the row into window frames, scrolling |
| `Sources/Lineup/WindowManager.swift` | Following real windows and applying frames |
| `Sources/Lineup/AXWindow.swift` | The Accessibility API wrapper |
| `Sources/Lineup/HotKeys.swift` | Global shortcuts through Carbon hot keys (no extra permission) |
| `Sources/Lineup/AppDelegate.swift` | Menu bar item and shortcut table |

Lineup is in the family of scrolling window managers like
[niri](https://github.com/YaLTeR/niri), [PaperWM](https://github.com/paperwm/PaperWM)
and [Paneru](https://github.com/karinushka/paneru).

## License

MIT. See [LICENSE](LICENSE).
