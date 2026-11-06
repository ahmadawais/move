import AppKit
import Testing
@testable import MoveKit

/// Suites that touch global state (Prefs, AppKit) run one at a time.
@Suite(.serialized) struct SharedState {}

enum Env {
    /// Fresh, isolated preferences for one test — never the user's real ones.
    @discardableResult
    static func prefs() -> UserDefaults {
        let d = UserDefaults(suiteName: "com.ahmadawais.move.tests.\(UUID().uuidString)")!
        Prefs.d = d
        Prefs.register()
        return d
    }
}

/// A window that remembers what was done to it (Accessibility coordinates).
final class FakeWindow: Placeable {
    var id: UInt32? = 42
    var bundleID: String? = "com.example.app"
    var frame: CGRect?
    var resizable = true
    var minSize = CGSize.zero
    var focused = 0
    var sets: [CGRect] = []

    init(_ f: CGRect) { frame = f }

    func setFrame(_ r: CGRect) {
        sets.append(r)
        frame = CGRect(origin: r.origin, size: CGSize(width: max(r.width, minSize.width), height: max(r.height, minSize.height)))
    }
    func setPosition(_ p: CGPoint) { frame?.origin = p; sets.append(frame!) }
    func focus() { focused += 1 }
}

extension SharedState {
    struct PrefsTests {
        init() { Env.prefs() }

        @Test("Defaults: 14 ⌃⌥⌘ shortcuts, next display on repeat")
        func defaults() {
            #expect(Prefs.mode == .nextDisplay)
            #expect(Prefs.showMenuIcon)
            #expect(LoginItem.enabled)
            let s = Prefs.shortcuts
            #expect(s.count == 14)
            #expect(s[.leftHalf].map(KeyName.display) == "⌃⌥⌘←")
            #expect(s[.maximize].map(KeyName.display) == "⌃⌥⌘↩")
            #expect(s[.center] == Shortcut(keyCode: 8, modifiers: [.control, .option, .command]))
            #expect(s[.topLeft] == nil)    // corners have no default
        }

        @Test func settingAShortcutTakesItFromTheOtherAction() {
            let s = Shortcut(keyCode: 123, modifiers: [.control, .option, .command])
            let taken = Prefs.setShortcut(s, for: .topLeft)
            #expect(taken == .leftHalf)
            #expect(Prefs.shortcut(.leftHalf) == nil)
            #expect(Prefs.shortcut(.topLeft) == s)
            Prefs.resetShortcuts()
            #expect(Prefs.shortcut(.leftHalf) == s)
            #expect(Prefs.shortcut(.topLeft) == nil)
        }

        @Test func clearingADefaultSticks() {
            Prefs.setShortcut(nil, for: .maximize)
            #expect(Prefs.shortcut(.maximize) == nil)
        }

        @Test func configReadsPrefs() {
            Prefs.d.set(12.0, forKey: K.gap)
            Prefs.d.set(0.8, forKey: K.almostWidth)
            Prefs.d.set(5.0, forKey: K.almostHeight)        // invalid → 0.9
            Prefs.d.set([0.25, 0.75], forKey: K.cycleSizes)
            let c = Prefs.config
            #expect(c.gap == 12 && c.almostMaximize == CGSize(width: 0.8, height: 0.9))
            #expect(c.cycleSizes == [0.25, 0.75])
        }

        @Test func ignoredApps() {
            Prefs.ignoredApps = ["b", "a"]
            #expect(Prefs.ignoredApps == ["a", "b"])
        }
    }

    @MainActor
    struct ControllerTests {
        let maxY: CGFloat = 982
        func make(_ w: FakeWindow, displays: [Display] = [laptop], config: Config = Config()) -> Controller {
            Env.prefs()
            let c = Controller()
            c.focused = { w }
            c.displays = { (displays, 982) }
            c.config = { config }
            c.beep = {}
            c.warpCursor = { _ in }
            return c
        }

        /// Laptop visible frame in Accessibility coordinates: y = 982 - 949 = 33.
        let axVisible = CGRect(x: 0, y: 33, width: 1512, height: 889)

        @Test func leftHalfEndToEnd() {
            let w = FakeWindow(CGRect(x: 100, y: 100, width: 600, height: 400))
            let c = make(w)
            #expect(c.run(.leftHalf))
            #expect(w.frame == CGRect(x: 0, y: 33, width: 756, height: 889))
        }

        @Test func restoreReturnsToWhereTheUserHadIt() {
            let start = CGRect(x: 100, y: 100, width: 600, height: 400)
            let w = FakeWindow(start)
            let c = make(w)
            c.run(.leftHalf); c.run(.maximize); c.run(.restore)
            #expect(w.frame == start)
        }

        @Test func restoreRemembersTheLatestManualPlace() {
            let w = FakeWindow(CGRect(x: 100, y: 100, width: 600, height: 400))
            let c = make(w)
            c.run(.leftHalf)
            w.frame = CGRect(x: 300, y: 300, width: 500, height: 300)   // user drags it
            c.run(.maximize); c.run(.restore)
            #expect(w.frame == CGRect(x: 300, y: 300, width: 500, height: 300))
        }

        @Test("Ahmad's ⌃⌥⌘1 twice: first fourth, then second fourth")
        func repeatCycles() {
            let w = FakeWindow(CGRect(x: 100, y: 100, width: 600, height: 400))
            let c = make(w)
            c.run(.firstFourth)
            #expect(w.frame?.minX == 0)
            c.run(.firstFourth)
            #expect(w.frame?.minX == 378)
        }

        @Test func movingTheWindowResetsTheCycle() {
            let w = FakeWindow(CGRect(x: 100, y: 100, width: 600, height: 400))
            let c = make(w)
            c.run(.firstFourth)
            w.frame?.origin.x += 1
            c.run(.firstFourth)
            #expect(w.frame?.minX == 0)
        }

        @Test func rightHalfTwiceCrossesToTheExternalDisplay() {
            let w = FakeWindow(CGRect(x: 100, y: 100, width: 600, height: 400))
            let c = make(w, displays: [laptop, external])
            c.run(.rightHalf); c.run(.rightHalf)
            // External visible (Cocoa 1512, -235, 2560×1415) → AX y = 982 - 1180 = -198.
            #expect(w.frame == CGRect(x: 1512, y: -198, width: 1280, height: 1415))
            #expect(w.focused == 1)
        }

        @Test func fixedSizeWindowIsOnlyMoved() {
            let w = FakeWindow(CGRect(x: 100, y: 100, width: 600, height: 400))
            w.resizable = false
            let c = make(w)
            c.run(.rightHalf)
            #expect(w.frame?.size == CGSize(width: 600, height: 400))
            #expect(w.frame?.maxX == 1512)      // flush with the right edge it was meant to touch
        }

        @Test func windowWithMinimumSizeIsKeptOnScreen() {
            let w = FakeWindow(CGRect(x: 100, y: 100, width: 600, height: 400))
            w.minSize = CGSize(width: 700, height: 0)
            let c = make(w)
            c.run(.lastThird)
            #expect(w.frame?.width == 700 && w.frame?.maxX == 1512)
        }

        @Test func noWindowBeeps() {
            Env.prefs()
            let c = Controller()
            var beeps = 0
            c.focused = { nil }
            c.beep = { beeps += 1 }
            #expect(!c.run(.leftHalf))
            #expect(beeps == 1)
        }

        @Test func sameFrameIsNotWrittenAgain() {
            let w = FakeWindow(CGRect(x: 0, y: 33, width: 756, height: 889))
            let c = make(w)
            c.run(.leftHalf)
            #expect(w.sets.isEmpty)
        }

        @Test func maximizeTwiceRestoresWhenEnabled() {
            var cfg = Config(); cfg.repeatedMaximizeRestores = true
            let start = CGRect(x: 100, y: 100, width: 600, height: 400)
            let w = FakeWindow(start)
            let c = make(w, config: cfg)
            c.run(.maximize)
            #expect(w.frame == axVisible)
            c.run(.maximize)
            #expect(w.frame == start)
        }

        @Test func flipIsItsOwnInverse() {
            let r = CGRect(x: 10, y: 20, width: 30, height: 40)
            #expect(Controller.flip(Controller.flip(r, 982), 982) == r)
        }
    }

    @MainActor
    struct AppTests {
        @Test func urls() {
            #expect(AppDelegate.parse(URL(string: "move://execute-action?name=center-half")!) == .action(.centerHalf))
            #expect(AppDelegate.parse(URL(string: "move://execute-action?name=firstFourth")!) == .action(.firstFourth))
            #expect(AppDelegate.parse(URL(string: "other://execute-action?name=first-fourth")!) == nil)
            #expect(AppDelegate.parse(URL(string: "move://execute-task?name=ignore-app&app-bundle-id=com.apple.Safari")!)
                    == .ignore("com.apple.Safari"))
            #expect(AppDelegate.parse(URL(string: "move://execute-task?name=unignore-app")!) == .unignore(nil))
            #expect(AppDelegate.parse(URL(string: "move://execute-action?name=nope")!) == nil)
            #expect(AppDelegate.parse(URL(string: "https://execute-action?name=left-half")!) == nil)
        }

        @Test func hotKeysRegisterAndUnregister() {
            Env.prefs()
            let h = HotKeys()
            // Unusual combo so it can't clash with the real app if it's running.
            let s = Shortcut(keyCode: 105, modifiers: [.control, .option, .shift, .command]) // F13
            let failed = h.register([.leftHalf: s])
            #expect(failed.isEmpty && h.count == 1)
            var fired: Action?
            h.onPress = { fired = $0 }
            h.fire(1)   // id of leftHalf (first case)
            #expect(fired == .leftHalf)
            h.unregister()
            #expect(h.count == 0)
        }

        @Test func keyNames() {
            #expect(KeyName.modifiers([.control, .option, .shift, .command]) == "⌃⌥⇧⌘")
            #expect(KeyName.key(123) == "←" && KeyName.key(36) == "↩")
            #expect(KeyName.menuEquivalent(36) == "\r")
        }

        @Test func carbonModifiers() {
            #expect(HotKeys.carbon([.command]) == 256 && HotKeys.carbon([.control, .option]) == 6144)
        }

        @Test func menuGroupsCoverHisShortcuts() {
            let inMenu = Set(AppDelegate.menuGroups.flatMap { $0 })
            for a in Prefs.defaultShortcuts.keys { #expect(inMenu.contains(a), "\(a)") }
        }

        @Test("Settings window uses golden-ratio toolbar tabs")
        func goldenRatio() throws {
            _ = NSApplication.shared
            Env.prefs()
            let window = SettingsWindow.make()
            let tabs = try #require(window.contentViewController as? NSTabViewController)
            #expect(tabs.tabStyle == .toolbar)
            #expect(tabs.tabViewItems.map(\.label) == ["General", "Shortcuts", "Layout", "Apps", "Advanced"])
            #expect(SettingsWindow.short == 346)
        }

        /// Renders every tab to .build/renders/*.png — open them and look before calling the UI done.
        @Test("Render settings for review")
        func render() throws {
            _ = NSApplication.shared
            Env.prefs()
            let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("../../.build/renders").standardized
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let window = SettingsWindow.make()
                window.appearance = NSAppearance(named: appearance)
                let tabs = try #require(window.contentViewController as? NSTabViewController)
                tabs.transitionOptions = []
                for i in tabs.tabViewItems.indices {
                    tabs.selectedTabViewItemIndex = i
                    window.layoutIfNeeded()
                    let view = try #require(window.contentView?.superview)
                    view.layoutSubtreeIfNeeded()
                    let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                    view.cacheDisplay(in: view.bounds, to: rep)
                    let png = try #require(rep.representation(using: .png, properties: [:]))
                    try png.write(to: dir.appendingPathComponent("settings-\(name)-\(i)-\(tabs.tabViewItems[i].label).png"))
                }
            }
        }
    }
}
