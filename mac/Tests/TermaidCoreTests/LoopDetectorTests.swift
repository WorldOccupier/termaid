import Testing
@testable import TermaidCore

@Suite struct LoopDetectorTests {
    private let detector = LoopDetector()
    private let box: [Int32] = [1, 2, 3, 4, 5]

    @Test func stopsOnThirdIdenticalRun() {
        #expect(!detector.isLooping([9] + box + box))
        #expect(detector.isLooping([9] + box + box + box))
    }

}
