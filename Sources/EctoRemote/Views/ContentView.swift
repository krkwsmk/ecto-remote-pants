import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    private func openSettings() {
        // Works across macOS 13 (showSettingsWindow:) and older (showPreferencesWindow:).
        if NSApp.responds(to: Selector(("showSettingsWindow:"))) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

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
    }

    // MARK: - Left column

    private var controlColumn: some View {
        VStack(spacing: 14) {
            NeonPanel(accent: Theme.neonCyan, title: "Link Control") {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("PORT")
                    NeonTextField(placeholder: "e.g. 9000", text: $model.port, accent: Theme.neonCyan)

                    fieldLabel("RELAY PASSWORD")
                    NeonSecureField(placeholder: "••••••••", text: $model.password)

                    Toggle(isOn: $model.savePasswordEnabled) {
                        Text("Remember password (Keychain)")
                            .font(Theme.monoSmall)
                            .foregroundStyle(Theme.textDim)
                    }
                    .toggleStyle(.switch)
                    .tint(Theme.neonMagenta)

                    Text("Relay: \(model.sshUser)@\(model.sshHost)")
                        .font(Theme.monoSmall)
                        .foregroundStyle(Theme.textDim)

                    if model.phase.isActive {
                        NeonButton(title: "Disconnect", accent: Theme.neonRed,
                                   systemImage: "bolt.slash.fill") {
                            model.disconnect()
                        }
                    } else {
                        NeonButton(title: "Connect", accent: Theme.neonGreen,
                                   systemImage: "bolt.fill") {
                            model.connect()
                        }
                    }

                    if model.phase == .tunnelUp && !model.autoStartListener {
                        NeonButton(title: "Start Listener", accent: Theme.neonAmber,
                                   systemImage: "dot.radiowaves.left.and.right") {
                            model.startListener()
                        }
                    }
                }
            }

            ConnectionsPanel()

            NeonPanel(accent: Theme.neonPurple, title: "Logs") {
                VStack(spacing: 10) {
                    NeonButton(title: "Open Logs Folder", accent: Theme.neonPurple,
                               systemImage: "folder.fill") {
                        model.revealLogsInFinder()
                    }
                    HStack(spacing: 10) {
                        NeonButton(title: "Settings", accent: Theme.neonCyan,
                                   systemImage: "gearshape.fill") {
                            openSettings()
                        }
                        NeonButton(title: "Clear", accent: Theme.textDim,
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
                Text("DATA STREAM")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(Theme.neonGreen)
                Spacer()
                Text("\(model.totalBytes) bytes")
                    .font(Theme.monoSmall)
                    .foregroundStyle(Theme.textDim)
                Toggle(isOn: $model.autoScroll) {
                    Text("auto-scroll").font(Theme.monoSmall)
                }
                .toggleStyle(.switch)
                .tint(Theme.neonGreen)
                .foregroundStyle(Theme.textDim)
            }
            ConsoleView()
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
            Text("tunnel relay client")
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
