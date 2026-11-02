import Foundation

/// Speaking an edit instead of typing it: record until stopped, showing the words so far, then transcribe.
@MainActor protocol VoiceInstructionInput {
    func start(onPartialText: @escaping @MainActor (String) -> Void) throws
    func stopAndTranscribe() async throws -> String
}

/// Records with the microphone and transcribes with the same Parakeet model as the capsule.
@MainActor final class MicrophoneInstructionInput: VoiceInstructionInput {
    private let recorder: VoiceRecorder
    private let models: ModelStore
    private let live: LiveTranscript

    init(recorder: VoiceRecorder = VoiceRecorder(), models: ModelStore) {
        self.recorder = recorder
        self.models = models
        live = LiveTranscript(recorder: recorder, models: models)
    }

    func start(onPartialText: @escaping @MainActor (String) -> Void) throws {
        try recorder.start()
        live.start(onText: onPartialText)
    }

    func stopAndTranscribe() async throws -> String {
        live.stop()
        let clip = try await recorder.stop()
        defer { try? FileManager.default.removeItem(at: clip) }
        let transcriber = try await models.transcriber()
        return try await transcriber.transcribe(fileAt: clip)
    }
}
