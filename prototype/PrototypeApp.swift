import AppKit
import SwiftUI

final class ThinkingPanel: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor final class PrototypeDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation, NSMenuDelegate {
    private let connection = OpenAIConnection()
    private lazy var store = SessionStore(connection: connection)
    private var panel: ThinkingPanel!
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        do { try store.start() }
        catch {
            let alert = NSAlert(); alert.messageText = "Maie could not start"; alert.informativeText = error.localizedDescription
            alert.runModal(); NSApp.terminate(nil); return
        }
        configureMenus()

        panel = ThinkingPanel(contentRect: NSRect(x: 0, y: 0, width: 430, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        panel.title = "Maie"
        panel.setAccessibilityLabel("Maie window")
        panel.isReleasedWhenClosed = false
        panel.level = .normal
        panel.collectionBehavior = [.fullScreenPrimary]
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.minSize = NSSize(width: 400, height: 520)
        panel.maxSize = NSSize(width: 1200, height: 1600)
        panel.delegate = self

        let view = PrototypeView(store: store, connection: connection,
                                 resize: { [weak self] expanded in self?.resize(expanded: expanded) })

        panel.contentView = NSHostingView(rootView: view)
        store.onPendingQuestionsChange = { [weak self] in self?.updatePendingIndicator() }
        updatePendingIndicator()

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
        appMenu.addItem(item("Close Window", #selector(closeWindow), "w"))
        appMenu.addItem(item("Minimize", #selector(minimizeWindow), "m"))
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

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "leaf", accessibilityDescription: "Maie")
        statusItem.button?.toolTip = "Maie"
        let statusMenu = NSMenu()
        statusMenu.delegate = self
        statusItem.menu = statusMenu
    }

    private func updatePendingIndicator() {
        let count = store.pendingQuestions.count
        let label = count == 0 ? "Waiting for Claude" : "\(count) pending question set\(count == 1 ? "" : "s")"
        statusItem.button?.title = count == 0 ? "" : " •"
        statusItem.button?.toolTip = "Maie · " + label
        statusItem.button?.setAccessibilityLabel("Maie · " + label)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let pending = store.pendingQuestions
        let summary = NSMenuItem(title: pending.isEmpty ? "Waiting for Claude" : "\(pending.count) pending question set\(pending.count == 1 ? "" : "s")",
                                 action: nil, keyEquivalent: "")
        menu.addItem(summary)
        for target in pending {
            let entry = item("\(target.title)", #selector(openPendingQuestion(_:)), "")
            entry.toolTip = "\(target.count) question\(target.count == 1 ? "" : "s") waiting"
            entry.representedObject = target
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        menu.addItem(item("Show Maie", #selector(show), ""))
        menu.addItem(item("Quit Maie", #selector(quit), "q"))
    }

    @objc private func openPendingQuestion(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? QuestionNotice,
              store.showPendingQuestion(target) else { updatePendingIndicator(); return }
        show()
    }

    private func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let result = NSMenuItem(title: title, action: action, keyEquivalent: key)
        result.target = self
        return result
    }

    @objc private func show() {
        keepOnScreen()
        if panel.isMiniaturized { panel.deminiaturize(nil) }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func closeWindow() { panel.performClose(nil) }
    @objc private func minimizeWindow() { panel.performMiniaturize(nil) }

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
