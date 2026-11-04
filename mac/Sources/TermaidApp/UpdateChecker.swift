import Foundation

/// A published release: its version and where to download the app zip.
struct AppRelease: Equatable {
    let version: String
    let downloadURL: URL

    /// Reads GitHub's latest-release JSON, picking the Termaid.zip asset.
    static func parse(_ data: Data) throws -> AppRelease {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        struct Release: Decodable { let tag_name: String; let assets: [Asset] }
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard let zip = release.assets.first(where: { $0.name == UpdateChecker.assetName }) else {
            throw UserFacingError(message: "The latest release has no \(UpdateChecker.assetName)")
        }
        let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        return AppRelease(version: version, downloadURL: zip.browser_download_url)
    }
}

/// Asks GitHub for the latest release.
struct UpdateChecker {
    static let assetName = "Termaid.zip"
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/WorldOccupier/termaid/releases/latest")!

    var fetch: @Sendable (URL) async throws -> Data = { url in
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            throw UserFacingError(message: "Couldn't reach GitHub (HTTP \(status))")
        }
        return data
    }

    func latestRelease() async throws -> AppRelease {
        try AppRelease.parse(try await fetch(Self.latestReleaseURL))
    }

    /// Compares dotted versions numerically, so 0.1.10 is newer than 0.1.9.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let parts = { (v: String) in v.split(separator: ".").map { Int($0) ?? 0 } }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
