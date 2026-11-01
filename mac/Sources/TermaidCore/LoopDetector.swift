/// Spots a reply stuck in a loop (`"Crusher", "Crusher", "Crusher", …`): the same run of tokens
/// three times back to back. Diagrams never legitimately repeat a whole box or edge, so stopping
/// there fails the attempt in a fraction of the time it takes to hit the reply-length cap.
struct LoopDetector {
    // Shorter runs are punctuation patterns like `", "` that appear between every string.
    static let shortestLoop = 4
    static let longestLoop = 64
    static let repeatsToStop = 3

    func isLooping(_ tokens: [Int32]) -> Bool {
        let longest = min(Self.longestLoop, tokens.count / Self.repeatsToStop)
        guard longest >= Self.shortestLoop else { return false }
        return (Self.shortestLoop...longest).contains { endsWithRepeats(of: $0, in: tokens) }
    }

    private func endsWithRepeats(of length: Int, in tokens: [Int32]) -> Bool {
        let lastRun = tokens.suffix(length)
        return (1..<Self.repeatsToStop).allSatisfy { repeatIndex in
            let end = tokens.count - repeatIndex * length
            return tokens[(end - length)..<end].elementsEqual(lastRun)
        }
    }
}
