import Foundation

public struct ClaudeProjectsPathResolver {

    private static let candidatePaths: [String] = [
        "~/.claude/projects",
        "~/Documents/Claude",
        "~/Library/Application Support/Claude/projects",
        "~/Claude"
    ]

    /// Resolves the Claude Code projects folder.
    /// Priority: user override > auto-detect (first candidate with .jsonl files)
    public static func resolve() -> URL? {
        if let userPath = userConfiguredPath() {
            let expanded = (userPath as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            if containsJSONLFiles(at: url) {
                return url
            }
        }

        for candidate in candidatePaths {
            let expanded = (candidate as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            if containsJSONLFiles(at: url) {
                return url
            }
        }

        return nil
    }

    public static func userConfiguredPath() -> String? {
        let value = UserDefaults.standard.string(forKey: "claudeProjectsPath")
        return value?.isEmpty == false ? value : nil
    }

    public static func setUserConfiguredPath(_ path: String?) {
        if let path = path, !path.isEmpty {
            UserDefaults.standard.set(path, forKey: "claudeProjectsPath")
        } else {
            UserDefaults.standard.removeObject(forKey: "claudeProjectsPath")
        }
    }

    private static func containsJSONLFiles(at url: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return false }

        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension.lowercased() == "jsonl" {
                return true
            }
        }
        return false
    }
}
