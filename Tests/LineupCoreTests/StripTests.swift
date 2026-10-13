import CoreGraphics
import Testing
@testable import LineupCore

private func strip(_ ids: String..., width: CGFloat = 0.5) -> Strip<String> {
    var s = Strip<String>()
    for id in ids { s.insert(id, width: width) }
    return s
}

@Suite struct InsertAndRemove {
    @Test func newWindowLandsRightAfterTheFocusedOne() {
        var s = strip("a", "b", "c")
        s.focus("a")
        s.insert("d", width: 0.5)
        #expect(s.windows == ["a", "d", "b", "c"])
        #expect(s.focusedWindow == "d")
    }

    @Test func insertKeepsOtherWidths() {
        var s = strip("a")
        s.setWidth(of: "a", to: 2.0 / 3)
        s.insert("b", width: 0.5)
        #expect(s.columns[0].width == 2.0 / 3)
    }

    @Test func closingFocusedWindowFocusesItsLeftNeighbour() {
        var s = strip("a", "b", "c")
        s.focus("b")
        s.remove("b")
        #expect(s.focusedWindow == "a")
    }

    @Test func closingFirstWindowFocusesTheNextOne() {
        var s = strip("a", "b")
        s.focus("a")
        s.remove("a")
        #expect(s.focusedWindow == "b")
    }

    @Test func closingAWindowLeftOfFocusKeepsFocus() {
        var s = strip("a", "b", "c")
        s.remove("a")
        #expect(s.focusedWindow == "c")
    }

    @Test func removingTheLastWindowEmptiesTheStrip() {
        var s = strip("a")
        let removed = s.remove("a")
        #expect(removed)
        #expect(s.isEmpty)
        #expect(s.focusedWindow == nil)
        let removedAgain = s.remove("a")
        #expect(!removedAgain)
    }
}

@Suite struct FocusAndMove {
    @Test func focusStopsAtTheEnds() {
        var s = strip("a", "b")
        s.focusRight()
        #expect(s.focusedWindow == "b")
        s.focusLeft(); s.focusLeft()
        #expect(s.focusedWindow == "a")
    }

    @Test func moveSwapsWithTheNeighbourAndKeepsFocus() {
        var s = strip("a", "b", "c")
        s.moveLeft()
        #expect(s.windows == ["a", "c", "b"])
        #expect(s.focusedWindow == "c")
        s.moveRight(); s.moveRight()
        #expect(s.windows == ["a", "b", "c"])
    }
}

@Suite struct Widths {
    @Test func cycleStepsThroughPresetsAndWraps() {
        var s = strip("a")
        let presets: [CGFloat] = [1.0 / 3, 0.5, 2.0 / 3]
        s.cycleWidth(presets: presets)
        #expect(s.columns[0].width == 2.0 / 3)
        s.cycleWidth(presets: presets)
        #expect(s.columns[0].width == 1.0 / 3)
    }

    @Test func fillTogglesBackToThePreviousWidth() {
        var s = strip("a")
        s.toggleFill()
        #expect(s.columns[0].width == 1)
        s.toggleFill()
        #expect(s.columns[0].width == 0.5)
    }

    @Test func widthIsClamped() {
        var s = strip("a")
        s.resize(by: -5)
        #expect(s.columns[0].width == Strip<String>.minimumWidth)
        s.resize(by: 5)
        #expect(s.columns[0].width == 1)
    }

    @Test func pixelWidthRoundTrips() {
        let px = Strip<String>.pixelWidth(of: 0.4, viewportWidth: 1440, gap: 10)
        #expect(abs(Strip<String>.fraction(of: px, viewportWidth: 1440, gap: 10) - 0.4) < 1e-9)
    }
}

@Suite struct Stacking {
    @Test func stackJoinsTheLeftColumnAndUnstackSplitsItOut() {
        var s = strip("a", "b", "c")
        s.focus("b")
        s.stackLeft()
        #expect(s.columns.map(\.windows) == [["a", "b"], ["c"]])
        #expect(s.focusedWindow == "b")
        s.focusUp()
        #expect(s.focusedWindow == "a")
        s.focusDown()
        s.unstack()
        #expect(s.columns.map(\.windows) == [["a"], ["b"], ["c"]])
        #expect(s.focusedWindow == "b")
    }

    @Test func removingAStackedWindowKeepsTheColumn() {
        var s = strip("a", "b")
        s.stackLeft()
        s.remove("a")
        #expect(s.columns.map(\.windows) == [["b"]])
        #expect(s.focusedWindow == "b")
    }

    @Test func stackDoesNothingOnTheFirstColumn() {
        var s = strip("a", "b")
        s.focus("a")
        s.stackLeft()
        #expect(s.columns.count == 2)
    }
}

@Suite struct Frames {
    let viewport = CGRect(x: 0, y: 25, width: 1000, height: 775)
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func twoHalvesFillTheViewportWithEvenGaps() {
        var s = strip("a", "b")
        s.revealFocused(viewportWidth: viewport.width, gap: 10)
        let f = s.frames(viewport: viewport, screen: screen, gap: 10)
        #expect(f["a"] == CGRect(x: 10, y: 35, width: 485, height: 755))
        #expect(f["b"] == CGRect(x: 505, y: 35, width: 485, height: 755))
    }

    @Test func aLoneWindowStartsAtTheLeftEdge() {
        var s = strip("a")
        s.revealFocused(viewportWidth: viewport.width, gap: 10)
        #expect(s.frames(viewport: viewport, screen: screen, gap: 10)["a"]!.minX == 10)
    }

    @Test func focusingOffscreenColumnSlidesTheRowAndParksTheRest() {
        var s = strip("a", "b", "c")
        s.revealFocused(viewportWidth: viewport.width, gap: 10)
        let f = s.frames(viewport: viewport, screen: screen, gap: 10)
        #expect(f["c"]!.maxX == viewport.maxX - 10)
        #expect(f["b"]!.minX == viewport.minX + 10)
        // "a" is fully out of view on the left: parked in the bottom-left corner.
        #expect(f["a"] == CGRect(x: -484, y: 799, width: 485, height: 755))

        s.focusLeft(); s.focusLeft()
        s.revealFocused(viewportWidth: viewport.width, gap: 10)
        let g = s.frames(viewport: viewport, screen: screen, gap: 10)
        #expect(g["a"]!.minX == 10)
        #expect(g["c"]!.origin == CGPoint(x: 999, y: 799))
    }

    @Test func centreAndScrollStayWithinBounds() {
        var s = strip("a", "b", "c")
        s.focus("a")
        s.centerFocused(viewportWidth: viewport.width, gap: 10)
        let f = s.frames(viewport: viewport, screen: screen, gap: 10)
        #expect(abs(f["a"]!.midX - viewport.midX) < 0.001)

        s.scroll(by: -10_000, viewportWidth: viewport.width, gap: 10)
        #expect(s.scroll == s.scrollBounds(viewportWidth: viewport.width, gap: 10).lowerBound)
        s.scroll(by: 10_000, viewportWidth: viewport.width, gap: 10)
        let h = s.frames(viewport: viewport, screen: screen, gap: 10)
        #expect(abs(h["c"]!.midX - viewport.midX) < 0.001)
    }

    @Test func stackedWindowsSplitTheHeight() {
        var s = strip("a", "b")
        s.stackLeft()
        let f = s.frames(viewport: viewport, screen: screen, gap: 10)
        #expect(f["a"]!.minX == f["b"]!.minX)
        #expect(f["a"]!.height == f["b"]!.height)
        #expect(f["b"]!.minY == f["a"]!.maxY + 10)
        #expect(f["b"]!.maxY == viewport.maxY - 10)
    }

    @Test func viewportOffsetOnSecondDisplay() {
        let second = CGRect(x: 1000, y: 0, width: 800, height: 600)
        var s = strip("a")
        s.toggleFill()
        let f = s.frames(viewport: second, screen: second, gap: 0)
        #expect(f["a"] == second)
    }
}
