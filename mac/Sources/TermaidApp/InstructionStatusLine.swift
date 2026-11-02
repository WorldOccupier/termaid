import SwiftUI

/// One short line under an instruction field: the error, else what's happening, else an optional hint.
/// Kept to two lines so a long error never pushes the buttons around.
struct InstructionStatusLine: View {
    @ObservedObject var session: InstructionSession
    var idleHint: String?

    var body: some View {
        Group {
            if let error = session.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Obsidian.rose)
                    .lineLimit(2)
                    .help(error)
            } else if let working = session.statusLabel {
                Label(working, systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Obsidian.muted)
            } else if let idleHint {
                Text(idleHint).foregroundStyle(Obsidian.muted)
            }
        }
        .font(Obsidian.font(11.5))
    }
}
