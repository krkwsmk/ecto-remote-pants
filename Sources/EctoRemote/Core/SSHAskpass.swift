import Foundation

/// Creates a tiny askpass helper script that OpenSSH invokes to obtain the
/// password. The script contains no secret: it simply echoes the value of the
/// `ECTO_SSH_PASS` environment variable, which we pass only to the ssh child
/// process. This avoids writing the password to disk and avoids needing a PTY.
enum SSHAskpass {
    static let envVar = "ECTO_SSH_PASS"

    private static var scriptURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent(LogFiles.appName, isDirectory: true)
            .appendingPathComponent("askpass.sh")
    }

    /// Ensures the helper exists and is executable; returns its path.
    static func ensureScript() throws -> String {
        let url = scriptURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let body = "#!/bin/sh\nprintf '%s\\n' \"$\(envVar)\"\n"
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: url.path
        )
        return url.path
    }
}
