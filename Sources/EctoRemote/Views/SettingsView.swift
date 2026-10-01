import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("НАСТРОЙКИ")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(Theme.titleGradient)

                NeonPanel(accent: Theme.neonCyan, title: "Релей") {
                    VStack(alignment: .leading, spacing: 10) {
                        label("ПОЛЬЗОВАТЕЛЬ SSH")
                        NeonTextField(placeholder: "debug", text: $model.sshUser)
                        label("ХОСТ SSH (IP)")
                        NeonTextField(placeholder: "176.53.160.131", text: $model.sshHost)
                        label("ПАРОЛЬ РЕЛЕЯ")
                        NeonSecureField(placeholder: "••••••••", text: $model.password)
                        Toggle(isOn: $model.savePasswordEnabled) {
                            Text("Запоминать пароль (Keychain)")
                                .font(Theme.monoSmall)
                                .foregroundStyle(Theme.textDim)
                        }
                        .toggleStyle(.switch)
                        .tint(Theme.neonMagenta)
                        label("ДОП. АРГУМЕНТЫ SSH (необязательно)")
                        NeonTextField(placeholder: "-o Option=value", text: $model.sshExtraArgs)
                        Text("Пароль хранится в Keychain, отдельно для каждого user@host.")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.textDim)
                    }
                }

                NeonPanel(accent: Theme.neonGreen, title: "Слушатель") {
                    VStack(alignment: .leading, spacing: 10) {
                        label("КОМАНДА СЛУШАТЕЛЯ  ({PORT} подставляется)")
                        NeonTextField(placeholder: "ncat -lvkp {PORT}", text: $model.ncatTemplate, accent: Theme.neonGreen)
                        Toggle(isOn: $model.autoStartListener) {
                            Text("Запускать слушатель автоматически после поднятия туннеля")
                                .font(Theme.monoSmall)
                                .foregroundStyle(Theme.textDim)
                        }
                        .toggleStyle(.switch)
                        .tint(Theme.neonGreen)
                        Text("Нужен ncat (установка: brew install nmap). Можно заменить на другой, напр. nc -lk {PORT}.")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.textDim)
                    }
                }

                NeonPanel(accent: Theme.neonPurple, title: "Хранилище") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Папка логов:")
                            .font(Theme.monoSmall)
                            .foregroundStyle(Theme.textDim)
                        Text(model.logsFolderURL.path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.textPrimary)
                            .textSelection(.enabled)
                        NeonButton(title: "Открыть папку логов", accent: Theme.neonPurple,
                                   systemImage: "folder.fill") {
                            model.revealLogsInFinder()
                        }
                    }
                }

                HStack {
                    Spacer()
                    NeonButton(title: "Сохранить", accent: Theme.neonCyan, systemImage: "checkmark.seal.fill") {
                        model.persistSettings()
                    }
                    .frame(width: 180)
                }
            }
            .padding(22)
        }
        .frame(width: 520, height: 560)
        .background(Theme.bg)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(Theme.textDim)
    }
}
