import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            appHeader
            Divider().overlay(Theme.stroke)
            tabStrip
            Divider().overlay(Theme.stroke)
            if let s = model.selected {
                SessionView(session: s)
                    .id(s.id)
            } else {
                Spacer()
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .sheet(isPresented: $showingSettings) { settingsSheet }
    }

    private var appHeader: some View {
        HStack(spacing: 14) {
            HStack(spacing: 2) {
                Text("ECTO").font(.system(size: 20, weight: .black, design: .monospaced))
                    .foregroundStyle(Theme.titleGradient)
                Text("//REMOTE").font(.system(size: 20, weight: .black, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
            }
            Text("клиент релейного туннеля").font(Theme.monoSmall).foregroundStyle(Theme.textDim)
            Spacer()
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(Theme.neonCyan)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(Theme.panel)
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.sessions) { s in
                    TabChip(session: s, selected: s.id == model.selectedId,
                            canClose: model.sessions.count > 1,
                            onSelect: { model.selectedId = s.id },
                            onClose: { model.closeSession(s) })
                }
                Button { model.addSession() } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Theme.neonCyan)
                        .frame(width: 30, height: 30)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.stroke, lineWidth: 1).foregroundStyle(Theme.stroke))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .background(Theme.panel)
    }

    private var settingsSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("НАСТРОЙКИ").font(.system(size: 12, weight: .black, design: .monospaced))
                    .tracking(2).foregroundStyle(Theme.neonCyan)
                Spacer()
                Button {
                    model.persistSettings()
                    showingSettings = false
                } label: {
                    Text("ГОТОВО").font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .tracking(1).padding(.horizontal, 14).padding(.vertical, 6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.neonGreen.opacity(0.8), lineWidth: 1))
                        .foregroundStyle(Theme.neonGreen)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Theme.panel)

            SettingsView().environmentObject(model)
        }
        .frame(width: 520, height: 640)
        .background(Theme.bg)
    }
}

struct TabChip: View {
    @ObservedObject var session: TunnelSession
    let selected: Bool
    let canClose: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(session.phase.color).frame(width: 8, height: 8)
            Text(session.title.isEmpty ? "Вкладка" : session.title)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            if canClose {
                Button { onClose() } label: {
                    Image(systemName: "xmark").font(.system(size: 9)).foregroundStyle(Theme.textDim)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Theme.panelRaised : Theme.bg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(selected ? Theme.neonCyan.opacity(0.45) : Theme.stroke, lineWidth: 1)
        )
        .frame(maxWidth: 230)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }
}

struct StatusPill: View {
    let phase: ConnectionPhase
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(phase.color).frame(width: 9, height: 9)
                .shadow(color: phase.color, radius: pulse ? 6 : 2)
                .opacity(phase.isActive ? (pulse ? 1 : 0.5) : 1)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
                }
            Text(phase.label).font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(2).foregroundStyle(phase.color)
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(Capsule().fill(phase.color.opacity(0.12)))
        .overlay(Capsule().stroke(phase.color.opacity(0.6), lineWidth: 1))
    }
}
