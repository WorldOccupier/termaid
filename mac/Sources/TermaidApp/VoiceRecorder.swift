import AVFoundation
import Foundation

/// Records the microphone to a 16 kHz mono 16-bit WAV and reports a smoothed 0...1 level while recording.
final class VoiceRecorder {
    var onLevel: ((Float) -> Void)?

    enum RecorderError: LocalizedError {
        case micRequested, micDenied, notRecording, noInput
        var errorDescription: String? {
            switch self {
            case .micRequested: return "Microphone access was just requested. Grant it in the prompt, then try again."
            case .micDenied: return "Microphone access is off for termaid. Enable it in System Settings > Privacy & Security > Microphone."
            case .notRecording: return "No recording is in progress."
            case .noInput: return "No microphone input is available."
            }
        }
    }

    private static let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                              channels: 1, interleaved: false)!
    private let engine = AVAudioEngine()
    private let lock = NSLock()  // guards the state below; the tap runs on the audio thread
    private var file: AVAudioFile?   // non-nil while recording
    private var converter: AVAudioConverter?
    private var outputURL: URL?
    private var smoothed: Float = 0
    private var samples: [Float] = []

    func start() throws {
        lock.lock(); let busy = file != nil; lock.unlock()
        if busy { return }  // already recording: keep the current take

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            throw RecorderError.micRequested
        default: throw RecorderError.micDenied
        }

        let input = engine.inputNode
        let hwFormat = input.outputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0, let conv = AVAudioConverter(from: hwFormat, to: Self.target) else {
            throw RecorderError.noInput
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("termaid", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(UUID().uuidString + ".wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ]
        let newFile = try AVAudioFile(forWriting: url, settings: settings,
                                      commonFormat: .pcmFormatFloat32, interleaved: false)
        lock.lock(); file = newFile; converter = conv; outputURL = url; smoothed = 0; samples = []; lock.unlock()

        input.installTap(onBus: 0, bufferSize: 1600, format: hwFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            clearState()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    func stop() async throws -> URL {
        guard let url = currentURL() else { throw RecorderError.notRecording }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        clearState()  // releasing the file closes it
        return url
    }

    /// Everything recorded so far as 16 kHz mono samples, for showing a transcript while the user speaks.
    func recordedSamples() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        return samples
    }

    private func currentURL() -> URL? {
        lock.lock(); defer { lock.unlock() }
        return outputURL
    }

    private func clearState() {
        lock.lock(); defer { lock.unlock() }
        file = nil; converter = nil; outputURL = nil; samples = []
    }

    private func process(_ input: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard let file, let converter else { return }
        let capacity = AVAudioFrameCount(Double(input.frameLength) * Self.target.sampleRate / input.format.sampleRate) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: Self.target, frameCapacity: capacity) else { return }
        var supplied = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return input
        }
        guard error == nil, out.frameLength > 0, let converted = out.floatChannelData?[0] else { return }
        try? file.write(from: out)
        samples.append(contentsOf: UnsafeBufferPointer(start: converted, count: Int(out.frameLength)))

        // RMS -> dBFS -> 0...1 over -50...0 dB, then a little smoothing so the meter doesn't jitter.
        var sum: Float = 0
        for i in 0..<Int(out.frameLength) { sum += converted[i] * converted[i] }
        let rms = (sum / Float(out.frameLength)).squareRoot()
        let db = 20 * log10(max(rms, 1e-6))
        let level = min(max((db + 50) / 50, 0), 1)
        smoothed = smoothed * 0.6 + level * 0.4
        let value = smoothed
        DispatchQueue.main.async { [weak self] in self?.onLevel?(value) }
    }
}
