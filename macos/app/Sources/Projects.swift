import AppKit

/// A project Claude Code worked in, as recorded by the plugin in ~/.steerpin/projects.json.
/// Its files are the same ones Claude sees. Marks still waiting in the inbox belong to the most
/// recent project, since they go there with the next message.
struct Project: Decodable {
    let project: String
    let marks: String
    let roadmap: String
    let later: String
    let lastUsed: String

    enum List {
        case steering, saved, roadmap
    }

    var name: String { URL(fileURLWithPath: project).lastPathComponent }
    var displayPath: String { (project as NSString).abbreviatingWithTildeInPath }
    private var folder: String { (marks as NSString).deletingLastPathComponent }
    private var clearedMarks: String { (folder as NSString).appendingPathComponent("cleared.md") }
    private var clearedInbox: String { (folder as NSString).appendingPathComponent("cleared-inbox.jsonl") }

    /// Recent projects that have any marks, or a clear that can still be undone, newest first.
    static func recent(limit: Int = 5) -> [Project] {
        let file = Inbox.folder.appendingPathComponent("projects.json")
        guard let data = try? Data(contentsOf: file),
              let all = try? JSONDecoder().decode([Project].self, from: data) else { return [] }
        var shown: [Project] = []
        for (index, project) in all.enumerated() where shown.count < limit {
            if project.hasAnything(isLatest: index == 0) || project.canUndoClear { shown.append(project) }
        }
        return shown
    }

    /// The project Claude Code worked in last, marks or not.
    static var latest: Project? {
        let file = Inbox.folder.appendingPathComponent("projects.json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return (try? JSONDecoder().decode([Project].self, from: data))?.first
    }

    var isLatest: Bool { Project.latest?.project == project }

    private static let relative = RelativeDateTimeFormatter()

    var lastUsedText: String {
        guard let date = ISO8601DateFormatter.withFractions.date(from: lastUsed) ?? ISO8601DateFormatter.plain.date(from: lastUsed)
        else { return "" }
        return "used " + Project.relative.localizedString(for: date, relativeTo: Date())
    }

    private func hasAnything(isLatest: Bool) -> Bool {
        let waiting = isLatest ? Inbox.waiting().count : 0
        return waiting + Project.steeringMarks(at: marks).count + Project.listItems(at: roadmap).count
            + Project.listItems(at: later).count > 0
    }

    // MARK: Reading

    func items(_ type: MarkType) -> [String] {
        var texts: [String]
        switch type {
        case .priority, .wrong: texts = Project.steeringMarks(at: marks).filter { $0.type == type }.map(\.text)
        case .roadmap: texts = Project.listItems(at: roadmap)
        case .later: texts = Project.listItems(at: later)
        }
        if isLatest {
            for waiting in Inbox.waiting() where waiting.type == type && !texts.contains(waiting.text) {
                texts.append(waiting.text)
            }
        }
        return texts
    }

    func count(_ list: List) -> Int {
        switch list {
        case .steering: return items(.priority).count + items(.wrong).count
        case .saved: return items(.later).count
        case .roadmap: return items(.roadmap).count
        }
    }

    /// The block to paste. Nil when the list is empty.
    func block(_ list: List) -> String? {
        let bullets = { (texts: [String], quoted: Bool) in
            texts.map { text -> String in
                let body = text.replacingOccurrences(of: "\n", with: "\n  ")
                return quoted ? "- \"\(body)\"" : "- \(body)"
            }
        }
        var lines: [String]
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

    func openMarksFile() {
        if !FileManager.default.fileExists(atPath: marks) {
            try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            try? "# Steerpin marks\n".write(toFile: marks, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: marks))
    }

    // MARK: Clear and undo

    /// Removes the priority and wrong marks, like /steerpin:clear-marks, and keeps them so the clear
    /// can be undone until the next one. Roadmap and saved marks stay. Returns how many were cleared.
    @discardableResult
    func clearSteering() -> Int {
        let cleared = count(.steering)
        var removedSections = ""
        if var content = try? String(contentsOfFile: marks, encoding: .utf8),
           let first = content.range(of: #"(?m)^## \[\d+\] (priority|wrong)"#, options: .regularExpression) {
            removedSections = String(content[first.lowerBound...])
            // The header also holds the next id, so new marks don't reuse old ids.
            content = String(content[..<first.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
            try? content.write(toFile: marks, atomically: true, encoding: .utf8)
        }
        let removedWaiting = isLatest ? Inbox.removeWaiting { $0 == .priority || $0 == .wrong } : []
        try? removedSections.write(toFile: clearedMarks, atomically: true, encoding: .utf8)
        try? removedWaiting.map { $0 + "\n" }.joined().write(toFile: clearedInbox, atomically: true, encoding: .utf8)
        return cleared
    }

    var canUndoClear: Bool { FileManager.default.fileExists(atPath: clearedMarks) }

    /// Puts the last cleared marks back, next to any marks made since.
    func undoClear() {
        if let sections = try? String(contentsOfFile: clearedMarks, encoding: .utf8), !sections.isEmpty {
            var content = (try? String(contentsOfFile: marks, encoding: .utf8)) ?? "# Steerpin marks\n"
            if !content.hasSuffix("\n") { content += "\n" }
            content += "\n" + sections
            try? content.write(toFile: marks, atomically: true, encoding: .utf8)
        }
        if let waiting = try? String(contentsOfFile: clearedInbox, encoding: .utf8), !waiting.isEmpty {
            Inbox.appendRaw(waiting)
        }
        try? FileManager.default.removeItem(atPath: clearedMarks)
        try? FileManager.default.removeItem(atPath: clearedInbox)
    }

    // MARK: File formats

    /// Reads marks.md: sections headed "## [id] priority|wrong", an optional _meta_ line, then the text.
    static func steeringMarks(at path: String) -> [(type: MarkType, text: String)] {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        var marks: [(MarkType, String)] = []
        var type: MarkType?
        var body: [String] = []
        func flush() {
            if let type {
                let text = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { marks.append((type, text)) }
            }
            body = []
        }
        for line in content.components(separatedBy: "\n") {
            if let match = line.range(of: #"^## \[\d+\] (priority|wrong)\s*$"#, options: .regularExpression) {
                flush()
                type = MarkType(rawValue: line[match].split(separator: " ")[2].trimmingCharacters(in: .whitespaces))
            } else if type != nil {
                if body.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }),
                   line.hasPrefix("_"), line.hasSuffix("_") { continue } // meta line
                body.append(line.hasPrefix("\\## [") ? String(line.dropFirst()) : line)
            }
        }
        flush()
        return marks
    }

    /// Reads roadmap.md / later.md: "- text", indented continuation lines, and an indented _meta_ line.
    static func listItems(at path: String) -> [String] {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        var items: [String] = []
        var current: [String]?
        for line in content.components(separatedBy: "\n") {
            if line.hasPrefix("- ") {
                if let current { items.append(current.joined(separator: "\n")) }
                current = [String(line.dropFirst(2))]
            } else if current != nil, line.hasPrefix("  ") {
                let inner = String(line.dropFirst(2))
                if inner.hasPrefix("_") && inner.hasSuffix("_") { continue } // meta line
                current?.append(inner)
            } else if current != nil, line.isEmpty {
                continue
            } else if let done = current {
                items.append(done.joined(separator: "\n"))
                current = nil
            }
        }
        if let current { items.append(current.joined(separator: "\n")) }
        return items
    }
}

extension ISO8601DateFormatter {
    static let plain = ISO8601DateFormatter()
    static let withFractions: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
