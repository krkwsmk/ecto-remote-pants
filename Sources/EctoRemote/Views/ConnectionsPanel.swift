import SwiftUI

struct ConnectionsPanel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NeonPanel(accent: Theme.neonMagenta, title: "Connections (\(model.connections.count))") {
            if model.connections.isEmpty {
                Text("No inbound connections yet.")
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
                .frame(maxHeight: 180)
            }
        }
    }
}

struct ConnectionRow: View {
    let index: Int
    let conn: ConnectionRecord
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Text(String(format: "#%03d", index))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.neonMagenta)
            VStack(alignment: .leading, spacing: 1) {
                Text(conn.peer)
                    .font(Theme.monoSmall)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("\(conn.bytes) B · \(conn.startedString)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                model.revealConnection(conn)
            } label: {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(Theme.neonCyan)
            }
            .buttonStyle(.plain)
            .help("Reveal log file in Finder")
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(Theme.bg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6).stroke(Theme.stroke, lineWidth: 1)
        )
    }
}
