import Foundation

enum CleanupModel: String, CaseIterable {
    case haiku  = "claude-haiku-4-5-20251001"
    case sonnet = "claude-sonnet-4-6"
    case opus   = "claude-opus-4-6"

    var displayName: String {
        switch self {
        case .haiku:  return "Haiku (fast)"
        case .sonnet: return "Sonnet (quality)"
        case .opus:   return "Opus (best)"
        }
    }
}

struct CleanupResult {
    let text: String
    let inputTokens: Int
    let outputTokens: Int
}

enum CleanupError: LocalizedError {
    case noApiKey
    case httpError(Int)
    case parseError

    var errorDescription: String? {
        switch self {
        case .noApiKey:          return "No Anthropic API key configured"
        case .httpError(let c):  return "Cleanup API returned HTTP \(c)"
        case .parseError:        return "Could not parse cleanup response"
        }
    }
}

struct CleanupService {
    static let defaultSystemPrompt = """
        You are a transcription cleanup assistant. The input is a raw voice transcription that \
        may contain filler words, false starts, stutters, and repetitions. \
        Remove fillers (um, uh, like, you know, I mean, sort of, kind of), \
        collapse false starts and repeated phrases, and fix grammar to make the text readable. \
        Preserve all meaning, tone, and content. \
        Return only the cleaned text — no explanation, no preamble.
        """

    /// Checks ANTHROPIC_API_KEY env var first, then falls back to UserDefaults.
    static func resolvedApiKey() -> String? {
        let env = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
        if !env.isEmpty { return env }
        let stored = UserDefaults.standard.string(forKey: "anthropicApiKey") ?? ""
        return stored.isEmpty ? nil : stored
    }

    /// Returns the effective system prompt: custom override if enabled, otherwise default.
    static func resolvedSystemPrompt() -> String? {
        guard UserDefaults.standard.bool(forKey: "cleanupSystemPromptEnabled") else {
            return defaultSystemPrompt
        }
        let custom = UserDefaults.standard.string(forKey: "cleanupSystemPrompt") ?? ""
        return custom.isEmpty ? nil : custom
    }

    static func clean(_ text: String, model: CleanupModel, apiKey: String) async throws -> CleanupResult {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey,             forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01",       forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 2048,
            "messages": [["role": "user", "content": text]],
        ]
        if let systemPrompt = resolvedSystemPrompt() {
            body["system"] = systemPrompt
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw CleanupError.httpError(http.statusCode)
        }

        guard
            let json    = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]],
            let first   = content.first,
            let result  = first["text"] as? String
        else { throw CleanupError.parseError }

        let usage      = json["usage"] as? [String: Any]
        let inputTok   = usage?["input_tokens"]  as? Int ?? 0
        let outputTok  = usage?["output_tokens"] as? Int ?? 0

        return CleanupResult(
            text: result.trimmingCharacters(in: .whitespacesAndNewlines),
            inputTokens: inputTok,
            outputTokens: outputTok
        )
    }
}
