import Foundation

/// Installs and updates the Steerpin plugin through the `claude` command line tool,
/// so people only install the app.
enum ClaudeCode {
    enum PluginState: Equatable {
        case noCLI
        case notInstalled
        case outdated(installed: String, available: String)
        case connected
    }

    static let pluginID = "steerpin@steerpin"
    static let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    /// Apps opened from Finder don't get the shell's PATH, so ask the login shell for it once.
    static let shellPath: String = {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let result = run(shell, ["-lc", "printf '__PATH__%s__PATH__' \"$PATH\""], path: nil)
        if let range = result.output.range(of: "__PATH__(.*)__PATH__", options: .regularExpression) {
            return String(result.output[range]).replacingOccurrences(of: "__PATH__", with: "")
        }
        return "/usr/bin:/bin:/usr/sbin:/sbin"
    }()

    static var searchPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extra = ["\(home)/.local/bin", "\(home)/.claude/local", "/opt/homebrew/bin", "/usr/local/bin"]
        return (shellPath.split(separator: ":").map(String.init) + extra).joined(separator: ":")
    }

    static func find(_ tool: String) -> String? {
        for dir in searchPath.split(separator: ":") {
            let candidate = "\(dir)/\(tool)"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    static var installedVersion: String? {
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/plugins/installed_plugins.json")
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plugins = json["plugins"] as? [String: Any],
              let entries = plugins[pluginID] as? [[String: Any]],
              let user = entries.first(where: { $0["scope"] as? String == "user" }) ?? entries.first
        else { return nil }
        return user["version"] as? String
    }

    /// Offers an update only when GitHub has a newer plugin than the installed one.
    /// Uses the last known published version; call `refreshPublishedVersion()` off the main thread.
    static func state() -> PluginState {
        guard find("claude") != nil else { return .noCLI }
        guard let installed = installedVersion else { return .notInstalled }
        guard let published = publishedVersion, isOlder(installed, than: published) else { return .connected }
        return .outdated(installed: installed, available: published)
    }

    private static let manifestURL =
        URL(string: "https://raw.githubusercontent.com/gregkozakiewicz/steerpin/main/.claude-plugin/plugin.json")!
    private static let queue = DispatchQueue(label: "steerpin.published-version")
    private static var published: (version: String, fetched: Date)?

    static var publishedVersion: String? { queue.sync { published?.version } }

    /// Asks GitHub for the newest plugin version, at most once an hour. Blocks, so never call it on the main thread.
    static func refreshPublishedVersion(force: Bool = false) {
        if !force, let fetched = queue.sync(execute: { published?.fetched }), Date().timeIntervalSince(fetched) < 3600 { return }
        var request = URLRequest(url: manifestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.httpMethod = "GET"
        let done = DispatchSemaphore(value: 0)
        var version: String?
        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                version = json["version"] as? String
            }
            done.signal()
        }.resume()
        done.wait()
        if let version { queue.sync { published = (version, Date()) } }
    }

    /// Settings from 0.3.1 to 0.4.1, which remembered the latest version and could stop offering updates.
    static func forgetOldUpdateChecks() {
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("latestPublishedPlugin") {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// Installs the plugin, or updates it when it's already there. Runs off the main thread.
    static func connect(completion: @escaping (_ ok: Bool, _ message: String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let finish = { (ok: Bool, message: String) in DispatchQueue.main.async { completion(ok, message) } }
            guard let claude = find("claude") else {
                return finish(false, "Claude Code isn't installed")
            }
            let updating = installedVersion != nil
            let steps: [[String]] = updating
                ? [["plugin", "marketplace", "update", "steerpin"], ["plugin", "update", pluginID]]
                : [["plugin", "marketplace", "add", "gregkozakiewicz/steerpin"], ["plugin", "install", pluginID]]
            for args in steps {
                let result = run(claude, args, path: searchPath)
                if !result.ok {
                    let lastLine = result.output.split(separator: "\n").last.map(String.init) ?? "Unknown error"
                    return finish(false, lastLine)
                }
            }
            refreshPublishedVersion(force: true)
            if find("node") == nil {
                return finish(true, "Also install Node.js 18 or later, which the plugin needs")
            }
            finish(true, "Restart Claude Code to start using your marks")
        }
    }

    @discardableResult
    static func run(_ executable: String, _ args: [String], path: String?) -> (ok: Bool, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        if let path { env["PATH"] = path }
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return (false, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus == 0, String(decoding: data, as: UTF8.self))
    }

    static func isOlder(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l < r }
        }
        return false
    }
}
