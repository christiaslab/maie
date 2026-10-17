import AppKit
import SwiftUI

final class ThinkingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor final class PrototypeDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    private let connection = OpenAIConnection()
    private lazy var store = SessionStore(connection: connection)
    private var panel: ThinkingPanel!
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        do { try store.start() }
        catch {
            let alert = NSAlert(); alert.messageText = "Maie could not start"; alert.informativeText = error.localizedDescription
            alert.runModal(); NSApp.terminate(nil); return
        }
        configureMenus()

        panel = ThinkingPanel(contentRect: NSRect(x: 0, y: 0, width: 430, height: 600),
                              styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        panel.title = "Maie"
        panel.setAccessibilityLabel("Maie window")
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.minSize = NSSize(width: 400, height: 520)
        panel.maxSize = NSSize(width: 580, height: 1100)
        panel.delegate = self

        let view = PrototypeView(store: store, connection: connection, hide: { [weak self] in self?.hide() },
                                 resize: { [weak self] expanded in self?.resize(expanded: expanded) })
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.primary.opacity(0.10), lineWidth: 1))
        panel.contentView = NSHostingView(rootView: view)
        store.onQuestion = { [weak self] in self?.show() }

        if !panel.setFrameUsingName("MaiePrototypePanel") {
            let bounds = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            panel.setFrameOrigin(NSPoint(x: bounds.maxX - panel.frame.width - 24,
                                         y: bounds.midY - panel.frame.height / 2))
        }
        panel.setFrameAutosaveName("MaiePrototypePanel")
        keepOnScreen()
        show()
        Task { await connection.restoreModels() }
    }

    private func configureMenus() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(item("Show Maie", #selector(show), "0"))
        appMenu.addItem(item("Discuss", #selector(focusDiscussion), "j"))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Quit Maie", #selector(quit), "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [
            ("Undo", Selector(("undo:")), "z"),
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a")
        ] {
            edit.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
        }
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "leaf", accessibilityDescription: "Maie")
        statusItem.button?.toolTip = "Maie"
        let statusMenu = NSMenu()
        statusMenu.addItem(item("Show Maie", #selector(show), ""))
        statusMenu.addItem(.separator())
        statusMenu.addItem(item("Quit Maie", #selector(quit), "q"))
        statusItem.menu = statusMenu
    }

    private func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let result = NSMenuItem(title: title, action: action, keyEquivalent: key)
        result.target = self
        return result
    }

    @objc private func show() {
        keepOnScreen()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func hide() { panel.orderOut(nil) }
    @objc private func focusDiscussion() {
        guard store.activeRequest != nil else { return }
        show()
        NotificationCenter.default.post(name: .maieFocusDiscussion, object: nil)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action != #selector(focusDiscussion) || store.activeRequest != nil
    }

    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { store.stop() }

    private func resize(expanded: Bool) {
        guard panel != nil else { return }
        let bounds = (panel.screen ?? NSScreen.main)?.visibleFrame ?? panel.frame
        var frame = panel.frame
        let height = min(expanded ? 780.0 : 600.0, bounds.height - 24)
        frame.origin.y += frame.height - height
        frame.size.height = height
        frame.origin.y = min(max(frame.origin.y, bounds.minY + 12), bounds.maxY - height - 12)
        panel.setFrame(frame, display: true, animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    private func keepOnScreen() {
        guard panel != nil else { return }
        let bounds = (panel.screen ?? NSScreen.main)?.visibleFrame ?? panel.frame
        var frame = panel.frame
        frame.size.width = min(frame.width, bounds.width - 24)
        frame.size.height = min(frame.height, bounds.height - 24)
        frame.origin.x = min(max(frame.origin.x, bounds.minX + 12), bounds.maxX - frame.width - 12)
        frame.origin.y = min(max(frame.origin.y, bounds.minY + 12), bounds.maxY - frame.height - 12)
        panel.setFrame(frame, display: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { hide(); return false }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show(); return true
    }
}

@main
struct PrototypeApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = PrototypeDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
