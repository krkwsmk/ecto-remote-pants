import Foundation

/// Finds command-line tools across the common macOS locations, since GUI apps
/// do not inherit the user's shell PATH.
enum ToolLocator {
    static let searchDirs = [
        "/opt/homebrew/bin",   // Apple Silicon Homebrew
        "/usr/local/bin",      // Intel Homebrew
        "/usr/bin",
        "/bin",
        "/opt/local/bin"       // MacPorts
    ]

    /// Returns the absolute path to `name`, or nil if not found.
    static func find(_ name: String) -> String? {
        // Absolute path given directly
        if name.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: name) ? name : nil
        }
        for dir in searchDirs {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// Splits a command template into tokens, respecting simple quoting, and
    /// substitutes `{PORT}`.
    static func tokenize(_ template: String, port: String) -> [String] {
        let substituted = template.replacingOccurrences(of: "{PORT}", with: port)
        var tokens: [String] = []
        var current = ""
        var quote: Character? = nil
        for ch in substituted {
            if let q = quote {
                if ch == q { quote = nil } else { current.append(ch) }
            } else if ch == "\"" || ch == "'" {
                quote = ch
            } else if ch == " " {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}
