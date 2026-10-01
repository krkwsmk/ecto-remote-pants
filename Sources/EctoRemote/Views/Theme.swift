import SwiftUI

/// Cyberpunk palette and reusable styling helpers.
enum Theme {
    // Core background tones
    static let bg = Color(hex: 0x05060B)
    static let panel = Color(hex: 0x0B0F1A)
    static let panelRaised = Color(hex: 0x111726)
    static let stroke = Color(hex: 0x1C2740)

    // Neon accents
    static let neonCyan = Color(hex: 0x19F0FF)
    static let neonMagenta = Color(hex: 0xFF2E97)
    static let neonPurple = Color(hex: 0x9B5CFF)
    static let neonGreen = Color(hex: 0x3BFF8F)
    static let neonAmber = Color(hex: 0xFFB020)
    static let neonRed = Color(hex: 0xFF4D5E)

    static let textPrimary = Color(hex: 0xE6F6FF)
    static let textDim = Color(hex: 0x7C8AA6)

    static let mono = Font.system(size: 12.5, weight: .regular, design: .monospaced)
    static let monoSmall = Font.system(size: 11, weight: .regular, design: .monospaced)

    static var titleGradient: LinearGradient {
        LinearGradient(
            colors: [neonCyan, neonMagenta],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [neonPurple, neonCyan],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

/// A framed panel with neon edge glow.
struct NeonPanel<Content: View>: View {
    var accent: Color = Theme.neonCyan
    var title: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(accent)
                        .frame(width: 3, height: 14)
                    Text(title.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(accent)
                }
            }
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(accent.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: accent.opacity(0.12), radius: 14, x: 0, y: 0)
    }
}

/// Primary neon action button.
struct NeonButton: View {
    let title: String
    var accent: Color = Theme.neonCyan
    var systemImage: String? = nil
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .tracking(1.5)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accent.opacity(enabled ? 0.16 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(accent.opacity(enabled ? 0.9 : 0.25), lineWidth: 1.2)
            )
            .foregroundStyle(enabled ? accent : Theme.textDim)
            .shadow(color: accent.opacity(enabled ? 0.35 : 0), radius: 10)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Monospaced neon text field.
struct NeonTextField: View {
    let placeholder: String
    @Binding var text: String
    var accent: Color = Theme.neonCyan

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(Theme.mono)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Theme.bg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(accent.opacity(0.4), lineWidth: 1)
            )
    }
}

struct NeonSecureField: View {
    let placeholder: String
    @Binding var text: String
    var accent: Color = Theme.neonMagenta

    var body: some View {
        SecureField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(Theme.mono)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Theme.bg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(accent.opacity(0.4), lineWidth: 1)
            )
    }
}
