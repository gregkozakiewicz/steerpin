import AppKit

/// Copy-ready lists of marks from the project Claude Code worked in last. The plugin records that
/// project in ~/.steerpin/last-project.json; its files are the same ones Claude sees. Marks still
/// waiting in the inbox are included, since they'll go to that project with the next message.
enum MarkLists {
    enum List {
        case steering, saved, roadmap
    }

    private struct Project: Decodable {
        let project: String
        let marks: String
        let roadmap: String
        let later: String
    }

    private static var project: Project? {
        let file = Inbox.folder.appendingPathComponent("last-project.json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Project.self, from: data)
    }

    /// Folder name of the last project, for the menu.
    static var projectName: String? {
        project.map { URL(fileURLWithPath: $0.project).lastPathComponent }
    }

    static func items(_ type: MarkType) -> [String] {
        guard let project else { return [] }
        var texts: [String]
        switch type {
        case .priority, .wrong: texts = steeringMarks(at: project.marks).filter { $0.type == type }.map(\.text)
        case .roadmap: texts = listItems(at: project.roadmap)
        case .later: texts = listItems(at: project.later)
        }
        for waiting in Inbox.waiting() where waiting.type == type && !texts.contains(waiting.text) {
            texts.append(waiting.text)
        }
        return texts
    }

    static func count(_ list: List) -> Int {
        switch list {
        case .steering: return items(.priority).count + items(.wrong).count
        case .saved: return items(.later).count
        case .roadmap: return items(.roadmap).count
        }
    }

    /// The block to paste. Nil when the list is empty.
    static func block(_ list: List) -> String? {
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

    /// Reads marks.md: sections headed "## [id] priority|wrong", an optional _meta_ line, then the text.
    private static func steeringMarks(at path: String) -> [(type: MarkType, text: String)] {
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
    private static func listItems(at path: String) -> [String] {
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
