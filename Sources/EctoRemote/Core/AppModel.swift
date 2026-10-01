import Foundation
import SwiftUI
import AppKit

enum ConnectionPhase: Equatable {
    case idle
    case startingTunnel
    case tunnelUp
    case listening
    case failed(String)

    var label: String {
        switch self {
        case .idle: return "OFFLINE"
        case .startingTunnel: return "LINKING…"
        case .tunnelUp: return "TUNNEL UP"
        case .listening: return "LISTENING"
        case .failed: return "FAULT"
        }
    }

    var color: Color {
        switch self {
        case .idle: return Theme.textDim
        case .startingTunnel: return Theme.neonAmber
        case .tunnelUp: return Theme.neonCyan
        case .listening: return Theme.neonGreen
        case .failed: return Theme.neonRed
        }
    }

    var isActive: Bool {
        switch self {
        case .idle, .failed: return false
        default: return true
        }
    }
}

/// Central controller. All `@Published` mutations happen on the main thread:
/// UI-initiated calls are already on main, and output arriving on background
/// pipe threads is funnelled back through `DispatchQueue.main.async`.
final class AppModel: ObservableObject {
    static let shared = AppModel()

    // User-editable fields
    @Published var port: String = AppSettings.shared.lastPort
    @Published var password: String = AppSettings.shared.savedPassword() ?? ""
    @Published var savePasswordEnabled: Bool = AppSettings.shared.hasSavedPassword()

    // Settings-backed mirrors
    @Published var sshUser: String = AppSettings.shared.sshUser
    @Published var sshHost: String = AppSettings.shared.sshHost
    @Published var sshExtraArgs: String = AppSettings.shared.sshExtraArgs
    @Published var ncatTemplate: String = AppSettings.shared.ncatTemplate
    @Published var autoStartListener: Bool = AppSettings.shared.autoStartListener

    // Live state
    @Published private(set) var phase: ConnectionPhase = .idle
    @Published private(set) var lines: [LogLine] = []
    @Published private(set) var connections: [ConnectionRecord] = []
    @Published private(set) var totalBytes: Int = 0
    @Published var autoScroll: Bool = true

    // Processes
    private var sshProcess: Process?
    private var ncatProcess: Process?

    // Buffers for line assembly
    private var controlBuffer = ""          // ssh stderr/stdout
    private var listenerControlBuffer = ""  // ncat stderr
    private var dataBuffer = ""             // ncat stdout payload
    private var sawAuthenticated = false

    private let logFiles = LogFiles()
    private let maxLines = 6000

    private var activePort = ""

    var logsFolderURL: URL { LogFiles.rootLogsDir }

    // MARK: - Public actions

    func connect() {
        guard !phase.isActive else { return }
        let trimmedPort = port.trimmingCharacters(in: .whitespaces)
        guard let portNum = Int(trimmedPort), (1...65535).contains(portNum) else {
            appendLine(.error, "Invalid port. Enter a number between 1 and 65535.")
            return
        }
        activePort = trimmedPort
        persistSettings()

        // Reset view state for the new session
        lines.removeAll()
        connections.removeAll()
        totalBytes = 0
        controlBuffer = ""
        listenerControlBuffer = ""
        dataBuffer = ""
        sawAuthenticated = false

        let dir = logFiles.startSession(port: trimmedPort)
        appendLine(.info, "Session log: \(dir.path)")

        startTunnel(port: trimmedPort)
    }

    func disconnect() {
        appendLine(.info, "Shutting down…")
        terminateProcesses()
        logFiles.appendSession("[\(now())] SYS session closed")
        logFiles.closeSession()
        phase = .idle
    }

    func revealLogsInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([logsFolderURL])
    }

    func revealConnection(_ record: ConnectionRecord) {
        NSWorkspace.shared.activateFileViewerSelecting([record.fileURL])
    }

    func clearScreen() {
        lines.removeAll()
    }

    func persistSettings() {
        let s = AppSettings.shared
        s.lastPort = port.trimmingCharacters(in: .whitespaces)
        s.sshUser = sshUser
        s.sshHost = sshHost
        s.sshExtraArgs = sshExtraArgs
        s.ncatTemplate = ncatTemplate
        s.autoStartListener = autoStartListener
        if savePasswordEnabled {
            s.savePassword(password)
        } else {
            s.savePassword("")
        }
    }

    func shutdownForTermination() {
        sshProcess?.terminate()
        ncatProcess?.terminate()
    }

    // MARK: - Stage 1: reverse SSH tunnel

    private func startTunnel(port: String) {
        phase = .startingTunnel

        guard let sshPath = ToolLocator.find("ssh") else {
            fail("ssh binary not found on this system.")
            return
        }

        let askpassPath: String
        do {
            askpassPath = try SSHAskpass.ensureScript()
        } catch {
            fail("Could not prepare credential helper: \(error.localizedDescription)")
            return
        }

        var args = [
            "-v",
            "-N",
            "-R", "\(port):localhost:\(port)",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ConnectTimeout=15",
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3",
            "-o", "NumberOfPasswordPrompts=3"
        ]
        let extra = sshExtraArgs.trimmingCharacters(in: .whitespaces)
        if !extra.isEmpty {
            args.append(contentsOf: ToolLocator.tokenize(extra, port: port))
        }
        args.append("\(sshUser)@\(sshHost)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: sshPath)
        process.arguments = args

        var env = ProcessInfo.processInfo.environment
        env["SSH_ASKPASS"] = askpassPath
        env["SSH_ASKPASS_REQUIRE"] = "force"
        env["DISPLAY"] = env["DISPLAY"] ?? ":0"
        env[SSHAskpass.envVar] = password
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let displayCmd = "ssh " + args.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
        appendLine(.command, displayCmd)
        logFiles.appendSession("[\(now())] CMD \(displayCmd)")

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            guard let self, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self.handleSSHText(text) }
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            guard let self, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self.handleSSHText(text) }
        }

        process.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            guard let self else { return }
            DispatchQueue.main.async { self.sshDidExit(status: status) }
        }

        do {
            try process.run()
            sshProcess = process
            appendLine(.info, "Establishing reverse tunnel to \(sshUser)@\(sshHost)…")
            // Fallback: if ssh authenticated but we never matched a forward
            // marker (wording varies by version), promote after a short grace.
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                guard let self else { return }
                if self.phase == .startingTunnel,
                   self.sawAuthenticated,
                   self.sshProcess?.isRunning == true {
                    self.tunnelBecameReady()
                }
            }
        } catch {
            fail("Failed to launch ssh: \(error.localizedDescription)")
        }
    }

    private func handleSSHText(_ text: String) {
        controlBuffer += text
        emitControlLines(prefix: "ssh")

        if text.contains("Authenticated to") || text.contains("Authentication succeeded") {
            sawAuthenticated = true
        }

        // Detect a healthy tunnel from ssh's verbose output.
        if phase == .startingTunnel {
            let markers = ["remote forward success", "Entering interactive session",
                           "All remote forwarding requests processed"]
            if markers.contains(where: { text.contains($0) }) {
                tunnelBecameReady()
            }
        }
        // Surface common auth failures clearly.
        if text.contains("Permission denied") {
            appendLine(.error, "Authentication failed. Check the saved password in Settings.")
        }
    }

    private func tunnelBecameReady() {
        guard phase == .startingTunnel else { return }
        phase = .tunnelUp
        appendLine(.info, "Reverse tunnel established on port \(activePort).")
        logFiles.appendSession("[\(now())] SYS tunnel up on port \(activePort)")
        if autoStartListener {
            startListener(port: activePort)
        }
    }

    private func sshDidExit(status: Int32) {
        emitControlLines(prefix: "ssh", flush: true)
        if phase.isActive {
            // Unexpected drop
            if status != 0 && phase == .startingTunnel {
                fail("ssh exited before the tunnel came up (status \(status)). Check host, credentials, and network.")
            } else {
                appendLine(.error, "ssh tunnel closed (status \(status)).")
                phase = .idle
            }
        }
        sshProcess = nil
    }

    // MARK: - Stage 2: listener (ncat)

    func startListener() {
        guard phase == .tunnelUp else {
            appendLine(.error, "Start the tunnel first.")
            return
        }
        startListener(port: activePort)
    }

    private func startListener(port: String) {
        let tokens = ToolLocator.tokenize(ncatTemplate, port: port)
        guard let first = tokens.first else {
            fail("Listener command is empty. Fix it in Settings.")
            return
        }
        guard let binPath = ToolLocator.find(first) else {
            appendLine(.error, "'\(first)' not found. Install it (e.g. `brew install nmap`) or change the listener command in Settings.")
            return
        }
        let args = Array(tokens.dropFirst())

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binPath)
        process.arguments = args
        process.environment = ProcessInfo.processInfo.environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let displayCmd = ([first] + args).joined(separator: " ")
        appendLine(.command, displayCmd)
        logFiles.appendSession("[\(now())] CMD \(displayCmd)")

        // stdout = payload stream
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            guard let self else { return }
            DispatchQueue.main.async { self.handlePayload(data) }
        }
        // stderr = ncat control chatter (incl. "Connection from")
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            guard let self, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self.handleListenerControl(text) }
        }

        process.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            guard let self else { return }
            DispatchQueue.main.async { self.listenerDidExit(status: status) }
        }

        do {
            try process.run()
            ncatProcess = process
            phase = .listening
            appendLine(.info, "Listener active on port \(port). Waiting for data…")
            logFiles.appendSession("[\(now())] SYS listener up on port \(port)")
        } catch {
            fail("Failed to launch listener: \(error.localizedDescription)")
        }
    }

    private func handleListenerControl(_ text: String) {
        listenerControlBuffer += text
        // Detect new inbound connections.
        for raw in splitBufferedLines(&listenerControlBuffer) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            appendLine(.control, line)
            logFiles.appendSession("[\(now())] NET \(line)")
            if let peer = Self.parseConnectionPeer(line) {
                openConnection(peer: peer)
            }
        }
    }

    private func handlePayload(_ data: Data) {
        totalBytes += data.count
        if !connections.isEmpty {
            connections[connections.count - 1].bytes += data.count
        } else {
            // Payload before an explicit connection notice: open a default one.
            openConnection(peer: "stream")
            if !connections.isEmpty {
                connections[connections.count - 1].bytes += data.count
            }
        }
        logFiles.appendPayload(data)

        // Render readable text, line-buffered.
        let text = String(decoding: data, as: UTF8.self)
        dataBuffer += text
        for line in splitBufferedLines(&dataBuffer) {
            appendLine(.data, sanitizeForDisplay(line))
        }
    }

    private func openConnection(peer: String) {
        // Flush any trailing payload text from the previous connection.
        if !dataBuffer.isEmpty {
            appendLine(.data, sanitizeForDisplay(dataBuffer))
            dataBuffer = ""
        }
        let url = logFiles.beginConnectionFile(peer: peer) ?? logFiles.rootFallback()
        let record = ConnectionRecord(peer: peer, startedAt: Date(), bytes: 0, fileURL: url)
        connections.append(record)
        appendLine(.info, "New connection #\(connections.count) from \(peer) → \(url.lastPathComponent)")
    }

    private func listenerDidExit(status: Int32) {
        if !dataBuffer.isEmpty {
            appendLine(.data, sanitizeForDisplay(dataBuffer))
            dataBuffer = ""
        }
        appendLine(.info, "Listener stopped (status \(status)).")
        logFiles.appendSession("[\(now())] SYS listener stopped (status \(status))")
        ncatProcess = nil
        if phase == .listening {
            phase = sshProcess != nil ? .tunnelUp : .idle
        }
    }

    // MARK: - Helpers

    private func terminateProcesses() {
        ncatProcess?.terminate()
        sshProcess?.terminate()
        ncatProcess = nil
        sshProcess = nil
    }

    private func fail(_ message: String) {
        appendLine(.error, message)
        logFiles.appendSession("[\(now())] ERR \(message)")
        terminateProcesses()
        phase = .failed(message)
    }

    private func appendLine(_ kind: LogKind, _ text: String) {
        lines.append(LogLine(timestamp: Date(), kind: kind, text: text))
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }

    private func emitControlLines(prefix: String, flush: Bool = false) {
        for line in splitBufferedLines(&controlBuffer, flushRemainder: flush) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            appendLine(.control, trimmed)
            logFiles.appendSession("[\(now())] \(prefix.uppercased()) \(trimmed)")
        }
    }

    /// Pulls complete lines out of a buffer, leaving any partial trailing line
    /// in place (unless flushRemainder is set).
    private func splitBufferedLines(_ buffer: inout String, flushRemainder: Bool = false) -> [String] {
        var result: [String] = []
        while let range = buffer.range(of: "\n") {
            let line = String(buffer[buffer.startIndex..<range.lowerBound])
            result.append(line.replacingOccurrences(of: "\r", with: ""))
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
        }
        if flushRemainder && !buffer.isEmpty {
            result.append(buffer.replacingOccurrences(of: "\r", with: ""))
            buffer = ""
        }
        return result
    }

    private func sanitizeForDisplay(_ s: String) -> String {
        // Replace non-printable control characters (except tab) with a glyph.
        var out = ""
        for scalar in s.unicodeScalars {
            if scalar == "\t" || scalar.value >= 0x20 {
                out.unicodeScalars.append(scalar)
            } else {
                out.append("·")
            }
        }
        return out
    }

    private func now() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f.string(from: Date())
    }

    static func parseConnectionPeer(_ line: String) -> String? {
        // Matches: "Ncat: Connection from 127.0.0.1:52345." or similar.
        guard line.localizedCaseInsensitiveContains("connection from") else { return nil }
        if let range = line.range(of: "from ", options: .caseInsensitive) {
            var peer = String(line[range.upperBound...])
            peer = peer.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
            return peer.isEmpty ? "unknown" : peer
        }
        return "unknown"
    }
}

private extension LogFiles {
    func rootFallback() -> URL {
        (sessionDir ?? LogFiles.rootLogsDir).appendingPathComponent("stream.log")
    }
}
