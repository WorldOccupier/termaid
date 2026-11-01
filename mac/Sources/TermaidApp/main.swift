import AppKit
import Combine

/// Owns the capsule panel, the menu-bar item, the hotkeys and the app model.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private let hotkeys = Hotkeys()
    private var menuBar: MenuBar!
    private var panel: CapsulePanel!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = self.model
        let hosting = CapsuleHostingView(rootView: CapsuleRootView(model: model))
        hosting.shapeSize = { model.shapeSize }
        panel = CapsulePanel(contentView: hosting)
        panel.onEscape = { [weak self] in self?.model.escape() }

        menuBar = MenuBar(
            onTalk: { [weak self] in self?.model.flashHint() },
            onType: { [weak self] in self?.model.startTyping() },
            onLibrary: { LibraryWindow.show(highlighting: nil) },
            onSetup: { [weak self] in SetupWindow.show { self?.model.flashHint() } }
        )

        hotkeys.onVoiceDown = { [weak self] in self?.model.voiceDown() }
        hotkeys.onVoiceUp = { [weak self] in self?.model.voiceUp() }
        hotkeys.onType = { [weak self] in self?.model.startTyping() }
        hotkeys.register()

        Publishers.CombineLatest3(model.$phase, model.$hintVisible, model.$errorMessage)
            .receive(on: RunLoop.main)
            .sink { [weak self] phase, hint, error in self?.sync(phase: phase, hint: hint, error: error) }
            .store(in: &cancellables)

        model.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in self?.menuBar.setListening(phase == .listening) }
            .store(in: &cancellables)

        // Clicks outside our windows dismiss the card and typing box.
        _ = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.dismissOnOutsideClick() }
        }

        // Load both models now, so the first ⌥ Space or ⌥ T doesn't wait on them.
        if ModelStore.shared.needsSetup {
            SetupWindow.show { [weak self] in self?.model.flashHint() }
        } else {
            ModelStore.shared.prepare()
            model.flashHint()
        }
        // For checking the Library by eye or from scripts: "grid" or "detail" (opens the newest diagram).
        if let mode = ProcessInfo.processInfo.environment["TERMAID_SHOW_LIBRARY"] {
            let newest = DiagramLibrary.shared.items.max(by: { $0.created < $1.created })?.id
            if mode != "grid" { UserDefaults.standard.set(mode == "info", forKey: "libraryInfoOpen") }
            LibraryWindow.show(highlighting: nil, opening: mode == "grid" ? nil : newest)
        }
    }

    /// Clicking the Dock icon while the Library is in app mode brings the Library back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        LibraryWindow.show(highlighting: nil)
        return false
    }

    private func dismissOnOutsideClick() {
        switch model.phase {
        case .card, .saved, .typing, .idle: model.escape()
        default: break
        }
    }

    private func sync(phase: AppModel.Phase, hint: Bool, error: String?) {
        let visible = phase != .idle || hint || error != nil
        guard visible else {
            panel.orderOut(nil)
            return
        }
        if !panel.isVisible { position() }
        switch phase {
        case .typing:
            if !panel.isKeyWindow {
                NSApp.activate(ignoringOtherApps: true)
                panel.makeKeyAndOrderFront(nil)
            }
        case .card, .saved:
            if !panel.isKeyWindow { panel.makeKeyAndOrderFront(nil) }
        default:
            panel.orderFrontRegardless()
        }
    }

    /// Centers the panel under the status item, 8pt below the menu bar.
    private func position() {
        let size = CapsuleMetrics.panelSize
        guard let fallback = NSScreen.main ?? NSScreen.screens.first else { return }
        var screen = fallback
        var centerX = fallback.frame.midX
        var top = fallback.visibleFrame.maxY - 8
        if let button = menuBar.button, let window = button.window {
            let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
            let mid = CGPoint(x: rect.midX, y: rect.midY)
            if let found = NSScreen.screens.first(where: { $0.frame.contains(mid) }) { screen = found }
            centerX = rect.midX
            top = rect.minY - 8
        }
        let minX = screen.visibleFrame.minX + 4
        let maxX = screen.visibleFrame.maxX - size.width - 4
        let x = min(max(centerX - size.width / 2, minX), maxX)
        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
    }
}

@MainActor
func runApp() {
    let app = NSApplication.shared
    let delegate = AppDelegate()  // kept alive by this frame for the whole app.run()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}

MainActor.assumeIsolated { runApp() }
