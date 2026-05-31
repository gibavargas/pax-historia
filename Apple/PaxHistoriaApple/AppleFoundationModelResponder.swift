import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class AppleFoundationModelResponder {
    private let fallbackContextWindow = 4096
    private let safetyTokens = 384

    func respond(to request: AppleAIRequest) async -> AppleAIResponse {
        guard !request.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallbackResponse(for: request, availability: "invalid-request", error: "Missing system prompt.")
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard model.isAvailable else {
                let availability = availabilityDescription(model.availability)
                return fallbackResponse(
                    for: request,
                    availability: availability,
                    error: "Apple Intelligence is not ready on this device."
                )
            }

            do {
                let result = try await generateWithFoundationModels(request: request, model: model)
                return AppleAIResponse(
                    availability: "available",
                    error: nil,
                    fallbackUsed: false,
                    ok: true,
                    provider: "apple-foundation",
                    recoverySuggestion: nil,
                    requestId: request.requestId,
                    taskKey: request.taskKey,
                    text: result.text,
                    tokenBudget: result.budgetDescription
                )
            } catch let error as LanguageModelSession.GenerationError {
                return fallbackResponse(
                    for: request,
                    availability: generationErrorDescription(error),
                    error: error.localizedDescription
                )
            } catch {
                return fallbackResponse(
                    for: request,
                    availability: "generation-error",
                    error: error.localizedDescription
                )
            }
        }
        #endif

        return fallbackResponse(
            for: request,
            availability: "unsupported-os",
            error: "Foundation Models require iOS 26 or macOS 26."
        )
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private func generateWithFoundationModels(
        request: AppleAIRequest,
        model: SystemLanguageModel
    ) async throws -> (text: String, budgetDescription: String) {
        let responseBudget = resolvedResponseBudget(for: request)
        let contextWindow = min(
            request.contextWindowTokens ?? fallbackContextWindow,
            max(model.contextSize, fallbackContextWindow)
        )
        let inputBudget = max(700, contextWindow - responseBudget - safetyTokens)
        var instructions = compact(request.systemPrompt, tokenBudget: max(300, inputBudget / 4))
        var prompt = compact(
            request.promptEnvelope ?? buildPromptEnvelope(for: request),
            tokenBudget: max(500, inputBudget - estimateTokens(instructions))
        )

        if #available(iOS 26.4, macOS 26.4, *) {
            let instructionTokens = try await model.tokenCount(for: instructions)
            let promptTokens = try await model.tokenCount(for: prompt)
            let measured = instructionTokens + promptTokens
            if measured + responseBudget + safetyTokens > contextWindow {
                let emergencyBudget = max(700, contextWindow - responseBudget - safetyTokens)
                instructions = compact(systemInstructions(for: request), tokenBudget: 240)
                prompt = compact(buildPromptEnvelope(for: request), tokenBudget: emergencyBudget - 240)
            }
        }

        let session = LanguageModelSession(model: model, instructions: instructions)
        let options = GenerationOptions(
            sampling: .greedy,
            temperature: min(max(request.temperature ?? 0.2, 0), 1),
            maximumResponseTokens: responseBudget
        )
        let response = try await session.respond(
            to: prompt,
            options: options
        )

        return (
            response.content.trimmingCharacters(in: .whitespacesAndNewlines),
            "context=\(contextWindow), inputBudget=\(inputBudget), maxResponse=\(responseBudget), estimate=\(request.inputTokenEstimate ?? 0)"
        )
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func availabilityDescription(_ availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available:
            return "available"
        case .unavailable(.appleIntelligenceNotEnabled):
            return "apple-intelligence-not-enabled"
        case .unavailable(.deviceNotEligible):
            return "device-not-eligible"
        case .unavailable(.modelNotReady):
            return "model-not-ready"
        case .unavailable:
            return "unavailable"
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func generationErrorDescription(_ error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .exceededContextWindowSize:
            return "context-window-exceeded"
        case .rateLimited:
            return "rate-limited"
        case .assetsUnavailable:
            return "assets-unavailable"
        case .unsupportedLanguageOrLocale:
            return "unsupported-language-or-locale"
        case .guardrailViolation:
            return "guardrail-violation"
        case .refusal:
            return "refusal"
        case .concurrentRequests:
            return "concurrent-request"
        default:
            return "generation-error"
        }
    }
    #endif

    private func fallbackResponse(
        for request: AppleAIRequest,
        availability: String,
        error: String?
    ) -> AppleAIResponse {
        AppleAIResponse(
            availability: availability,
            error: error,
            fallbackUsed: true,
            ok: true,
            provider: "apple-foundation",
            recoverySuggestion: recoverySuggestion(forAvailability: availability),
            requestId: request.requestId,
            taskKey: request.taskKey,
            text: fallbackText(for: request),
            tokenBudget: "fallback context=\(request.contextWindowTokens ?? fallbackContextWindow), estimate=\(request.inputTokenEstimate ?? 0), maxResponse=\(resolvedResponseBudget(for: request))"
        )
    }

    private func recoverySuggestion(forAvailability availability: String) -> String {
        switch availability {
        case "apple-intelligence-not-enabled":
            return "Turn on Apple Intelligence in Settings or System Settings, then relaunch Pax Historia."
        case "model-not-ready":
            return "This device is eligible, but the local model files are not ready yet. Keep the device on power and Wi-Fi, wait for Apple Intelligence to finish preparing, then retry."
        case "device-not-eligible":
            return "This device does not report Apple Intelligence eligibility to the Foundation Models framework."
        case "assets-unavailable":
            return "The model assets are temporarily unavailable. Let the system finish downloads or preparation, then retry."
        case "unsupported-language-or-locale":
            return "Apple Foundation Models rejected the current language or locale. Use a supported Apple Intelligence language and region."
        case "context-window-exceeded":
            return "The request exceeded the on-device context window. Pax Historia kept the turn safe; future requests should use the compact Apple prompt path."
        case "rate-limited":
            return "Apple Foundation Models rate-limited the request. Wait briefly before asking the game to generate more AI content."
        case "concurrent-request":
            return "Apple Foundation Models only accepted one request at a time here. Wait for the current generation to finish, then retry."
        case "guardrail-violation", "refusal":
            return "The on-device model declined this generation. The game used a deterministic safe result instead."
        case "unsupported-os":
            return "Run the native app on an OS version that includes the Foundation Models framework."
        case "invalid-request":
            return "The game sent an invalid Apple AI request. This is a harness bug, not a device compatibility issue."
        default:
            return "The game used a deterministic safe result. Check Apple Intelligence readiness and retry from the native app."
        }
    }

    private func buildPromptEnvelope(for request: AppleAIRequest) -> String {
        let history = request.history
            .suffix(8)
            .map { "\($0.role): \($0.text)" }
            .joined(separator: "\n")

        return [
            request.responseFormat == "json"
                ? "Return strict JSON only. No Markdown or commentary."
                : "Return concise in-game prose.",
            "Task: \(request.taskKey ?? "general")",
            "",
            "Recent messages:",
            history,
            "",
            "Request:",
            request.userMessage ?? "",
        ].joined(separator: "\n")
    }

    private func systemInstructions(for request: AppleAIRequest) -> String {
        request.responseFormat == "json"
            ? "You are Pax Historia's strategy-game generator. Return one valid compact JSON object only."
            : "You are Pax Historia's concise strategy advisor. Answer briefly and preserve game continuity."
    }

    private func resolvedResponseBudget(for request: AppleAIRequest) -> Int {
        let requested = request.responseTokenBudget ?? request.maxTokens ?? (request.responseFormat == "json" ? 420 : 320)
        return min(900, max(64, requested))
    }

    private func compact(_ text: String, tokenBudget: Int) -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if estimateTokens(normalized) <= tokenBudget {
            return normalized
        }

        let suffix = "\n\n[Trimmed for Apple's 4096-token on-device context window.]"
        let maxCharacters = max(120, tokenBudget * 3 - suffix.count)
        return String(normalized.prefix(maxCharacters)).trimmingCharacters(in: .whitespacesAndNewlines) + suffix
    }

    private func estimateTokens(_ text: String) -> Int {
        let cjkCount = text.unicodeScalars.filter { scalar in
            (0x3040...0x30ff).contains(Int(scalar.value)) ||
            (0x3400...0x9fff).contains(Int(scalar.value)) ||
            (0xac00...0xd7af).contains(Int(scalar.value))
        }.count
        let latinCount = max(0, text.count - cjkCount)
        return Int(ceil(Double(cjkCount) + Double(latinCount) / 3.3))
    }

    private func fallbackText(for request: AppleAIRequest) -> String {
        guard request.responseFormat == "json" else {
            return "The on-device advisor is temporarily unavailable. The safest course is to keep objectives concrete, preserve leverage, and avoid committing to irreversible moves until the next turn clarifies the balance."
        }

        switch request.taskKey {
        case "nativeStatusCheck":
            return "ready"
        case "nativeJumpForward":
            return """
            {"summary":"The native deterministic simulator advanced the campaign because Apple Foundation Models were not available for this request.","stabilityDelta":-1,"worldTensionDelta":2,"events":[{"date":"","title":"External pressure reshapes the strategic environment","description":"Independent actors adjust energy, security, and diplomatic positions. The development does not revolve around the player, but it changes the costs and incentives that future orders must account for.","id":"native-fallback-world-event","importance":"major","kind":"world","linkedActionIDs":[],"notable":true,"playerRelated":false,"strategicEffects":[{"date":"","eventId":"native-fallback-world-event","id":"native-fallback-world-event-effect","magnitude":2,"summary":"Background tension rises and constrains future diplomatic room.","target":"International system","track":"world-tension"}]}]}
            """
        case "actions":
            return """
            {"topics":[{"title":"Stabilize the position","description":"Keep the state playable while the on-device model is unavailable.","actions":[{"kind":"action","title":"Review the current position","text":"Audit diplomacy, internal stability, military readiness, and economic reserves before committing to the next major move."}]}]}
            """
        case "descriptionToAction":
            let title = (request.userMessage ?? "Clarify the order").trimmingCharacters(in: .whitespacesAndNewlines)
            return #"{"kind":"action","title":"\#(jsonEscaped(title.prefix(72)))","text":"\#(jsonEscaped(title)). Define the instrument, timing, and expected effect before execution.","invitees":[],"chatStarter":""}"#
        case "eventConsolidator":
            return #"{"summary":"Recent campaign history remains intact. Continue from the latest recorded events and chats."}"#
        case "nextSpeaker":
            return #"{"nextSpeaker":""}"#
        case "catalystCreation":
            return #"{"title":"Emerging decision point","premise":"A situation now requires direct judgment.","opening":"The cabinet asks for a clear line of action.","choices":["Act decisively","Probe cautiously","Hold position"]}"#
        case "catalystExecutor":
            return #"{"summary":"The chosen line shapes the crisis without creating unsafe state changes.","nextChoices":["Continue pressure","Pause and reassess"],"resolved":false}"#
        case "catalystSummary":
            return #"{"title":"Catalyst resolved","description":"The situation resolves into a manageable campaign development.","importance":"major"}"#
        case "gameMaster":
            return #"{"summary":"The command was noted without unsafe automatic map edits.","impacts":{"regionTransfers":[],"polityChanges":[]}}"#
        case "jumpForward", "autoJumpForward":
            return """
            {"summary":"Time advances cautiously while the game protects continuity.","stopDate":"","clearActions":false,"events":[{"date":"","title":"The international balance remains in motion","description":"Governments adjust to the current situation without a disruptive generated change.","importance":"minor","kind":"world","playerRelated":false,"notable":false,"impacts":{"regionTransfers":[],"polityChanges":[],"createdChats":[]}}],"catalyst":null}
            """
        default:
            return #"{"summary":"The on-device model was unavailable, so Pax Historia used a safe deterministic result."}"#
        }
    }

    private func jsonEscaped<S: StringProtocol>(_ value: S) -> String {
        let string = String(value)
        let data = (try? JSONEncoder().encode(string)) ?? Data(#""""#.utf8)
        let encoded = String(decoding: data, as: UTF8.self)
        return String(encoded.dropFirst().dropLast())
    }
}
