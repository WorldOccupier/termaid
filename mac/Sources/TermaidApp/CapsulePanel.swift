import AppKit
import SwiftUI

enum CapsuleMetrics {
    /// The panel's frame: the largest shape plus room for its shadow.
    static let panelSize = CGSize(width: 820, height: 360)
    static let pill = CGSize(width: 236, height: 36)
    static let bar = CGSize(width: 540, height: 54)
    static let card = CGSize(width: 800, height: 324)
}

/// Borderless, non-activating panel that floats under the menu-bar icon.
/// It can become key so the typing field receives keystrokes.
@MainActor
final class CapsulePanel: NSPanel {
    var onEscape: (() -> Void)?

    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: CapsuleMetrics.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.contentView = contentView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

/// Hosts the SwiftUI capsule but only takes clicks inside the visible shape,
/// so the transparent part of the panel passes events through to apps below.
@MainActor
final class CapsuleHostingView: NSHostingView<CapsuleRootView> {
    var shapeSize: @MainActor () -> CGSize = { .zero }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let size = shapeSize()
        // The shape is anchored top-center; this view's origin is bottom-left.
        let shape = CGRect(
            x: (bounds.width - size.width) / 2,
            y: bounds.height - size.height,
            width: size.width,
            height: size.height
        )
        return shape.contains(local) ? super.hitTest(point) : nil
    }
}
