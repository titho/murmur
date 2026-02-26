import Foundation

struct TranscriptionEntry: Codable, Identifiable {
    let id: UUID
    let text: String               // always raw Whisper output
    let date: Date
    var cleanedText: String?       // AI cleanup result; nil = no cleanup ran
    var inputTokens: Int?
    var outputTokens: Int?
    var cleanupModel: String?

    // Metrics
    var audioDurationSeconds: Double?
    var transcriptionTimeSeconds: Double?
    var whisperModel: String?
    var cpuPercentAtTranscription: Double?
    var memoryMBAtTranscription: Double?

    var wordCount: Int { text.split(separator: " ").count }

    /// What gets pasted / copied — cleaned if available, otherwise raw.
    var effectiveText: String { cleanedText ?? text }

    /// Estimated cost in USD based on stored token counts and model pricing.
    var estimatedCost: Double? {
        guard let input = inputTokens, let output = outputTokens, let model = cleanupModel else { return nil }
        let pricing: [String: (Double, Double)] = [
            "claude-haiku-4-5-20251001": (0.80,  4.00),
            "claude-sonnet-4-6":         (3.00,  15.00),
            "claude-opus-4-6":           (15.00, 75.00),
        ]
        guard let (inPrice, outPrice) = pricing[model] else { return nil }
        return Double(input) * inPrice / 1_000_000 + Double(output) * outPrice / 1_000_000
    }

    init(
        text: String,
        cleanedText: String? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        cleanupModel: String? = nil,
        audioDurationSeconds: Double? = nil,
        transcriptionTimeSeconds: Double? = nil,
        whisperModel: String? = nil,
        cpuPercentAtTranscription: Double? = nil,
        memoryMBAtTranscription: Double? = nil
    ) {
        self.id = UUID()
        self.text = text
        self.date = Date()
        self.cleanedText = cleanedText
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cleanupModel = cleanupModel
        self.audioDurationSeconds = audioDurationSeconds
        self.transcriptionTimeSeconds = transcriptionTimeSeconds
        self.whisperModel = whisperModel
        self.cpuPercentAtTranscription = cpuPercentAtTranscription
        self.memoryMBAtTranscription = memoryMBAtTranscription
    }
}
