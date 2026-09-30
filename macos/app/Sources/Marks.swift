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
    private static let iso = ISO8601DateFormatter()

    static func append(_ mark: Mark, sourceApp: String) throws {
        let entry: [String: String] = [
            "type": mark.type.rawValue,
            "text": mark.text,
            "timestamp": iso.string(from: mark.date),
            "source_app": sourceApp,
        ]
        var line = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys, .withoutEscapingSlashes])
        line.append(0x0A)
        try appendData(line)
    }

    /// Appends already-encoded inbox lines, e.g. when undoing a clear.
    static func appendRaw(_ lines: String) {
        try? appendData(Data(lines.utf8))
    }

    /// O_APPEND, so a line the plugin's `capture` command writes at the same moment is never overwritten.
    /// Folder and file are owner-only: marked text can hold anything the user selected, secrets included.
    private static func appendData(_ data: Data) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        chmod(folder.path, 0o700)
        let fd = open(file.path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        try handle.write(contentsOf: data)
    }

    /// Replaces the inbox with these lines, keeping it owner-only.
    private static func rewrite(_ lines: [String]) {
        let rest = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        try? rest.write(to: file, atomically: true, encoding: .utf8)
        chmod(file.path, 0o600)
    }

    /// Removes the newest waiting mark. Returns nil when the inbox is empty,
    /// which means the marks were already delivered to Claude Code.
    static func removeLast() -> (type: MarkType, text: String)? {
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        var lines = content.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard let last = lines.popLast() else { return nil }
        rewrite(lines)
        guard let data = last.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = MarkType(rawValue: json["type"] as? String ?? ""),
              let text = json["text"] as? String
        else { return nil }
        return (type, text)
    }

    /// Drops waiting marks of the given types, keeping the rest in order. Returns the dropped lines.
    @discardableResult
    static func removeWaiting(where shouldRemove: (MarkType) -> Bool) -> [String] {
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        var kept: [Substring] = [], removed: [String] = []
        for line in content.split(separator: "\n") {
            if let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
               let type = MarkType(rawValue: json["type"] as? String ?? ""), shouldRemove(type) {
                removed.append(String(line))
            } else {
                kept.append(line)
            }
        }
        rewrite(kept.map(String.init))
        return removed
    }

    /// Every mark waiting for the next Claude Code message.
    static func waiting() -> [(type: MarkType, text: String)] {
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return content.split(separator: "\n").compactMap { line in
            guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let type = MarkType(rawValue: json["type"] as? String ?? ""),
                  let text = json["text"] as? String
            else { return nil }
            return (type, text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Marks waiting for the next Claude Code message.
    static func pendingCount() -> Int {
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { return 0 }
        return content.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }
}
