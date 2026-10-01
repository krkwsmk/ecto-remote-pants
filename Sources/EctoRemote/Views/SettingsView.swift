import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("CONFIGURATION")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(Theme.titleGradient)

                NeonPanel(accent: Theme.neonCyan, title: "Relay") {
                    VStack(alignment: .leading, spacing: 10) {
                        label("SSH USER")
                        NeonTextField(placeholder: "debug", text: $model.sshUser)
                        label("SSH HOST")
                        NeonTextField(placeholder: "176.53.160.131", text: $model.sshHost)
                        label("EXTRA SSH ARGS (optional)")
                        NeonTextField(placeholder: "-o Option=value", text: $model.sshExtraArgs)
                        Text("Changing the user or host switches to that relay's saved password.")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.textDim)
                    }
                }

                NeonPanel(accent: Theme.neonGreen, title: "Listener") {
                    VStack(alignment: .leading, spacing: 10) {
                        label("LISTENER COMMAND  ({PORT} is substituted)")
                        NeonTextField(placeholder: "ncat -lvkp {PORT}", text: $model.ncatTemplate, accent: Theme.neonGreen)
                        Toggle(isOn: $model.autoStartListener) {
                            Text("Start listener automatically once the tunnel is up")
                                .font(Theme.monoSmall)
                                .foregroundStyle(Theme.textDim)
                        }
                        .toggleStyle(.switch)
                        .tint(Theme.neonGreen)
                        Text("Requires ncat (install with: brew install nmap). You may substitute another listener, e.g. nc -lk {PORT}.")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.textDim)
                    }
                }

                NeonPanel(accent: Theme.neonPurple, title: "Storage") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Logs folder:")
                            .font(Theme.monoSmall)
                            .foregroundStyle(Theme.textDim)
                        Text(model.logsFolderURL.path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.textPrimary)
                            .textSelection(.enabled)
                        NeonButton(title: "Open Logs Folder", accent: Theme.neonPurple,
                                   systemImage: "folder.fill") {
                            model.revealLogsInFinder()
                        }
                    }
                }

                HStack {
                    Spacer()
                    NeonButton(title: "Save", accent: Theme.neonCyan, systemImage: "checkmark.seal.fill") {
                        model.persistSettings()
                    }
                    .frame(width: 160)
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
