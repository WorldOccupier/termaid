import AVFoundation
import AppKit
import SwiftUI

/// First-run setup: downloads and loads both models and asks for the microphone, so the first ⌥ Space is instant.
@MainActor
enum SetupWindow {
    private static var window: NSWindow?

    static func show(onDone: @escaping @MainActor () -> Void) {
        ModelStore.shared.prepare()  // loads what's already here; downloads wait for the button
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let view = SetupView(store: .shared) {
            ModelStore.shared.markSetupDone()
            close()
            onDone()
        }
        let hosting = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hosting)
        win.title = "Set up termaid"
        win.styleMask = [.titled, .closable, .fullSizeContentView]
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.appearance = NSAppearance(named: .darkAqua)
        win.backgroundColor = NSColor(red: 5 / 255, green: 5 / 255, blue: 6 / 255, alpha: 1)
        win.isReleasedWhenClosed = false
        win.center()
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    static func close() {
        window?.close()
        window = nil
    }
}

/// One round control per row that changes in place: an icon button, then a progress ring, then a green tick.
private struct StatusOrb: View {
    enum Look: Equatable {
        case action(symbol: String, help: String)  // tappable, blue
        case progress(Double?)                      // a ring; nil spins
        case done                                   // green tick
        case problem(symbol: String, help: String)  // tappable, amber
        case idle                                   // waiting on something else
    }

    let look: Look
    var size: CGFloat = 24
    var action: () -> Void = {}
    @State private var spin = false

    var body: some View {
        ZStack {
            switch look {
            case .action(let symbol, _):
                Circle().fill(Obsidian.accent)
                    .overlay(Circle().stroke(Color.white.opacity(0.15)))
                Image(systemName: symbol).font(.system(size: size * 0.42, weight: .heavy)).foregroundStyle(.white)
            case .problem(let symbol, _):
                Circle().fill(Obsidian.amber)
                    .overlay(Circle().stroke(Color.white.opacity(0.2)))
                Image(systemName: symbol).font(.system(size: size * 0.42, weight: .heavy)).foregroundStyle(.black.opacity(0.85))
            case .progress(let fraction):
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: fraction.map { max(0.03, $0) } ?? 0.28)
                    .stroke(Obsidian.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(fraction == nil ? (spin ? 270 : -90) : -90))
                    .animation(fraction == nil ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .easeOut(duration: 0.25), value: spin)
                    .animation(.easeOut(duration: 0.25), value: fraction)
                    .onAppear { spin = true }
                    .onDisappear { spin = false }
                    .padding(2)
            case .done:
                Circle().fill(Obsidian.green)
                    .overlay(Circle().stroke(Color.white.opacity(0.2)))
                Image(systemName: "checkmark").font(.system(size: size * 0.42, weight: .heavy)).foregroundStyle(.white)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            case .idle:
                Circle().stroke(Obsidian.border, lineWidth: 1.5)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .onTapGesture { if tappable { action() } }
        .help(helpText)
        .onHover { inside in if tappable { inside ? NSCursor.pointingHand.push() : NSCursor.pop() } }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: look)
    }

    private var tappable: Bool {
        switch look {
        case .action, .problem: return true
        default: return false
        }
    }

    private var helpText: String {
        switch look {
        case .action(_, let h), .problem(_, let h): return h
        default: return ""
        }
    }
}

private struct SetupView: View {
    @ObservedObject var store: ModelStore
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Set up termaid")
                .font(Obsidian.font(24, .semibold))
                .foregroundStyle(Obsidian.fg)
            Text("Everything runs on this Mac. Download the speech model once; after that termaid starts ready.")
                .font(Obsidian.font(13))
                .foregroundStyle(Obsidian.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            VStack(spacing: 0) {
                row(icon: "waveform", title: "Speech model", detail: speechDetail,
                    failed: isFailure(store.speech)) {
                    StatusOrb(look: speechLook) {
                        if case .failed = store.speech { store.retry() } else { store.downloadSpeech() }
                    }
                }
                divider
                row(icon: "point.3.connected.trianglepath.dotted", title: "Diagram model", detail: diagramDetail,
                    failed: isFailure(store.diagram)) {
                    StatusOrb(look: diagramLook) { store.chooseModelFile() }
                }
                divider
                row(icon: "mic", title: "Microphone", detail: micDetail, failed: false) {
                    StatusOrb(look: micLook) { store.requestMicrophone() }
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(Obsidian.surface))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Obsidian.border.opacity(0.8)))
            .padding(.top, 20)

            HStack {
                Text(store.allReady ? "Ready. Hold ⌥ Space to talk · ⌥ T to type" : "Hold ⌥ Space to talk · ⌥ T to type")
                    .font(Obsidian.font(12))
                    .foregroundStyle(store.allReady ? Obsidian.fg : Obsidian.muted)
                Spacer()
                StatusOrb(look: .action(symbol: "arrow.right", help: "Get started"), size: 28) {
                    if store.allReady { onDone() }
                }
                .saturation(store.allReady ? 1 : 0)
                .opacity(store.allReady ? 1 : 0.3)
                .allowsHitTesting(store.allReady)
                .animation(.easeOut(duration: 0.3), value: store.allReady)
            }
            .padding(.top, 18)
            .padding(.trailing, 14)
        }
        .padding(28)
        .frame(width: 480)
        .background(Obsidian.canvas)
        .preferredColorScheme(.dark)
        .background {
            // Return still finishes setup once everything's ready.
            Button("", action: onDone).keyboardShortcut(.defaultAction).disabled(!store.allReady).hidden()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshMicrophone()
        }
    }

    private var divider: some View {
        Rectangle().fill(Obsidian.border.opacity(0.6)).frame(height: 1)
    }

    // MARK: Speech

    private var speechLook: StatusOrb.Look {
        switch store.speech {
        case .notDownloaded: return .action(symbol: "arrow.down", help: "Download the speech model")
        case .downloading(let f): return .progress(f)
        case .loading, .waiting: return .progress(nil)
        case .ready: return .done
        case .failed: return .problem(symbol: "arrow.clockwise", help: "Try again")
        case .missing: return .idle
        }
    }

    private var speechDetail: String {
        switch store.speech {
        case .notDownloaded: return "About 480 MB, downloaded once"
        case .downloading(let f): return "Downloading · \(Int(f * 100))%"
        case .loading: return "Preparing for this Mac…"
        case .ready: return "Ready"
        case .failed(let m): return m
        default: return "Waiting"
        }
    }

    // MARK: Diagram

    private var diagramLook: StatusOrb.Look {
        switch store.diagram {
        case .ready: return .done
        case .missing, .failed: return .problem(symbol: "folder", help: "Choose the .gguf model file")
        default: return .progress(nil)
        }
    }

    private var diagramDetail: String {
        switch store.diagram {
        case .loading, .waiting: return "Loading…"
        case .ready: return "Ready"
        case .missing: return "Not found — choose the .gguf model file"
        case .failed(let m): return m
        default: return "Waiting"
        }
    }

    // MARK: Microphone

    private var micLook: StatusOrb.Look {
        switch store.microphone {
        case .authorized: return .done
        case .denied, .restricted: return .problem(symbol: "gearshape", help: "Open Privacy settings")
        default: return .action(symbol: "mic.fill", help: "Allow microphone access")
        }
    }

    private var micDetail: String {
        switch store.microphone {
        case .authorized: return "Allowed"
        case .denied, .restricted: return "Blocked — allow termaid in System Settings to talk"
        default: return "Needed to talk; typing works without it"
        }
    }

    // MARK: Layout

    private func row<Trailing: View>(icon: String, title: String, detail: String, failed: Bool,
                                     @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .frame(width: 22)
                .foregroundStyle(Obsidian.muted)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Obsidian.font(13.5, .semibold)).foregroundStyle(Obsidian.fg)
                Text(detail)
                    .font(Obsidian.font(12))
                    .foregroundStyle(failed ? Obsidian.rose : Obsidian.muted)
                    .lineLimit(2)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.2), value: detail)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func isFailure(_ status: ModelStore.Status) -> Bool {
        if case .failed = status { return true }
        return false
    }
}
