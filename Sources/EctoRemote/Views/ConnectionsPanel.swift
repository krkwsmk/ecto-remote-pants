import SwiftUI

struct ConnectionsPanel: View {
    @ObservedObject var session: TunnelSession

    var body: some View {
        NeonPanel(accent: Theme.neonMagenta, title: "Соединения (\(session.connections.count))") {
            if session.connections.isEmpty {
                Text("Нет подключений устройств.")
                    .font(Theme.monoSmall).foregroundStyle(Theme.textDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(session.connections.reversed()) { conn in
                            ConnectionRow(session: session, conn: conn)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
    }
}

struct ConnectionRow: View {
    @ObservedObject var session: TunnelSession
    let conn: ConnectionRecord

    private var isTarget: Bool { session.targetConnId == conn.id }

    var body: some View {
        HStack(spacing: 8) {
            Button { session.setTarget(conn) } label: {
                Text(isTarget ? "●" : "○")
                    .font(.system(size: 13))
                    .foregroundStyle(conn.status == .active ? Theme.neonAmber : Theme.textDim)
            }
            .buttonStyle(.plain)
            .disabled(conn.status != .active)
            .help("Сделать активным для команд")

            Text(String(format: "#%03d", conn.number))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.neonMagenta)

            VStack(alignment: .leading, spacing: 1) {
                Text(conn.peer + (conn.status == .closed ? "  (закрыто)" : ""))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.neonCyan).lineLimit(1).truncationMode(.middle)
                Text("\(conn.bytes) B · \(conn.startedString)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary.opacity(0.85)).lineLimit(1)
            }

            Spacer(minLength: 4)

            if conn.status == .active {
                Button { session.closeConnection(conn) } label: {
                    Text("ОБОРВАТЬ").font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.neonRed.opacity(0.7), lineWidth: 1))
                        .foregroundStyle(Theme.neonRed)
                }
                .buttonStyle(.plain)
            }
            Button { session.revealConnection(conn) } label: {
                Text("ФАЙЛ").font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.neonCyan.opacity(0.6), lineWidth: 1))
                    .foregroundStyle(Theme.neonCyan)
            }
            .buttonStyle(.plain)
            .disabled(conn.fileURL == nil)
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.panelRaised))
        .overlay(RoundedRectangle(cornerRadius: 7)
            .stroke(isTarget ? Theme.neonAmber.opacity(0.6) : Theme.stroke, lineWidth: 1))
        .opacity(conn.status == .closed ? 0.55 : 1)
    }
}
