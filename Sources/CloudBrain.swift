import Foundation

struct ChatMessage {
    let role: String // "user" | "assistant"
    let text: String
}

enum CloudProvider: String {
    case anthropic
    case groq
}

enum CloudBrainError: Error, LocalizedError {
    case noApiKey
    case consentDeclined
    case httpError(status: Int, body: String)
    case emptyReply

    var errorDescription: String? {
        switch self {
        case .noApiKey:
            return "No cloud API key set — add one in Settings."
        case .consentDeclined:
            return "Cloud call declined — nothing was sent."
        case .httpError(let status, let body):
            return "Cloud API error \(status): \(body.prefix(200))"
        case .emptyReply:
            return "Cloud provider returned an empty reply."
        }
    }
}

// Native counterpart to ../js/brain.js's cloud-fallback path
// (_cloudCompleteAnthropic / _cloudCompleteGroq / cloudComplete). Same
// consent-gate contract: `confirm` is only called (and awaited) when
// requireConsent is true, and a "no" throws .consentDeclined instead of
// silently going ahead — see PANDIA.md's CONSENT GATE section for why that
// matters (real money per call, data leaving the device).
//
// Built on plain URLSession async/await + JSONSerialization — both stable,
// long-standing Foundation APIs, not a third-party dependency like
// LANClient.swift's Socket.IO library, so this file carries much less
// first-build-failure risk than that one.
enum CloudBrain {
    private static let timeout: TimeInterval = 20

    static func complete(
        history: [ChatMessage],
        provider: CloudProvider,
        apiKey: String,
        requireConsent: Bool,
        confirm: (@Sendable (CloudProvider) async -> Bool)?
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw CloudBrainError.noApiKey }
        if requireConsent {
            let ok = await confirm?(provider) ?? false
            guard ok else { throw CloudBrainError.consentDeclined }
        }
        switch provider {
        case .groq:
            return try await completeGroq(history: history, apiKey: apiKey)
        case .anthropic:
            return try await completeAnthropic(history: history, apiKey: apiKey)
        }
    }

    private static func completeAnthropic(history: [ChatMessage], apiKey: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        // Same opt-in header the PWA uses for a direct-from-client call —
        // see ../js/brain.js's comment: Anthropic's own documented opt-in
        // for exactly this use case, not a workaround.
        request.setValue("true", forHTTPHeaderField: "anthropic-dangerous-direct-browser-access")

        let body: [String: Any] = [
            "model": "claude-haiku-4-5",
            "max_tokens": 500,
            "system": pandiaSystemPrompt,
            "messages": history.map { ["role": $0.role, "content": $0.text] },
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw CloudBrainError.httpError(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = json?["content"] as? [[String: Any]] ?? []
        let text = content.compactMap { $0["text"] as? String }.joined()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CloudBrainError.emptyReply }
        return trimmed
    }

    private static func completeGroq(history: [ChatMessage], apiKey: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")

        var messages: [[String: String]] = [["role": "system", "content": pandiaSystemPrompt]]
        messages.append(contentsOf: history.map { ["role": $0.role, "content": $0.text] })
        let body: [String: Any] = [
            "model": "openai/gpt-oss-120b", // same model Selene's SELENE_VOICE_MODEL defaults to
            "max_tokens": 500,
            "messages": messages,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw CloudBrainError.httpError(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]] ?? []
        let text = (choices.first?["message"] as? [String: Any])?["content"] as? String ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CloudBrainError.emptyReply }
        return trimmed
    }
}
