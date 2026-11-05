import CoreGraphics
import Foundation

/// What a repeated shortcut does (Rectangle's "subsequentExecutionMode", same raw values).
nonisolated public enum RepeatMode: Int, CaseIterable, Sendable {
    case cycleSizes = 0          // ½ → ⅔ → ⅓ on halves and corners (Spectacle)
    case nextDisplay = 1         // halves (and edges) move on to the adjacent display
    case nothing = 2
    case nextDisplayThenSizes = 3
    case cycleDisplays = 4       // any position action repeats on the next display
    case quadrantsAndSizes = 5   // corners step through the quadrants, halves cycle sizes
    case switchSides = 6         // left half ↔ right half

    public var title: String {
        switch self {
        case .cycleSizes: "Cycle sizes"
        case .nextDisplay: "Move to the next display"
        case .nothing: "Do nothing"
        case .nextDisplayThenSizes: "Next display, then cycle sizes"
        case .cycleDisplays: "Cycle through displays"
        case .quadrantsAndSizes: "Cycle quadrants and sizes"
        case .switchSides: "Switch sides"
        }
    }

    public static let ordered: [RepeatMode] = [.nextDisplay, .cycleSizes, .nextDisplayThenSizes, .cycleDisplays,
                                               .quadrantsAndSizes, .switchSides, .nothing]

    var resizes: Bool { [.cycleSizes, .nextDisplayThenSizes, .quadrantsAndSizes].contains(self) }
    var traversesDisplays: Bool { self == .nextDisplay || self == .nextDisplayThenSizes }
}

/// Every tunable the geometry reads. Plain values, so tests build one directly.
nonisolated public struct Config: Equatable, Sendable {
    public var mode: RepeatMode = .nextDisplay
    public var gap: CGFloat = 0
    public var screenEdgeGaps = Insets()
    public var almostMaximize = CGSize(width: 0.9, height: 0.9)
    public var sizeStep: CGFloat = 30
    public var widthStep: CGFloat = 30
    /// Fractions repeated halves/corners cycle through, first is ½.
    public var cycleSizes: [CGFloat] = [1.0 / 2, 2.0 / 3, 1.0 / 3]
    public var centerHalfCycles = false
    public var centeredDirectionalMove = true
    public var repeatedMaximizeRestores = false
    public var gapsOnMaximize = true
    public var specified = CGSize(width: 1680, height: 1050)
    public var curtainChangeSize = true
    public var minimumFraction: CGFloat = 0.25
    public init() {}
}

nonisolated public struct Insets: Equatable, Sendable {
    public var top: CGFloat = 0, bottom: CGFloat = 0, left: CGFloat = 0, right: CGFloat = 0
    public init(top: CGFloat = 0, bottom: CGFloat = 0, left: CGFloat = 0, right: CGFloat = 0) {
        self.top = top; self.bottom = bottom; self.left = left; self.right = right
    }
}

/// A display in Cocoa coordinates (origin bottom-left of the primary display, y up).
nonisolated public struct Display: Equatable, Sendable {
    public var frame: CGRect
    public var visible: CGRect
    public init(frame: CGRect, visible: CGRect) { self.frame = frame; self.visible = visible }
}

/// The last action Move applied to a window. Only passed in while the window still sits where Move left it.
nonisolated public struct LastAction: Equatable, Sendable {
    public var action: Action
    public var sub: String?
    public var rect: CGRect
    public var count: Int
    public init(action: Action, sub: String? = nil, rect: CGRect, count: Int = 1) {
        self.action = action; self.sub = sub; self.rect = rect; self.count = count
    }
}

nonisolated public struct Outcome: Equatable, Sendable {
    public var rect: CGRect
    public var display: Int
    public var action: Action
    public var sub: String?
    /// True when a repeated maximize put the window back where it was.
    public var restored = false
}

/// Pure window geometry: no AppKit, no Accessibility, fully unit-tested.
nonisolated public struct Engine {
    public var config: Config
    public var displays: [Display]          // ordered for next/previous
    public var current: Int
    public var window: CGRect               // Cocoa coordinates
    public var last: LastAction?
    public var preMaximize: CGRect?

    public init(config: Config, displays: [Display], current: Int, window: CGRect,
                last: LastAction? = nil, preMaximize: CGRect? = nil) {
        self.config = config; self.displays = displays; self.current = current
        self.window = window; self.last = last; self.preMaximize = preMaximize
    }

    // MARK: Display helpers

    /// Visible frame minus the user's screen-edge gaps.
    public func area(_ i: Int) -> CGRect {
        let v = displays[i].visible
        let g = config.screenEdgeGaps
        return CGRect(x: v.minX + g.left, y: v.minY + g.bottom,
                      width: v.width - g.left - g.right, height: v.height - g.top - g.bottom)
    }

    var adjacent: (prev: Int, next: Int)? {
        let n = displays.count
        guard n > 1 else { return nil }
        return ((current - 1 + n) % n, (current + 1) % n)
    }

    /// Display whose frame holds most of `rect` (Cocoa coordinates).
    public static func display(containing rect: CGRect, in displays: [Display]) -> Int {
        var best = 0, bestArea: CGFloat = -1
        for (i, d) in displays.enumerated() {
            if d.frame.contains(rect) { return i }
            let r = d.frame.intersection(rect)
            let a = r.isNull ? 0 : r.width * r.height
            if a > bestArea { bestArea = a; best = i }
        }
        return best
    }

    /// Top-to-bottom, then left-to-right (Rectangle's default ordering).
    public static func ordered(_ displays: [Display]) -> [Display] {
        displays.sorted { a, b in
            if b.frame.maxY <= a.frame.minY { return true }
            if a.frame.maxY <= b.frame.minY { return false }
            return a.frame.minX < b.frame.minX
        }
    }

    /// Nearest display above/below that overlaps horizontally; wraps to the far end when asked.
    func verticalNeighbor(above: Bool, wrap: Bool) -> Int? {
        let src = displays[current].frame
        typealias C = (i: Int, distance: CGFloat, overlap: CGFloat, opposite: Bool)
        let cands: [C] = displays.indices.compactMap { i in
            guard i != current else { return nil }
            let f = displays[i].frame
            let overlap = min(src.maxX, f.maxX) - max(src.minX, f.minX)
            guard overlap > 0 else { return nil }
            return (i, above ? f.minY - src.maxY : src.minY - f.maxY, overlap,
                    above ? f.maxY <= src.minY : f.minY >= src.maxY)
        }
        let closer: (C, C) -> Bool = { ($0.distance, $1.overlap) < ($1.distance, $0.overlap) }
        return cands.filter { $0.distance >= 0 }.min(by: closer)?.i
            ?? (wrap ? cands.filter { $0.opposite }.min(by: closer)?.i : nil)
    }

    var repeated: Bool { last != nil }
    func repeated(_ a: Action) -> Bool { last?.action == a }

    // MARK: Entry point

    public func calculate(_ action: Action) -> Outcome? {
        var engine = self
        // "Cycle through displays": a repeated position action runs again, fresh, on the next display.
        if config.mode == .cycleDisplays, repeated(action), action.group != .size, action.group != .displays,
           !(config.repeatedMaximizeRestores && (action == .maximize || action == .almostMaximize)),
           let next = adjacent?.next {
            engine.current = next
            engine.last = nil
        }
        guard var out = engine.raw(action) else { return nil }
        if !out.restored { out.rect = engine.applyGaps(out) }
        return out
    }

    func applyGaps(_ out: Outcome) -> CGRect {
        let g = config.gap
        var (h, v) = out.action.gaps
        if out.action == .maximize || out.action == .maximizeHeight, !config.gapsOnMaximize { h = false; v = false }
        guard g > 0, h || v else { return out.rect }
        let screen = area(out.display)
        var r = out.rect.insetBy(dx: h ? g : 0, dy: v ? g : 0)
        let half = g / 2
        // An edge inside the screen is shared with a neighbouring window: it gets half a gap.
        func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) <= 1 }
        if h {
            if !near(out.rect.minX, screen.minX) { r.origin.x -= half; r.size.width += half }
            if !near(out.rect.maxX, screen.maxX) { r.size.width += half }
        }
        if v {
            if !near(out.rect.minY, screen.minY) { r.origin.y -= half; r.size.height += half }
            if !near(out.rect.maxY, screen.maxY) { r.size.height += half }
        }
        return r
    }

    func out(_ rect: CGRect, _ action: Action, sub: String? = nil, display: Int? = nil) -> Outcome {
        Outcome(rect: rect, display: display ?? current, action: action, sub: sub)
    }

    // MARK: Calculations

    func raw(_ a: Action) -> Outcome? {
        let f = area(current)
        switch a {
        case .leftHalf, .rightHalf: return sideHalf(a)
        case .topHalf, .bottomHalf: return verticalHalf(a)
        case .centerHalf:
            let cycles = (repeated && config.mode.resizes) || config.centerHalfCycles
            let frac = cycles && repeated(a) ? cycleFraction() : 0.5
            return out(Geometry.centered(f, fraction: frac), a, sub: "centerHalf")
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return corner(a)
        case .firstThird, .centerThird, .lastThird: return line(a, family: [.firstThird, .centerThird, .lastThird])
        case .firstFourth, .secondFourth, .thirdFourth, .lastFourth:
            return line(a, family: [.firstFourth, .secondFourth, .thirdFourth, .lastFourth])
        case .firstTwoThirds, .lastTwoThirds:
            let first = a == .firstTwoThirds
            let flip = config.mode != .nothing && last?.sub == (first ? "firstTwoThirds" : "lastTwoThirds")
            let side = first != flip
            return out(Geometry.segment(f, n: 3, index: side ? 0 : 1, span: 2), a,
                       sub: side ? "firstTwoThirds" : "lastTwoThirds")
        case .centerTwoThirds: return out(Geometry.centered(f, fraction: 2.0 / 3, floorInset: 3), a, sub: "centerTwoThirds")
        case .firstThreeFourths, .lastThreeFourths:
            let first = a == .firstThreeFourths
            let flip = config.mode != .nothing && last?.sub == (first ? "firstThreeFourths" : "lastThreeFourths")
            let side = first != flip
            return out(Geometry.segment(f, n: 4, index: side ? 0 : 1, span: 3), a,
                       sub: side ? "firstThreeFourths" : "lastThreeFourths")
        case .centerThreeFourths:
            return out(Geometry.centered(f, fraction: 3.0 / 4, floorInset: 4), a, sub: "centerThreeFourths")
        case .maximize:
            if let r = maximizeRestore(a) { return r }
            return out(f, a)
        case .almostMaximize:
            if let r = maximizeRestore(a) { return r }
            var r = f
            r.size.width = (f.width * config.almostMaximize.width).rounded()
            r.size.height = (f.height * config.almostMaximize.height).rounded()
            r.origin.x = ((f.width - r.width) / 2).rounded() + f.minX
            r.origin.y = ((f.height - r.height) / 2).rounded() + f.minY
            return out(r, a)
        case .maximizeHeight:
            var r = window
            r.origin.y = f.minY; r.size.height = f.height
            return out(r, a)
        case .center: return center(in: f, action: a)
        case .centerProminently:
            let c = center(in: f, action: a)
            var r = c.rect
            r.origin.y += -0.25 * r.height + 0.25 * f.height
            return out(r, c.action)
        case .specified:
            var r = f
            let s = config.specified
            r.size.height = s.height <= 1 ? f.height * s.height : s.height.rounded()
            r.size.width = s.width <= 1 ? f.width * s.width : min(f.width, s.width.rounded())
            r.origin.x = ((f.width - r.width) / 2).rounded() + f.minX
            r.origin.y = ((f.height - r.height) / 2).rounded() + f.minY
            return out(r, a)
        case .restore: return nil // handled by the controller, it owns the history
        case .larger, .smaller, .largerWidth, .smallerWidth, .largerHeight, .smallerHeight: return changeSize(a)
        case .halveHeightUp, .halveHeightDown, .halveWidthLeft, .halveWidthRight,
             .doubleHeightUp, .doubleHeightDown, .doubleWidthLeft, .doubleWidthRight: return halveOrDouble(a)
        case .moveLeft, .moveRight: return moveSideways(a)
        case .moveUp, .moveDown:
            var r = window
            r.origin.y = a == .moveUp ? f.maxY - r.height : f.minY
            if config.centeredDirectionalMove { r.origin.x = ((f.width - r.width) / 2).rounded() + f.minX }
            if window.width >= f.width { r.size.width = f.width; r.origin.x = f.minX }
            return out(r, a)
        case .nextDisplay, .previousDisplay:
            guard let adj = adjacent else { return nil }
            return toDisplay(a == .nextDisplay ? adj.next : adj.prev, action: a)
        case .displayOne, .displayTwo, .displayThree, .displayFour, .displayFive, .displaySix, .displaySeven,
             .displayEight, .displayNine:
            guard let i = a.displayIndex, i < displays.count, i != current else { return nil }
            return toDisplay(i, action: a)
        case .topVerticalThird, .middleVerticalThird, .bottomVerticalThird:
            let i = [Action.topVerticalThird, .middleVerticalThird, .bottomVerticalThird].firstIndex(of: a)!
            return out(Geometry.cell(f, cols: 1, rows: 3, c: 0, r: i), a, sub: "cell\(i)")
        case .topVerticalTwoThirds, .bottomVerticalTwoThirds:
            return out(Geometry.cell(f, cols: 1, rows: 3, c: 0, r: a == .topVerticalTwoThirds ? 0 : 1, sr: 2), a)
        default:
            if let grid = Grid.of(a) { return gridCell(a, grid) }
            return nil
        }
    }

    // Halves

    func sideHalf(_ a: Action) -> Outcome {
        let f = area(current)
        switch config.mode {
        case .nextDisplay: return acrossDisplays(a)
        case .nextDisplayThenSizes: return displays.count == 1 ? resizedSide(a) : acrossDisplays(a)
        case .cycleSizes, .quadrantsAndSizes: return resizedSide(a)
        case .switchSides where repeated(a):
            let o: Action = a == .rightHalf ? .leftHalf : .rightHalf
            return out(Geometry.half(f, side: o), o)
        default: return out(Geometry.half(f, side: a), a)
        }
    }

    func resizedSide(_ a: Action) -> Outcome {
        let f = area(current)
        guard repeated(a) else { return out(Geometry.half(f, side: a), a) }
        return out(Geometry.half(f, side: a, fraction: cycleFraction()), a)
    }

    /// Repeating Left Half on a window already there sends it to the right half of the previous display.
    func acrossDisplays(_ a: Action) -> Outcome {
        if repeated(a), let adj = adjacent {
            let target = a == .leftHalf ? adj.prev : adj.next
            if config.mode == .nextDisplayThenSizes,
               target == (a == .leftHalf ? displays.count - 1 : 0) {
                return resizedSide(a)
            }
            let o: Action = a == .leftHalf ? .rightHalf : .leftHalf
            return out(Geometry.half(area(target), side: o), o, display: target)
        }
        return out(Geometry.half(area(current), side: a), a)
    }

    func verticalHalf(_ a: Action) -> Outcome {
        let f = area(current)
        let facing: Action = a == .topHalf ? .bottomHalf : .topHalf
        if config.mode.traversesDisplays, repeated(a),
           let n = verticalNeighbor(above: a == .topHalf, wrap: !config.mode.resizes) {
            return out(Geometry.verticalHalf(area(n), top: facing == .topHalf), facing, display: n)
        }
        if config.mode == .switchSides {
            return repeated(a) ? out(Geometry.verticalHalf(f, top: facing == .topHalf), facing)
                : out(Geometry.verticalHalf(f, top: a == .topHalf), a)
        }
        if config.mode.resizes, repeated(a) {
            return out(Geometry.verticalHalf(f, top: a == .topHalf, fraction: cycleFraction()), a)
        }
        return out(Geometry.verticalHalf(f, top: a == .topHalf), a)
    }

    /// Index into the cycle sizes for the current repeat count: ½ (1st press) → ⅔ → ⅓ → ½ …
    func cycleFraction() -> CGFloat {
        let sizes = Geometry.sortedCycle(config.cycleSizes)
        guard !sizes.isEmpty, let count = last?.count else { return 0.5 }
        let i = sizes.contains(where: { abs($0 - 0.5) < 0.001 }) ? count % sizes.count : max(0, count - 1) % sizes.count
        return sizes[i]
    }

    // Corners

    static let quadrants: [Action] = [.topLeft, .topRight, .bottomRight, .bottomLeft]

    func corner(_ a: Action) -> Outcome {
        let f = area(current)
        if config.mode == .quadrantsAndSizes {
            if let l = last, let sub = l.sub, let i = Engine.quadrants.firstIndex(where: { $0.rawValue == sub }),
               l.action == a {
                let next = Engine.quadrants[(i + 1) % 4]
                return out(Geometry.corner(f, next), a, sub: next.rawValue)
            }
            return out(Geometry.corner(f, a), a, sub: a.rawValue)
        }
        if config.mode.resizes, repeated(a) {
            return out(Geometry.corner(f, a, widthFraction: cycleFraction()), a)
        }
        return out(Geometry.corner(f, a), a)
    }

    // Thirds & fourths: First cycles forward, Last backward; the rest stay put (or step to wider spans).

    func line(_ a: Action, family: [Action]) -> Outcome {
        let f = area(current)
        let n = family.count
        let index = family.firstIndex(of: a)!
        let cycles = config.mode != .nothing
        var target = index
        if cycles, let l = last, let sub = l.sub, let at = Int(sub.dropFirst(4)), sub.hasPrefix("cell") {
            if a == family.first {
                if l.action == a { target = (at + 1) % n } else if l.action == family.last, at == 0 { target = 1 }
            } else if a == family.last {
                if l.action == a { target = (at - 1 + n) % n } else if l.action == family.first, at == n - 1 { target = n - 2 }
            }
        }
        // Second / third fourth: repeat widens to three fourths, then the center half.
        if n == 4, cycles, index == 1 || index == 2, let l = last, l.action == a, let sub = l.sub {
            let three: Action = index == 1 ? .lastThreeFourths : .firstThreeFourths
            if sub == "cell\(index)" {
                return out(Geometry.segment(f, n: 4, index: index == 1 ? 1 : 0, span: 3), a, sub: three.rawValue)
            }
            if sub == three.rawValue { return out(Geometry.centered(f, fraction: 0.5), a, sub: "centerHalf") }
        }
        return out(Geometry.segment(f, n: n, index: target), a, sub: "cell\(target)")
    }

    // Grids (sixths, ninths, eighths, twelfths, sixteenths, corner thirds, columns)

    func gridCell(_ a: Action, _ g: Grid) -> Outcome {
        let f = area(current)
        var index = g.index
        if config.mode != .nothing, let l = last, l.action == a, let sub = l.sub, sub.hasPrefix("cell"),
           let at = Int(sub.dropFirst(4)) {
            let n = g.count
            switch g.cycle {
            case .all: index = (at + 1) % n
            case .allBackFromLast: index = g.index == n - 1 ? (at - 1 + n) % n : (at + 1) % n
            case .ends:
                if g.index == 0 { index = (at + 1) % n } else if g.index == n - 1 { index = (at - 1 + n) % n }
            }
        }
        return out(g.rect(in: f, index: index), a, sub: "cell\(index)")
    }

    // Maximize / center

    func maximizeRestore(_ a: Action) -> Outcome? {
        guard config.repeatedMaximizeRestores, repeated(a), let pre = preMaximize else { return nil }
        var o = out(pre, .restore)
        o.restored = true
        return o
    }

    func center(in f: CGRect, action a: Action) -> Outcome {
        var r = window
        let tall = window.height > f.height, wide = window.width > f.width
        if tall && wide { return out(f, .maximize) }
        if tall { r.size.height = f.height; r.origin.y = f.minY } else { r.origin.y = ((f.height - window.height) / 2).rounded() + f.minY }
        if wide { r.size.width = f.width; r.origin.x = f.minX } else { r.origin.x = ((f.width - window.width) / 2).rounded() + f.minX }
        return out(r, a)
    }

    // Size

    func changeSize(_ a: Action) -> Outcome {
        let f = area(current)
        let step: CGFloat
        switch a {
        case .larger, .largerHeight: step = config.sizeStep
        case .smaller, .smallerHeight: step = -config.sizeStep
        case .largerWidth: step = config.widthStep
        default: step = -config.widthStep
        }
        let edge = config.gap <= 0 ? 5 : config.gap
        func against(_ d: CGFloat) -> Bool { abs(d) <= edge }
        let w = window
        let l = against(w.minX - f.minX), r = against(w.maxX - f.maxX)
        let t = against(w.maxY - f.maxY), b = against(w.minY - f.minY)
        var out = w
        if [.larger, .smaller, .largerWidth, .smallerWidth].contains(a) {
            out.size.width += step
            out.origin.x -= (step / 2).rounded(.down)
            if config.curtainChangeSize {
                if r {
                    out.origin.x = f.maxX - out.width - config.gap
                    if l { out.size.width = f.width - config.gap * 2 }
                }
                if l { out.origin.x = f.minX + config.gap }
            }
            if out.width >= f.width { out.size.width = f.width }
        }
        if [.larger, .smaller, .largerHeight, .smallerHeight].contains(a) {
            out.size.height += step
            out.origin.y -= (step / 2).rounded(.down)
            if config.curtainChangeSize, a != .smallerHeight {
                if t {
                    out.origin.y = f.maxY - out.height - config.gap
                    if b { out.size.height = f.height - config.gap * 2 }
                }
                if b { out.origin.y = f.minY + config.gap }
            }
            if out.height >= f.height { out.size.height = f.height; out.origin.y = w.minY }
        }
        // A maximized window shrinks around its center instead of sticking to every edge.
        if l && r && t && b && step < 0 {
            if [.smaller, .smallerWidth].contains(a) {
                out.size.width = w.width + step; out.origin.x = w.minX - (step / 2).rounded(.down)
            }
            if [.smaller, .smallerHeight].contains(a) {
                out.size.height = w.height + step; out.origin.y = w.minY - (step / 2).rounded(.down)
            }
        }
        if step < 0, tooSmall(out, f) { out = w }
        return self.out(out, a)
    }

    func tooSmall(_ r: CGRect, _ f: CGRect) -> Bool {
        r.width <= f.width * config.minimumFraction || r.height <= f.height * config.minimumFraction
    }

    func halveOrDouble(_ a: Action) -> Outcome {
        let w = window
        var r = w
        switch a {
        case .halveHeightUp, .halveHeightDown: r.size.height *= 0.5
        case .halveWidthLeft, .halveWidthRight: r.size.width *= 0.5
        case .doubleHeightUp, .doubleHeightDown: r.size.height *= 2
        default: r.size.width *= 2
        }
        switch a {
        case .halveHeightUp: r = r.offsetBy(dx: 0, dy: r.height)
        case .halveWidthRight: r = r.offsetBy(dx: r.width, dy: 0)
        case .doubleHeightDown: r = r.offsetBy(dx: 0, dy: -w.height)
        case .doubleWidthLeft: r = r.offsetBy(dx: -w.width, dy: 0)
        default: break
        }
        let shrinking = [.halveHeightUp, .halveHeightDown, .halveWidthLeft, .halveWidthRight].contains(a)
        if shrinking, tooSmall(r, area(current)) { r = w }
        return out(r, a)
    }

    func moveSideways(_ a: Action) -> Outcome {
        var target = current
        var action = a
        if config.mode.traversesDisplays, displays.count > 1, repeated(a), let adj = adjacent {
            target = a == .moveLeft ? adj.prev : adj.next
            action = a == .moveLeft ? .moveRight : .moveLeft
        }
        let f = area(target)
        var r = window
        r.origin.x = action == .moveRight ? f.maxX - r.width : f.minX
        if config.centeredDirectionalMove { r.origin.y = ((f.height - r.height) / 2).rounded() + f.minY }
        if window.height >= f.height { r.size.height = f.height; r.origin.y = f.minY }
        return out(r, action, display: target)
    }

    // Displays

    func toDisplay(_ i: Int, action: Action) -> Outcome {
        let src = area(current), dst = area(i)
        let t = DisplayTransfer.transferredRect(window: window, source: src, destination: dst,
                                                edgeTolerance: 4 + config.gap)
        if t.sharedEdges == .all { return out(dst, .maximize, display: i) }
        return out(t.rect, action, display: i)
    }
}

// MARK: - Shapes

nonisolated enum Geometry {
    /// Rectangle's rounding: floor with a hair of tolerance.
    static func fl(_ v: CGFloat) -> CGFloat { (v + 0.0001).rounded(.down) }

    static func half(_ f: CGRect, side: Action, fraction: CGFloat = 0.5) -> CGRect {
        var r = f
        r.size.width = fl(f.width * fraction)
        if side == .rightHalf { r.origin.x = f.maxX - r.width }
        return r
    }

    static func verticalHalf(_ f: CGRect, top: Bool, fraction: CGFloat = 0.5) -> CGRect {
        var r = f
        r.size.height = fl(f.height * fraction)
        if top { r.origin.y = f.maxY - r.height }
        return r
    }

    static func corner(_ f: CGRect, _ a: Action, widthFraction: CGFloat = 0.5) -> CGRect {
        var r = f
        r.size.width = fl(f.width * widthFraction)
        r.size.height = fl(f.height * 0.5)
        if a == .topRight || a == .bottomRight { r.origin.x = f.maxX - r.width }
        if a == .topLeft || a == .topRight { r.origin.y = f.maxY - r.height }
        return r
    }

    /// Centered band across the long axis: columns on landscape, rows on portrait.
    static func centered(_ f: CGRect, fraction: CGFloat, floorInset: CGFloat? = nil) -> CGRect {
        var r = f
        if f.width > f.height {
            r.size.width = floorInset == nil ? (f.width * fraction).rounded() : f.width * fraction
            r.origin.x = floorInset.map { f.minX + fl(f.width / $0) / 2 } ?? (((f.width - r.width) / 2).rounded() + f.minX)
        } else {
            r.size.height = floorInset == nil ? (f.height * fraction).rounded() : f.height * fraction
            r.origin.y = floorInset.map { f.minY + fl(f.height / $0) / 2 } ?? (((f.height - r.height) / 2).rounded() + f.minY)
        }
        return r
    }

    /// `index`-th of `n` slices along the long axis (left→right on landscape, top→bottom on portrait).
    static func segment(_ f: CGRect, n: Int, index: Int, span: Int = 1) -> CGRect {
        f.width > f.height ? cell(f, cols: n, rows: 1, c: index, r: 0, sc: span)
            : cell(f, cols: 1, rows: n, c: 0, r: index, sr: span)
    }

    /// Cell (c, r) of a cols × rows grid; rows counted from the top. Edge cells sit flush with the screen edge.
    static func cell(_ f: CGRect, cols: Int, rows: Int, c: Int, r: Int, sc: Int = 1, sr: Int = 1) -> CGRect {
        let w = fl(f.width * CGFloat(sc) / CGFloat(cols))
        let h = fl(f.height * CGFloat(sr) / CGFloat(rows))
        let x = c == 0 ? f.minX : (c + sc == cols ? f.maxX - w : f.minX + fl(f.width / CGFloat(cols)) * CGFloat(c))
        let y = r == 0 ? f.maxY - h : (r + sr == rows ? f.minY : f.maxY - fl(f.height / CGFloat(rows)) * CGFloat(r) - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// ½ first, then larger sizes ascending, then smaller ones: ½ → ⅔ → ¾ → ¼ → ⅓.
    static func sortedCycle(_ sizes: [CGFloat]) -> [CGFloat] {
        var s: [CGFloat] = []
        for v in sizes.sorted() where !s.contains(where: { abs($0 - v) < 0.001 }) { s.append(v) }
        func isHalf(_ v: CGFloat) -> Bool { abs(v - 0.5) < 0.001 }
        return s.filter(isHalf) + s.filter { $0 > 0.5 && !isHalf($0) } + s.filter { $0 < 0.5 && !isHalf($0) }
    }
}

/// A cell in a grid family, in reading order; portrait displays transpose the grid (keeping reading order).
nonisolated struct Grid {
    enum Cycle { case all, allBackFromLast, ends }
    var cols: Int, rows: Int, index: Int, count: Int
    var spanC = 1, spanR = 1
    var cycle: Cycle
    var custom: ((CGRect, Int) -> CGRect)?

    func rect(in f: CGRect, index i: Int) -> CGRect {
        if let custom { return custom(f, i) }
        let portrait = f.height > f.width
        let (cc, rr) = portrait && cols != rows ? (rows, cols) : (cols, rows)
        let (sc, sr) = portrait && cols != rows ? (spanR, spanC) : (spanC, spanR)
        return Geometry.cell(f, cols: cc, rows: rr, c: i % cc, r: i / cc, sc: sc, sr: sr)
    }

    static func of(_ a: Action) -> Grid? {
        func find(_ family: [Action], cols: Int, rows: Int, cycle: Cycle) -> Grid? {
            guard let i = family.firstIndex(of: a) else { return nil }
            return Grid(cols: cols, rows: rows, index: i, count: family.count, cycle: cycle)
        }
        if let g = find([.topLeftSixth, .topCenterSixth, .topRightSixth, .bottomLeftSixth, .bottomCenterSixth,
                         .bottomRightSixth], cols: 3, rows: 2, cycle: .allBackFromLast) { return g }
        if let g = find([.topLeftNinth, .topCenterNinth, .topRightNinth, .middleLeftNinth, .middleCenterNinth,
                         .middleRightNinth, .bottomLeftNinth, .bottomCenterNinth, .bottomRightNinth],
                        cols: 3, rows: 3, cycle: .allBackFromLast) { return g }
        if let g = find([.topLeftEighth, .topCenterLeftEighth, .topCenterRightEighth, .topRightEighth,
                         .bottomLeftEighth, .bottomCenterLeftEighth, .bottomCenterRightEighth, .bottomRightEighth],
                        cols: 4, rows: 2, cycle: .allBackFromLast) { return g }
        if let g = find([.topLeftTwelfth, .topCenterLeftTwelfth, .topCenterRightTwelfth, .topRightTwelfth,
                         .middleLeftTwelfth, .middleCenterLeftTwelfth, .middleCenterRightTwelfth, .middleRightTwelfth,
                         .bottomLeftTwelfth, .bottomCenterLeftTwelfth, .bottomCenterRightTwelfth, .bottomRightTwelfth],
                        cols: 4, rows: 3, cycle: .allBackFromLast) { return g }
        if let g = find([.topLeftSixteenth, .topCenterLeftSixteenth, .topCenterRightSixteenth, .topRightSixteenth,
                         .upperMiddleLeftSixteenth, .upperMiddleCenterLeftSixteenth, .upperMiddleCenterRightSixteenth,
                         .upperMiddleRightSixteenth, .lowerMiddleLeftSixteenth, .lowerMiddleCenterLeftSixteenth,
                         .lowerMiddleCenterRightSixteenth, .lowerMiddleRightSixteenth, .bottomLeftSixteenth,
                         .bottomCenterLeftSixteenth, .bottomCenterRightSixteenth, .bottomRightSixteenth],
                        cols: 4, rows: 4, cycle: .allBackFromLast) { return g }
        if let g = find([.firstVerticalSixth, .secondVerticalSixth, .thirdVerticalSixth, .fourthVerticalSixth,
                         .fifthVerticalSixth, .lastVerticalSixth], cols: 6, rows: 1, cycle: .ends) { return g }
        if let g = find([.firstVerticalEighth, .secondVerticalEighth, .thirdVerticalEighth, .fourthVerticalEighth,
                         .fifthVerticalEighth, .sixthVerticalEighth, .seventhVerticalEighth, .lastVerticalEighth],
                        cols: 8, rows: 1, cycle: .ends) { return g }
        let thirds: [Action] = [.topLeftThird, .topRightThird, .bottomLeftThird, .bottomRightThird]
        if let i = thirds.firstIndex(of: a) {
            // ⅔ wide × ½ high on landscape; ½ wide × ⅔ high on portrait.
            return Grid(cols: 2, rows: 2, index: i, count: 4, cycle: .all) { f, i in
                let right = i % 2 == 1, top = i < 2
                if f.width > f.height {
                    return Geometry.cell(f, cols: 3, rows: 2, c: right ? 1 : 0, r: top ? 0 : 1, sc: 2)
                }
                return Geometry.cell(f, cols: 2, rows: 3, c: right ? 1 : 0, r: top ? 0 : 1, sr: 2)
            }
        }
        return nil
    }
}

// MARK: - Display transfer (ported from Rectangle's DisplayTransfer)

nonisolated public struct Edges: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let left = Edges(rawValue: 1), right = Edges(rawValue: 2), top = Edges(rawValue: 4), bottom = Edges(rawValue: 8)
    public static let all: Edges = [.left, .right, .top, .bottom]
}

/// Moves a window to another display keeping the edges it touches and its relative place.
nonisolated public enum DisplayTransfer {
    enum Contact { case neither, start, end, both
        var oneEdge: Bool { self == .start || self == .end }
    }
    typealias Span = (origin: CGFloat, length: CGFloat)

    public static func transferredRect(window: CGRect, source: CGRect, destination: CGRect,
                                       edgeTolerance: CGFloat = 4) -> (rect: CGRect, sharedEdges: Edges) {
        guard source.width > 0, source.height > 0, destination.width > 0, destination.height > 0 else {
            return (window, [])
        }
        var h = transfer((window.minX, window.width), (source.minX, source.width), (destination.minX, destination.width), edgeTolerance)
        var v = transfer((window.minY, window.height), (source.minY, source.height), (destination.minY, destination.height), edgeTolerance)
        let turns = (source.width > source.height && destination.height > destination.width)
            || (source.height > source.width && destination.width > destination.height)
        if turns {
            if h.contact == .both, v.contact.oneEdge {
                h.span = centered(window.width, on: h.span, destination: (destination.minX, destination.width))
            } else if v.contact == .both, h.contact.oneEdge {
                v.span = centered(window.height, on: v.span, destination: (destination.minY, destination.height))
            }
        }
        var edges: Edges = []
        switch h.contact { case .start: edges.insert(.left); case .end: edges.insert(.right)
        case .both: edges.formUnion([.left, .right]); case .neither: break }
        // Rectangle's vertical "start" is the lower edge in Cocoa coordinates; it names it top. Kept as is.
        switch v.contact { case .start: edges.insert(.top); case .end: edges.insert(.bottom)
        case .both: edges.formUnion([.top, .bottom]); case .neither: break }
        return (CGRect(x: h.span.origin, y: v.span.origin, width: h.span.length, height: v.span.length), edges)
    }

    static func centered(_ length: CGFloat, on spanned: Span, destination: Span) -> Span {
        guard length < spanned.length else { return spanned }
        return (destination.origin + (destination.length - length) / 2, length)
    }

    static func transfer(_ window: Span, _ source: Span, _ destination: Span, _ tol: CGFloat) -> (span: Span, contact: Contact) {
        let startInset = window.origin - source.origin
        let endInset = (source.origin + source.length) - (window.origin + window.length)
        let atStart = startInset <= tol, atEnd = endInset <= tol
        if atStart, atEnd {
            let s = clamp(startInset, 0, destination.length / 2), e = clamp(endInset, 0, destination.length / 2)
            return ((destination.origin + s, destination.length - s - e), .both)
        }
        let length = min(window.length, destination.length)
        let slack = destination.length - length
        if atStart { return ((destination.origin + clamp(startInset, 0, slack), length), .start) }
        if atEnd { return ((destination.origin + destination.length - length - clamp(endInset, 0, slack), length), .end) }
        let center = (window.origin + window.length / 2 - source.origin) / source.length
        let origin = destination.origin + center * destination.length - length / 2
        return ((clamp(origin, destination.origin, destination.origin + slack), length), .neither)
    }

    static func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(max(v, lo), hi) }
}
