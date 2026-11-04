import Foundation
import Testing
@testable import TermaidApp

struct UpdateCheckerTests {
    @Test func comparesVersionsNumerically() {
        #expect(UpdateChecker.isNewer("0.1.10", than: "0.1.9"))
        #expect(UpdateChecker.isNewer("0.2", than: "0.1.9"))
        #expect(!UpdateChecker.isNewer("0.1.0", than: "0.1"))
        #expect(!UpdateChecker.isNewer("0.1.0", than: "0.1.1"))
    }

    @Test func parsesLatestReleaseZip() throws {
        let json = """
        {"tag_name":"v0.1.1","assets":[{"name":"notes.txt","browser_download_url":"https://x/notes.txt"},
        {"name":"Termaid.zip","browser_download_url":"https://x/Termaid.zip"}]}
        """
        let release = try AppRelease.parse(Data(json.utf8))
        #expect(release == AppRelease(version: "0.1.1", downloadURL: URL(string: "https://x/Termaid.zip")!))
    }
}
