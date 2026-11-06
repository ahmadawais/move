import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// `@State` is a macro shipped only with Xcode; this keeps the app buildable with Command Line Tools.
final class Box<T>: ObservableObject {
    @Published var v: T
    init(_ v: T) { self.v = v }
    // Swift 6.3.3 (Xcode 26.6) crashes inlining into this deinit in -O builds. Nothing to optimize here.
    @_optimize(none) deinit {}
}

/// Toolbar-tab settings window. Golden ratio: short tabs 560 × 346 (width ÷ φ), long tabs 560 × 560.
enum SettingsWindow {
    static let width: CGFloat = 560
    static let short = (width / 1.618).rounded()
    static let tall = width

    static func make() -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.canPropagateSelectedChildViewControllerTitle = true
        func add<V: View>(_ title: String, _ symbol: String, height: CGFloat, _ view: V) {
            let host = NSHostingController(rootView: view.frame(width: width, height: height))
            host.sizingOptions = .preferredContentSize
            host.title = title
            let item = NSTabViewItem(viewController: host)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }
        add("General", "gearshape", height: short, GeneralTab())
        add("Shortcuts", "keyboard", height: tall, ShortcutsTab())
        add("Layout", "rectangle.split.2x2", height: tall, LayoutTab())
        add("Apps", "app.badge.checkmark", height: short, AppsTab())
        add("Advanced", "slider.horizontal.3", height: tall, AdvancedTab())

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

// MARK: Building blocks — label left, value/control flush right

/// "Gap            8 pt [⌃⌄]"
struct StepperRow: View {
    let title: String
    var subtitle: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var unit = "pt"
    var format: (Double) -> String = { String(Int($0.rounded())) }
    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                Text("\(format(value)) \(unit)").monospacedDigit().foregroundStyle(.secondary)
                Stepper(title, value: $value, in: range, step: step).labelsHidden()
            }
        } label: {
            Text(title)
            if let subtitle { Text(subtitle) }
        }
    }
}

func defaultsBinding(_ key: String) -> Binding<Double> {
    Binding(get: { Prefs.d.double(forKey: key) }, set: { Prefs.d.set($0, forKey: key) })
}

/// Re-renders views when any preference changes (settings written elsewhere: menu, URL, other tab).
final class PrefsWatcher: ObservableObject {
    @Published var tick = 0
    private var c: AnyCancellable?
    private var s: AnyCancellable?
    init() {
        c = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.tick += 1 }
        s = NotificationCenter.default.publisher(for: .moveShortcutsChanged)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.tick += 1 }
    }
}

// MARK: General

struct GeneralTab: View {
    @AppStorage(K.showMenuIcon, store: Prefs.d) private var showIcon = true
    @AppStorage(K.mode, store: Prefs.d) private var mode = RepeatMode.nextDisplay.rawValue
    @StateObject private var launchAtLogin = Box(LoginItem.enabled)
    @StateObject private var trusted = Box(Permission.trusted)
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    if trusted.v {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Allow…") { Permission.request(); Permission.openSettings() }
                    }
                } label: {
                    Text("Accessibility")
                    Text(trusted.v ? "Allowed. Used only to move and resize windows." : "Needed to move other apps' windows.")
                }
                Toggle("Launch at login", isOn: $launchAtLogin.v)
                    .onChange(of: launchAtLogin.v) { _, on in LoginItem.enabled = on }
                Toggle(isOn: $showIcon) {
                    Text("Show menu bar icon")
                    Text("When hidden, open Move from Spotlight to get here.")
                }
            }
            Section {
                Picker(selection: $mode) {
                    ForEach(RepeatMode.ordered, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                } label: {
                    Text("Pressing a shortcut again")
                    Text("Halves, corners, edges and fourths.")
                }
                if RepeatMode(rawValue: mode)?.resizes == true { CycleSizesRow() }
            }
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in trusted.v = Permission.trusted }
    }
}

struct CycleSizesRow: View {
    @StateObject private var sizes = Box(Set((Prefs.d.array(forKey: K.cycleSizes) as? [Double] ?? []).map { Int(($0 * 1000).rounded()) }))
    static let options: [(String, Double)] = [("½", 0.5), ("⅔", 2.0 / 3), ("¾", 0.75), ("¼", 0.25), ("⅓", 1.0 / 3)]

    var body: some View {
        LabeledContent("Cycle sizes") {
            HStack(spacing: 10) {
                ForEach(CycleSizesRow.options, id: \.0) { label, v in
                    let key = Int((v * 1000).rounded())
                    Toggle(label, isOn: Binding(get: { sizes.v.contains(key) }, set: { on in
                        if on { sizes.v.insert(key) } else if sizes.v.count > 1 { sizes.v.remove(key) }
                        Prefs.d.set(sizes.v.sorted().map { Double($0) / 1000 }, forKey: K.cycleSizes)
                    }))
                    .toggleStyle(.checkbox)
                }
            }
        }
    }
}

// MARK: Shortcuts

/// Click to record; Esc cancels; ⌫ clears. A shortcut used by another action moves here.
struct ShortcutField: View {
    let action: Action
    @ObservedObject var watcher: PrefsWatcher
    @ObservedObject var note: Box<String>
    @StateObject private var recording = Box(false)
    @StateObject private var monitor = Box<Any?>(nil)

    var body: some View {
        let current = Prefs.shortcut(action)
        HStack(spacing: 4) {
            Button {
                recording.v ? stop() : start()
            } label: {
                Text(recording.v ? "Type…" : current.map(KeyName.display) ?? "Record")
                    .foregroundStyle(current == nil && !recording.v ? .secondary : .primary)
                    .monospacedDigit()
                    .frame(minWidth: 76)
            }
            .focusable(false)
            .help("Click, then press the new shortcut. Esc cancels, ⌫ clears.")
            // Always laid out so every recorder lines up; hidden when there's nothing to clear.
            Button { Prefs.setShortcut(nil, for: action) } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .help("Remove shortcut")
            .opacity(current != nil && !recording.v ? 1 : 0)
            .disabled(current == nil || recording.v)
        }
        .onDisappear { if recording.v { stop() } }
    }

    private func start() {
        recording.v = true
        NotificationCenter.default.post(name: .moveRecording, object: true)
        monitor.v = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let mods = e.modifierFlags.intersection(Shortcut.relevant)
            if e.keyCode == 53, mods.isEmpty { stop(); return nil }                        // Esc
            if e.keyCode == 51 || e.keyCode == 117, mods.isEmpty {                          // ⌫ ⌦
                Prefs.setShortcut(nil, for: action); stop(); return nil
            }
            let s = Shortcut(keyCode: Int(e.keyCode), modifiers: mods)
            if let taken = Prefs.setShortcut(s, for: action) {
                note.v = "\(KeyName.display(s)) moved from \(taken.title) to \(action.title)."
            } else {
                note.v = ""
            }
            stop()
            return nil
        }
    }

    private func stop() {
        if let m = monitor.v { NSEvent.removeMonitor(m) }
        monitor.v = nil
        recording.v = false
        NotificationCenter.default.post(name: .moveRecording, object: false)
    }
}

struct ShortcutsTab: View {
    @StateObject private var watcher = PrefsWatcher()
    @StateObject private var note = Box("")

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Button("Restore Defaults") { Prefs.resetShortcuts(); note.v = "" }
                } label: {
                    Text("Shortcuts")
                    Text(note.v.isEmpty ? "Defaults: ⌃⌥⌘ + arrows, ↩ ' C \\ 1–4 [ ]." : note.v)
                }
            }
            ForEach(Action.Group.allCases, id: \.self) { g in
                Section(g.rawValue) {
                    ForEach(Action.allCases.filter { $0.group == g }, id: \.self) { a in
                        LabeledContent(a.title) { ShortcutField(action: a, watcher: watcher, note: note) }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Layout

struct LayoutTab: View {
    @StateObject private var watcher = PrefsWatcher()
    @AppStorage(K.gapsOnMaximize, store: Prefs.d) private var gapsOnMaximize = true
    @AppStorage(K.centerHalfCycles, store: Prefs.d) private var centerHalfCycles = false
    @AppStorage(K.repeatedMaximizeRestores, store: Prefs.d) private var maximizeRestores = false
    @AppStorage(K.centerOnEdgeMove, store: Prefs.d) private var centeredMove = true

    private func percent(_ key: String) -> Binding<Double> {
        Binding(get: { (Prefs.d.double(forKey: key) * 100).rounded() }, set: { Prefs.d.set($0 / 100, forKey: key) })
    }

    var body: some View {
        Form {
            Section("Gaps") {
                StepperRow(title: "Between windows", value: defaultsBinding(K.gap), range: 0...100)
                Toggle("Gaps around maximized windows", isOn: $gapsOnMaximize)
            }
            Section("Almost Maximize") {
                StepperRow(title: "Width", value: percent(K.almostWidth), range: 50...100, unit: "%")
                StepperRow(title: "Height", value: percent(K.almostHeight), range: 50...100, unit: "%")
            }
            Section("Larger & Smaller") {
                StepperRow(title: "Step", value: defaultsBinding(K.sizeStep), range: 5...300, step: 5)
                StepperRow(title: "Width step", subtitle: "Larger Width and Smaller Width.",
                           value: defaultsBinding(K.widthStep), range: 5...300, step: 5)
            }
            Section("Specified Size") {
                StepperRow(title: "Width", value: defaultsBinding(K.specifiedWidth), range: 200...8000, step: 10)
                StepperRow(title: "Height", value: defaultsBinding(K.specifiedHeight), range: 200...8000, step: 10)
            }
            Section("Behaviour") {
                Toggle(isOn: $centerHalfCycles) {
                    Text("Center Half cycles sizes")
                    Text("Pressing it again goes ½ → ⅔ → ⅓.")
                }
                Toggle(isOn: $maximizeRestores) {
                    Text("Maximize again to restore")
                    Text("Also for Almost Maximize.")
                }
                Toggle(isOn: $centeredMove) {
                    Text("Center when moving to an edge")
                    Text("Move Left/Right centers vertically, Up/Down horizontally.")
                }
            }
        }
        .formStyle(.grouped)
        .id(watcher.tick)
    }
}

// MARK: Apps

/// Shortcuts pause while one of these apps is frontmost.
struct AppsTab: View {
    @StateObject private var watcher = PrefsWatcher()
    @StateObject private var selection = Box<String?>(nil)

    struct AppInfo: Identifiable { let id: String; let name: String; let icon: NSImage?; let installed: Bool }

    static func info(_ bundle: String) -> AppInfo {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            return AppInfo(id: bundle, name: name, icon: NSWorkspace.shared.icon(forFile: url.path), installed: true)
        }
        return AppInfo(id: bundle, name: bundle, icon: nil, installed: false)
    }

    var body: some View {
        let apps = Prefs.ignoredApps.sorted().map(AppsTab.info).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        Form {
            Section {
                List(selection: $selection.v) {
                    ForEach(apps) { app in
                        HStack(spacing: 8) {
                            if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
                            else { Image(systemName: "app.dashed").frame(width: 18, height: 18) }
                            Text(app.name)
                            Spacer()
                            Text(app.installed ? app.id : "Not installed").foregroundStyle(.secondary).font(.callout)
                        }
                        .tag(app.id)
                    }
                }
                .frame(height: 150)
                .overlay { if apps.isEmpty { Text("No ignored apps").foregroundStyle(.secondary) } }
                HStack(spacing: 0) {
                    Menu {
                        let running = NSWorkspace.shared.runningApplications
                            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil
                                && $0.bundleIdentifier != Bundle.main.bundleIdentifier
                                && !Prefs.ignoredApps.contains($0.bundleIdentifier!) }
                            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
                        ForEach(running, id: \.processIdentifier) { app in
                            Button(app.localizedName ?? app.bundleIdentifier!) {
                                Prefs.ignoredApps.insert(app.bundleIdentifier!)
                            }
                        }
                        Divider()
                        Button("Other…") { pickApp() }
                    } label: { Image(systemName: "plus") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .padding(.horizontal, 6)
                    Button { if let s = selection.v { Prefs.ignoredApps.remove(s); selection.v = nil } } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.borderless).disabled(selection.v == nil)
                    .padding(.horizontal, 6)
                    Spacer()
                }
            } header: {
                Text("Ignored Apps")
            } footer: {
                Text("Move's shortcuts are off while one of these apps is in front.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .id(watcher.tick)
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        Prefs.ignoredApps.insert(id)
    }
}

// MARK: Advanced

struct AdvancedTab: View {
    @StateObject private var watcher = PrefsWatcher()
    @AppStorage(K.moveCursorAcrossDisplays, store: Prefs.d) private var cursorAcross = false
    @AppStorage(K.moveCursor, store: Prefs.d) private var cursorAlways = false

    var body: some View {
        Form {
            Section("Screen Edge Gaps") {
                StepperRow(title: "Top", value: defaultsBinding(K.edgeTop), range: 0...300)
                StepperRow(title: "Bottom", value: defaultsBinding(K.edgeBottom), range: 0...300)
                StepperRow(title: "Left", value: defaultsBinding(K.edgeLeft), range: 0...300)
                StepperRow(title: "Right", value: defaultsBinding(K.edgeRight), range: 0...300)
            }
            Section("Cursor") {
                Toggle("Follow a window to another display", isOn: $cursorAcross)
                Toggle("Center on the window after every action", isOn: $cursorAlways)
            }
            Section("Privacy") {
                LabeledContent("Network") { Text(NoNetwork.active ? "Blocked by the kernel" : "Not blocked, see Console") }
                LabeledContent("Updates & analytics") { Text("None") }
                LabeledContent("Permissions") { Text("Accessibility only") }
                LabeledContent("Data") { Text("Settings on this Mac only") }
            }
            Section("Scripting") {
                LabeledContent("URL") {
                    Text("move://execute-action?name=left-half").font(.callout.monospaced()).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .id(watcher.tick)
    }
}
