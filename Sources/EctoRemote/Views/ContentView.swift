import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar()
            Divider().overlay(Theme.stroke)
            HStack(spacing: 14) {
                controlColumn
                    .frame(width: 320)
                consoleColumn
            }
            .padding(14)
        }
        .background(Theme.bg.ignoresSafeArea())
        .onDisappear { model.persistSettings() }
        .sheet(isPresented: $showingSettings) { settingsSheet }
    }

    private var settingsSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("НАСТРОЙКИ")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(Theme.neonCyan)
                Spacer()
                Button {
                    model.persistSettings()
                    showingSettings = false
                } label: {
                    Text("ГОТОВО")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .tracking(1)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Theme.neonGreen.opacity(0.8), lineWidth: 1)
                        )
                        .foregroundStyle(Theme.neonGreen)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.panel)

            SettingsView()
                .environmentObject(model)
        }
        .frame(width: 520, height: 624)
        .background(Theme.bg)
    }

    // MARK: - Left column

    private var controlColumn: some View {
        VStack(spacing: 14) {
            NeonPanel(accent: Theme.neonCyan, title: "Управление") {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("ПОРТ")
                    NeonTextField(placeholder: "напр. 9000", text: $model.port, accent: Theme.neonCyan)

                    if !model.hasRelayPassword {
                        Text("Пароль и релей задаются в Настройках.")
                            .font(Theme.monoSmall)
                            .foregroundStyle(Theme.neonAmber.opacity(0.9))
                    }

                    if model.phase.isActive {
                        NeonButton(title: "Отключить", accent: Theme.neonRed,
                                   systemImage: "bolt.slash.fill") {
                            model.disconnect()
                        }
                    } else {
                        NeonButton(title: "Подключить", accent: Theme.neonGreen,
                                   systemImage: "bolt.fill") {
                            model.connect()
                        }
                    }

                    if model.phase == .tunnelUp && !model.autoStartListener {
                        NeonButton(title: "Запустить слушатель", accent: Theme.neonAmber,
                                   systemImage: "dot.radiowaves.left.and.right") {
                            model.startListener()
                        }
                    }
                }
            }

            ConnectionsPanel()

            NeonPanel(accent: Theme.neonPurple, title: "Логи") {
                VStack(spacing: 10) {
                    NeonButton(title: "Открыть папку логов", accent: Theme.neonPurple,
                               systemImage: "folder.fill") {
                        model.revealLogsInFinder()
                    }
                    HStack(spacing: 10) {
                        NeonButton(title: "Настройки", accent: Theme.neonCyan,
                                   systemImage: "gearshape.fill") {
                            showingSettings = true
                        }
                        NeonButton(title: "Очистить", accent: Theme.textDim,
                                   systemImage: "trash") {
                            model.clearScreen()
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Right column

    private var consoleColumn: some View {
        VStack(spacing: 10) {
            HStack {
                Text("ПОТОК ДАННЫХ")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(Theme.neonGreen)
                Spacer()
                Text("\(model.totalBytes) байт")
                    .font(Theme.monoSmall)
                    .foregroundStyle(Theme.textDim)
                Toggle(isOn: $model.autoScroll) {
                    Text("автопрокрутка").font(Theme.monoSmall)
                }
                .toggleStyle(.switch)
                .tint(Theme.neonGreen)
                .foregroundStyle(Theme.textDim)
            }
            ConsoleView()
            commandBar
        }
    }

    private var commandBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(model.canSend ? Theme.neonAmber : Theme.textDim)
            TextField(model.canSend ? "Команда устройству, Enter — отправить" : "Нет активного соединения",
                      text: $model.commandInput)
                .textFieldStyle(.plain)
                .font(Theme.mono)
                .foregroundStyle(Theme.textPrimary)
                .disabled(!model.canSend)
                .onSubmit { model.sendCommand() }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.bg))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.neonAmber.opacity(model.canSend ? 0.5 : 0.2), lineWidth: 1))
            Button { model.sendCommand() } label: {
                Text("SEND")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .tracking(1)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.neonAmber.opacity(model.canSend ? 0.16 : 0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.neonAmber.opacity(model.canSend ? 0.9 : 0.25), lineWidth: 1.2))
                    .foregroundStyle(model.canSend ? Theme.neonAmber : Theme.textDim)
            }
            .buttonStyle(.plain)
            .disabled(!model.canSend)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(Theme.textDim)
    }
}

struct HeaderBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 2) {
                Text("ECTO")
                    .font(.system(size: 22, weight: .black, design: .monospaced))
                    .foregroundStyle(Theme.titleGradient)
                Text("//REMOTE")
                    .font(.system(size: 22, weight: .black, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
            }
            Text("клиент релейного туннеля")
                .font(Theme.monoSmall)
                .foregroundStyle(Theme.textDim)
            Spacer()
            StatusPill(phase: model.phase)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Theme.panel)
    }
}

struct StatusPill: View {
    let phase: ConnectionPhase
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(phase.color)
                .frame(width: 9, height: 9)
                .shadow(color: phase.color, radius: pulse ? 6 : 2)
                .opacity(phase.isActive ? (pulse ? 1 : 0.5) : 1)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                }
            Text(phase.label)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(phase.color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Capsule().fill(phase.color.opacity(0.12))
        )
        .overlay(
            Capsule().stroke(phase.color.opacity(0.6), lineWidth: 1)
        )
    }
}
