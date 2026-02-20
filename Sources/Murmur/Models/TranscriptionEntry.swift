import Foundation

struct TranscriptionEntry: Codable, Identifiable {
    let id: UUID
    let text: String
    let date: Date
    var inputTokens: Int?
    var outputTokens: Int?
    var cleanupModel: String?

    var wordCount: Int { text.split(separator: " ").count }

    /// Estimated cost in USD based on stored token counts and model pricing.
    var estimatedCost: Double? {
        guard let input = inputTokens, let output = outputTokens, let model = cleanupModel else { return nil }
        // Prices in USD per 1M tokens (input, output)
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
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        cleanupModel: String? = nil
    ) {
        self.id = UUID()
        self.text = text
        self.date = Date()
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cleanupModel = cleanupModel
    }
}
