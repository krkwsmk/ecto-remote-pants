import Foundation

/// Owns the on-disk log layout:
///
///   ~/Library/Application Support/EctoRemote/logs/
///       session_<port>_<timestamp>/
///           session.log                  (everything, human readable)
///           connection_<idx>_<peer>_<ts>.log   (raw payload per connection)
///
/// Writing happens on a dedicated serial queue so the UI never blocks.
final class LogFiles {
    static let appName = "EctoRemote"

    private let queue = DispatchQueue(label: "com.ectoremote.logfiles")
    private(set) var sessionDir: URL?
    private var sessionHandle: FileHandle?
    private var connectionHandle: FileHandle?
    private var connectionIndex = 0

    /// Root logs directory, always created.
    static var rootLogsDir: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent(appName, isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Begin a new session folder. Returns the session directory.
    @discardableResult
    func startSession(port: String) -> URL {
        var created: URL = LogFiles.rootLogsDir
        queue.sync {
            let ts = LogFiles.stamp()
            let dir = LogFiles.rootLogsDir
                .appendingPathComponent("session_\(port)_\(ts)", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.sessionDir = dir
            self.connectionIndex = 0

            let sessionFile = dir.appendingPathComponent("session.log")
            FileManager.default.createFile(atPath: sessionFile.path, contents: nil)
            self.sessionHandle = try? FileHandle(forWritingTo: sessionFile)
            created = dir
        }
        return created
    }

    /// Open a fresh per-connection payload file. Returns its URL.
    @discardableResult
    func beginConnectionFile(peer: String) -> URL? {
        var url: URL?
        queue.sync {
            guard let dir = self.sessionDir else { return }
            self.connectionIndex += 1
            let safePeer = LogFiles.sanitize(peer)
            let name = String(format: "connection_%03d_%@_%@.log",
                              self.connectionIndex, safePeer, LogFiles.stamp())
            let fileURL = dir.appendingPathComponent(name)
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            try? self.connectionHandle?.close()
            self.connectionHandle = try? FileHandle(forWritingTo: fileURL)
            url = fileURL
        }
        return url
    }

    /// Append raw payload bytes to the current connection file.
    func appendPayload(_ data: Data) {
        queue.async {
            try? self.connectionHandle?.write(contentsOf: data)
        }
    }

    /// Append a human-readable line to the master session log.
    func appendSession(_ line: String) {
        queue.async {
            guard let handle = self.sessionHandle,
                  let data = (line + "\n").data(using: .utf8) else { return }
            try? handle.write(contentsOf: data)
        }
    }

    func closeSession() {
        queue.sync {
            try? self.connectionHandle?.close()
            try? self.sessionHandle?.close()
            self.connectionHandle = nil
            self.sessionHandle = nil
        }
    }

    // MARK: - Helpers

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }

    private static func sanitize(_ s: String) -> String {
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-_")
        let cleaned = s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let str = String(cleaned)
        return str.isEmpty ? "peer" : str
    }
}
