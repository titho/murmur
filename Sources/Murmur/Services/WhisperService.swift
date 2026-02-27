import Foundation
import WhisperKit

// MARK: - Model catalog

struct WhisperModel: Identifiable, Hashable {
    let id: String          // WhisperKit variant name
    let displayName: String
    let sizeMB: Int
    let speedRating: Int    // 1 (slowest) – 5 (fastest)
    let accuracyRating: Int // 1 (lowest) – 5 (highest)
    let isEnglishOnly: Bool
    let isHeavy: Bool       // Noticeably taxes CPU/memory on older machines
    let isRecommended: Bool
    let description: String

    static let catalog: [WhisperModel] = [
        WhisperModel(
            id: "tiny.en",
            displayName: "Tiny",
            sizeMB: 75,
            speedRating: 5,
            accuracyRating: 2,
            isEnglishOnly: true,
            isHeavy: false,
            isRecommended: false,
            description: "Instant results. Good for quick notes when speed matters more than accuracy."
        ),
        WhisperModel(
            id: "base.en",
            displayName: "Base",
            sizeMB: 142,
            speedRating: 4,
            accuracyRating: 3,
            isEnglishOnly: true,
            isHeavy: false,
            isRecommended: false,
            description: "Fast and lightweight. A solid default for everyday English dictation."
        ),
        WhisperModel(
            id: "small.en",
            displayName: "Small",
            sizeMB: 466,
            speedRating: 3,
            accuracyRating: 3,
            isEnglishOnly: true,
            isHeavy: false,
            isRecommended: false,
            description: "Better accuracy than Base with only a modest speed trade-off."
        ),
        WhisperModel(
            id: "medium.en",
            displayName: "Medium",
            sizeMB: 1500,
            speedRating: 2,
            accuracyRating: 4,
            isEnglishOnly: true,
            isHeavy: true,
            isRecommended: false,
            description: "High accuracy for English. Noticeably slower on older Macs."
        ),
        WhisperModel(
            id: "large-v3_turbo",
            displayName: "Large v3 Turbo",
            sizeMB: 1600,
            speedRating: 3,
            accuracyRating: 5,
            isEnglishOnly: false,
            isHeavy: true,
            isRecommended: true,
            description: "Best quality-to-speed ratio. Supports all languages."
        ),
        WhisperModel(
            id: "large-v3",
            displayName: "Large v3",
            sizeMB: 3100,
            speedRating: 1,
            accuracyRating: 5,
            isEnglishOnly: false,
            isHeavy: true,
            isRecommended: false,
            description: "Highest accuracy. Slow on all but the most powerful Macs. Best for complex speech."
        ),
    ]

    static var `default`: WhisperModel { catalog.first { $0.id == "large-v3_turbo" } ?? catalog[1] }
}

// MARK: - Service

@MainActor
class WhisperService: ObservableObject {
    @Published var activeDownloads: Set<String> = []
    @Published var downloadProgress: [String: (bytesDownloaded: Int64, totalBytes: Int64?)] = [:]
    /// Reactive set of variants confirmed to exist on disk. Drive UI from this.
    @Published private(set) var downloadedVariants: Set<String> = []

    private var pipe: WhisperKit?
    private let downloadedPathsKey = "whisperDownloadedModelPaths"

    init() {
        refreshDownloadedVariants()
    }

    // MARK: - Public API

    /// Load a model variant. Downloads first if not already on disk.
    func loadModel(variant: String) async throws {
        pipe = nil

        let modelFolder: String
        if let cached = cachedPath(for: variant), FileManager.default.fileExists(atPath: cached) {
            modelFolder = cached
        } else if FileManager.default.fileExists(atPath: defaultModelPath(for: variant)) {
            // Model is on disk at WhisperKit's default location (e.g. after a bundle ID rename)
            modelFolder = defaultModelPath(for: variant)
            storeCachedPath(modelFolder, for: variant)
        } else {
            let url = try await WhisperKit.download(
                variant: variant,
                from: "argmaxinc/whisperkit-coreml"
            )
            modelFolder = url.path
            storeCachedPath(modelFolder, for: variant)
        }

        let config = WhisperKitConfig(modelFolder: modelFolder, load: true, download: false)
        pipe = try await WhisperKit(config)
        refreshDownloadedVariants()
    }

    /// Download a model without loading it (for the Models settings UI).
    func downloadModel(variant: String) async throws {
        activeDownloads.insert(variant)
        defer {
            activeDownloads.remove(variant)
            downloadProgress.removeValue(forKey: variant)
        }

        let url = try await WhisperKit.download(
            variant: variant,
            from: "argmaxinc/whisperkit-coreml",
            progressCallback: { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.downloadProgress[variant] = (
                        bytesDownloaded: progress.completedUnitCount,
                        totalBytes: progress.totalUnitCount > 0 ? progress.totalUnitCount : nil
                    )
                }
            }
        )

        storeCachedPath(url.path, for: variant)
        refreshDownloadedVariants()
    }

    /// Delete a downloaded model from disk and remove it from the cache.
    /// Returns true if it was the currently loaded model (caller should reset state).
    @discardableResult
    func deleteModel(variant: String) -> Bool {
        let wasLoaded = pipe != nil && !downloadedVariants.subtracting([variant]).isEmpty == false

        // Delete at cached path
        if let cached = cachedPath(for: variant) {
            try? FileManager.default.removeItem(atPath: cached)
        }
        // Delete at default path (covers post-rename case)
        let defaultPath = defaultModelPath(for: variant)
        if FileManager.default.fileExists(atPath: defaultPath) {
            try? FileManager.default.removeItem(atPath: defaultPath)
        }

        removeCachedPath(for: variant)

        // Unload if this was the active model
        let isActive = !isOnDisk(variant) && pipe != nil
        if isActive { pipe = nil }

        refreshDownloadedVariants()
        return isActive || wasLoaded
    }

    func unloadModel() {
        pipe = nil
    }

    /// Prime the ANE/GPU pipeline with a silent audio clip so the first real transcription is fast.
    func warmup() async {
        guard pipe != nil else { return }
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur_warmup.wav")
        createSilentWAV(at: tmpURL, durationSeconds: 1)
        _ = try? await transcribe(audioURL: tmpURL)
        try? FileManager.default.removeItem(at: tmpURL)
    }

    private func createSilentWAV(at url: URL, durationSeconds: Int) {
        let sampleRate: UInt32 = 16000
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let numSamples = UInt32(sampleRate) * UInt32(durationSeconds)
        let dataSize = numSamples * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let chunkSize = 36 + dataSize

        var wav = Data()
        func u32le(_ v: UInt32) { var x = v.littleEndian; wav.append(Data(bytes: &x, count: 4)) }
        func u16le(_ v: UInt16) { var x = v.littleEndian; wav.append(Data(bytes: &x, count: 2)) }

        wav.append("RIFF".data(using: .ascii)!); u32le(chunkSize)
        wav.append("WAVE".data(using: .ascii)!)
        wav.append("fmt ".data(using: .ascii)!); u32le(16); u16le(1)
        u16le(numChannels); u32le(sampleRate)
        u32le(sampleRate * UInt32(numChannels) * UInt32(bitsPerSample / 8))
        u16le(numChannels * bitsPerSample / 8); u16le(bitsPerSample)
        wav.append("data".data(using: .ascii)!); u32le(dataSize)
        wav.append(Data(count: Int(dataSize)))

        try? wav.write(to: url)
    }

    /// Transcribe a WAV/M4A/MP3 file.
    /// - Parameter language: ISO 639-1 language code (e.g. "bg", "en"), or nil for auto-detect.
    /// NOTE: WhisperKit's DecodingOptions does not expose a string-based initial prompt;
    /// the `whisperPrompt` UserDefault setting is therefore inert.
    func transcribe(audioURL: URL, language: String? = nil) async throws -> String {
        guard let pipe else { throw WhisperServiceError.modelNotLoaded }

        let options = DecodingOptions(
            task: .transcribe,
            language: language?.isEmpty == false ? language : nil,
            temperature: 0.0
        )
        let results = try await pipe.transcribe(audioPath: audioURL.path, decodeOptions: options)
        return results.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func isModelDownloaded(_ variant: String) -> Bool {
        downloadedVariants.contains(variant)
    }

    var isLoaded: Bool { pipe != nil }

    /// Parent directory where downloaded models live.
    var modelsDirectory: URL? {
        // Prefer a cached path; fall back to the default WhisperKit location
        let dict = UserDefaults.standard.dictionary(forKey: downloadedPathsKey) as? [String: String]
        if let path = dict?.values.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            return URL(fileURLWithPath: path).deletingLastPathComponent()
        }
        let defaultBase = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")
        return FileManager.default.fileExists(atPath: defaultBase.path) ? defaultBase : nil
    }

    // MARK: - Private

    private func isOnDisk(_ variant: String) -> Bool {
        if let path = cachedPath(for: variant), FileManager.default.fileExists(atPath: path) {
            return true
        }
        return FileManager.default.fileExists(atPath: defaultModelPath(for: variant))
    }

    private func refreshDownloadedVariants() {
        downloadedVariants = Set(WhisperModel.catalog.map(\.id).filter { isOnDisk($0) })
    }

    private func cachedPath(for variant: String) -> String? {
        let dict = UserDefaults.standard.dictionary(forKey: downloadedPathsKey) as? [String: String]
        return dict?[variant]
    }

    private func storeCachedPath(_ path: String, for variant: String) {
        var dict = UserDefaults.standard.dictionary(forKey: downloadedPathsKey) as? [String: String] ?? [:]
        dict[variant] = path
        UserDefaults.standard.set(dict, forKey: downloadedPathsKey)
    }

    private func removeCachedPath(for variant: String) {
        var dict = UserDefaults.standard.dictionary(forKey: downloadedPathsKey) as? [String: String] ?? [:]
        dict.removeValue(forKey: variant)
        UserDefaults.standard.set(dict, forKey: downloadedPathsKey)
    }

    /// WhisperKit downloads to: ~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-<variant>
    private func defaultModelPath(for variant: String) -> String {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents
            .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")
            .appendingPathComponent("openai_whisper-\(variant)")
            .path
    }
}

enum WhisperServiceError: LocalizedError {
    case modelNotLoaded

    var errorDescription: String? {
        "Whisper model is not loaded. Please select and download a model in Settings."
    }
}
