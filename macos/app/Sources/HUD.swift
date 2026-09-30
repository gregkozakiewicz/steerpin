import AppKit

/// Small confirmation popup under the menu bar icon. Replaces system notifications,
/// so the app needs no notification permission.
final class HUD {
    private let panel: NSPanel
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private var hideWork: DispatchWorkItem?

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 58),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        panel.contentView = background

        icon.symbolConfiguration = .init(pointSize: 20, weight: .semibold)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail

        let text = NSStackView(views: [title, detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        let row = NSStackView(views: [icon, text])
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(lessThanOrEqualTo: background.trailingAnchor, constant: -14),
            row.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            detail.widthAnchor.constraint(lessThanOrEqualToConstant: 232),
        ])
    }

    func show(symbol: String, tint: NSColor, title: String, detail: String, below anchor: NSRect?) {
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = tint
        self.title.stringValue = title
        self.detail.stringValue = detail.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        let size = panel.frame.size
        let screen = NSScreen.main?.visibleFrame ?? .zero
        var origin = NSPoint(x: screen.maxX - size.width - 12, y: screen.maxY - size.height - 8)
        if let anchor {
            origin.x = min(max(anchor.midX - size.width / 2, screen.minX + 8), screen.maxX - size.width - 8)
            origin.y = anchor.minY - size.height - 6
        }
        panel.setFrameOrigin(origin)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [panel] in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                panel.animator().alphaValue = 0
            }, completionHandler: { panel.orderOut(nil) })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }
}
