import SwiftUI
import AppKit

// MARK: - Menu bar controller (left click: popover panel / right click: menu)

final class MenuBarController: NSObject {
    private let item: NSStatusItem
    private let state: AppState
    private var timer: Timer?
    private let statusMenu = NSMenu()
    private var popover: NSPopover?

    init(state: AppState) {
        self.state = state
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let speedItem = NSMenuItem(title: "监控中…", action: nil, keyEquivalent: "")
        speedItem.isEnabled = false
        statusMenu.addItem(speedItem)
        statusMenu.addItem(.separator())

        let open = NSMenuItem(title: "打开 NetGlass", action: #selector(openMain), keyEquivalent: "o")
        open.target = self
        statusMenu.addItem(open)

        let pause = NSMenuItem(title: "暂停监控", action: #selector(togglePause), keyEquivalent: "p")
        pause.target = self
        statusMenu.addItem(pause)

        statusMenu.addItem(.separator())
        let quit = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        statusMenu.addItem(quit)
        statusMenu.delegate = self

        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.updateTitle() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        updateTitle()
    }

    @objc private func statusItemClicked() {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            item.menu = statusMenu
            item.button?.performClick(nil)
            item.menu = nil
            return
        }
        togglePopover()
    }

    private func togglePopover() {
        if let p = popover, p.isShown {
            p.performClose(nil)
            return
        }
        let p = NSPopover()
        p.behavior = .transient
        let vc = NSHostingController(rootView: MenuBarPanel().environmentObject(state))
        vc.sizingOptions = .preferredContentSize   // SwiftUI content sizes the popover
        p.contentViewController = vc
        if let button = item.button {
            p.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        popover = p
    }

    func updateTitle() {
        item.isVisible = state.settings.showMenuBarIcon
        guard state.settings.showMenuBarIcon else { return }
        let d = state.paused ? "已暂停" : compact(state.liveDown)
        let u = state.paused ? "" : compact(state.liveUp)
        item.button?.title = " ⇩ \(d)  ⇧ \(u)"
    }

    private func compact(_ v: Double) -> String {
        if v < 0.5 { return "0" }
        let kb = v / 1024
        if kb < 1024 { return String(format: "%.0fK", kb) }
        return String(format: "%.1fM", kb / 1024)
    }

    @objc private func openMain() {
        popover?.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let win = NSApp.windows.first(where: { $0.canBecomeMain }) {
            win.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func togglePause() {
        state.togglePause()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension MenuBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        if let speedItem = menu.items.first {
            speedItem.title = "⬇︎ \(Fmt.speed(state.liveDown))   ⬆︎ \(Fmt.speed(state.liveUp))"
        }
        if menu.items.count > 3 {
            menu.items[3].title = state.paused ? "继续监控" : "暂停监控"
        }
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    private var menuBar: MenuBarController?
    private var started = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        menuBar = MenuBarController(state: state)
        startOnce()
    }

    func startOnce() {
        guard !started else { return }
        started = true
        state.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

// MARK: - Entry

@main
struct NetGlassApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(delegate.state)
                .frame(minWidth: 1150, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
