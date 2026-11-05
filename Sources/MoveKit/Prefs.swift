import AppKit

/// Preference keys. Shortcut keys are the action names (`leftHalf` …), in Rectangle's format.
enum K {
    static let showMenuIcon = "showMenuIcon"
    static let launchAtLogin = "launchOnLogin"
    static let mode = "subsequentExecutionMode"
    static let gap = "gapSize"
    static let edgeTop = "screenEdgeGapTop", edgeBottom = "screenEdgeGapBottom"
    static let edgeLeft = "screenEdgeGapLeft", edgeRight = "screenEdgeGapRight"
    static let almostWidth = "almostMaximizeWidth", almostHeight = "almostMaximizeHeight"
    static let sizeStep = "sizeOffset", widthStep = "widthStepSize"
    static let cycleSizes = "cycleSizes"
    static let centerHalfCycles = "centerHalfCycles"
    static let centeredDirectionalMove = "centeredDirectionalMove"
    static let repeatedMaximizeRestores = "repeatedMaximizeRestoresPrevious"
    static let gapsOnMaximize = "applyGapsToMaximize"
    static let specifiedWidth = "specifiedWidth", specifiedHeight = "specifiedHeight"
    static let moveCursorAcrossDisplays = "moveCursorAcrossDisplays"
    static let moveCursor = "moveCursor"
    static let ignoredApps = "disabledApps"
    static let lastRelaunch = "lastRelaunch"
}

/// A key + modifiers, stored like Rectangle (`{keyCode, modifierFlags}` with NSEvent flag bits).
public struct Shortcut: Equatable, Hashable, Sendable {
    public var keyCode: Int
    public var modifiers: UInt   // NSEvent.ModifierFlags raw value (device-independent bits only)

    public init(keyCode: Int, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Shortcut.relevant).rawValue
    }

    static let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    public var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var dict: [String: Int] { ["keyCode": keyCode, "modifierFlags": Int(modifiers)] }

    init?(dict: Any?) {
        guard let d = dict as? [String: Any], let code = (d["keyCode"] as? NSNumber)?.intValue,
              let mods = (d["modifierFlags"] as? NSNumber)?.uintValue else { return nil }
        self.init(keyCode: code, modifiers: NSEvent.ModifierFlags(rawValue: mods))
    }
}

/// All settings go through `Prefs.d`, so tests can swap in an isolated suite.
public enum Prefs {
    nonisolated(unsafe) static var d = UserDefaults.standard

    static let hyper: NSEvent.ModifierFlags = [.control, .option, .command]

    /// Ahmad's Rectangle shortcuts (~/.dotfiles/rectangle/com.knollsoft.Rectangle.plist): ⌃⌥⌘ + key.
    public static let defaultShortcuts: [Action: Shortcut] = [
        .leftHalf: Shortcut(keyCode: 123, modifiers: hyper),        // ←
        .rightHalf: Shortcut(keyCode: 124, modifiers: hyper),       // →
        .topHalf: Shortcut(keyCode: 126, modifiers: hyper),         // ↑
        .bottomHalf: Shortcut(keyCode: 125, modifiers: hyper),      // ↓
        .maximize: Shortcut(keyCode: 36, modifiers: hyper),         // ↩
        .almostMaximize: Shortcut(keyCode: 39, modifiers: hyper),   // '
        .center: Shortcut(keyCode: 8, modifiers: hyper),            // C
        .centerHalf: Shortcut(keyCode: 42, modifiers: hyper),       // \
        .firstFourth: Shortcut(keyCode: 18, modifiers: hyper),      // 1
        .secondFourth: Shortcut(keyCode: 19, modifiers: hyper),     // 2
        .thirdFourth: Shortcut(keyCode: 20, modifiers: hyper),      // 3
        .lastFourth: Shortcut(keyCode: 21, modifiers: hyper),       // 4
        .larger: Shortcut(keyCode: 30, modifiers: hyper),           // ]
        .smaller: Shortcut(keyCode: 33, modifiers: hyper),          // [
    ]

    public static func register() {
        var defaults: [String: Any] = [
            K.showMenuIcon: true,
            K.launchAtLogin: true,
            K.mode: RepeatMode.nextDisplay.rawValue,   // his Rectangle setting
            K.gap: 0.0,
            K.edgeTop: 0.0, K.edgeBottom: 0.0, K.edgeLeft: 0.0, K.edgeRight: 0.0,
            K.almostWidth: 0.9, K.almostHeight: 0.9,
            K.sizeStep: 30.0, K.widthStep: 30.0,
            K.cycleSizes: [0.5, 2.0 / 3, 1.0 / 3],
            K.centerHalfCycles: false,
            K.centeredDirectionalMove: true,
            K.repeatedMaximizeRestores: false,
            K.gapsOnMaximize: true,
            K.specifiedWidth: 1680.0, K.specifiedHeight: 1050.0,
            K.moveCursorAcrossDisplays: false,
            K.moveCursor: false,
            K.ignoredApps: [String](),
        ]
        for (a, s) in defaultShortcuts { defaults[a.rawValue] = s.dict }
        d.register(defaults: defaults)
    }

    // MARK: Shortcuts

    public static func shortcut(_ a: Action) -> Shortcut? { Shortcut(dict: d.object(forKey: a.rawValue)) }

    /// Setting a shortcut takes it away from any other action that had it. Returns that action.
    @discardableResult
    public static func setShortcut(_ s: Shortcut?, for a: Action) -> Action? {
        var taken: Action?
        if let s {
            for other in Action.allCases where other != a && shortcut(other) == s {
                d.set([String: Int](), forKey: other.rawValue)
                taken = other
            }
            d.set(s.dict, forKey: a.rawValue)
        } else {
            d.set([String: Int](), forKey: a.rawValue)   // explicit "none" (overrides a default)
        }
        NotificationCenter.default.post(name: .moveShortcutsChanged, object: nil)
        return taken
    }

    public static func resetShortcuts() {
        for a in Action.allCases { d.removeObject(forKey: a.rawValue) }
        NotificationCenter.default.post(name: .moveShortcutsChanged, object: nil)
    }

    public static var shortcuts: [Action: Shortcut] {
        var out: [Action: Shortcut] = [:]
        for a in Action.allCases { if let s = shortcut(a) { out[a] = s } }
        return out
    }

    // MARK: Behaviour

    public static var showMenuIcon: Bool {
        get { d.bool(forKey: K.showMenuIcon) }
        set { d.set(newValue, forKey: K.showMenuIcon) }
    }

    public static var mode: RepeatMode {
        get { RepeatMode(rawValue: d.integer(forKey: K.mode)) ?? .nextDisplay }
        set { d.set(newValue.rawValue, forKey: K.mode) }
    }

    static func cg(_ k: String) -> CGFloat { CGFloat(d.double(forKey: k)) }

    static func fraction(_ k: String) -> CGFloat {
        let v = cg(k)
        return v <= 0 || v > 1 ? 0.9 : v
    }

    public static var config: Config {
        var c = Config()
        c.mode = mode
        c.gap = max(0, cg(K.gap))
        c.screenEdgeGaps = Insets(top: max(0, cg(K.edgeTop)), bottom: max(0, cg(K.edgeBottom)),
                                  left: max(0, cg(K.edgeLeft)), right: max(0, cg(K.edgeRight)))
        c.almostMaximize = CGSize(width: fraction(K.almostWidth), height: fraction(K.almostHeight))
        c.sizeStep = cg(K.sizeStep) <= 0 ? 30 : cg(K.sizeStep)
        c.widthStep = cg(K.widthStep) <= 0 ? 30 : cg(K.widthStep)
        let sizes = (d.array(forKey: K.cycleSizes) as? [Double] ?? []).map { CGFloat($0) }.filter { $0 > 0 && $0 < 1 }
        c.cycleSizes = sizes.isEmpty ? [0.5] : sizes
        c.centerHalfCycles = d.bool(forKey: K.centerHalfCycles)
        c.centeredDirectionalMove = d.bool(forKey: K.centeredDirectionalMove)
        c.repeatedMaximizeRestores = d.bool(forKey: K.repeatedMaximizeRestores)
        c.gapsOnMaximize = d.bool(forKey: K.gapsOnMaximize)
        c.specified = CGSize(width: max(0.1, cg(K.specifiedWidth)), height: max(0.1, cg(K.specifiedHeight)))
        return c
    }

    public static var ignoredApps: Set<String> {
        get { Set(d.stringArray(forKey: K.ignoredApps) ?? []) }
        set { d.set(newValue.sorted(), forKey: K.ignoredApps) }
    }
}

extension Notification.Name {
    static let moveShortcutsChanged = Notification.Name("com.ahmadawais.move.shortcutsChanged")
    static let moveRecording = Notification.Name("com.ahmadawais.move.recording")
}
