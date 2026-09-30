import AppKit

/// Small confirmation pill under the menu bar icon. Replaces system notifications,
/// so the app needs no notification permission. Apple's Liquid Glass on macOS 26, frosted before.
final class HUD {
    private let panel: NSPanel
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let hint = NSTextField(labelWithString: "")
    private let content = NSView()
    private var hideWork: DispatchWorkItem?

    private let height: CGFloat = 40
    private let hintHeight: CGFloat = 58

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 220, height: height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        icon.symbolConfiguration = .init(pointSize: 15, weight: .semibold)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        hint.font = .systemFont(ofSize: 11.5)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byTruncatingTail

        let text = NSStackView(views: [title, hint])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        let row = NSStackView(views: [icon, text])
        row.spacing = 8
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            row.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            title.widthAnchor.constraint(lessThanOrEqualToConstant: 300),
            hint.widthAnchor.constraint(lessThanOrEqualToConstant: 300),
        ])

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.contentView = content
            panel.contentView = glass
        } else {
            let frosted = NSVisualEffectView()
            frosted.material = .hudWindow
            frosted.state = .active
            frosted.wantsLayer = true
            frosted.addSubview(content)
            content.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: frosted.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: frosted.trailingAnchor),
                content.topAnchor.constraint(equalTo: frosted.topAnchor),
                content.bottomAnchor.constraint(equalTo: frosted.bottomAnchor),
            ])
            panel.contentView = frosted
        }
    }

    /// `hint` is for popups that tell the user what to do next; confirmations are title only.
    func show(symbol: String, tint: NSColor, title: String, hint: String?, below anchor: NSRect?) {
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = tint
        self.title.stringValue = title
        self.hint.stringValue = hint ?? ""
        self.hint.isHidden = hint == nil

        // Size the pill to its text.
        content.layoutSubtreeIfNeeded()
        let textWidth = max(self.title.intrinsicContentSize.width, hint == nil ? 0 : self.hint.intrinsicContentSize.width)
        let size = NSSize(width: min(max(14 + 15 + 8 + textWidth + 16, 160), 360), height: hint == nil ? height : hintHeight)
        let radius = hint == nil ? size.height / 2 : 18
        if #available(macOS 26.0, *), let glass = panel.contentView as? NSGlassEffectView {
            glass.cornerRadius = radius
        } else if let frosted = panel.contentView {
            frosted.layer?.cornerRadius = radius
            frosted.layer?.masksToBounds = true
        }

        let screen = NSScreen.main?.visibleFrame ?? .zero
        var origin = NSPoint(x: screen.maxX - size.width - 12, y: screen.maxY - size.height - 8)
        if let anchor {
            origin.x = min(max(anchor.midX - size.width / 2, screen.minX + 8), screen.maxX - size.width - 8)
            origin.y = anchor.minY - size.height - 6
        }

        hideWork?.cancel()
        let final = NSRect(origin: origin, size: size)
        let wasVisible = panel.isVisible && panel.alphaValue > 0.5
        panel.setFrame(wasVisible ? final : final.offsetBy(dx: 0, dy: 6), display: true)
        panel.alphaValue = wasVisible ? 1 : 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            panel.animator().setFrame(final, display: true)
            panel.animator().alphaValue = 1
        }

        let work = DispatchWorkItem { [panel] in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            }, completionHandler: { panel.orderOut(nil) })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (hint == nil ? 1.4 : 3.0), execute: work)
    }
}

