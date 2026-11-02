import Foundation
import TermaidCore

/// While a recording runs, re-transcribes everything recorded so far every `interval` and reports the text,
/// so the words show up as they are spoken. The final transcript still comes from the finished recording.
@MainActor final class LiveTranscript {
    private let recorder: VoiceRecorder
    private let models: ModelStore
    private let interval: Duration
    /// Under half a second of audio is mostly silence before the first word.
    private let minimumSamples = 8_000
    private var task: Task<Void, Never>?

    init(recorder: VoiceRecorder, models: ModelStore, interval: Duration = .milliseconds(700)) {
        self.recorder = recorder
        self.models = models
        self.interval = interval
    }

    /// Only runs when the speech model is already loaded, so it never competes with a first-time download.
    func start(onText: @escaping @MainActor (String) -> Void) {
        stop()
        guard models.speech.isReady else { return }
        task = Task { [recorder, models, interval, minimumSamples] in
            guard let transcriber = try? await models.transcriber() else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                let samples = recorder.recordedSamples()
                guard samples.count >= minimumSamples,
                      let text = try? await transcriber.transcribe(samples: samples),
                      !Task.isCancelled, !text.isEmpty else { continue }
                onText(text)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
