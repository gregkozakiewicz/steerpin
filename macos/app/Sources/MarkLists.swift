import AppKit

/// Every mark the app captured, kept by the app itself so the menu can copy each kind as a
/// ready-to-paste block. Separate from the project files the Claude Code plugin writes.
enum MarkLists {
    private static let file = Inbox.folder.appendingPathComponent("chat-marks.json")

    struct Entry: Codable, Equatable {
        let type: String
        let text: String
    }

    enum List {
        case steering, saved, roadmap

        var types: [MarkType] {
            switch self {
            case .steering: return [.priority, .wrong]
            case .saved: return [.later]
            case .roadmap: return [.roadmap]
            }
        }
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
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var entries = load()
        if type == .priority || type == .wrong {
            // Re-marking as the other steering type replaces the old mark.
            entries.removeAll { $0.text == clean && ($0.type == MarkType.priority.rawValue || $0.type == MarkType.wrong.rawValue) }
        } else {
            entries.removeAll { $0.text == clean && $0.type == type.rawValue }
        }
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

    static func count(_ list: List) -> Int {
        let types = Set(list.types.map(\.rawValue))
        return load().filter { types.contains($0.type) }.count
    }

    /// The block to paste. Nil when the list is empty.
    static func block(_ list: List) -> String? {
        let entries = load()
        let items = { (type: MarkType) in entries.filter { $0.type == type.rawValue }.map(\.text) }
        let bullets = { (texts: [String], quoted: Bool) in
            texts.map { text -> String in
                let body = text.replacingOccurrences(of: "\n", with: "\n  ")
                return quoted ? "- \"\(body)\"" : "- \(body)"
            }
        }
        var lines: [String] = []
        switch list {
        case .steering:
            let priority = items(.priority), wrong = items(.wrong)
            guard !priority.isEmpty || !wrong.isEmpty else { return nil }
            lines = ["My marks for this conversation. Keep applying them until I say otherwise."]
            if !priority.isEmpty {
                lines += ["", "Priority, keep these at the top of your attention:"] + bullets(priority, false)
            }
            if !wrong.isEmpty {
                lines += ["", "Wrong, don't rely on or repeat these. If anything you said depends on them, say so and correct it:"]
                    + bullets(wrong, true)
            }
        case .saved:
            let later = items(.later)
            guard !later.isEmpty else { return nil }
            lines = ["Saved for later:"] + bullets(later, false)
        case .roadmap:
            let roadmap = items(.roadmap)
            guard !roadmap.isEmpty else { return nil }
            lines = ["Roadmap:"] + bullets(roadmap, false)
        }
        return lines.joined(separator: "\n")
    }
}
