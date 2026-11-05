import AppKit

/// Runs actions: finds the window, asks the engine, places the window, remembers what it did.
/// Everything external (window, displays, cursor) is injected so tests drive it end to end.
final class Controller {
    struct History {
        var restore: [UInt32: CGRect] = [:]     // where the user had the window before Move touched it
        var last: [UInt32: LastAction] = [:]    // what Move did last, and where the window ended up
        var preMaximize: [UInt32: CGRect] = [:]
    }

    var history = History()
    var focused: () -> Placeable? = { AXWindow.focused() }
    var displays: () -> (all: [Display], primaryMaxY: CGFloat) = { Controller.systemDisplays() }
    var warpCursor: (CGPoint) -> Void = { CGWarpMouseCursorPosition($0) }
    var beep: () -> Void = { NSSound.beep() }
    var config: () -> Config = { Prefs.config }
    var moveCursorAcrossDisplays: () -> Bool = { Prefs.d.bool(forKey: K.moveCursorAcrossDisplays) }
    var moveCursor: () -> Bool = { Prefs.d.bool(forKey: K.moveCursor) }

    static func systemDisplays() -> (all: [Display], primaryMaxY: CGFloat) {
        let screens = NSScreen.screens
        return (screens.map { Display(frame: $0.frame, visible: $0.visibleFrame) }, screens.first?.frame.maxY ?? 0)
    }

    /// Accessibility (top-left origin) ↔ Cocoa (bottom-left origin). The flip is its own inverse.
    static func flip(_ r: CGRect, _ primaryMaxY: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryMaxY - r.maxY, width: r.width, height: r.height)
    }

    @discardableResult
    func run(_ action: Action) -> Bool {
        guard let w = focused(), let id = w.id, let axFrame = w.frame, !axFrame.isNull else { beep(); return false }
        if (w as? AXWindow)?.isSheet == true { beep(); return false }

        if action == .restore {
            history.last[id] = nil
            guard let r = history.restore[id] else { beep(); return false }
            w.setFrame(r)
            return true
        }

        // Forget the last action if the user moved the window since.
        var last = history.last[id]
        let movedByUser = last.map { $0.rect != axFrame } ?? true
        if movedByUser { last = nil; history.last[id] = nil }
        if history.restore[id] == nil || movedByUser { history.restore[id] = axFrame }

        let (all, maxY) = displays()
        guard !all.isEmpty else { beep(); return false }
        let ordered = Engine.ordered(all)
        let window = Controller.flip(axFrame, maxY)
        let cur = Engine.display(containing: window, in: ordered)
        let lastCocoa = last.map { LastAction(action: $0.action, sub: $0.sub, rect: Controller.flip($0.rect, maxY), count: $0.count) }
        let engine = Engine(config: config(), displays: ordered, current: cur, window: window,
                            last: lastCocoa, preMaximize: history.preMaximize[id].map { Controller.flip($0, maxY) })
        guard let out = engine.calculate(action) else { beep(); return false }

        if (action == .maximize || action == .almostMaximize), !out.restored { history.preMaximize[id] = axFrame }

        let target = Controller.flip(out.rect, maxY)
        if target == axFrame {
            record(id, out, frame: axFrame, last: last)
            return true
        }
        place(w, target: target, area: Controller.flip(engine.area(out.display), maxY), action: out.action)
        let landed = w.frame ?? target
        if out.display != cur {
            w.focus()
            if moveCursorAcrossDisplays() { warpCursor(CGPoint(x: landed.midX, y: landed.midY)) }
        }
        if moveCursor() { warpCursor(CGPoint(x: landed.midX, y: landed.midY)) }
        if out.restored { history.last[id] = nil } else { record(id, out, frame: landed, last: last) }
        log.debug("\(action.rawValue, privacy: .public) → \(out.action.rawValue, privacy: .public) \(NSStringFromRect(landed), privacy: .public)")
        return true
    }

    private func record(_ id: UInt32, _ out: Outcome, frame: CGRect, last: LastAction?) {
        let count = last?.action == out.action ? (last?.count ?? 0) + 1 : 1
        history.last[id] = LastAction(action: out.action, sub: out.sub, rect: frame, count: count)
    }

    /// Places the window; fixed-size windows are only moved. If the app kept the window bigger than asked
    /// (minimum sizes), slide it back inside the screen, keeping the edge it was meant to touch.
    func place(_ w: Placeable, target: CGRect, area: CGRect, action: Action) {
        if w.resizable || target.size == w.frame?.size {
            w.setFrame(target)
        } else {
            let size = w.frame?.size ?? target.size
            w.setPosition(Controller.aligned(size: size, in: target))
        }
        guard !action.mayExtendPastScreen, let got = w.frame, got != target else { return }
        var fixed = Controller.aligned(size: got.size, in: target, screen: area)
        fixed = Controller.constrained(fixed, to: area)
        if fixed.origin != got.origin { w.setPosition(fixed.origin) }
    }

    /// A window that ended up a different size than its slot: keep it flush with the screen edges the slot
    /// touches, centered on the rest. (Accessibility coordinates.)
    static func aligned(size: CGSize, in zone: CGRect, screen: CGRect? = nil) -> CGRect {
        var r = CGRect(origin: zone.origin, size: size)
        let s = screen ?? zone
        func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) <= 1 }
        if abs(size.width - zone.width) > 1 {
            let l = near(zone.minX, s.minX), rt = near(zone.maxX, s.maxX)
            r.origin.x = l && !rt ? zone.minX : (rt && !l ? zone.maxX - size.width : ((zone.width - size.width) / 2).rounded() + zone.minX)
        }
        if abs(size.height - zone.height) > 1 {
            let t = near(zone.minY, s.minY), b = near(zone.maxY, s.maxY)
            r.origin.y = t && !b ? zone.minY : (b && !t ? zone.maxY - size.height : ((zone.height - size.height) / 2).rounded() + zone.minY)
        }
        return r
    }

    static func aligned(size: CGSize, in zone: CGRect) -> CGPoint { aligned(size: size, in: zone, screen: nil).origin }

    /// Keep a window that fits on the screen fully on it.
    static func constrained(_ r: CGRect, to s: CGRect) -> CGRect {
        guard r.width <= s.width, r.height <= s.height else { return r }
        var o = r
        if o.minX < s.minX { o.origin.x = s.minX } else if o.maxX > s.maxX { o.origin.x = s.maxX - o.width }
        if o.minY < s.minY { o.origin.y = s.minY } else if o.maxY > s.maxY { o.origin.y = s.maxY - o.height }
        return o
    }
}
