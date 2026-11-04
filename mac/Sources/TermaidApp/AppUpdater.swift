import Foundation

/// Checks for a newer release when asked, then downloads, verifies and installs it.
@MainActor final class AppUpdater: ObservableObject {
    enum Status: Equatable {
        case idle, checking, upToDate
        case available(AppRelease)
        case downloading(Double)
        case installing
        case failed(String)
    }

    static let shared = AppUpdater()

    @Published private(set) var status: Status = .idle
    let currentVersion: String
    private let checker: UpdateChecker
    private let installer: AppInstaller

    init(currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
         checker: UpdateChecker = UpdateChecker(),
         installer: AppInstaller = AppInstaller(installedApp: Bundle.main.bundleURL)) {
        self.currentVersion = currentVersion
        self.checker = checker
        self.installer = installer
    }

    func check() async {
        status = .checking
        do {
            let release = try await checker.latestRelease()
            status = UpdateChecker.isNewer(release.version, than: currentVersion) ? .available(release) : .upToDate
        } catch {
            status = .failed(message(error))
        }
    }

    func install(_ release: AppRelease) async {
        status = .downloading(0)
        do {
            let workDir = FileManager.default.temporaryDirectory.appendingPathComponent("termaid-update-\(UUID().uuidString)")
            let zip = workDir.appendingPathComponent(UpdateChecker.assetName)
            try await ModelDownloader(source: release.downloadURL, destination: zip) { fraction in
                Task { @MainActor in
                    if case .downloading = self.status { self.status = .downloading(fraction) }
                }
            }.download()
            status = .installing
            let installer = self.installer
            let app = try await Task.detached { try installer.unpackAndVerify(zip: zip, in: workDir) }.value
            try installer.replaceAndRelaunch(with: app)
        } catch {
            status = .failed(message(error))
        }
    }

    private func message(_ error: Error) -> String {
        (error as? UserFacingError)?.message ?? error.localizedDescription
    }
}
