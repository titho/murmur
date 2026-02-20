import AVFoundation
import Foundation

class AudioRecorder {
    var onWaveformSample: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var tempURL: URL?
    private var isRunning = false

    // whisper.cpp expects 16kHz mono float32
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    func start() async throws {
        guard !isRunning else { return }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Create temp WAV file
        let tmpDir = FileManager.default.temporaryDirectory
        let url = tmpDir.appendingPathComponent("dictation_\(Date().timeIntervalSince1970).wav")
        tempURL = url
        audioFile = try AVAudioFile(forWriting: url, settings: targetFormat.settings)

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecorderError.converterFailed
        }

        let bufferSize: AVAudioFrameCount = 4096

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let audioFile = self.audioFile else { return }

            // Compute RMS for waveform
            if let channelData = buffer.floatChannelData?[0] {
                let frames = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<frames { sum += channelData[i] * channelData[i] }
                let rms = sqrt(sum / Float(frames))
                self.onWaveformSample?(rms)
            }

            // Resample and write
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * (16000.0 / inputFormat.sampleRate))
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: self.targetFormat, frameCapacity: capacity) else { return }

            var error: NSError?
            var filled = false
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                if filled {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                filled = true
                outStatus.pointee = .haveData
                return buffer
            }

            if error == nil {
                try? audioFile.write(from: convertedBuffer)
            }
        }

        try engine.start()
        isRunning = true
    }

    func stop() async throws -> URL {
        guard isRunning, let url = tempURL else {
            throw RecorderError.notRecording
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioFile = nil
        isRunning = false
        tempURL = nil

        return url
    }
}

enum RecorderError: LocalizedError {
    case converterFailed
    case notRecording

    var errorDescription: String? {
        switch self {
        case .converterFailed: return "Could not create audio converter"
        case .notRecording: return "Not currently recording"
        }
    }
}
