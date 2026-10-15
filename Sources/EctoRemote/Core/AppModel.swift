import Foundation
import SwiftUI
import AppKit

/// Owns the list of tab sessions and the global relay settings shared by them.
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var sessions: [TunnelSession] = []
    @Published var selectedId: UUID?

    // Global relay settings (shared across tabs)
    @Published var sshUser: String = AppSettings.shared.sshUser
    @Published var sshHost: String = AppSettings.shared.sshHost
    @Published var password: String = AppSettings.shared.savedPassword() ?? ""
    @Published var savePasswordEnabled: Bool = AppSettings.shared.hasSavedPassword()
    @Published var sshExtraArgs: String = AppSettings.shared.sshExtraArgs
    @Published var lineEnding: String = AppSettings.shared.lineEnding
    @Published var autoReconnect: Bool = AppSettings.shared.autoReconnect

    init() {
        addSession()
    }

    var selected: TunnelSession? { sessions.first { $0.id == selectedId } }
    var hasRelayPassword: Bool { !password.isEmpty }
    var logsFolderURL: URL { LogFiles.rootLogsDir }

    @discardableResult
    func addSession() -> TunnelSession {
        let s = TunnelSession(port: AppSettings.shared.lastPort)
        sessions.append(s)
        selectedId = s.id
        return s
    }

    func closeSession(_ session: TunnelSession) {
        session.dispose()
        sessions.removeAll { $0.id == session.id }
        if selectedId == session.id {
            if let first = sessions.first { selectedId = first.id }
            else { addSession() }
        }
    }

    func connect(_ session: TunnelSession) {
        AppSettings.shared.lastPort = session.port.trimmingCharacters(in: .whitespaces)
        persistSettings()
        session.connect(relayConfig(for: session))
    }

    func relayConfig(for session: TunnelSession) -> RelayConfig {
        RelayConfig(
            port: session.port,
            user: sshUser.trimmingCharacters(in: .whitespaces),
            host: sshHost.trimmingCharacters(in: .whitespaces),
            password: password,
            extraArgs: sshExtraArgs,
            lineEnding: lineEnding,
            autoReconnect: autoReconnect
        )
    }

    func persistSettings() {
        let s = AppSettings.shared
        s.sshUser = sshUser
        s.sshHost = sshHost
        s.sshExtraArgs = sshExtraArgs
        s.lineEnding = lineEnding
        s.autoReconnect = autoReconnect
        if savePasswordEnabled { s.savePassword(password) } else { s.savePassword("") }
    }

    func revealLogsInFinder() { NSWorkspace.shared.activateFileViewerSelecting([logsFolderURL]) }

    func shutdownForTermination() {
        for s in sessions { s.dispose() }
    }
}
