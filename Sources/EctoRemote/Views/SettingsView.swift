import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var savedFlash = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("НАСТРОЙКИ").font(.system(size: 13, weight: .black, design: .monospaced))
                    .tracking(3).foregroundStyle(Theme.titleGradient)

                NeonPanel(accent: Theme.neonCyan, title: "Релей") {
                    VStack(alignment: .leading, spacing: 10) {
                        label("ПОЛЬЗОВАТЕЛЬ SSH")
                        NeonTextField(placeholder: "debug", text: $model.sshUser)
                        label("ХОСТ SSH (IP)")
                        NeonTextField(placeholder: "176.53.160.131", text: $model.sshHost)
                        label("ПАРОЛЬ РЕЛЕЯ")
                        NeonSecureField(placeholder: "••••••••", text: $model.password)
                        Toggle(isOn: $model.savePasswordEnabled) {
                            Text("Запоминать пароль").font(Theme.monoSmall).foregroundStyle(Theme.textDim)
                        }
                        .toggleStyle(.switch).tint(Theme.neonMagenta)
                        label("ДОП. АРГУМЕНТЫ SSH (необязательно)")
                        NeonTextField(placeholder: "-o Option=value", text: $model.sshExtraArgs)
                        Text("Релей общий для всех вкладок. Порт указывается в каждой вкладке.")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.textDim)
                    }
                }

                NeonPanel(accent: Theme.neonGreen, title: "Команды") {
                    VStack(alignment: .leading, spacing: 10) {
                        label("ПЕРЕВОД СТРОКИ ДЛЯ КОМАНД")
                        Picker("", selection: $model.lineEnding) {
                            Text("LF (\\n)").tag("lf")
                            Text("CR (\\r)").tag("cr")
                            Text("CRLF").tag("crlf")
                        }
                        .pickerStyle(.segmented).labelsHidden()
                        Text("Для терминальных устройств часто нужен CR.")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.textDim)
                    }
                }

                NeonPanel(accent: Theme.neonAmber, title: "Туннель") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $model.autoReconnect) {
                            Text("Авто-переподключение при обрыве туннеля (ssh)")
                                .font(Theme.monoSmall).foregroundStyle(Theme.textDim)
                        }
                        .toggleStyle(.switch).tint(Theme.neonAmber)
                        Text("При ошибке ssh (напр. код 255) туннель поднимется заново, принятые данные не теряются.")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.textDim)
                    }
                }

                NeonPanel(accent: Theme.neonPurple, title: "Хранилище") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Папка логов:").font(Theme.monoSmall).foregroundStyle(Theme.textDim)
                        Text(model.logsFolderURL.path).font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.textPrimary).textSelection(.enabled)
                        NeonButton(title: "Открыть папку логов", accent: Theme.neonPurple, systemImage: "folder.fill") {
                            model.revealLogsInFinder()
                        }
                    }
                }

                HStack(spacing: 12) {
                    if savedFlash {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Сохранено").font(.system(size: 11, weight: .bold, design: .monospaced))
                        }
                        .foregroundStyle(Theme.neonGreen).transition(.opacity)
                    }
                    Spacer()
                    NeonButton(title: "Сохранить", accent: Theme.neonCyan, systemImage: "checkmark.seal.fill") {
                        model.persistSettings()
                        withAnimation { savedFlash = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { savedFlash = false } }
                    }
                    .frame(width: 180)
                }
            }
            .padding(22)
        }
        .frame(width: 520, height: 580)
        .background(Theme.bg)
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(1.5).foregroundStyle(Theme.textDim)
    }
}
