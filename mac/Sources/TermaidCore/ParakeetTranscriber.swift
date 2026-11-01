import FluidAudio
import Foundation

public protocol AudioFileTranscribing: Sendable {
    func transcribe(fileAt url: URL) async throws -> String
}

/// Parakeet TDT 0.6B v3 on Core ML via FluidAudio. The first load downloads the models
/// (~480 MB) to ~/Library/Application Support/FluidAudio/Models.
public actor ParakeetTranscriber: AudioFileTranscribing {
    private let manager: AsrManager

    private init(manager: AsrManager) {
        self.manager = manager
    }

    /// Whether the models are already on disk, so loading won't download anything.
    public static var isDownloaded: Bool {
        AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: .v3), version: .v3)
    }

    /// Downloads (first time only), compiles and loads the models. `progress` gets the download
    /// fraction in [0, 1], and `nil` once the download is done and the models are compiling.
    public static func load(progress: (@Sendable (Double?) -> Void)? = nil) async throws -> ParakeetTranscriber {
        let manager = AsrManager(config: .default)
        let models = try await AsrModels.downloadAndLoad(version: .v3) { update in
            switch update.phase {
            case .compiling: progress?(nil)
            default: progress?(update.fractionCompleted)
            }
        }
        try await manager.loadModels(models)
        return ParakeetTranscriber(manager: manager)
    }

    public func transcribe(fileAt url: URL) async throws -> String {
        var decoderState = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        return try await manager.transcribe(url, decoderState: &decoderState).text
    }
}
