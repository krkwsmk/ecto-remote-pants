import SwiftUI

struct ConsoleView: View {
    @ObservedObject var session: TunnelSession

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(session.lines) { line in
                        ConsoleRow(line: line).id(line.id)
                    }
                    Color.clear.frame(height: 1).id("BOTTOM")
                }
                .padding(12)
            }
            .background(ZStack { Theme.bg; ScanlineOverlay() })
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.neonGreen.opacity(0.25), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .onChange(of: session.lines.count) { _ in
                if session.autoScroll {
                    withAnimation(.linear(duration: 0.1)) { proxy.scrollTo("BOTTOM", anchor: .bottom) }
                }
            }
        }
    }
}

struct ConsoleRow: View {
    let line: LogLine

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(line.timeString).font(Theme.monoSmall).foregroundStyle(Theme.textDim.opacity(0.7))
            Text(line.kind.tag).font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(line.kind.color)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(line.kind.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 3))
            Text(line.text).font(Theme.mono)
                .foregroundStyle(line.kind == .data ? Theme.textPrimary : line.kind.color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ScanlineOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let lineHeight: CGFloat = 3
            let count = max(1, Int(geo.size.height / lineHeight) + 1)
            VStack(spacing: lineHeight - 1) {
                ForEach(Array(0..<count), id: \.self) { _ in
                    Rectangle().fill(Color.white.opacity(0.012)).frame(height: 1)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
