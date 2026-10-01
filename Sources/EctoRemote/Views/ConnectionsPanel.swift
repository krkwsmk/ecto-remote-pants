import SwiftUI

struct ConnectionsPanel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NeonPanel(accent: Theme.neonMagenta, title: "Соединения (\(model.connections.count))") {
            if model.connections.isEmpty {
                Text("Пока нет входящих соединений с данными.")
                    .font(Theme.monoSmall)
                    .foregroundStyle(Theme.textDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(model.connections.enumerated().reversed()), id: \.element.id) { idx, conn in
                            ConnectionRow(index: idx + 1, conn: conn)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
    }
}

struct ConnectionRow: View {
    let index: Int
    let conn: ConnectionRecord
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Text(String(format: "#%03d", index))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.neonMagenta)

            VStack(alignment: .leading, spacing: 2) {
                Text(conn.peer)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.neonCyan)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(conn.bytes) B  ·  \(conn.startedString)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary.opacity(0.85))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Button {
                model.revealConnection(conn)
            } label: {
                Text("ОТКРЫТЬ")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Theme.neonCyan.opacity(0.7), lineWidth: 1)
                    )
                    .foregroundStyle(Theme.neonCyan)
            }
            .buttonStyle(.plain)
            .help("Показать файл лога в Finder")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7).fill(Theme.panelRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7).stroke(Theme.stroke, lineWidth: 1)
        )
    }
}
