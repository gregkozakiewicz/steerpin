import AppKit
import Carbon.HIToolbox
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let hotKeys = HotKeys()
    private let hud = HUD()
    private var unavailable: Set<MarkType> = []
    private var recent: [Mark] = []
    private var accessTimer: Timer?
    private var pluginState: ClaudeCode.PluginState?
    private var connecting = false
    private var undoAvailable = true
    private var copyAvailable = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        for (index, type) in MarkType.allCases.enumerated() {
            let ok = hotKeys.register(id: UInt32(index + 1), keyCode: type.keyCode) { [weak self] in
                // Let the hotkey's own key events settle before sending ⌘C.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self?.capture(type) }
            }
            if !ok { unavailable.insert(type) }
        }
        undoAvailable = hotKeys.register(id: 99, keyCode: UInt32(kVK_ANSI_Z)) { [weak self] in
            self?.undoLastMark()
        }
        copyAvailable = hotKeys.register(id: 98, keyCode: UInt32(kVK_ANSI_C)) { [weak self] in
            self?.copySteering()
        }

        ClaudeCode.forgetOldUpdateChecks()

        // The app used to keep its own copy lists; the project files replaced them.
        try? FileManager.default.removeItem(at: Inbox.folder.appendingPathComponent("chat-marks.json"))

        updateIcon()
        if Selection.hasAccess {
            offerToConnect()
        } else {
            Selection.requestAccess()
            watchForAccess()
        }
        refreshPluginState()
    }

    /// Opening Steerpin again (Finder, Spotlight) while it runs: a way in when the menu bar hides the pin.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Steerpin is running"
        alert.informativeText = """
            Look for the pin in your menu bar. If you can't see it, macOS is hiding it: \
            either the menu bar is full, or Steerpin is switched off in System Settings › Menu Bar.
            """
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Menu Bar Settings")
        alert.addButton(withTitle: "Quit Steerpin")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!)
        case .alertThirdButtonReturn:
            NSApp.terminate(nil)
        default:
            break
        }
        return false
    }

    // MARK: Marking

    private func capture(_ type: MarkType) {
        guard Selection.hasAccess else {
            flash(symbol: "exclamationmark.triangle.fill", tint: .systemOrange,
                  title: "Steerpin needs Accessibility access",
                  detail: "Turn on Steerpin in the settings that just opened")
            Selection.openAccessibilitySettings()
            watchForAccess()
            return
        }
        let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        Selection.copy { [weak self] text in
            guard let self else { return }
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.flash(symbol: "text.cursor", tint: .secondaryLabelColor,
                           title: "No text selected", detail: "Select some text, then press \(type.shortcut)")
                return
            }
            let mark = Mark(type: type, text: text, date: Date())
            do {
                try Inbox.append(mark, sourceApp: sourceApp)
            } catch {
                self.flash(symbol: "xmark.octagon.fill", tint: .systemRed,
                           title: "Couldn't save the mark", detail: error.localizedDescription)
                return
            }
            self.recent.insert(mark, at: 0)
            self.recent = Array(self.recent.prefix(10))
            self.flash(symbol: type.symbol, tint: self.tint(type), title: type.confirmation, detail: text)
        }
    }

    @objc private func undoLastMark() {
        guard let removed = Inbox.removeLast() else {
            flash(symbol: "arrow.uturn.backward.circle.fill", tint: .secondaryLabelColor,
                  title: "Nothing waiting to undo",
                  detail: "Already sent to Claude? Run /steerpin:undo in Claude Code")
            return
        }
        if let index = recent.firstIndex(where: { $0.type == removed.type && $0.text == removed.text }) {
            recent.remove(at: index)
        }
        flash(symbol: "arrow.uturn.backward.circle.fill", tint: .systemOrange,
              title: "Undid \(removed.type.name.lowercased()) mark", detail: removed.text)
    }

    // MARK: Projects

    /// ⌥⇧C copies from the project Claude Code worked in last.
    @objc private func copySteering() {
        guard let project = Project.latest else {
            flash(symbol: "doc.on.clipboard", tint: .secondaryLabelColor, title: "Nothing to copy",
                  detail: "Send a message in Claude Code first")
            return
        }
        copy(.steering, from: project)
    }

    private func project(for sender: NSMenuItem) -> Project? {
        guard let path = sender.representedObject as? String else { return nil }
        return Project.recent(limit: 20).first { $0.project == path } ?? (Project.latest?.project == path ? Project.latest : nil)
    }

    @objc private func copyFromMenu(_ sender: NSMenuItem) {
        guard let project = project(for: sender) else { return }
        let lists: [Project.List] = [.steering, .saved, .roadmap]
        copy(lists[sender.tag], from: project)
    }

    private func copy(_ list: Project.List, from project: Project) {
        let name: String
        switch list {
        case .steering: name = "priority and wrong mark"
        case .saved: name = "saved mark"
        case .roadmap: name = "roadmap mark"
        }
        guard let block = project.block(list) else {
            flash(symbol: "doc.on.clipboard", tint: .secondaryLabelColor, title: "Nothing to copy",
                  detail: "No \(name)s in \(project.name)")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(block, forType: .string)
        let n = project.count(list)
        flash(symbol: "doc.on.clipboard.fill", tint: .systemBlue,
              title: "Copied \(n) \(name)\(n == 1 ? "" : "s")", detail: "From \(project.name). Paste anywhere with ⌘V")
    }

    @objc private func openMarksFile(_ sender: NSMenuItem) {
        project(for: sender)?.openMarksFile()
    }

    @objc private func clearFromMenu(_ sender: NSMenuItem) {
        guard let project = project(for: sender) else { return }
        let n = project.count(.steering)
        let alert = NSAlert()
        alert.messageText = "Clear \(n) mark\(n == 1 ? "" : "s") from \(project.name)?"
        alert.informativeText = "Claude stops receiving your priority and wrong marks. Roadmap and saved marks stay. You can undo this from the menu until you do the next clear."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let cleared = project.clearSteering()
        flash(symbol: "trash.circle.fill", tint: .secondaryLabelColor,
              title: "Cleared \(cleared) mark\(cleared == 1 ? "" : "s")",
              detail: "From \(project.name). Undo from the menu if you need them back.")
    }

    @objc private func undoClearFromMenu(_ sender: NSMenuItem) {
        guard let project = project(for: sender) else { return }
        project.undoClear()
        flash(symbol: "arrow.uturn.backward.circle.fill", tint: .systemOrange, title: "Marks restored",
              detail: "\(project.count(.steering)) priority and wrong marks in \(project.name)")
    }

    private func projectMenu(_ project: Project) -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false
        let where_ = [project.displayPath, project.lastUsedText].filter { !$0.isEmpty }.joined(separator: " · ")
        sub.addItem(info(where_))
        let entries: [(String, Project.List)] = [
            ("Copy Priority and Wrong Marks", .steering), ("Copy Saved Marks", .saved), ("Copy Roadmap Marks", .roadmap),
        ]
        for (index, (title, list)) in entries.enumerated() {
            let n = project.count(list)
            let entry = item(n == 0 ? title : "\(title) (\(n))", #selector(copyFromMenu(_:)))
            entry.tag = index
            entry.representedObject = project.project
            entry.isEnabled = n > 0
            if list == .steering, project.isLatest, copyAvailable { shortcut(entry, UInt32(kVK_ANSI_C)) }
            sub.addItem(entry)
        }
        sub.addItem(.separator())
        let open = item("Open Marks File", #selector(openMarksFile(_:)))
        open.representedObject = project.project
        sub.addItem(open)
        sub.addItem(.separator())
        let steering = project.count(.steering)
        let clear = item("Clear Priority and Wrong Marks…", #selector(clearFromMenu(_:)))
        clear.representedObject = project.project
        clear.isEnabled = steering > 0
        if steering > 0 {
            clear.attributedTitle = NSAttributedString(string: clear.title, attributes: [
                .foregroundColor: NSColor.systemRed, .font: NSFont.menuFont(ofSize: 0),
            ])
        }
        sub.addItem(clear)
        if project.canUndoClear {
            let undo = item("Undo Clear", #selector(undoClearFromMenu(_:)))
            undo.representedObject = project.project
            sub.addItem(undo)
        }
        return sub
    }

    /// "steerpin        3 marks", with the count right-aligned and dimmed.
    private func projectTitle(_ project: Project) -> NSAttributedString {
        let n = project.count(.steering)
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .right, location: 230)]
        let title = NSMutableAttributedString(string: project.name, attributes: [
            .font: NSFont.menuFont(ofSize: 0), .paragraphStyle: style,
        ])
        let status = n > 0 ? "\(n) mark\(n == 1 ? "" : "s")" : (project.canUndoClear ? "cleared" : "")
        if !status.isEmpty {
            title.append(NSAttributedString(string: "\t\(status)", attributes: [
                .font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: style,
            ]))
        }
        return title
    }

    private func tint(_ type: MarkType) -> NSColor {
        switch type {
        case .priority: return .systemBlue
        case .wrong: return .systemRed
        case .roadmap: return .systemGreen
        case .later: return .systemPurple
        }
    }

    private func flash(symbol: String, tint: NSColor, title: String, detail: String) {
        let anchor = statusItem.button?.window?.frame
        hud.show(symbol: symbol, tint: tint, title: title, detail: detail, below: anchor)
    }

    // MARK: Accessibility

    private func watchForAccess() {
        accessTimer?.invalidate()
        accessTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard Selection.hasAccess else { return }
            timer.invalidate()
            self?.updateIcon()
            self?.flash(symbol: "checkmark.circle.fill", tint: .systemGreen, title: "Steerpin is ready",
                        detail: "Select text and press ⌥⇧R, ⌥⇧W, ⌥⇧A or ⌥⇧S")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.offerToConnect() }
        }
    }

    // MARK: Claude Code

    /// Checking runs a shell once to find `claude`, so it happens off the main thread.
    private func refreshPluginState(then next: ((ClaudeCode.PluginState) -> Void)? = nil) {
        DispatchQueue.global(qos: .utility).async {
            ClaudeCode.refreshPublishedVersion()
            let state = ClaudeCode.state()
            DispatchQueue.main.async {
                self.pluginState = state
                next?(state)
            }
        }
    }

    /// Asks whether to install the Claude Code plugin (once per app version),
    /// or to update it (once per newly published plugin version).
    private func offerToConnect() {
        refreshPluginState { [weak self] state in
            guard let self else { return }
            let alert = NSAlert()
            let key: String
            switch state {
            case .notInstalled:
                key = "offeredConnect-\(ClaudeCode.appVersion)"
                alert.messageText = "Connect Steerpin to Claude Code?"
                alert.informativeText = "This installs the Steerpin plugin, which gives your marks to Claude with every message."
                alert.addButton(withTitle: "Connect")
            case .outdated(let installed, let available):
                key = "offeredUpdate-\(available)"
                alert.messageText = "Update the Claude Code plugin?"
                alert.informativeText = "Steerpin plugin \(available) is available. You have \(installed)."
                alert.addButton(withTitle: "Update")
            default:
                return
            }
            guard !UserDefaults.standard.bool(forKey: key) else { return }
            alert.addButton(withTitle: "Not Now")
            UserDefaults.standard.set(true, forKey: key)
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn { self.connectClaudeCode() }
        }
    }

    @objc private func connectClaudeCode() {
        guard !connecting else { return }
        connecting = true
        flash(symbol: "arrow.triangle.2.circlepath", tint: .systemBlue,
              title: "Connecting to Claude Code…", detail: "Installing the Steerpin plugin")
        ClaudeCode.connect { [weak self] ok, message in
            guard let self else { return }
            self.connecting = false
            self.refreshPluginState()
            if ok {
                self.flash(symbol: "checkmark.circle.fill", tint: .systemGreen,
                           title: "Connected to Claude Code", detail: message)
            } else {
                self.flash(symbol: "xmark.octagon.fill", tint: .systemRed,
                           title: "Couldn't connect to Claude Code", detail: message)
            }
        }
    }

    @objc private func showConnection() {
        flash(symbol: "checkmark.circle.fill", tint: .systemGreen, title: "Connected to Claude Code",
              detail: "Steerpin plugin \(ClaudeCode.installedVersion ?? "") is installed")
    }

    @objc private func getClaudeCode() {
        NSWorkspace.shared.open(URL(string: "https://code.claude.com")!)
    }

    private func updateIcon() {
        let name = Selection.hasAccess ? "pin.fill" : "pin.slash"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Steerpin")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateIcon()
        if !connecting, pluginState != nil {
            pluginState = ClaudeCode.state()
            refreshPluginState() // checks GitHub at most once an hour; the result shows next time
        }
        menu.removeAllItems()

        if !Selection.hasAccess {
            menu.addItem(item("Allow Accessibility Access…", #selector(grantAccess)))
            menu.addItem(info("Steerpin needs it to copy your selection."))
            menu.addItem(.separator())
        }

        let pending = Inbox.pendingCount()
        menu.addItem(header("Select text, then click or press"))
        for type in MarkType.allCases {
            let suffix = unavailable.contains(type) ? " (shortcut used by another app)" : ""
            let entry = item("\(type.name)\(suffix)", #selector(markFromMenu(_:)))
            entry.representedObject = type.rawValue
            entry.image = NSImage(systemSymbolName: type.symbol, accessibilityDescription: nil)
            if !unavailable.contains(type) { shortcut(entry, type.keyCode) }
            menu.addItem(entry)
        }
        let undoEntry = item("Undo Last Mark", #selector(undoLastMark))
        undoEntry.image = NSImage(systemSymbolName: "arrow.uturn.backward.circle.fill", accessibilityDescription: nil)
        undoEntry.isEnabled = pending > 0
        if undoAvailable { shortcut(undoEntry, UInt32(kVK_ANSI_Z)) }
        menu.addItem(undoEntry)

        menu.addItem(.separator())
        menu.addItem(info(pending == 0
            ? "No marks waiting"
            : "\(pending) mark\(pending == 1 ? "" : "s") waiting for your next message"))

        let recentItem = NSMenuItem(title: "Recent Marks", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu()
        if recent.isEmpty {
            recentMenu.addItem(info("Nothing marked yet"))
        } else {
            for mark in recent {
                let preview = mark.text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                let entry = info(preview.count > 60 ? String(preview.prefix(57)) + "…" : preview)
                entry.image = NSImage(systemSymbolName: mark.type.symbol, accessibilityDescription: nil)
                recentMenu.addItem(entry)
            }
        }
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)

        menu.addItem(.separator())
        menu.addItem(header("Projects"))
        let projects = Project.recent()
        if projects.isEmpty {
            menu.addItem(info(Project.latest == nil ? "Send a message in Claude Code first" : "No marks yet"))
        }
        for project in projects {
            let entry = NSMenuItem(title: project.name, action: nil, keyEquivalent: "")
            entry.attributedTitle = projectTitle(project)
            entry.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            entry.submenu = projectMenu(project)
            menu.addItem(entry)
        }


        menu.addItem(.separator())
        menu.addItem(header("Claude Code"))
        switch pluginState {
        case _ where connecting:
            menu.addItem(info("Connecting…"))
        case .connected:
            let entry = item("Connected", #selector(showConnection))
            let config = NSImage.SymbolConfiguration(paletteColors: [.white, .systemGreen])
            entry.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            menu.addItem(entry)
        case .notInstalled:
            menu.addItem(item("Connect to Claude Code", #selector(connectClaudeCode)))
        case .outdated(let installed, let available):
            menu.addItem(item("Update Plugin (\(installed) → \(available))", #selector(connectClaudeCode)))
        case .noCLI:
            menu.addItem(info("Claude Code not found"))
            menu.addItem(item("Get Claude Code…", #selector(getClaudeCode)))
        case nil:
            menu.addItem(info("Checking…"))
        }

        menu.addItem(.separator())
        let login = item("Launch at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(item("Show Steerpin Folder", #selector(openInbox)))
        menu.addItem(item("Steerpin on GitHub", #selector(openGitHub)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Steerpin \(ClaudeCode.appVersion)", #selector(quit), key: "q"))
    }

    /// Shows ⌥⇧<key> at the right edge of a menu item.
    private func shortcut(_ item: NSMenuItem, _ keyCode: UInt32) {
        let letters: [UInt32: String] = [UInt32(kVK_ANSI_R): "r", UInt32(kVK_ANSI_W): "w", UInt32(kVK_ANSI_A): "a",
                                         UInt32(kVK_ANSI_S): "s", UInt32(kVK_ANSI_Z): "z", UInt32(kVK_ANSI_C): "c"]
        item.keyEquivalent = letters[keyCode] ?? ""
        item.keyEquivalentModifierMask = [.option, .shift]
    }

    /// Marking from the menu: the menu doesn't take focus, so the selection is still there once it closes.
    @objc private func markFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let type = MarkType(rawValue: raw) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.capture(type) }
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func header(_ title: String) -> NSMenuItem {
        if #available(macOS 14.0, *) { return .sectionHeader(title: title) }
        return info(title)
    }

    @objc private func grantAccess() {
        Selection.requestAccess()
        Selection.openAccessibilitySettings()
        watchForAccess()
    }

    @objc private func openInbox() {
        try? FileManager.default.createDirectory(at: Inbox.folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Inbox.folder)
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            flash(symbol: "xmark.octagon.fill", tint: .systemRed,
                  title: "Couldn't change Launch at Login", detail: error.localizedDescription)
        }
    }

    @objc private func openGitHub() {
        NSWorkspace.shared.open(URL(string: "https://github.com/gregkozakiewicz/steerpin")!)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
