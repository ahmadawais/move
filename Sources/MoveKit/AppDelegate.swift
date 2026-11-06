import AppKit
import OSLog

nonisolated let log = Logger(subsystem: "com.ahmadawais.move", category: "app")

/// Status item, menus, hotkeys, URLs and the Accessibility grant. Window logic lives in `Controller`.
public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let controller = Controller()
    let hotKeys = HotKeys()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var permissionTimer: Timer?
    private var recording = false

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.register()
        LoginItem.apply()
        installMainMenu()
        updateStatusItem()
        hotKeys.onPress = { [weak self] a in self?.perform(a) }
        refreshHotKeys()

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(defaultsChanged), name: UserDefaults.didChangeNotification, object: nil)
        nc.addObserver(self, selector: #selector(shortcutsChanged), name: .moveShortcutsChanged, object: nil)
        nc.addObserver(self, selector: #selector(recordingChanged(_:)), name: .moveRecording, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appActivated),
                                                          name: NSWorkspace.didActivateApplicationNotification, object: nil)
        if Permission.trusted {
            log.info("Ready: Accessibility allowed, \(self.hotKeys.count, privacy: .public) shortcuts")
        } else {
            waitForPermission()
            Permission.request()
        }
    }

    /// Launching again (Spotlight, Finder) opens Settings: the way back when the icon is hidden.
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    // MARK: Actions

    func perform(_ a: Action) {
        guard Permission.trusted else {
            NSSound.beep()
            if permissionTimer == nil { Permission.request() }   // macOS's prompt once, not on every press
            waitForPermission()
            return
        }
        controller.run(a)
    }

    // MARK: URLs: move://execute-action?name=left-half · move://execute-task?name=ignore-app[&app-bundle-id=…]

    public func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { handle(url) }
    }

    enum URLCommand: Equatable { case action(Action), ignore(String?), unignore(String?) }

    static func parse(_ url: URL) -> URLCommand? {
        guard url.scheme?.lowercased() == "move",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let name = items.first(where: { $0.name == "name" })?.value else { return nil }
        let bundle = items.first(where: { $0.name == "app-bundle-id" })?.value
        switch url.host {
        case "execute-action": return Action(urlName: name).map { .action($0) }
        case "execute-task":
            if name == "ignore-app" { return .ignore(bundle) }
            if name == "unignore-app" { return .unignore(bundle) }
            return nil
        default: return nil
        }
    }

    func handle(_ url: URL) {
        switch AppDelegate.parse(url) {
        case .action(let a)?: perform(a)
        case .ignore(let b)?: setIgnored(b ?? frontmostBundleID(), true)
        case .unignore(let b)?: setIgnored(b ?? frontmostBundleID(), false)
        case nil: log.error("Unknown URL \(url.absoluteString, privacy: .public)"); NSSound.beep()
        }
    }

    // MARK: Hotkeys & ignored apps

    func frontmostBundleID() -> String? {
        let b = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return b == Bundle.main.bundleIdentifier ? nil : b
    }

    /// Shortcuts are off while an ignored app is frontmost or a shortcut is being recorded.
    func refreshHotKeys() {
        let ignored = frontmostBundleID().map { Prefs.ignoredApps.contains($0) } ?? false
        if ignored || recording { hotKeys.unregister() } else { hotKeys.register(Prefs.shortcuts) }
    }

    func setIgnored(_ bundle: String?, _ on: Bool) {
        guard let bundle else { return }
        var s = Prefs.ignoredApps
        if on { s.insert(bundle) } else { s.remove(bundle) }
        Prefs.ignoredApps = s
        refreshHotKeys()
    }

    @objc private func appActivated() { refreshHotKeys() }
    @objc private func shortcutsChanged() { refreshHotKeys() }
    @objc private func recordingChanged(_ n: Notification) {
        recording = (n.object as? Bool) ?? false
        refreshHotKeys()
    }

    @objc private func defaultsChanged() {
        DispatchQueue.main.async { [weak self] in self?.updateStatusItem() }
    }

    // MARK: Accessibility

    /// macOS applies a fresh grant reliably only to a new process, so relaunch once it's given.
    private func waitForPermission() {
        guard permissionTimer == nil else { return }
        log.info("Waiting for Accessibility")
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.permissionTick() }
        }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(accessibilityListChanged),
                                                            name: .init("com.apple.accessibility.api"), object: nil)
    }

    @objc private func accessibilityListChanged() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.permissionTick() }
    }

    private func permissionTick() {
        guard Permission.trusted else { return }
        permissionTimer?.invalidate(); permissionTimer = nil
        updateStatusItem()
        let last = Prefs.d.double(forKey: K.lastRelaunch)
        guard Date().timeIntervalSince1970 - last > 30 else { return }   // never loop
        Prefs.d.set(Date().timeIntervalSince1970, forKey: K.lastRelaunch)
        log.info("Accessibility allowed; relaunching so it takes effect")
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.createsNewApplicationInstance = true
        cfg.activates = false
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: cfg) { _, error in
            if let error { log.error("Relaunch failed: \(error.localizedDescription, privacy: .public)"); return }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    // MARK: Status item & menu

    private func updateStatusItem() {
        guard Prefs.showMenuIcon else {
            if let s = statusItem { NSStatusBar.system.removeStatusItem(s) }
            statusItem = nil
            return
        }
        if statusItem == nil {
            let s = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            let image = NSImage(systemSymbolName: "rectangle.split.2x2", accessibilityDescription: "Move")
            image?.isTemplate = true
            s.button?.image = image
            let menu = NSMenu()
            menu.delegate = self
            s.menu = menu
            statusItem = s
        }
        statusItem?.button?.appearsDisabled = !Permission.trusted
    }

    /// The groups shown at the top level; the rest go under "More".
    static let menuGroups: [[Action]] = [
        [.leftHalf, .rightHalf, .centerHalf, .topHalf, .bottomHalf],
        [.topLeft, .topRight, .bottomLeft, .bottomRight],
        [.firstThird, .centerThird, .lastThird, .firstTwoThirds, .centerTwoThirds, .lastTwoThirds],
        [.firstFourth, .secondFourth, .thirdFourth, .lastFourth],
        [.maximize, .almostMaximize, .maximizeHeight, .larger, .smaller, .center, .restore],
        [.nextDisplay, .previousDisplay],
    ]

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if !Permission.trusted {
            menu.addItem(withTitle: "Allow Accessibility…", action: #selector(allowAccessibility), keyEquivalent: "").target = self
            menu.addItem(.separator())
        }
        let top = Set(AppDelegate.menuGroups.flatMap { $0 })
        for group in AppDelegate.menuGroups {
            for a in group { menu.addItem(item(a)) }
            menu.addItem(.separator())
        }
        let more = NSMenuItem(title: "More", action: nil, keyEquivalent: "")
        let moreMenu = NSMenu()
        for g in Action.Group.allCases {
            let actions = Action.allCases.filter { $0.group == g && !top.contains($0) }
            guard !actions.isEmpty else { continue }
            let sub = NSMenuItem(title: g.rawValue, action: nil, keyEquivalent: "")
            let subMenu = NSMenu()
            for a in actions { subMenu.addItem(item(a)) }
            sub.submenu = subMenu
            moreMenu.addItem(sub)
        }
        more.submenu = moreMenu
        menu.addItem(more)
        menu.addItem(.separator())

        if let bundle = frontmostBundleID() {
            let name = NSWorkspace.shared.frontmostApplication?.localizedName ?? bundle
            let ignore = menu.addItem(withTitle: "Ignore \(name)", action: #selector(toggleIgnore(_:)), keyEquivalent: "")
            ignore.target = self
            ignore.representedObject = bundle
            ignore.state = Prefs.ignoredApps.contains(bundle) ? .on : .off
        }
        menu.addItem(withTitle: "Settings…", action: #selector(openSettingsMenu), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Move", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    private func item(_ a: Action) -> NSMenuItem {
        let i = NSMenuItem(title: a.title, action: #selector(menuAction(_:)), keyEquivalent: "")
        i.target = self
        i.representedObject = a.rawValue
        if let s = Prefs.shortcut(a), let key = KeyName.menuEquivalent(s.keyCode) {
            i.keyEquivalent = key
            i.keyEquivalentModifierMask = s.flags
        }
        return i
    }

    @objc private func menuAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let a = Action(rawValue: raw) else { return }
        perform(a)
    }

    @objc private func toggleIgnore(_ sender: NSMenuItem) {
        guard let b = sender.representedObject as? String else { return }
        setIgnored(b, !Prefs.ignoredApps.contains(b))
    }

    @objc private func allowAccessibility() { Permission.request(); Permission.openSettings(); waitForPermission() }

    @objc private func openSettingsMenu() { openSettings() }

    func openSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindow.make() }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Edit menu so ⌘C/⌘V/⌘A work in text fields of an accessory (LSUIElement) app.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettingsMenu), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Quit Move", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
}
