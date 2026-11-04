import AppKit
import Foundation

/// Unpacks a downloaded app zip, checks it is signed by the same developer, and swaps it in for the running app.
struct AppInstaller {
    static let teamID = "84NWPU429Z"

    let installedApp: URL

    /// Returns the unpacked, verified app inside `workDir`.
    func unpackAndVerify(zip: URL, in workDir: URL) throws -> URL {
        let unpacked = workDir.appendingPathComponent("unpacked")
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])
        let app = unpacked.appendingPathComponent(installedApp.lastPathComponent)
        guard FileManager.default.fileExists(atPath: app.path) else {
            throw UserFacingError(message: "The download doesn't contain \(installedApp.lastPathComponent)")
        }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        let details = try run("/usr/bin/codesign", ["-dv", app.path])
        guard details.contains("TeamIdentifier=\(Self.teamID)") else {
            throw UserFacingError(message: "The download isn't signed by termaid's developer")
        }
        return app
    }

    /// Replaces the installed app once this process exits, then opens the new one.
    func replaceAndRelaunch(with newApp: URL) throws {
        guard FileManager.default.isWritableFile(atPath: installedApp.deletingLastPathComponent().path) else {
            throw UserFacingError(message: "Can't write to \(installedApp.deletingLastPathComponent().path)")
        }
        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        rm -rf "$2" && mv "$3" "$2" && open "$2"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier),
                             installedApp.path, newApp.path]
        try process.run()
        NSApp.terminate(nil)
    }

    /// Runs a tool and returns its combined output, throwing if it fails.
    @discardableResult
    private func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UserFacingError(message: "\(URL(fileURLWithPath: tool).lastPathComponent) failed: \(output)")
        }
        return output
    }
}
