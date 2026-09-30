import AppKit
import Carbon.HIToolbox

enum MarkType: String, CaseIterable {
    case priority, wrong, roadmap, later

    var keyCode: UInt32 {
        switch self {
        case .priority: return UInt32(kVK_ANSI_R)
        case .wrong: return UInt32(kVK_ANSI_W)
        case .roadmap: return UInt32(kVK_ANSI_A)
        case .later: return UInt32(kVK_ANSI_S)
        }
    }

    var shortcut: String {
        switch self {
        case .priority: return "⌥⇧R"
        case .wrong: return "⌥⇧W"
        case .roadmap: return "⌥⇧A"
        case .later: return "⌥⇧S"
        }
    }

    var name: String {
        switch self {
        case .priority: return "Priority"
        case .wrong: return "Wrong"
        case .roadmap: return "Add to roadmap"
        case .later: return "Save for later"
        }
    }

    var confirmation: String {
        switch self {
        case .priority: return "Marked as priority"
        case .wrong: return "Marked as wrong"
        case .roadmap: return "Added to roadmap"
        case .later: return "Saved for later"
        }
    }

    var symbol: String {
        switch self {
        case .priority: return "exclamationmark.circle.fill"
        case .wrong: return "xmark.circle.fill"
        case .roadmap: return "map.fill"
        case .later: return "bookmark.fill"
        }
    }
}

struct Mark {
    let type: MarkType
    let text: String
    let date: Date
}

/// Appends marks to ~/.steerpin/inbox.jsonl, the file the Claude Code plugin reads.
enum Inbox {
    static let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".steerpin")
    static let file = folder.appendingPathComponent("inbox.jsonl")

    static func append(_ mark: Mark, sourceApp: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let iso = ISO8601DateFormatter()
        let entry: [String: String] = [
            "type": mark.type.rawValue,
            "text": mark.text,
            "timestamp": iso.string(from: mark.date),
            "source_app": sourceApp,
        ]
        var line = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys, .withoutEscapingSlashes])
        line.append(0x0A)
        if !FileManager.default.fileExists(atPath: file.path) {
            FileManager.default.createFile(atPath: file.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    /// Marks waiting for the next Claude Code message.
    static func pendingCount() -> Int {
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { return 0 }
        return content.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }
}
