import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Something Move can read and place. The real one is an Accessibility window; tests use a fake.
@MainActor protocol Placeable: AnyObject {
    var id: UInt32? { get }
    var bundleID: String? { get }
    /// Accessibility coordinates: origin top-left of the primary display, y down.
    var frame: CGRect? { get }
    var resizable: Bool { get }
    func setFrame(_ r: CGRect)
    func setPosition(_ p: CGPoint)
    func focus()
}

/// The focused window of the frontmost app, through the Accessibility API.
final class AXWindow: Placeable {
    let element: AXUIElement
    let app: AXUIElement
    let pid: pid_t

    init(element: AXUIElement, app: AXUIElement, pid: pid_t) {
        self.element = element; self.app = app; self.pid = pid
        AXUIElementSetMessagingTimeout(app, 1.0)   // a hung app must not hang Move
    }

    static func focused() -> AXWindow? {
        guard let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier > 0 else { return nil }
        let pid = front.processIdentifier
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        if let w: AXUIElement = copy(app, kAXFocusedWindowAttribute) { return AXWindow(element: w, app: app, pid: pid) }
        if let ws: [AXUIElement] = copy(app, kAXWindowsAttribute), let w = ws.first {
            return AXWindow(element: w, app: app, pid: pid)
        }
        // Some apps only answer system-wide: take the focused element's window.
        let sys = AXUIElementCreateSystemWide()
        if let el: AXUIElement = copy(sys, kAXFocusedUIElementAttribute) {
            if let role: String = copy(el, kAXRoleAttribute), role == kAXWindowRole {
                return AXWindow(element: el, app: app, pid: pid)
            }
            if let w: AXUIElement = copy(el, kAXWindowAttribute) { return AXWindow(element: w, app: app, pid: pid) }
        }
        return nil
    }

    static func copy<T>(_ el: AXUIElement, _ attr: String) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success, let v else { return nil }
        return v as? T
    }

    var id: UInt32? {
        var wid: CGWindowID = 0
        if _AXUIElementGetWindow(element, &wid) == .success, wid != 0 { return wid }
        // Stand-in id from the element's identity (stable for the window's life), high bit set.
        return 0x8000_0000 | (UInt32(truncatingIfNeeded: CFHash(element)) & 0x7FFF_FFFF)
    }

    var bundleID: String? { NSRunningApplication(processIdentifier: pid)?.bundleIdentifier }

    var isSheet: Bool {
        let role: String? = AXWindow.copy(element, kAXRoleAttribute)
        return role == kAXSheetRole
    }

    var frame: CGRect? {
        guard let p = point(kAXPositionAttribute), let s = size(kAXSizeAttribute) else { return nil }
        return CGRect(origin: p, size: s)
    }

    var resizable: Bool {
        var settable: DarwinBoolean = true
        guard AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &settable) == .success else { return true }
        return settable.boolValue
    }

    private func point(_ attr: String) -> CGPoint? {
        guard let v: AXValue = AXWindow.copy(element, attr) else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v, .cgPoint, &p) ? p : nil
    }

    private func size(_ attr: String) -> CGSize? {
        guard let v: AXValue = AXWindow.copy(element, attr) else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v, .cgSize, &s) ? s : nil
    }

    private func set(position p: CGPoint) {
        var p = p
        if let v = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, v) }
    }

    private func set(size s: CGSize) {
        var s = s
        if let v = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, v) }
    }

    /// Size, move, size again: macOS clamps sizes to the display a window is on, so moving across
    /// displays needs the second resize.
    func setFrame(_ r: CGRect) {
        withEnhancedUIOff {
            set(size: r.size)
            set(position: r.origin)
            set(size: r.size)
        }
    }

    func setPosition(_ p: CGPoint) { withEnhancedUIOff { set(position: p) } }

    func focus() {
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    /// Apps with AXEnhancedUserInterface on (set by assistive tools, Chromium) animate and fight frame
    /// changes. Turn it off while moving; turn it back on afterwards except for Chromium browsers,
    /// where it only costs performance (Rectangle's "automatic" behaviour).
    private func withEnhancedUIOff(_ body: () -> Void) {
        let attr = "AXEnhancedUserInterface" as CFString
        var v: CFTypeRef?
        let was = AXUIElementCopyAttributeValue(app, attr, &v) == .success && (v as? Bool) == true
        if was { AXUIElementSetAttributeValue(app, attr, kCFBooleanFalse) }
        body()
        let assistive = NSWorkspace.shared.isVoiceOverEnabled || NSWorkspace.shared.isSwitchControlEnabled
        if was, assistive || !AXWindow.isChromium(bundleID) { AXUIElementSetAttributeValue(app, attr, kCFBooleanTrue) }
    }

    static let chromium = ["com.google.Chrome", "org.chromium.Chromium", "com.microsoft.edgemac", "com.brave.Browser",
                           "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "company.thebrowser.Browser",
                           "company.thebrowser.dia", "ai.perplexity.comet", "com.openai.atlas"]

    static func isChromium(_ id: String?) -> Bool {
        guard let id else { return false }
        return chromium.contains { id == $0 || id.hasPrefix($0 + ".") }
    }
}

/// Accessibility permission: needed to move other apps' windows. Nothing else.
enum Permission {
    static var trusted: Bool { AXIsProcessTrusted() }

    /// Shows macOS's own prompt, which links to System Settings.
    static func request() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
