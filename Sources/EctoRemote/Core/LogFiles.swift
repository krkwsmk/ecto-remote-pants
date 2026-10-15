import Foundation

/// On-disk log layout for one session:
///
///   ~/Library/Application Support/EctoRemote/logs/
///       session_<port>_<timestamp>/
///           session.log                       (human-readable transcript)
///           connection_<idx>_<peer>_<ts>.log  (raw payload, one per connection)
///
/// Supports many concurrent connection files at once. All writes happen on a
/// dedicated serial queue so the UI never blocks.
final class LogFiles {
    static let appName = "EctoRemote"

    private let queue = DispatchQueue(label: "com.ectoremote.logfiles")
    private(set) var sessionDir: URL?
    private var sessionHandle: FileHandle?
    private var connHandles: [URL: FileHandle] = [:]
    private var connectionIndex = 0

    static var rootLogsDir: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent(appName, isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    @discardableResult
    func startSession(port: String) -> URL {
        var created = LogFiles.rootLogsDir
        queue.sync {
            let dir = LogFiles.rootLogsDir
                .appendingPathComponent("session_\(port)_\(LogFiles.stamp())", isDirectory: true)
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

    /// Create a new per-connection payload file and return its URL.
    func beginConnectionFile(peer: String) -> URL {
        var url = LogFiles.rootLogsDir.appendingPathComponent("stream_\(LogFiles.stamp()).log")
        queue.sync {
            let dir = self.sessionDir ?? LogFiles.rootLogsDir
            self.connectionIndex += 1
            let name = String(format: "connection_%03d_%@_%@.log",
                              self.connectionIndex, LogFiles.sanitize(peer), LogFiles.stamp())
            let fileURL = dir.appendingPathComponent(name)
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            self.connHandles[fileURL] = try? FileHandle(forWritingTo: fileURL)
            url = fileURL
        }
        return url
    }

    func appendPayload(_ data: Data, to url: URL?) {
        guard let url else { return }
        queue.async { try? self.connHandles[url]?.write(contentsOf: data) }
    }

    func appendSession(_ line: String) {
        queue.async {
            guard let handle = self.sessionHandle, let data = (line + "\n").data(using: .utf8) else { return }
            try? handle.write(contentsOf: data)
        }
    }

    func closeSession() {
        queue.sync {
            for (_, h) in self.connHandles { try? h.close() }
            self.connHandles.removeAll()
            try? self.sessionHandle?.close()
            self.sessionHandle = nil
        }
    }

    // MARK: - Helpers

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss_SSS"
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
