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

    private var pipe: WhisperKit?
    private let downloadedPathsKey = "whisperDownloadedModelPaths"

    // MARK: - Public API

    /// Load a model variant. Downloads first if not already cached.
    func loadModel(variant: String) async throws {
        pipe = nil

        let modelFolder: String
        if let cached = cachedPath(for: variant), FileManager.default.fileExists(atPath: cached) {
            modelFolder = cached
        } else {
            // Download
            let url = try await WhisperKit.download(
                variant: variant,
                from: "argmaxinc/whisperkit-coreml"
            )
            modelFolder = url.path
            storeCachedPath(modelFolder, for: variant)
        }

        let config = WhisperKitConfig(modelFolder: modelFolder, load: true, download: false)
        pipe = try await WhisperKit(config)
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
    }

    /// Transcribe a WAV/M4A/MP3 file.
    func transcribe(audioURL: URL, initialPrompt: String? = nil) async throws -> String {
        guard let pipe else { throw WhisperServiceError.modelNotLoaded }

        let options = DecodingOptions(
            task: .transcribe,
            temperature: 0.0
        )

        let results = try await pipe.transcribe(audioPath: audioURL.path, decodeOptions: options)
        return results.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func isModelDownloaded(_ variant: String) -> Bool {
        guard let path = cachedPath(for: variant) else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    var isLoaded: Bool { pipe != nil }

    /// Parent directory where downloaded models live, derived from the first known path.
    var modelsDirectory: URL? {
        let dict = UserDefaults.standard.dictionary(forKey: downloadedPathsKey) as? [String: String]
        guard let path = dict?.values.first else { return nil }
        return URL(fileURLWithPath: path).deletingLastPathComponent()
    }

    // MARK: - Persistence

    private func cachedPath(for variant: String) -> String? {
        let dict = UserDefaults.standard.dictionary(forKey: downloadedPathsKey) as? [String: String]
        return dict?[variant]
    }

    private func storeCachedPath(_ path: String, for variant: String) {
        var dict = UserDefaults.standard.dictionary(forKey: downloadedPathsKey) as? [String: String] ?? [:]
        dict[variant] = path
        UserDefaults.standard.set(dict, forKey: downloadedPathsKey)
    }
}

enum WhisperServiceError: LocalizedError {
    case modelNotLoaded

    var errorDescription: String? {
        "Whisper model is not loaded. Please select and download a model in Settings."
    }
}
