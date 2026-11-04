import SwiftUI

/// The vertical tabs down the left of the termaid window.
enum WindowTab: String, CaseIterable, Identifiable {
    case library = "Library"
    case settings = "Settings"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .library: "square.grid.2x2"
        case .settings: "gearshape"
        }
    }
}

struct WindowSidebar: View {
    @Binding var selection: WindowTab
    static let width: CGFloat = 176

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(WindowTab.allCases) { tab in
                SidebarTabButton(tab: tab, isSelected: tab == selection) { selection = tab }
            }
            Spacer()
        }
        .padding(.top, 56)
        .padding(.horizontal, 12)
        .frame(width: Self.width)
        .background(Obsidian.surface.opacity(0.6))
        .overlay(alignment: .trailing) { Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1) }
    }
}

private struct SidebarTabButton: View {
    let tab: WindowTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.symbol).frame(width: 18)
                Text(tab.rawValue).font(Obsidian.font(14, .medium))
                Spacer()
            }
            .foregroundStyle(isSelected ? Obsidian.fg : Obsidian.muted)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Color.white.opacity(0.08) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
