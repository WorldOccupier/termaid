import SwiftUI

/// The Settings tab: the app version and the updater.
struct SettingsView: View {
    @ObservedObject var updater: AppUpdater

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Settings").font(Obsidian.font(24, .semibold)).foregroundStyle(Obsidian.fg)
            VStack(alignment: .leading, spacing: 14) {
                Text("UPDATES").font(Obsidian.font(11, .semibold)).tracking(1.2).foregroundStyle(Obsidian.muted)
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("termaid \(updater.currentVersion)").font(Obsidian.font(15, .semibold)).foregroundStyle(Obsidian.fg)
                        statusText
                    }
                    Spacer()
                    actionButton
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 12).fill(Obsidian.surface))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08)))
            }
            .frame(maxWidth: 560)
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.top, 48)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var statusText: some View {
        let text: String = switch updater.status {
        case .idle: "Check GitHub for a newer version."
        case .checking: "Checking…"
        case .upToDate: "You're up to date."
        case .available(let release): "Version \(release.version) is available."
        case .downloading(let fraction): "Downloading… \(Int(fraction * 100))%"
        case .installing: "Installing…"
        case .failed(let message): message
        }
        Text(text)
            .font(Obsidian.font(13))
            .foregroundStyle(isFailure ? Obsidian.rose : Obsidian.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var isFailure: Bool {
        if case .failed = updater.status { true } else { false }
    }

    @ViewBuilder private var actionButton: some View {
        switch updater.status {
        case .available(let release):
            Button("Update and restart") { Task { await updater.install(release) } }
                .buttonStyle(.borderedProminent)
        case .checking, .downloading, .installing:
            ProgressView().controlSize(.small)
        default:
            Button("Check for updates") { Task { await updater.check() } }
        }
    }
}
