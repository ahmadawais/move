import CoreGraphics
import Testing
@testable import MoveKit

/// Ported 1:1 from Rectangle's DisplayTransferTests (same inputs and expected values).

struct DisplayTransferTests {
    /// A built-in display, and a larger external display placed to the right of it and lower down,
    /// so that a transfer that forgets to translate coordinates is caught.
    private let laptop = CGRect(x: 0, y: 0, width: 1512, height: 945)
    private let external = CGRect(x: 1512, y: -235, width: 2560, height: 1415)
    /// A portrait display to the left of the laptop, for moves that change orientation.
    private let portrait = CGRect(x: -1440, y: -800, width: 1440, height: 2560)

    /// The tolerance is passed in so that the tests don't depend on the user's gap size.
    private func transfer(_ window: CGRect, from source: CGRect, to destination: CGRect,
                          edgeTolerance: CGFloat = 4) -> CGRect {
        DisplayTransfer.transferredRect(window: window, source: source, destination: destination,
                                        edgeTolerance: edgeTolerance).rect
    }

    private func assertRect(_ rect: CGRect, _ expected: CGRect, accuracy: CGFloat = 0.001,
                            sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(abs(rect.minX - expected.minX) <= accuracy, "minX \(rect) vs \(expected)", sourceLocation: sourceLocation)
        #expect(abs(rect.minY - expected.minY) <= accuracy, "minY \(rect) vs \(expected)", sourceLocation: sourceLocation)
        #expect(abs(rect.width - expected.width) <= accuracy, "width \(rect) vs \(expected)", sourceLocation: sourceLocation)
        #expect(abs(rect.height - expected.height) <= accuracy, "height \(rect) vs \(expected)", sourceLocation: sourceLocation)
    }

    // MARK: - Against both edges: the window follows both, so it spans the destination

    @Test func testMaximizedWindowFillsTheLargerDestination() {
        assertRect(transfer(laptop, from: laptop, to: external), external)
    }

    @Test func testMaximizedWindowFillsTheSmallerDestination() {
        assertRect(transfer(external, from: external, to: laptop), laptop)
    }

    @Test func testTheDistanceFromTheEdgesIsCarriedOverSoGapsSurvive() {
        // What a maximize looks like with a 10pt gap: never flush, so the tolerance has to allow
        // for it, and the same gap has to come out the other side.
        let window = laptop.insetBy(dx: 10, dy: 10)
        assertRect(transfer(window, from: laptop, to: external, edgeTolerance: 14),
                   external.insetBy(dx: 10, dy: 10))
    }

    // MARK: - Against one edge: the window keeps its size and stays against that edge

    @Test func testLeftHalfKeepsItsWidthAndStaysOnTheLeft() {
        let window = CGRect(x: 0, y: 0, width: 756, height: 945)
        assertRect(transfer(window, from: laptop, to: external),
                   CGRect(x: 1512, y: -235, width: 756, height: 1415))
    }

    @Test func testRightHalfKeepsItsWidthAndStaysOnTheRight() {
        let window = CGRect(x: 756, y: 0, width: 756, height: 945)
        assertRect(transfer(window, from: laptop, to: external),
                   CGRect(x: 3316, y: -235, width: 756, height: 1415))
    }

    @Test func testRightHalfOfTheLargerDisplayStaysOnTheRightOfTheSmallerOne() {
        let window = CGRect(x: 2792, y: -235, width: 1280, height: 1415)
        assertRect(transfer(window, from: external, to: laptop),
                   CGRect(x: 232, y: 0, width: 1280, height: 945))
    }

    @Test func testQuarterArrivesInTheSameCorner() {
        let window = CGRect(x: 756, y: 472.5, width: 756, height: 472.5)
        assertRect(transfer(window, from: laptop, to: external),
                   CGRect(x: 3316, y: 707.5, width: 756, height: 472.5))
    }

    @Test func testWindowHangingOffTheEdgeIsBroughtBackOn() {
        let window = CGRect(x: -200, y: 0, width: 500, height: 400)
        assertRect(transfer(window, from: laptop, to: external),
                   CGRect(x: 1512, y: -235, width: 500, height: 400))
    }

    // MARK: - Against neither edge: the window keeps its size and its relative spot

    @Test func testCenteredWindowStaysCenteredAtTheSameSize() {
        let window = CGRect(x: 556, y: 300, width: 400, height: 345)
        assertRect(transfer(window, from: laptop, to: external),
                   CGRect(x: 2592, y: 300, width: 400, height: 345))
    }

    @Test func testWindowInTheRightThirdArrivesInTheRightThird() {
        let window = CGRect(x: 1000, y: 300, width: 400, height: 345)
        let transferred = transfer(window, from: laptop, to: external)
        #expect(abs(((transferred.midX - external.minX) / external.width) - ((window.midX - laptop.minX) / laptop.width)) <= 0.001)
        #expect(transferred.size == window.size)
    }

    @Test func testTheTwoAxesAreIndependent() {
        // Against the left edge, floating vertically.
        let window = CGRect(x: 0, y: 300, width: 400, height: 345)
        assertRect(transfer(window, from: laptop, to: external),
                   CGRect(x: 1512, y: 300, width: 400, height: 345))
    }

    @Test func testWindowTooLargeForTheDestinationIsCutDownToFit() {
        let window = CGRect(x: 1612, y: -135, width: 2360, height: 1215)
        assertRect(transfer(window, from: external, to: laptop), laptop)
    }

    // MARK: - Against three edges, changing orientation: centered along the middle edge

    @Test func testLeftHalfMovedToPortraitIsCenteredAlongTheLeftEdge() {
        let window = CGRect(x: 1512, y: -235, width: 1280, height: 1415)
        assertRect(transfer(window, from: external, to: portrait),
                   CGRect(x: -1440, y: -227.5, width: 1280, height: 1415))
    }

    @Test func testRightHalfMovedToPortraitIsCenteredAlongTheRightEdge() {
        let window = CGRect(x: 2792, y: -235, width: 1280, height: 1415)
        assertRect(transfer(window, from: external, to: portrait),
                   CGRect(x: -1280, y: -227.5, width: 1280, height: 1415))
    }

    @Test func testTopHalfMovedToLandscapeIsCenteredAlongTheTopEdge() {
        let window = CGRect(x: -1440, y: -800, width: 1440, height: 1280)
        assertRect(transfer(window, from: portrait, to: external),
                   CGRect(x: 2072, y: -235, width: 1440, height: 1280))
    }

    @Test func testBottomHalfMovedToLandscapeIsCenteredAlongTheBottomEdge() {
        let window = CGRect(x: -1440, y: 480, width: 1440, height: 1280)
        assertRect(transfer(window, from: portrait, to: external),
                   CGRect(x: 2072, y: -100, width: 1440, height: 1280))
    }

    @Test func testCenteringAlongTheMiddleEdgeKeepsTheGapAgainstIt() {
        let window = CGRect(x: 1522, y: -225, width: 1270, height: 1395)
        assertRect(transfer(window, from: external, to: portrait, edgeTolerance: 14),
                   CGRect(x: -1430, y: -217.5, width: 1270, height: 1395))
    }

    @Test func testThreeEdgeWindowTooLongToCenterStillSpans() {
        // A left half of the portrait display is taller than the whole laptop display.
        let window = CGRect(x: -1440, y: -800, width: 720, height: 2560)
        assertRect(transfer(window, from: portrait, to: laptop),
                   CGRect(x: 0, y: 0, width: 720, height: 945))
    }

    @Test func testMaximizedWindowStillFillsADisplayOfTheOtherOrientation() {
        assertRect(transfer(external, from: external, to: portrait), portrait)
        assertRect(transfer(portrait, from: portrait, to: laptop), laptop)
    }

    @Test func testWindowAgainstOnlyTwoOppositeEdgesStillSpansAcrossOrientations() {
        // Full height but floating horizontally: two edges, not three, so the usual rule applies.
        let window = CGRect(x: 2200, y: -235, width: 1000, height: 1415)
        assertRect(transfer(window, from: external, to: portrait),
                   CGRect(x: -1271.75, y: -800, width: 1000, height: 2560))
    }

    // MARK: - The #1723 geometries, which relativePositionedRect maps proportionally instead

    @Test func testIssue1723RightThirdStaysAgainstTheRightEdge() {
        // Full height, so it spans the destination vertically; against the right edge only, so it
        // keeps its 1000pt width. Proportionally it would be (1000, 0, 500, 1000).
        let window = CGRect(x: 2000, y: 0, width: 1000, height: 2000)
        assertRect(transfer(window, from: CGRect(x: 0, y: 0, width: 3000, height: 2000),
                            to: CGRect(x: 0, y: 0, width: 1500, height: 1000)),
                   CGRect(x: 500, y: 0, width: 1000, height: 1000))
    }

    @Test func testIssue1723CenteredQuarterKeepsItsSize() {
        // Proportionally it would be (480, 180, 320, 360).
        let window = CGRect(x: 960, y: 360, width: 640, height: 720)
        assertRect(transfer(window, from: CGRect(x: 0, y: 0, width: 2560, height: 1440),
                            to: CGRect(x: 0, y: 0, width: 1280, height: 720)),
                   CGRect(x: 320, y: 0, width: 640, height: 720))
    }

    @Test func testIssue1723OverflowIsCutDownToFit() {
        // Proportionally it would be (200, 0, 300, 500).
        let destination = CGRect(x: 0, y: 0, width: 500, height: 500)
        let window = CGRect(x: 500, y: 0, width: 600, height: 1000)
        assertRect(transfer(window, from: CGRect(x: 0, y: 0, width: 1000, height: 1000), to: destination),
                   destination)
    }

    // MARK: - Edge cases

    @Test func testMovingBetweenIdenticalDisplaysLeavesTheWindowAlone() {
        for window in [laptop,
                       CGRect(x: 0, y: 0, width: 756, height: 945),
                       CGRect(x: 556, y: 300, width: 400, height: 345),
                       CGRect(x: 1000, y: 300, width: 400, height: 345)] {
            assertRect(transfer(window, from: laptop, to: laptop), window)
        }
    }

    @Test func testEmptyFrameIsLeftAlone() {
        let window = CGRect(x: 556, y: 300, width: 400, height: 345)
        assertRect(transfer(window, from: .zero, to: external), window)
        assertRect(transfer(window, from: laptop, to: .zero), window)
    }

    @Test func testTheResultAlwaysFitsOnTheDestination() {
        let windows = [laptop,
                       laptop.insetBy(dx: 10, dy: 10),
                       CGRect(x: 0, y: 0, width: 756, height: 945),
                       CGRect(x: 756, y: 472.5, width: 756, height: 472.5),
                       CGRect(x: -200, y: -100, width: 500, height: 400),
                       CGRect(x: 1400, y: 800, width: 400, height: 345),
                       CGRect(x: 556, y: 300, width: 400, height: 345)]
        for window in windows {
            for (source, destination) in [(laptop, external), (external, laptop),
                                          (laptop, portrait), (portrait, laptop)] {
                let transferred = transfer(window, from: source, to: destination)
                #expect(destination.insetBy(dx: -0.001, dy: -0.001).contains(transferred), "\(transferred) does not fit on \(destination)")
            }
        }
    }
}
