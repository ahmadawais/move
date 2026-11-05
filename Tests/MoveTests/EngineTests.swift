import CoreGraphics
import Testing
@testable import MoveKit

/// A MacBook display (Dock at the bottom) and an external display to its right, lower down.
let laptop = Display(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                     visible: CGRect(x: 0, y: 60, width: 1512, height: 889))
let external = Display(frame: CGRect(x: 1512, y: -235, width: 2560, height: 1440),
                       visible: CGRect(x: 1512, y: -235, width: 2560, height: 1415))
let portrait = Display(frame: CGRect(x: -1080, y: -500, width: 1080, height: 1920),
                       visible: CGRect(x: -1080, y: -500, width: 1080, height: 1895))
let L = laptop.visible   // 0, 60, 1512 × 889

func engine(_ window: CGRect = CGRect(x: 100, y: 200, width: 600, height: 400), displays: [Display] = [laptop],
            current: Int = 0, last: LastAction? = nil, _ change: (inout Config) -> Void = { _ in }) -> Engine {
    var c = Config()
    change(&c)
    return Engine(config: c, displays: displays, current: current, window: window, last: last)
}

func rect(_ a: Action, _ e: Engine = engine()) -> CGRect? { e.calculate(a)?.rect }

/// Presses `a` repeatedly the way the controller does: the outcome becomes the next press's last action.
func presses(_ a: Action, _ n: Int, displays: [Display] = [laptop], start: Int = 0,
             _ change: @escaping (inout Config) -> Void = { _ in }) -> [Outcome] {
    var outs: [Outcome] = []
    var last: LastAction?
    var current = start
    var window = CGRect(x: 100, y: 200, width: 600, height: 400)
    for _ in 0..<n {
        let o = engine(window, displays: displays, current: current, last: last, change).calculate(a)!
        let count = last?.action == o.action ? (last?.count ?? 0) + 1 : 1
        last = LastAction(action: o.action, sub: o.sub, rect: o.rect, count: count)
        window = o.rect; current = o.display
        outs.append(o)
    }
    return outs
}

@Suite struct Halves {
    @Test func leftRightTopBottom() {
        #expect(rect(.leftHalf) == CGRect(x: 0, y: 60, width: 756, height: 889))
        #expect(rect(.rightHalf) == CGRect(x: 756, y: 60, width: 756, height: 889))
        #expect(rect(.topHalf) == CGRect(x: 0, y: 505, width: 1512, height: 444))   // floor(444.5)
        #expect(rect(.bottomHalf) == CGRect(x: 0, y: 60, width: 1512, height: 444))
    }

    @Test func centerHalfOnLandscapeAndPortrait() {
        #expect(rect(.centerHalf) == CGRect(x: 378, y: 60, width: 756, height: 889))
        let p = rect(.centerHalf, engine(displays: [portrait]))!
        #expect(p == CGRect(x: -1080, y: -500 + 474, width: 1080, height: 948))
    }

    @Test("Ahmad's setting: repeating a half moves it to the next display")
    func repeatMovesToNextDisplay() {
        let outs = presses(.rightHalf, 3, displays: [laptop, external])
        #expect(outs[0].display == 0 && outs[0].action == .rightHalf)
        #expect(outs[1].display == 1 && outs[1].action == .leftHalf)
        #expect(outs[1].rect == CGRect(x: 1512, y: -235, width: 1280, height: 1415))
        // Right half again, now reported as left half → the next press is a fresh right half on display 1.
        #expect(outs[2].display == 1 && outs[2].action == .rightHalf)
    }

    @Test func leftHalfRepeatedGoesToPreviousDisplay() {
        let outs = presses(.leftHalf, 2, displays: [laptop, external], start: 1)
        #expect(outs[1].display == 0 && outs[1].action == .rightHalf)
        #expect(outs[1].rect == CGRect(x: 756, y: 60, width: 756, height: 889))
    }

    @Test func oneDisplayRepeatJustStays() {
        let outs = presses(.leftHalf, 3)
        #expect(outs.allSatisfy { $0.rect == CGRect(x: 0, y: 60, width: 756, height: 889) })
    }

    @Test func cycleSizesHalfTwoThirdsThird() {
        let w = presses(.leftHalf, 4) { $0.mode = .cycleSizes }.map(\.rect.width)
        #expect(w == [756, 1008, 504, 756])
    }

    @Test func nextDisplayThenSizesOnOneDisplayCycles() {
        let w = presses(.rightHalf, 3) { $0.mode = .nextDisplayThenSizes }.map(\.rect.width)
        #expect(w == [756, 1008, 504])
    }

    @Test func nextDisplayThenSizesResizesAtTheEnd() {
        // Right half on the last display: next would wrap to the first, so it cycles sizes instead.
        let outs = presses(.rightHalf, 2, displays: [laptop, external], start: 1) { $0.mode = .nextDisplayThenSizes }
        #expect(outs[1].display == 1)
        #expect(outs[1].rect.width == 1706)
    }

    @Test func switchSides() {
        let outs = presses(.leftHalf, 3) { $0.mode = .switchSides }
        #expect(outs.map(\.action) == [.leftHalf, .rightHalf, .leftHalf])
    }

    @Test func nothingMode() {
        let outs = presses(.leftHalf, 3) { $0.mode = .nothing }
        #expect(outs.allSatisfy { $0.rect == outs[0].rect })
    }

    @Test func topHalfRepeatedGoesToDisplayAbove() {
        let below = Display(frame: CGRect(x: 0, y: -982, width: 1512, height: 982),
                            visible: CGRect(x: 0, y: -982, width: 1512, height: 982))
        let outs = presses(.bottomHalf, 2, displays: [laptop, below])
        #expect(outs[1].display == 1 && outs[1].action == .topHalf)
    }

    @Test func topHalfCyclesSizes() {
        let h = presses(.topHalf, 3) { $0.mode = .cycleSizes }.map(\.rect.height)
        #expect(h == [444, 592, 296])
    }

    @Test func centerHalfCyclesWhenAsked() {
        let w = presses(.centerHalf, 3) { $0.centerHalfCycles = true }.map(\.rect.width)
        #expect(w == [756, 1008, 504])
        let fixed = presses(.centerHalf, 3).map(\.rect.width)
        #expect(fixed == [756, 756, 756])
    }
}

@Suite struct Corners {
    @Test func quarters() {
        #expect(rect(.topLeft) == CGRect(x: 0, y: 505, width: 756, height: 444))
        #expect(rect(.topRight) == CGRect(x: 756, y: 505, width: 756, height: 444))
        #expect(rect(.bottomLeft) == CGRect(x: 0, y: 60, width: 756, height: 444))
        #expect(rect(.bottomRight) == CGRect(x: 756, y: 60, width: 756, height: 444))
    }

    @Test func cycleWidths() {
        let w = presses(.topRight, 3) { $0.mode = .cycleSizes }.map(\.rect.width)
        #expect(w == [756, 1008, 504])
    }

    @Test func quadrantCycleGoesClockwise() {
        let outs = presses(.topLeft, 5) { $0.mode = .quadrantsAndSizes }
        #expect(outs.map(\.sub) == ["topLeft", "topRight", "bottomRight", "bottomLeft", "topLeft"])
    }
}

@Suite struct ThirdsAndFourths {
    @Test func thirds() {
        #expect(rect(.firstThird) == CGRect(x: 0, y: 60, width: 504, height: 889))
        #expect(rect(.centerThird) == CGRect(x: 504, y: 60, width: 504, height: 889))
        #expect(rect(.lastThird) == CGRect(x: 1008, y: 60, width: 504, height: 889))
        #expect(rect(.firstTwoThirds) == CGRect(x: 0, y: 60, width: 1008, height: 889))
        #expect(rect(.lastTwoThirds) == CGRect(x: 504, y: 60, width: 1008, height: 889))
        #expect(rect(.centerTwoThirds) == CGRect(x: 252, y: 60, width: 1008, height: 889))
    }

    @Test func thirdsTurnIntoRowsOnPortrait() {
        let p = engine(displays: [portrait])
        #expect(rect(.firstThird, p) == CGRect(x: -1080, y: -500 + 1895 - 631, width: 1080, height: 631))
        #expect(rect(.lastThird, p) == CGRect(x: -1080, y: -500, width: 1080, height: 631))
    }

    @Test func firstThirdCyclesForwardLastBackward() {
        #expect(presses(.firstThird, 4).map(\.rect.minX) == [0, 504, 1008, 0])
        #expect(presses(.lastThird, 4).map(\.rect.minX) == [1008, 504, 0, 1008])
    }

    @Test func twoThirdsAlternate() {
        #expect(presses(.firstTwoThirds, 3).map(\.rect.minX) == [0, 504, 0])
    }

    @Test func fourths() {
        #expect(rect(.firstFourth) == CGRect(x: 0, y: 60, width: 378, height: 889))
        #expect(rect(.secondFourth) == CGRect(x: 378, y: 60, width: 378, height: 889))
        #expect(rect(.thirdFourth) == CGRect(x: 756, y: 60, width: 378, height: 889))
        #expect(rect(.lastFourth) == CGRect(x: 1134, y: 60, width: 378, height: 889))
        #expect(rect(.firstThreeFourths) == CGRect(x: 0, y: 60, width: 1134, height: 889))
        #expect(rect(.lastThreeFourths) == CGRect(x: 378, y: 60, width: 1134, height: 889))
        #expect(rect(.centerThreeFourths) == CGRect(x: 189, y: 60, width: 1134, height: 889))
    }

    @Test("Ahmad's ⌃⌥⌘1 pressed again steps through the fourths")
    func firstFourthCycles() {
        #expect(presses(.firstFourth, 5).map(\.rect.minX) == [0, 378, 756, 1134, 0])
        #expect(presses(.lastFourth, 5).map(\.rect.minX) == [1134, 756, 378, 0, 1134])
    }

    @Test func secondFourthWidens() {
        let outs = presses(.secondFourth, 4)
        #expect(outs.map(\.rect.width) == [378, 1134, 756, 378])
        #expect(outs[2].rect.minX == 378)
    }

    @Test func noCyclingWhenModeIsNothing() {
        #expect(presses(.firstFourth, 3) { $0.mode = .nothing }.map(\.rect.minX) == [0, 0, 0])
    }
}

@Suite struct Grids {
    @Test func sixths() {
        #expect(rect(.topLeftSixth) == CGRect(x: 0, y: 505, width: 504, height: 444))
        #expect(rect(.topCenterSixth) == CGRect(x: 504, y: 505, width: 504, height: 444))
        #expect(rect(.bottomRightSixth) == CGRect(x: 1008, y: 60, width: 504, height: 444))
    }

    @Test func sixthsCycleInReadingOrder() {
        let outs = presses(.topLeftSixth, 7)
        #expect(outs.map(\.sub) == ["cell0", "cell1", "cell2", "cell3", "cell4", "cell5", "cell0"])
        let back = presses(.bottomRightSixth, 3)
        #expect(back.map(\.sub) == ["cell5", "cell4", "cell3"])
    }

    @Test func portraitSixthsAreTwoByThree() {
        let p = engine(displays: [portrait])
        let r = rect(.topCenterSixth, p)!   // reading order: second cell = top right on portrait
        #expect(r == CGRect(x: -540, y: -500 + 1895 - 631, width: 540, height: 631))
    }

    @Test func ninthsEighthsTwelfthsSixteenths() {
        #expect(rect(.middleCenterNinth) == CGRect(x: 504, y: 60 + 889 - 296 - 296, width: 504, height: 296))
        #expect(rect(.topCenterRightEighth) == CGRect(x: 756, y: 505, width: 378, height: 444))
        #expect(rect(.bottomRightTwelfth) == CGRect(x: 1134, y: 60, width: 378, height: 296))
        #expect(rect(.lowerMiddleCenterLeftSixteenth) == CGRect(x: 378, y: 949 - 444 - 222, width: 378, height: 222))
    }

    @Test func cornerThirds() {
        #expect(rect(.topLeftThird) == CGRect(x: 0, y: 505, width: 1008, height: 444))
        #expect(rect(.topRightThird) == CGRect(x: 504, y: 505, width: 1008, height: 444))
        #expect(rect(.bottomLeftThird) == CGRect(x: 0, y: 60, width: 1008, height: 444))
        #expect(presses(.topLeftThird, 5).map(\.sub) == ["cell0", "cell1", "cell2", "cell3", "cell0"])
    }

    @Test func verticalColumnsCycleOnlyAtTheEnds() {
        #expect(rect(.firstVerticalSixth) == CGRect(x: 0, y: 60, width: 252, height: 889))
        #expect(rect(.lastVerticalEighth) == CGRect(x: 1323, y: 60, width: 189, height: 889))
        #expect(presses(.firstVerticalSixth, 3).map(\.sub) == ["cell0", "cell1", "cell2"])
        #expect(presses(.lastVerticalSixth, 3).map(\.sub) == ["cell5", "cell4", "cell3"])
        #expect(presses(.thirdVerticalEighth, 3).map(\.sub) == ["cell2", "cell2", "cell2"])
    }

    @Test func verticalThirdsAreAlwaysRows() {
        #expect(rect(.topVerticalThird) == CGRect(x: 0, y: 60 + 889 - 296, width: 1512, height: 296))
        #expect(rect(.bottomVerticalTwoThirds) == CGRect(x: 0, y: 60, width: 1512, height: 592))
    }

    @Test("Every grid cell stays on the screen", arguments: Action.allCases.filter { Grid.of($0) != nil })
    func cellsInsideScreen(a: Action) {
        for d in [laptop, external, portrait] {
            let r = rect(a, engine(displays: [d]))!
            #expect(d.visible.contains(r), "\(a) \(r)")
            #expect(r.width > 0 && r.height > 0)
        }
    }
}

@Suite struct MaximizeAndCenter {
    @Test func maximize() { #expect(rect(.maximize) == L) }

    @Test func almostMaximize() {
        #expect(rect(.almostMaximize) == CGRect(x: 76, y: 105, width: 1361, height: 800))
    }

    @Test func maximizeHeightKeepsX() {
        #expect(rect(.maximizeHeight) == CGRect(x: 100, y: 60, width: 600, height: 889))
    }

    @Test func centerKeepsSize() {
        #expect(rect(.center) == CGRect(x: 456, y: 305, width: 600, height: 400))
    }

    @Test func centerTooBigBecomesMaximize() {
        let o = engine(CGRect(x: 0, y: 0, width: 3000, height: 2000)).calculate(.center)!
        #expect(o.rect == L && o.action == .maximize)
    }

    @Test func centerTooTallFillsHeight() {
        #expect(rect(.center, engine(CGRect(x: 0, y: 0, width: 600, height: 2000)))
                == CGRect(x: 456, y: 60, width: 600, height: 889))
    }

    @Test func centerProminentlySitsHigher() {
        let r = rect(.centerProminently)!
        #expect(r.minX == 456 && r.minY == CGFloat(427.25))
    }

    @Test func specifiedClampsToScreen() {
        #expect(rect(.specified) == CGRect(x: 0, y: -21, width: 1512, height: 1050))
        #expect(rect(.specified, engine { $0.specified = CGSize(width: 800, height: 600) })
                == CGRect(x: 356, y: 205, width: 800, height: 600))
    }

    @Test func repeatedMaximizeRestores() {
        let pre = CGRect(x: 10, y: 100, width: 300, height: 300)
        var e = engine(L, last: LastAction(action: .maximize, rect: L)) { $0.repeatedMaximizeRestores = true }
        e.preMaximize = pre
        let o = e.calculate(.maximize)!
        #expect(o.restored && o.rect == pre)
        e.config.repeatedMaximizeRestores = false
        #expect(e.calculate(.maximize)!.rect == L)
    }
}

@Suite struct SizeAndMove {
    @Test func largerAndSmallerGrowAroundTheCenter() {
        #expect(rect(.larger) == CGRect(x: 85, y: 185, width: 630, height: 430))
        #expect(rect(.smaller) == CGRect(x: 115, y: 215, width: 570, height: 370))
        #expect(rect(.largerWidth) == CGRect(x: 85, y: 200, width: 630, height: 400))
        #expect(rect(.smallerHeight) == CGRect(x: 100, y: 215, width: 600, height: 370))
    }

    @Test func largerStaysAgainstTheEdgeItTouches() {
        let left = CGRect(x: 0, y: 60, width: 756, height: 889)   // left half
        #expect(rect(.larger, engine(left)) == CGRect(x: 0, y: 60, width: 786, height: 889))
    }

    @Test func smallerMaximizedShrinksAroundCenter() {
        #expect(rect(.smaller, engine(L)) == CGRect(x: 15, y: 75, width: 1482, height: 859))
    }

    @Test func smallerStopsAtAQuarterOfTheScreen() {
        let tiny = CGRect(x: 100, y: 200, width: 390, height: 300)
        #expect(rect(.smaller, engine(tiny)) == tiny)
    }

    @Test func customStep() {
        #expect(rect(.larger, engine { $0.sizeStep = 100 })?.width == 700)
    }

    @Test func halveAndDouble() {
        let big = engine(CGRect(x: 100, y: 100, width: 1000, height: 800))
        #expect(rect(.halveWidthLeft, big) == CGRect(x: 100, y: 100, width: 500, height: 800))
        #expect(rect(.halveWidthRight, big) == CGRect(x: 600, y: 100, width: 500, height: 800))
        #expect(rect(.halveHeightUp, big) == CGRect(x: 100, y: 500, width: 1000, height: 400))
        #expect(rect(.halveHeightDown, big) == CGRect(x: 100, y: 100, width: 1000, height: 400))
        #expect(rect(.doubleWidthLeft) == CGRect(x: -500, y: 200, width: 1200, height: 400))
        #expect(rect(.doubleHeightDown) == CGRect(x: 100, y: -200, width: 600, height: 800))
        // Halving below a quarter of the screen does nothing (Rectangle's minimum).
        #expect(rect(.halveWidthLeft) == CGRect(x: 100, y: 200, width: 600, height: 400))
    }

    @Test func moveToEdgesKeepsSizeAndCenters() {
        #expect(rect(.moveLeft) == CGRect(x: 0, y: 305, width: 600, height: 400))
        #expect(rect(.moveRight) == CGRect(x: 912, y: 305, width: 600, height: 400))
        #expect(rect(.moveUp) == CGRect(x: 456, y: 549, width: 600, height: 400))
        #expect(rect(.moveDown) == CGRect(x: 456, y: 60, width: 600, height: 400))
        #expect(rect(.moveLeft, engine { $0.centeredDirectionalMove = false }) == CGRect(x: 0, y: 200, width: 600, height: 400))
    }

    @Test func moveRightRepeatedCrossesDisplays() {
        let outs = presses(.moveRight, 2, displays: [laptop, external])
        #expect(outs[1].display == 1 && outs[1].action == .moveLeft && outs[1].rect.minX == 1512)
    }
}

@Suite struct Displays {
    @Test func nextDisplayKeepsRelativePlace() {
        let o = engine(displays: [laptop, external]).calculate(.nextDisplay)!
        #expect(o.display == 1 && o.rect.size == CGSize(width: 600, height: 400))
        #expect(external.visible.contains(o.rect))
    }

    @Test func maximizedStaysMaximized() {
        let o = engine(L, displays: [laptop, external]).calculate(.nextDisplay)!
        #expect(o.rect == external.visible && o.action == .maximize)
    }

    @Test func singleDisplayHasNowhereToGo() {
        #expect(engine().calculate(.nextDisplay) == nil)
        #expect(engine().calculate(.displayTwo) == nil)
    }

    @Test func specificDisplay() {
        let o = engine(displays: [laptop, external, portrait]).calculate(.displayThree)!
        #expect(o.display == 2)
        #expect(engine(displays: [laptop, external]).calculate(.displayOne) == nil)  // already there
    }

    @Test func threeDisplaysWrap() {
        let e = engine(displays: [laptop, external, portrait], current: 2)
        #expect(e.calculate(.nextDisplay)?.display == 0)
        #expect(e.calculate(.previousDisplay)?.display == 1)
    }

    @Test func cycleDisplaysMode() {
        let outs = presses(.leftHalf, 3, displays: [laptop, external]) { $0.mode = .cycleDisplays }
        #expect(outs.map(\.display) == [0, 1, 0])
        #expect(outs.allSatisfy { $0.action == .leftHalf })
    }

    @Test func orderingTopToBottomThenLeftToRight() {
        let above = Display(frame: CGRect(x: 500, y: 982, width: 1920, height: 1080), visible: .zero)
        let o = Engine.ordered([external, laptop, above])
        #expect(o.map(\.frame) == [above.frame, laptop.frame, external.frame])
    }

    @Test func displayContainingMostOfTheWindow() {
        let w = CGRect(x: 1400, y: 100, width: 600, height: 400)   // mostly on the external display
        #expect(Engine.display(containing: w, in: [laptop, external]) == 1)
    }
}

@Suite struct Gaps {
    @Test func halvesShareHalfAGap() {
        let e = engine { $0.gap = 10 }
        #expect(rect(.leftHalf, e) == CGRect(x: 10, y: 70, width: 741, height: 869))
        #expect(rect(.rightHalf, e) == CGRect(x: 761, y: 70, width: 741, height: 869))
    }

    @Test func maximizeGetsFullGapUnlessOff() {
        #expect(rect(.maximize, engine { $0.gap = 10 }) == L.insetBy(dx: 10, dy: 10))
        #expect(rect(.maximize, engine { $0.gap = 10; $0.gapsOnMaximize = false }) == L)
    }

    @Test func centerThirdHasHalfGapsBothSides() {
        let r = rect(.centerThird, engine { $0.gap = 10 })!
        #expect(r.minX == 504 + 5 && r.width == 504 - 10)
    }

    @Test func noGapForCenterOrSize() {
        #expect(rect(.center, engine { $0.gap = 10 }) == rect(.center))
    }

    @Test func screenEdgeGaps() {
        let e = engine { $0.screenEdgeGaps = Insets(top: 20, bottom: 10, left: 5, right: 5) }
        #expect(rect(.maximize, e) == CGRect(x: 5, y: 70, width: 1502, height: 859))
    }
}

@Suite struct Actions {
    @Test("Every action has a URL name, a title and round-trips", arguments: Action.allCases)
    func names(a: Action) {
        #expect(Action(urlName: a.urlName) == a)
        #expect(!a.title.isEmpty)
    }

    @Test func rectangleURLNamesAllWork() {
        // From Rectangle's README "Execute an action by URL" (single-window actions).
        let names = "left-half right-half center-half top-half bottom-half top-left top-right bottom-left bottom-right first-third center-third last-third first-two-thirds last-two-thirds maximize almost-maximize maximize-height smaller larger center center-prominently restore next-display previous-display move-left move-right move-up move-down first-fourth second-fourth third-fourth last-fourth first-three-fourths last-three-fourths top-left-sixth top-center-sixth top-right-sixth bottom-left-sixth bottom-center-sixth bottom-right-sixth specified top-left-ninth top-center-ninth top-right-ninth middle-left-ninth middle-center-ninth middle-right-ninth bottom-left-ninth bottom-center-ninth bottom-right-ninth top-left-third top-right-third bottom-left-third bottom-right-third top-left-eighth top-center-left-eighth top-center-right-eighth top-right-eighth bottom-left-eighth bottom-center-left-eighth bottom-center-right-eighth bottom-right-eighth"
        for n in names.split(separator: " ") { #expect(Action(urlName: String(n)) != nil, "\(n)") }
    }

    @Test func titles() {
        #expect(Action.leftHalf.title == "Left Half")
        #expect(Action.topCenterLeftEighth.title == "Top Center Left Eighth")
        #expect(Action.displayThree.title == "Display 3")
    }

    @Test("Every action except restore computes on every display", arguments: Action.allCases)
    func computes(a: Action) {
        guard a != .restore else { return }
        let e = engine(displays: [laptop, external, portrait], current: 1)
        if let i = a.displayIndex, i == 1 || i >= 3 { #expect(e.calculate(a) == nil); return }
        #expect(e.calculate(a) != nil, "\(a)")
    }

    @Test func cycleOrder() {
        #expect(Geometry.sortedCycle([0.25, 0.5, 2.0 / 3, 0.75, 1.0 / 3]).map { ($0 * 100).rounded() } == [50, 67, 75, 25, 33])
    }
}
