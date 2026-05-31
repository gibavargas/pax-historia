import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class NativeFoundationModelService {
    private let responder = AppleFoundationModelResponder()

    func checkReadiness() async -> AppleAIResponse {
        await responder.respond(
            to: AppleAIRequest(
                history: [
                    .init(role: "user", text: "Reply ready if the on-device model can generate."),
                ],
                contextWindowTokens: 4096,
                inputTokenBudget: 700,
                inputTokenEstimate: 120,
                maxTokens: 16,
                promptEnvelope: "Return exactly the word ready if generation is available.",
                requestId: requestID(prefix: "native-status"),
                responseFormat: "text",
                systemPrompt: "You are a readiness probe for Pax Historia. Reply with exactly: ready",
                taskKey: "nativeStatusCheck",
                temperature: 0,
                userMessage: "Reply ready if the on-device model can generate.",
                responseTokenBudget: 16
            )
        )
    }

    func generateTurn(for state: NativeCampaignState, months: Int) async -> AppleAIResponse {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            if let structured = await generateStructuredTurn(for: state, months: months) {
                return structured
            }
        }
        #endif

        let prompt = makeTurnPrompt(for: state, months: months)
        return await responder.respond(
            to: AppleAIRequest(
                history: state.timeline.prefix(8).map { event in
                    .init(role: "user", text: "\(event.date): \(event.title). \(event.description)")
                },
                contextWindowTokens: 4096,
                inputTokenBudget: 2_700,
                inputTokenEstimate: max(200, prompt.count / 3),
                maxTokens: 760,
                promptEnvelope: prompt,
                requestId: requestID(prefix: "native-turn"),
                responseFormat: "json",
                systemPrompt: nativeSystemPrompt,
                taskKey: "nativeJumpForward",
                temperature: 0.15,
                userMessage: "Advance the campaign by \(months) month(s).",
                responseTokenBudget: 760
            )
        )
    }

    private var nativeSystemPrompt: String {
        """
        You are Pax Historia's native Apple strategy simulation engine.
        Return strict compact JSON only.
        Events must be realistic, causal, and mechanically consequential.
        Do not make every event about the player. Include at least one independent world event unless a severe player crisis dominates the period.
        Every event needs concrete actors, stakes, and strategicEffects.
        """
    }

    private func makeTurnPrompt(for state: NativeCampaignState, months: Int) -> String {
        let actions = state.plannedActions
            .filter { $0.status == .planned }
            .prefix(6)
            .map { "- id=\($0.id) title=\($0.title) detail=\($0.detail)" }
            .joined(separator: "\n")
        let recent = state.timeline
            .prefix(8)
            .map { "- \($0.date): \($0.title) | \($0.description)" }
            .joined(separator: "\n")
        let effects = state.worldEffects
            .prefix(10)
            .map { "- \($0.track.rawValue) \($0.magnitude) on \($0.target): \($0.summary)" }
            .joined(separator: "\n")

        return """
        Return one JSON object matching this Swift Codable shape:
        {
          "summary": "one sentence describing the period",
          "stabilityDelta": 0,
          "worldTensionDelta": 0,
          "events": [{
            "id": "short-stable-id",
            "date": "YYYY-MM-DD",
            "title": "specific event title",
            "description": "specific causal description with actors and consequences",
            "kind": "action|crisis|diplomacy|economy|world",
            "importance": "minor|major|severe",
            "playerRelated": false,
            "notable": true,
            "linkedActionIDs": [],
            "strategicEffects": [{
              "id": "short-stable-id-effect",
              "eventId": "short-stable-id",
              "date": "YYYY-MM-DD",
              "target": "country or International system",
              "track": "diplomatic-leverage|economic-resilience|internal-stability|market-confidence|military-readiness|security-anxiety|world-tension",
              "magnitude": -5,
              "summary": "mechanical consequence"
            }]
          }]
        }

        Simulation date: \(state.gameDate)
        Advance months: \(months)
        Player country: \(state.country.name) (\(state.country.code))
        Stability: \(state.stability)/100
        World tension: \(state.worldTension)/100

        Planned player actions:
        \(actions.isEmpty ? "No planned player actions." : actions)

        Recent events:
        \(recent.isEmpty ? "No prior events." : recent)

        Existing strategic effects:
        \(effects.isEmpty ? "No persistent effects yet." : effects)
        """
    }

    private func requestID(prefix: String) -> String {
        "\(prefix)-\(UUID().uuidString.lowercased())"
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
extension NativeFoundationModelService {
    private func generateStructuredTurn(for state: NativeCampaignState, months: Int) async -> AppleAIResponse? {
        let model = SystemLanguageModel.default
        guard model.isAvailable else { return nil }

        do {
            let prompt = makeTurnPrompt(for: state, months: months)
            let session = LanguageModelSession(model: model, instructions: nativeSystemPrompt)
            let options = GenerationOptions(
                sampling: .greedy,
                temperature: 0.1,
                maximumResponseTokens: 760
            )
            let response = try await session.respond(
                to: prompt,
                generating: AppleNativeGeneratedTurn.self,
                includeSchemaInPrompt: true,
                options: options
            )
            let nativeTurn = response.content.toNativeTurn(fallbackState: state, months: months)
            let data = try JSONEncoder().encode(nativeTurn)
            let text = String(decoding: data, as: UTF8.self)

            return AppleAIResponse(
                availability: "available",
                error: nil,
                fallbackUsed: false,
                ok: true,
                provider: "apple-foundation",
                recoverySuggestion: nil,
                requestId: requestID(prefix: "native-structured-turn"),
                taskKey: "nativeJumpForward",
                text: text,
                tokenBudget: "guided-generation context=4096, maxResponse=760"
            )
        } catch {
            return nil
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
private struct AppleNativeGeneratedTurn {
    @Guide(description: "One concise sentence summarizing the simulated period.")
    var summary: String

    @Guide(description: "A number from -12 to 12 indicating domestic stability change.")
    var stabilityDelta: Int

    @Guide(description: "A number from -12 to 12 indicating international tension change.")
    var worldTensionDelta: Int

    @Guide(description: "Two to four concrete campaign events. At least one should be independent of the player unless a severe player crisis dominates.")
    var events: [AppleNativeGeneratedEvent]

    func toNativeTurn(fallbackState state: NativeCampaignState, months: Int) -> NativeGeneratedTurn {
        NativeGeneratedTurn(
            events: events.enumerated().map { index, event in
                event.toNativeEvent(fallbackState: state, months: months, index: index)
            },
            stabilityDelta: stabilityDelta,
            summary: summary,
            worldTensionDelta: worldTensionDelta
        )
    }
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
private struct AppleNativeGeneratedEvent {
    @Guide(description: "A short stable identifier using lowercase letters, digits, and hyphens.")
    var id: String

    @Guide(description: "The event date in YYYY-MM-DD format.")
    var date: String

    @Guide(description: "Specific event title with concrete actors.")
    var title: String

    @Guide(description: "A concrete causal description with actors, stakes, and consequences.")
    var description: String

    @Guide(description: "One of: action, crisis, diplomacy, economy, world.")
    var kind: String

    @Guide(description: "One of: minor, major, severe.")
    var importance: String

    @Guide(description: "True only when the event directly involves the player's country.")
    var playerRelated: Bool

    @Guide(description: "True when the event deserves timeline attention.")
    var notable: Bool

    @Guide(description: "IDs of player actions resolved or affected by this event.")
    var linkedActionIDs: [String]

    @Guide(description: "One or two mechanical consequences caused by the event.")
    var strategicEffects: [AppleNativeGeneratedEffect]

    func toNativeEvent(fallbackState state: NativeCampaignState, months: Int, index: Int) -> NativeCampaignEvent {
        let eventID = id.isEmpty ? "apple-event-\(state.round)-\(index)" : id
        let eventDate = date.isEmpty ? NativeGameEngine.advance(date: state.gameDate, months: months) : date
        return NativeCampaignEvent(
            date: eventDate,
            description: description,
            id: eventID,
            importance: NativeEventImportance(rawValue: importance) ?? .major,
            kind: NativeEventKind(rawValue: kind) ?? .world,
            linkedActionIDs: linkedActionIDs,
            notable: notable,
            playerRelated: playerRelated,
            strategicEffects: strategicEffects.enumerated().map { effectIndex, effect in
                effect.toNativeEffect(eventID: eventID, eventDate: eventDate, fallbackTarget: playerRelated ? state.country.name : "International system", index: effectIndex)
            },
            title: title
        )
    }
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
private struct AppleNativeGeneratedEffect {
    @Guide(description: "A short stable identifier using lowercase letters, digits, and hyphens.")
    var id: String

    @Guide(description: "The target country, actor, sector, or International system.")
    var target: String

    @Guide(description: "One of: diplomatic-leverage, economic-resilience, internal-stability, market-confidence, military-readiness, security-anxiety, world-tension.")
    var track: String

    @Guide(description: "A number from -5 to 5.")
    var magnitude: Int

    @Guide(description: "One sentence explaining the mechanical consequence.")
    var summary: String

    func toNativeEffect(eventID: String, eventDate: String, fallbackTarget: String, index: Int) -> NativeStrategicEffect {
        NativeStrategicEffect(
            date: eventDate,
            eventId: eventID,
            id: id.isEmpty ? "\(eventID)-effect-\(index)" : id,
            magnitude: max(-5, min(5, magnitude)),
            summary: summary,
            target: target.isEmpty ? fallbackTarget : target,
            track: NativeStrategicTrack(rawValue: track) ?? .worldTension
        )
    }
}
#endif
