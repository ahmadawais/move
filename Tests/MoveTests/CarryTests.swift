import CoreGraphics
import Testing
@testable import MoveKit

/// Carrying a window to another display.
@Suite struct CarryTests {
    let small = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let big = CGRect(x: 1000, y: -200, width: 2000, height: 1200)

    func carry(_ w: CGRect, from: CGRect? = nil, to: CGRect? = nil, tolerance: CGFloat = 4) -> (rect: CGRect, fills: Bool) {
        Carry.rect(w, from: from ?? small, to: to ?? big, tolerance: tolerance)
    }

    @Test func fullScreenFills() {
        let r = carry(small)
        #expect(r.fills && r.rect == big)
    }

    @Test func leftHalfStaysLeftAndFullHeight() {
        let r = carry(CGRect(x: 0, y: 0, width: 500, height: 800))
        #expect(!r.fills)
        #expect(r.rect == CGRect(x: 1000, y: -200, width: 500, height: 1200))
    }

    @Test func flushRightStaysFlushRight() {
        let r = carry(CGRect(x: 700, y: 100, width: 300, height: 300)).rect
        #expect(r.maxX == big.maxX && r.width == 300)
    }

    @Test func centeredStaysCentered() {
        let r = carry(CGRect(x: 300, y: 200, width: 400, height: 400)).rect
        #expect(r.midX == big.midX && r.midY == big.midY)
    }

    @Test func keepsItsShareOfTheFreeSpace() {
        // 100 of 400 free pixels on the left: a quarter of the way across.
        let r = carry(CGRect(x: 100, y: 0, width: 600, height: 300)).rect
        #expect(r.minX == big.minX + (2000 - 600) / 4)
    }

    @Test func tooBigShrinksToFit() {
        let r = carry(CGRect(x: 10, y: 10, width: 1900, height: 1100), from: big.insetBy(dx: -100, dy: -100), to: small).rect
        #expect(small.contains(r) && r.size == CGSize(width: 1000, height: 800))
    }

    @Test func gapsCountAsTouchingAndKeepTheirInsets() {
        let w = small.insetBy(dx: 10, dy: 10)
        #expect(!carry(w).fills)
        let r = carry(w, tolerance: 14)
        #expect(r.fills && r.rect == big.insetBy(dx: 10, dy: 10))
    }

    @Test func goesBackWhereItCameFrom() {
        let w = CGRect(x: 120, y: 90, width: 400, height: 300)
        let there = carry(w).rect
        let back = carry(there, from: big, to: small).rect
        #expect(abs(back.minX - w.minX) <= 1 && abs(back.minY - w.minY) <= 1 && back.size == w.size)
    }

    @Test func emptyDisplayLeavesWindowAlone() {
        let w = CGRect(x: 1, y: 2, width: 3, height: 4)
        #expect(carry(w, to: .zero).rect == w)
    }
}
