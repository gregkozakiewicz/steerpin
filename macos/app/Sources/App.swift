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

        updateIcon()
        if Selection.hasAccess {
            offerToConnect()
        } else {
            Selection.requestAccess()
            watchForAccess()
        }
        refreshPluginState()
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
            let state = ClaudeCode.state()
            DispatchQueue.main.async {
                self.pluginState = state
                next?(state)
            }
        }
    }

    /// Asks once per app version whether to install or update the Claude Code plugin.
    private func offerToConnect() {
        refreshPluginState { [weak self] state in
            guard let self else { return }
            let key = "offeredConnect-\(ClaudeCode.appVersion)"
            guard !UserDefaults.standard.bool(forKey: key) else { return }
            let alert = NSAlert()
            switch state {
            case .notInstalled:
                alert.messageText = "Connect Steerpin to Claude Code?"
                alert.informativeText = "This installs the Steerpin plugin, which gives your marks to Claude with every message."
                alert.addButton(withTitle: "Connect")
            case .outdated(let installed):
                alert.messageText = "Update the Claude Code plugin?"
                alert.informativeText = "Your Steerpin plugin is version \(installed). This app works best with \(ClaudeCode.appVersion)."
                alert.addButton(withTitle: "Update")
            default:
                return
            }
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
        if !connecting, pluginState != nil { pluginState = ClaudeCode.state() }
        menu.removeAllItems()

        if !Selection.hasAccess {
            menu.addItem(item("Allow Accessibility Access…", #selector(grantAccess)))
            menu.addItem(info("Steerpin needs it to copy your selection."))
            menu.addItem(.separator())
        }

        menu.addItem(header("Select text, then press"))
        for type in MarkType.allCases {
            let suffix = unavailable.contains(type) ? " (used by another app)" : ""
            let entry = info("\(type.shortcut)   \(type.name)\(suffix)")
            entry.image = NSImage(systemSymbolName: type.symbol, accessibilityDescription: nil)
            menu.addItem(entry)
        }

        let undoItem = info("⌥⇧Z   Undo last mark\(undoAvailable ? "" : " (used by another app)")")
        undoItem.image = NSImage(systemSymbolName: "arrow.uturn.backward.circle.fill", accessibilityDescription: nil)
        menu.addItem(undoItem)

        menu.addItem(.separator())
        let pending = Inbox.pendingCount()
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
        let undoAction = item("Undo Last Mark", #selector(undoLastMark))
        undoAction.isEnabled = pending > 0
        menu.addItem(undoAction)
        menu.addItem(item("Open Inbox Folder", #selector(openInbox)))

        menu.addItem(.separator())
        menu.addItem(header("Claude Code"))
        switch pluginState {
        case _ where connecting:
            menu.addItem(info("Connecting…"))
        case .connected:
            let entry = info("Connected")
            entry.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
            menu.addItem(entry)
        case .notInstalled:
            menu.addItem(item("Connect to Claude Code", #selector(connectClaudeCode)))
        case .outdated(let installed):
            menu.addItem(item("Update Plugin (\(installed) → \(ClaudeCode.appVersion))", #selector(connectClaudeCode)))
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
        menu.addItem(item("Steerpin on GitHub", #selector(openGitHub)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Steerpin", #selector(quit), key: "q"))
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
