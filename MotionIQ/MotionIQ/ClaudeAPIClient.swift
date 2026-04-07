import Foundation
import Security

// MARK: - Keychain

/// Stores and retrieves the Claude API key from the iOS Keychain.
///
/// Never store the key in UserDefaults, source code, or plists.
///
/// Development setup: call `KeychainHelper.save(apiKey:)` once from a
/// debug build scheme or unit test setUp(). Phase 4 onboarding will
/// surface this to the user via a settings screen.
enum KeychainHelper {
    private static let service = "com.danvo.MotionIQ.ClaudeAPIKey"

    static func save(apiKey: String) {
        guard let data = apiKey.data(using: .utf8) else { return }
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecValueData:   data
        ]
        SecItemDelete(query as CFDictionary)        // remove stale entry before adding
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load() -> String? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Errors

enum ClaudeError: Error {
    case missingAPIKey
    case httpError(Int)
    case parseError
}

// MARK: - Client

/// Sends prompts to the Claude Haiku 4.5 API over URLSession.
///
/// Design principles:
/// - API key lives in Keychain only — never in source or UserDefaults.
/// - System prompt is sent with `cache_control: ephemeral` so Anthropic
///   caches it server-side; subsequent calls with the same prompt hit the
///   cache and cost less.
/// - HTTP 429 is retried once after a 5-second wait.
/// - The `URLRequest` timeout is 10 seconds. Callers should also wrap in
///   a `Task` with a deadline if they need cancellation on navigation.
struct ClaudeAPIClient {

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    /// Shared system prompt. Kept constant so Anthropic's prompt cache stays warm.
    private static let systemPrompt = """
    You are a fitness coach giving feedback after a workout. Be direct and friendly. \
    Write like you're talking to someone, not writing a report. \
    Short sentences. No bullet points. No markdown. No filler words like "Great job!" or "Keep it up!". \
    Get straight to the point — what they did well and one thing to fix.
    """

    // MARK: - Fallback cues

    /// Hardcoded cues shown when the Claude call fails (network down, timeout, etc.).
    static func fallbackCue(for exercise: Exercise) -> String {
        switch exercise {
        case .squat:  "Focus on depth and keeping your chest up."
        case .pushup: "Keep hips level and elbows at 45° from your body."
        case .lunge:  "Drive through your front heel and keep your torso upright."
        }
    }

    // MARK: - Send

    /// Sends `prompt` to Claude and returns the response text.
    /// Retries once on HTTP 429. Throws on all other errors.
    func send(prompt: String) async throws -> String {
        guard let apiKey = KeychainHelper.load() else {
            throw ClaudeError.missingAPIKey
        }

        var request = URLRequest(url: Self.endpoint, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey,             forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01",       forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model":      "claude-haiku-4-5-20251001",
            "max_tokens": 256,
            "system": [
                ["type": "text",
                 "text": Self.systemPrompt,
                 "cache_control": ["type": "ephemeral"]]
            ],
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return try await sendWithRetry(request: request, attempt: 0)
    }

    // MARK: - Private

    private func sendWithRetry(request: URLRequest, attempt: Int) async throws -> String {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClaudeError.parseError }

        switch http.statusCode {
        case 200:
            return try parseText(from: data)
        case 429 where attempt == 0:
            try await Task.sleep(for: .seconds(5))
            return try await sendWithRetry(request: request, attempt: 1)
        default:
            throw ClaudeError.httpError(http.statusCode)
        }
    }

    private func parseText(from data: Data) throws -> String {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let text = (json?["content"] as? [[String: Any]])?.first?["text"] as? String
        else { throw ClaudeError.parseError }
        return text
    }
}
