import SwiftUI

struct SessionView: View {
    @ObservedObject var session: TunnelSession
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            controlColumn.frame(width: 330)
            consoleColumn
        }
        .padding(14)
    }

    private var controlColumn: some View {
        VStack(spacing: 14) {
            NeonPanel(accent: Theme.neonCyan, title: "Управление") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { StatusPill(phase: session.phase); Spacer() }

                    fieldLabel("ПОРТ")
                    NeonTextField(placeholder: "напр. 9000", text: $session.port, accent: Theme.neonCyan)

                    if !model.hasRelayPassword {
                        Text("Пароль и релей задаются в Настройках.")
                            .font(Theme.monoSmall).foregroundStyle(Theme.neonAmber.opacity(0.9))
                    }

                    if session.phase.isActive {
                        NeonButton(title: "Отключить", accent: Theme.neonRed, systemImage: "bolt.slash.fill") {
                            session.disconnect()
                        }
                    } else {
                        NeonButton(title: "Подключить", accent: Theme.neonGreen, systemImage: "bolt.fill") {
                            model.connect(session)
                        }
                    }
                }
            }

            ConnectionsPanel(session: session)

            NeonPanel(accent: Theme.neonPurple, title: "Логи") {
                VStack(spacing: 10) {
                    NeonButton(title: "Открыть папку логов", accent: Theme.neonPurple, systemImage: "folder.fill") {
                        session.revealLogsInFinder()
                    }
                    NeonButton(title: "Очистить экран", accent: Theme.textDim, systemImage: "trash") {
                        session.clearScreen()
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var consoleColumn: some View {
        VStack(spacing: 10) {
            HStack {
                Text("ПОТОК ДАННЫХ").font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(3).foregroundStyle(Theme.neonGreen)
                Spacer()
                if let tid = session.targetConnId,
                   let num = session.connections.first(where: { $0.id == tid })?.number {
                    Text("→ #\(String(format: "%03d", num))").font(Theme.monoSmall).foregroundStyle(Theme.neonAmber)
                }
                Text("\(session.totalBytes) байт").font(Theme.monoSmall).foregroundStyle(Theme.textDim)
                Toggle(isOn: $session.autoScroll) { Text("автопрокрутка").font(Theme.monoSmall) }
                    .toggleStyle(.switch).tint(Theme.neonGreen).foregroundStyle(Theme.textDim)
            }
            ConsoleView(session: session)
            commandBar
        }
    }

    private var commandBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                .foregroundStyle(session.canSend ? Theme.neonAmber : Theme.textDim)
            TextField(session.canSend ? "Команда устройству, Enter — отправить" : "Нет активного соединения",
                      text: $session.commandInput)
                .textFieldStyle(.plain).font(Theme.mono).foregroundStyle(Theme.textPrimary)
                .disabled(!session.canSend)
                .onSubmit { session.sendCommand() }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.bg))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.neonAmber.opacity(session.canSend ? 0.5 : 0.2), lineWidth: 1))
            Button { session.sendEnter() } label: {
                Image(systemName: "return").font(.system(size: 13, weight: .bold))
                    .padding(.horizontal, 12).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.neonCyan.opacity(session.canSend ? 0.14 : 0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.neonCyan.opacity(session.canSend ? 0.8 : 0.25), lineWidth: 1.2))
                    .foregroundStyle(session.canSend ? Theme.neonCyan : Theme.textDim)
            }
            .buttonStyle(.plain).disabled(!session.canSend).help("Отправить Enter устройству")
            Button { session.sendCommand() } label: {
                Text("SEND").font(.system(size: 12, weight: .heavy, design: .monospaced)).tracking(1)
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.neonAmber.opacity(session.canSend ? 0.16 : 0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.neonAmber.opacity(session.canSend ? 0.9 : 0.25), lineWidth: 1.2))
                    .foregroundStyle(session.canSend ? Theme.neonAmber : Theme.textDim)
            }
            .buttonStyle(.plain).disabled(!session.canSend)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(1.5).foregroundStyle(Theme.textDim)
    }
}
