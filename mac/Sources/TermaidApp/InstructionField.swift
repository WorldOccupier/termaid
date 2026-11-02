import SwiftUI

/// The words the instruction field uses, so the editor talks about changes and the composer about flows.
struct InstructionPrompts {
    let placeholder: String
    let submitHelp: String
    let speakHelp: String
    let stopHelp: String

    static let edit = InstructionPrompts(placeholder: "Describe a change…", submitHelp: "Apply change (Return)",
                                         speakHelp: "Say a change", stopHelp: "Stop and apply (Return)")
    static let create = InstructionPrompts(placeholder: "Describe a flow…", submitHelp: "Draw diagram (Return)",
                                           speakHelp: "Say a flow", stopHelp: "Stop and draw (Return)")
}

/// Where an instruction is described: type it and press Return, or click the mic, speak, and press Return or stop.
/// One trailing button: mic when empty, arrow once there's text, stop while listening.
struct InstructionField: View {
    @ObservedObject var session: InstructionSession
    var prompts = InstructionPrompts.edit
    /// Leaves the instruction being run in the field, grayed, instead of letting it fly off to a list.
    var showsPendingInstruction = false
    @FocusState private var focused: Bool

    private var listening: Bool { session.activity == .listening }
    private var hasText: Bool { !InstructionSession.trimmed(session.instruction).isEmpty }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            TextField(placeholder, text: $session.instruction, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .tint(Color.caretBlue)
                .lineLimit(1...5)
                .focused($focused)
                .onSubmit(submit)
                .disabled(session.isBusy)
            trailingButton
        }
        .padding(.leading, 12)
        .padding(.trailing, 5)
        .padding(.vertical, 5)
        .frame(minHeight: 38)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.35)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(listening ? Obsidian.rose : Obsidian.border.opacity(focused ? 1 : 0.6)))
        .animation(.easeOut(duration: 0.15), value: listening)
        .animation(.easeOut(duration: 0.15), value: hasText)
        .flightAnchor(FlightAnchor.source)
        .onAppear { focused = true }
        .onChange(of: listening) { _, isListening in if isListening { focused = true } }
    }

    private var placeholder: String {
        if listening { return StatusLabel.listening }
        if showsPendingInstruction, let pending = session.pendingInstruction { return pending }
        return prompts.placeholder
    }

    private func submit() {
        listening ? session.toggleListening() : session.applyInstruction()
    }

    @ViewBuilder private var trailingButton: some View {
        if listening {
            // Return must stop listening even when the click on the mic took focus away from the field.
            RoundIconButton(symbol: "stop.fill", filled: true, help: prompts.stopHelp, action: session.toggleListening)
                .keyboardShortcut(.defaultAction)
        } else if hasText {
            RoundIconButton(symbol: "arrow.up", filled: true, help: prompts.submitHelp, action: session.applyInstruction)
                .disabled(!session.canApply)
        } else {
            RoundIconButton(symbol: "mic.fill", filled: false, help: prompts.speakHelp, action: session.toggleListening)
                .disabled(session.activity != .idle)
        }
    }
}

/// A 26 pt circle with its symbol optically centered; used for the mic, stop and apply buttons.
private struct RoundIconButton: View {
    let symbol: String
    let filled: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(filled ? (symbol == "stop.fill" ? Obsidian.rose : Color.white) : Color.white.opacity(0.08))
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(filled ? (symbol == "stop.fill" ? Color.white : Color.black) : Obsidian.fg.opacity(0.85))
            }
            .frame(width: 26, height: 26)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
    }
}
