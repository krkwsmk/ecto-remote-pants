import Foundation
import SwiftUI
import AppKit
import Network

enum ConnectionPhase: Equatable {
    case idle
    case connecting
    case listening
    case reconnecting
    case failed(String)

    var label: String {
        switch self {
        case .idle: return "ОФФЛАЙН"
        case .connecting: return "ПОДКЛЮЧЕНИЕ…"
        case .listening: return "СЛУШАЮ"
        case .reconnecting: return "ПЕРЕПОДКЛ…"
        case .failed: return "ОШИБКА"
        }
    }

    var color: Color {
        switch self {
        case .idle: return Theme.textDim
        case .connecting: return Theme.neonAmber
        case .listening: return Theme.neonGreen
        case .reconnecting: return Theme.neonAmber
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

struct RelayConfig {
    var port: String
    var user: String
    var host: String
    var password: String
    var extraArgs: String
    var lineEnding: String
    var autoReconnect: Bool
}

/// One tab = one reverse SSH tunnel with a local listener (NWListener) that
/// accepts each device connection individually, so connections are visible and
/// can be closed one by one. The ssh tunnel auto-reconnects on drops.
final class TunnelSession: ObservableObject, Identifiable {
    let id = UUID()

    @Published var port: String
    @Published var title: String = "Новая вкладка"
    @Published private(set) var phase: ConnectionPhase = .idle
    @Published private(set) var lines: [LogLine] = []
    @Published private(set) var connections: [ConnectionRecord] = []
    @Published private(set) var totalBytes: Int = 0
    @Published var commandInput: String = ""
    @Published var autoScroll: Bool = true
    @Published private(set) var targetConnId: UUID?

    private var cfg: RelayConfig?
    private var lineEnding: String = "lf"
    private var autoReconnect = true

    // ssh
    private var sshProcess: Process?
    private var controlBuffer = ""
    private var sawAuthenticated = false
    private var userClosed = false
    private var retries = 0
    private let maxRetries = 5
    private let reconnectDelay: TimeInterval = 3

    // listener
    private var listener: NWListener?
    private var nwConns: [UUID: NWConnection] = [:]
    private let netQueue = DispatchQueue(label: "com.ectoremote.net")
    private var connCounter = 0

    private let logFiles = LogFiles()
    private let maxLines = 6000
    private var activePort = ""

    var logsFolderURL: URL { LogFiles.rootLogsDir }

    init(port: String = "") {
        self.port = port
    }

    // MARK: - Derived

    var canSend: Bool {
        guard phase == .listening, let tid = targetConnId else { return false }
        return nwConns[tid] != nil
    }

    private var terminator: String {
        switch lineEnding {
        case "cr": return "\r"
        case "crlf": return "\r\n"
        default: return "\n"
        }
    }

    // MARK: - Public actions

    func connect(_ config: RelayConfig) {
        guard !phase.isActive else { return }
        let trimmedPort = config.port.trimmingCharacters(in: .whitespaces)
        guard let portNum = Int(trimmedPort), (1...65535).contains(portNum) else {
            appendLine(.error, "Неверный порт. Введите число от 1 до 65535.")
            return
        }
        guard !config.host.isEmpty, !config.user.isEmpty else {
            appendLine(.error, "Укажите пользователя и хост релея в Настройках.")
            return
        }

        cfg = config
        lineEnding = config.lineEnding
        autoReconnect = config.autoReconnect
        activePort = trimmedPort
        userClosed = false
        retries = 0

        lines.removeAll()
        connections.removeAll()
        nwConns.removeAll()
        totalBytes = 0
        controlBuffer = ""
        sawAuthenticated = false
        connCounter = 0
        targetConnId = nil

        let dir = logFiles.startSession(port: trimmedPort)
        appendLine(.info, "Лог сессии: \(dir.path)")

        phase = .connecting
        if !startListener(portNum: portNum) { return }
        startTunnel(port: trimmedPort)
    }

    func disconnect() {
        userClosed = true
        appendLine(.info, "Отключение…")
        logFiles.appendSession("[\(now())] SYS session closed")
        stopEverything()
        logFiles.closeSession()
        phase = .idle
    }

    func dispose() {
        userClosed = true
        stopEverything()
        logFiles.closeSession()
    }

    func clearScreen() { lines.removeAll() }

    func revealLogsInFinder() { NSWorkspace.shared.activateFileViewerSelecting([logsFolderURL]) }
    func revealConnection(_ record: ConnectionRecord) {
        if let url = record.fileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        else { revealLogsInFinder() }
    }

    func setTarget(_ record: ConnectionRecord) {
        if record.status == .active, nwConns[record.id] != nil { targetConnId = record.id }
    }

    func closeConnection(_ record: ConnectionRecord) {
        guard let conn = nwConns[record.id] else { return }
        appendLine(.info, "Обрываю соединение #\(record.number)…")
        conn.cancel()
    }

    func sendCommand() {
        let cmd = commandInput
        writeToDevice(cmd, display: cmd.isEmpty ? "⏎" : cmd)
        commandInput = ""
    }

    func sendEnter() { writeToDevice("", display: "⏎") }

    private func writeToDevice(_ text: String, display: String) {
        guard phase == .listening, let tid = targetConnId, let conn = nwConns[tid] else {
            appendLine(.error, "Нет активного подключения устройства — отправлять некуда.")
            return
        }
        let data = Data((text + terminator).utf8)
        conn.send(content: data, completion: .contentProcessed { _ in })
        if let num = connections.first(where: { $0.id == tid })?.number {
            appendLine(.sent, "#\(num) \(display)")
            logFiles.appendSession("[\(now())] TX #\(num) \(display)")
        }
    }

    // MARK: - Listener (NWListener replaces ncat)

    private func startListener(portNum: Int) -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(portNum)) else {
            fail("Неверный порт для слушателя.")
            return false
        }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        do {
            let l = try NWListener(using: params, on: nwPort)
            l.newConnectionHandler = { [weak self] conn in self?.handleNewConnection(conn) }
            l.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                if case .failed(let err) = state {
                    DispatchQueue.main.async { self.fail("Слушатель не смог запуститься: \(err.localizedDescription)") }
                }
            }
            l.start(queue: netQueue)
            listener = l
            appendLine(.info, "Локальный слушатель поднят на порту \(portNum).")
            logFiles.appendSession("[\(now())] SYS listener up on port \(portNum)")
            return true
        } catch {
            fail("Не удалось запустить слушатель: \(error.localizedDescription)")
            return false
        }
    }

    private func handleNewConnection(_ conn: NWConnection) {
        conn.start(queue: netQueue)
        let peer = Self.peerString(conn.endpoint)
        DispatchQueue.main.async { self.openConnection(conn, peer: peer) }
    }

    private func openConnection(_ conn: NWConnection, peer: String) {
        connCounter += 1
        let number = connCounter
        let url = logFiles.beginConnectionFile(peer: peer)
        let rec = ConnectionRecord(number: number, peer: peer, startedAt: Date(), bytes: 0, status: .active, fileURL: url)
        let connId = rec.id
        connections.append(rec)
        nwConns[connId] = conn
        if targetConnId == nil { targetConnId = connId }
        appendLine(.control, "Подключение #\(number) от \(peer)")
        logFiles.appendSession("[\(now())] NET connection #\(number) from \(peer)")

        receiveLoop(connId: connId, conn: conn)
    }

    private func receiveLoop(connId: UUID, conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                DispatchQueue.main.async { self.ingest(connId: connId, data: data) }
            }
            if isComplete || error != nil {
                conn.cancel()
                DispatchQueue.main.async { self.markClosed(connId: connId) }
            } else {
                self.receiveLoop(connId: connId, conn: conn)
            }
        }
    }

    private func ingest(connId: UUID, data: Data) {
        guard let idx = connections.firstIndex(where: { $0.id == connId }) else { return }
        connections[idx].bytes += data.count
        totalBytes += data.count
        logFiles.appendPayload(data, to: connections[idx].fileURL)

        let text = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let pieces = text.components(separatedBy: "\n")
        let num = connections[idx].number
        for (i, piece) in pieces.enumerated() {
            if piece.isEmpty && i == pieces.count - 1 { continue }
            appendLine(.data, "#\(num) \(sanitizeForDisplay(piece))")
        }
    }

    private func markClosed(connId: UUID) {
        nwConns.removeValue(forKey: connId)
        if let idx = connections.firstIndex(where: { $0.id == connId }) {
            connections[idx].status = .closed
            logFiles.appendSession("[\(now())] NET connection #\(connections[idx].number) closed (\(connections[idx].bytes) B)")
        }
        if targetConnId == connId {
            targetConnId = connections.last(where: { $0.status == .active && nwConns[$0.id] != nil })?.id
        }
    }

    // MARK: - SSH tunnel (external ssh) with auto-reconnect

    private func startTunnel(port: String) {
        guard let cfg else { return }
        guard let sshPath = ToolLocator.find("ssh") else {
            fail("Не найден ssh в системе.")
            return
        }
        let askpassPath: String
        do { askpassPath = try SSHAskpass.ensureScript() }
        catch { fail("Не удалось подготовить помощник паролей: \(error.localizedDescription)"); return }

        var args = [
            "-v", "-N",
            "-R", "\(port):localhost:\(port)",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ConnectTimeout=15",
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3",
            "-o", "NumberOfPasswordPrompts=3"
        ]
        let extra = cfg.extraArgs.trimmingCharacters(in: .whitespaces)
        if !extra.isEmpty { args.append(contentsOf: ToolLocator.tokenize(extra, port: port)) }
        args.append("\(cfg.user)@\(cfg.host)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: sshPath)
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["SSH_ASKPASS"] = askpassPath
        env["SSH_ASKPASS_REQUIRE"] = "force"
        env["DISPLAY"] = env["DISPLAY"] ?? ":0"
        env[SSHAskpass.envVar] = cfg.password
        process.environment = env

        let outPipe = Pipe(); let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let displayCmd = "ssh " + args.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
        appendLine(.command, displayCmd)

        let handler: (FileHandle) -> Void = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            guard let self, let text = String(data: d, encoding: .utf8) else { return }
            DispatchQueue.main.async { self.handleSSHText(text) }
        }
        outPipe.fileHandleForReading.readabilityHandler = handler
        errPipe.fileHandleForReading.readabilityHandler = handler

        process.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            guard let self else { return }
            DispatchQueue.main.async { self.sshDidExit(status: status) }
        }

        do {
            try process.run()
            sshProcess = process
            appendLine(.info, retries > 0
                ? "Переподключение к \(cfg.user)@\(cfg.host) (попытка \(retries))…"
                : "Поднимаю обратный туннель к \(cfg.user)@\(cfg.host)…")
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                guard let self else { return }
                if (self.phase == .connecting || self.phase == .reconnecting),
                   self.sawAuthenticated, self.sshProcess?.isRunning == true {
                    self.tunnelBecameReady()
                }
            }
        } catch {
            fail("Не удалось запустить ssh: \(error.localizedDescription)")
        }
    }

    private func handleSSHText(_ text: String) {
        controlBuffer += text
        emitControlLines()
        if text.contains("Authenticated to") || text.contains("Authentication succeeded") {
            sawAuthenticated = true
        }
        if phase == .connecting || phase == .reconnecting {
            let markers = ["remote forward success", "Entering interactive session",
                           "All remote forwarding requests processed"]
            if markers.contains(where: { text.contains($0) }) { tunnelBecameReady() }
        }
        if text.contains("Permission denied") {
            appendLine(.error, "Аутентификация не удалась. Проверьте пароль в Настройках.")
        }
    }

    private func tunnelBecameReady() {
        guard phase == .connecting || phase == .reconnecting else { return }
        retries = 0
        phase = .listening
        appendLine(.info, "Обратный туннель поднят на порту \(activePort).")
        logFiles.appendSession("[\(now())] SYS tunnel up on port \(activePort)")
    }

    private func sshDidExit(status: Int32) {
        emitControlLines(flush: true)
        sshProcess = nil
        if userClosed { return }
        appendLine(.error, "ssh-туннель закрыт (код \(status)).")
        logFiles.appendSession("[\(now())] ERR ssh exited \(status)")
        if autoReconnect { scheduleReconnect() }
        else { phase = .failed("ssh exited \(status)") }
    }

    private func scheduleReconnect() {
        if userClosed { return }
        if retries >= maxRetries {
            appendLine(.error, "Исчерпаны попытки переподключения (\(maxRetries)).")
            phase = .failed("reconnect exhausted")
            return
        }
        retries += 1
        phase = .reconnecting
        appendLine(.info, "Связь потеряна. Переподключение через \(Int(reconnectDelay)) c…")
        DispatchQueue.main.asyncAfter(deadline: .now() + reconnectDelay) { [weak self] in
            guard let self, !self.userClosed, self.cfg != nil else { return }
            self.sawAuthenticated = false
            self.startTunnel(port: self.activePort)
        }
    }

    // MARK: - Teardown

    private func stopEverything() {
        sshProcess?.terminate()
        sshProcess = nil
        for (_, conn) in nwConns { conn.cancel() }
        nwConns.removeAll()
        listener?.cancel()
        listener = nil
    }

    // MARK: - Helpers

    private func fail(_ message: String) {
        appendLine(.error, message)
        logFiles.appendSession("[\(now())] ERR \(message)")
        stopEverything()
        phase = .failed(message)
    }

    private func appendLine(_ kind: LogKind, _ text: String) {
        lines.append(LogLine(timestamp: Date(), kind: kind, text: text))
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
    }

    private func emitControlLines(flush: Bool = false) {
        while let range = controlBuffer.range(of: "\n") {
            let line = String(controlBuffer[controlBuffer.startIndex..<range.lowerBound])
                .replacingOccurrences(of: "\r", with: "")
                .trimmingCharacters(in: .whitespaces)
            controlBuffer.removeSubrange(controlBuffer.startIndex..<range.upperBound)
            if !line.isEmpty {
                appendLine(.control, line)
                logFiles.appendSession("[\(now())] SSH \(line)")
            }
        }
        if flush, !controlBuffer.isEmpty {
            let line = controlBuffer.replacingOccurrences(of: "\r", with: "").trimmingCharacters(in: .whitespaces)
            controlBuffer = ""
            if !line.isEmpty { appendLine(.control, line) }
        }
    }

    private func sanitizeForDisplay(_ s: String) -> String {
        var out = ""
        for scalar in s.unicodeScalars {
            if scalar == "\t" || scalar.value >= 0x20 { out.unicodeScalars.append(scalar) }
            else { out.append("·") }
        }
        return out
    }

    private func now() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f.string(from: Date())
    }

    static func peerString(_ ep: NWEndpoint) -> String {
        switch ep {
        case .hostPort(let host, let port): return "\(host):\(port)"
        default: return "\(ep)"
        }
    }
}
