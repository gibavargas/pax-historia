import Foundation

struct AppleAIRequest: Decodable {
    struct Message: Decodable {
        let role: String
        let text: String
    }

    let history: [Message]
    let contextWindowTokens: Int?
    let inputTokenBudget: Int?
    let inputTokenEstimate: Int?
    let maxTokens: Int?
    let promptEnvelope: String?
    let requestId: String
    let responseFormat: String?
    let systemPrompt: String
    let taskKey: String?
    let temperature: Double?
    let userMessage: String?
    let responseTokenBudget: Int?
}

struct AppleAIResponse: Encodable {
    let availability: String
    let error: String?
    let fallbackUsed: Bool
    let ok: Bool
    let provider: String
    let requestId: String
    let text: String
    let tokenBudget: String?
}
