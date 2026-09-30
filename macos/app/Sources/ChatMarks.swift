import AppKit

/// Priority and wrong marks kept by the app itself, for chats without the Claude Code plugin
/// (ChatGPT, Claude.ai, …). They're pasted into the chat as a block with Copy Marks.
enum ChatMarks {
    private static let file = Inbox.folder.appendingPathComponent("chat-marks.json")

    struct Entry: Codable, Equatable {
        let type: String
        let text: String
    }

    static func load() -> [Entry] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private static func save(_ entries: [Entry]) {
        try? FileManager.default.createDirectory(at: Inbox.folder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: file, options: .atomic) }
    }

    static func add(_ type: MarkType, _ text: String) {
        guard type == .priority || type == .wrong else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var entries = load().filter { $0.text != clean } // re-marking replaces
        entries.append(Entry(type: type.rawValue, text: clean))
        save(entries)
    }

    static func remove(_ type: MarkType, _ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var entries = load()
        if let index = entries.lastIndex(of: Entry(type: type.rawValue, text: clean)) {
            entries.remove(at: index)
            save(entries)
        }
    }

    static func clear() {
        save([])
    }

    /// The block to paste into a chat. Nil when there's nothing to copy.
    static func block() -> String? {
        let entries = load()
        let priority = entries.filter { $0.type == MarkType.priority.rawValue }
        let wrong = entries.filter { $0.type == MarkType.wrong.rawValue }
        guard !priority.isEmpty || !wrong.isEmpty else { return nil }
        let indent = { (text: String) in text.replacingOccurrences(of: "\n", with: "\n  ") }
        var lines = ["My marks for this conversation. Keep applying them until I say otherwise."]
        if !priority.isEmpty {
            lines += ["", "Priority, keep these at the top of your attention:"]
            lines += priority.map { "- \(indent($0.text))" }
        }
        if !wrong.isEmpty {
            lines += ["", "Wrong, don't rely on or repeat these. If anything you said depends on them, say so and correct it:"]
            lines += wrong.map { "- \"\(indent($0.text))\"" }
        }
        return lines.joined(separator: "\n")
    }
}
