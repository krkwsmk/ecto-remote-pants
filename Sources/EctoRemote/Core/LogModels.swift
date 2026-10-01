import Foundation
import SwiftUI

enum LogKind {
    case info       // app-level status
    case command    // the exact command being run
    case control    // ncat/ssh control chatter (stderr)
    case data       // actual stream payload
    case error

    var color: Color {
        switch self {
        case .info: return Theme.neonCyan
        case .command: return Theme.neonPurple
        case .control: return Theme.textDim
        case .data: return Theme.neonGreen
        case .error: return Theme.neonRed
        }
    }

    var tag: String {
        switch self {
        case .info: return "SYS"
        case .command: return "CMD"
        case .control: return "NET"
        case .data: return "RX "
        case .error: return "ERR"
        }
    }
}

struct LogLine: Identifiable {
    let id = UUID()
    let timestamp: Date
    let kind: LogKind
    let text: String

    var timeString: String {
        LogLine.formatter.string(from: timestamp)
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}

/// Metadata describing a single inbound connection and its log file.
struct ConnectionRecord: Identifiable {
    let id = UUID()
    let peer: String
    let startedAt: Date
    var bytes: Int
    let fileURL: URL

    var startedString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: startedAt)
    }
}
