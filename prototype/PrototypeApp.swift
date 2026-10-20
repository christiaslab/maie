import AppKit
import SwiftUI

/// Banner adapter that posts through osascript's `display notification`.
/// UNUserNotificationCenter denies authorization to this ad-hoc signed bundle
/// without a prompt (UNErrorDomain code 1), so the prototype goes through the
/// script bridge instead: the banner plays the default sound, is listed under
/// Script Editor in System Settings > Notifications, cannot be withdrawn and
/// does not open Maie when clicked.
@MainActor final class SystemQuestionNotificationCenter: QuestionNotificationCenter {
    func requestBannerAuthorization() {
        // osascript needs no app authorization. The banner is listed under Script
        // Editor in System Settings > Notifications, where the owner can silence it.
    }

    func post(identifier: String, title: String, body: String) {
        // Title and body travel as argv and are read with `on run argv`. They are
        // never interpolated into the script text: the body carries a session
        // label, which is untrusted data.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e", "on run argv",
            "-e", "display notification (item 2 of argv) with title (item 1 of argv) sound name \"default\"",
            "-e", "end run",
            title, body
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() }
        catch { NSLog("Maie: osascript banner for %@ failed to launch: %@", identifier, error.localizedDescription) }
    }

    func remove(identifiers: [String]) {
        // osascript banners cannot be withdrawn; Notification Center keeps them
        // until the owner clears them.
    }
}

final class ThinkingPanel: NSWindow {
    func configureChrome() {
        isOpaque = false
        backgroundColor = .clear
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        styleMask.insert(.fullSizeContentView)
        let bar = NSToolbar(identifier: "MaieWindowToolbar")
        bar.showsBaselineSeparator = false
        toolbar = bar
        toolbarStyle = .unified

    }

    static let minimumFrameSize = NSSize(width: 400, height: 520)
    static let maximumFrameSize = NSSize(width: 1200, height: 1600)

    /// Sets the frame limits. AppKit adds the toolbar height to minSize and
    /// maxSize although the full-size content view already covers the toolbar,
    /// so the measured excess is taken back off.
    func applySizeLimits() {
        minSize = Self.minimumFrameSize
        maxSize = Self.maximumFrameSize
        let toolbarExcess = minSize.height - Self.minimumFrameSize.height
        guard toolbarExcess > 0 else { return }
        minSize.height = Self.minimumFrameSize.height - toolbarExcess
        maxSize.height = Self.maximumFrameSize.height - toolbarExcess
    }

    // NSHostingView rewrites the window's content min/max size from the SwiftUI
    // layout on every constraint pass, whatever its sizingOptions, which would
    // replace the limits above. The panel keeps the limits from applySizeLimits.
    override var contentMinSize: NSSize { get { super.contentMinSize } set {} }
    override var contentMaxSize: NSSize { get { super.contentMaxSize } set {} }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor final class PrototypeDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation, NSMenuDelegate {
    private let connection = OpenAIConnection()
    private lazy var store = SessionStore(connection: connection)
    private let notifier = QuestionNotifier(center: SystemQuestionNotificationCenter())
    private var panel: ThinkingPanel!
    private var statusItem: NSStatusItem!
    private var discussionGrowth: (from: CGFloat, to: CGFloat)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        do { try store.start() }
        catch {
            let alert = NSAlert(); alert.messageText = "Maie could not start"; alert.informativeText = error.localizedDescription
            alert.runModal(); NSApp.terminate(nil); return
        }
        configureMenus()
        notifier.requestAuthorization()

        panel = ThinkingPanel(contentRect: NSRect(x: 0, y: 0, width: 430, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        panel.configureChrome()
        panel.title = "Maie"
        panel.setAccessibilityLabel("Maie window")
        panel.isReleasedWhenClosed = false
        panel.level = .normal
        panel.collectionBehavior = [.fullScreenPrimary]
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.delegate = self

        let view = PrototypeView(store: store, connection: connection,
                                 resize: { [weak self] expanded in self?.resize(expanded: expanded) })
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .ignoresSafeArea(.container, edges: .top)

        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.applySizeLimits()
        store.onPendingQuestionsChange = { [weak self] in
            self?.updatePendingIndicator()
            self?.reconcileNotifications()
        }
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

    /// One banner per new live set, none while Maie is active and showing (the
    /// in-app notice covers that). A set that stops being pending is forgotten;
    /// its osascript banner stays in Notification Center.
    private func reconcileNotifications() {
        let showing = NSApp.isActive && panel != nil && panel.isVisible
        notifier.reconcile(store.pendingQuestions, windowVisible: showing)
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
    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
        notifier.reconcile([], windowVisible: false)
    }

    private func resize(expanded: Bool) {
        guard panel != nil else { return }
        let bounds = (panel.screen ?? NSScreen.main)?.visibleFrame ?? panel.frame
        var frame = panel.frame
        let height: CGFloat
        if expanded {
            // Grow a compact window for discussion; never shrink a size the person chose.
            let target = min(780.0, bounds.height - 24)
            guard frame.height < target else { discussionGrowth = nil; return }
            discussionGrowth = (frame.height, target); height = target
        } else {
            // Undo only Maie's own growth, and only if the window was not resized since.
            guard let growth = discussionGrowth, abs(frame.height - growth.to) < 1 else { discussionGrowth = nil; return }
            discussionGrowth = nil; height = growth.from
        }
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
    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
        WindowZoom.standardFrame(proposed: newFrame, maxSize: window.maxSize)
    }
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
