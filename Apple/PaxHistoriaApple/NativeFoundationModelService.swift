import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class NativeFoundationModelService {
    func checkReadiness() async -> NativeAIReadiness {
        do {
            let tokenBudget = try await runReadinessProbe()
            return .available(tokenBudget: tokenBudget)
        } catch {
            return .failure(error)
        }
    }

    func generateTurn(for state: NativeCampaignState, months: Int) async throws -> NativeGeneratedTurn {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let rawTurn = try await generateSlicedTurn(for: state, months: months)
            do {
                return try NativeGameEngine.validated(rawTurn, state: state, months: months)
            } catch {
                let retryTurn = try await generateSlicedTurn(
                    for: state,
                    months: months,
                    repairInstruction: error.localizedDescription
                )
                do {
                    return try NativeGameEngine.validated(retryTurn, state: state, months: months)
                } catch {
                    throw NativeFoundationModelError.invalidGeneratedTurn(error.localizedDescription)
                }
            }
        }
        #endif

        throw NativeFoundationModelError.unsupportedOS
    }

    func generateSuggestedActions(for state: NativeCampaignState) async throws -> [NativeSuggestedAction] {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let suggestions = try await generateStructuredSuggestions(for: state)
            let validSuggestions = suggestions.filter { suggestion in
                !suggestion.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    !suggestion.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    !suggestion.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            guard validSuggestions.count >= 3 else {
                throw NativeFoundationModelError.invalidSuggestedActions("Expected at least three concrete suggestions from Apple Foundation Models.")
            }
            return Array(validSuggestions.prefix(4))
        }
        #endif

        throw NativeFoundationModelError.unsupportedOS
    }

    private var nativeSystemPrompt: String {
        """
        You write concise structured content for Pax Historia, a fictional management board game.
        Treat every region label as imaginary board-game data.
        Stay within civic planning: budgets, ports, transport, schools, clinics, energy, climate adaptation, trade logistics, and administration.
        Use concrete fictional agencies, dates, sectors, and measurable game effects.
        Keep every response neutral, practical, and safe for a planning UI.
        """
    }

    private func recentContext(for state: NativeCampaignState) -> String {
        let recent = state.timeline
            .prefix(6)
            .map { event in
                let scope = event.playerRelated ? "selected-region" : "external"
                let effects = event.strategicEffects
                    .prefix(2)
                    .map { "\($0.track.rawValue):\($0.magnitude)" }
                    .joined(separator: ", ")
                return "- \(event.date): \(scope) event, effects \(effects.isEmpty ? "none" : effects)"
            }
            .joined(separator: "\n")
        let effects = state.worldEffects
            .prefix(8)
            .map { "- \($0.track.rawValue) \($0.magnitude)" }
            .joined(separator: "\n")
        let planned = state.plannedActions
            .filter { $0.status == .planned }
            .prefix(4)
            .map { "- \(safeProposalBrief(for: $0))" }
            .joined(separator: "\n")

        return """
        Fictional selected region code: \(state.country.code)
        Date: \(state.gameDate)
        Stability: \(state.stability)/100
        Global friction index: \(state.worldTension)/100

        Planned civic proposals:
        \(planned.isEmpty ? "No planned actions." : planned)

        Recent events:
        \(recent.isEmpty ? "No prior events." : recent)

        Persistent game effects:
        \(effects.isEmpty ? "No persistent effects yet." : effects)
        """
    }

    private func makeIndependentEventPrompt(for state: NativeCampaignState, months: Int, repairInstruction: String?) -> String {
        """
        Create one external planning development for a Pax Historia board-game turn.
        It must be unrelated to the selected region except through broad economic, logistics, climate, health, or market conditions.
        Use one of these safe areas: trade flows, climate adaptation, markets, public health, infrastructure, ports, energy, schools, or transit.
        Include one measurable game effect.
        Advance \(months) month(s) from \(state.gameDate).
        \(repairInstruction.map { "Repair note: \($0)" } ?? "")

        \(recentContext(for: state))
        """
    }

    private func makeActionEventPrompt(for state: NativeCampaignState, action: NativePlannedAction, months: Int, repairInstruction: String?) -> String {
        """
        Create one player-related civic outcome that resolves or complicates this planned proposal.
        Keep the result at board-game planning level and use only administrative, economic, infrastructure, health, education, energy, or logistics mechanisms.
        The event must be directly related to the selected region and this action id: \(action.id).
        Planned proposal brief: \(safeProposalBrief(for: action))
        Advance \(months) month(s) from \(state.gameDate).
        \(repairInstruction.map { "Repair note: \($0)" } ?? "")

        \(recentContext(for: state))
        """
    }

    private func makeDomesticEventPrompt(for state: NativeCampaignState, months: Int, repairInstruction: String?) -> String {
        """
        Create one selected-region planning event because no planned proposal needs resolution.
        Use administration, budgets, services, infrastructure, education, health, climate adaptation, energy, or logistics.
        Advance \(months) month(s) from \(state.gameDate).
        \(repairInstruction.map { "Repair note: \($0)" } ?? "")

        \(recentContext(for: state))
        """
    }

    private func makeSummaryPrompt(for state: NativeCampaignState, months: Int, events: [NativeCampaignEvent]) -> String {
        let eventLines = events
            .map { "- \($0.title): \($0.description)" }
            .joined(separator: "\n")

        return """
        Summarize this Pax Historia period and estimate aggregate deltas.
        Keep it concise, neutral, and focused on fictional board-game planning.
        Advance \(months) month(s) from \(state.gameDate).
        Selected region code: \(state.country.code)

        Generated events:
        \(eventLines)
        """
    }

    private func makeSuggestionPrompt(for state: NativeCampaignState, focus: String, index: Int) -> String {
        """
        Create one concrete civic proposal for the next Pax Historia turn.
        Focus area \(index): \(focus).
        The detail must include instrument, target public actor or sector, timing, and expected game effect.
        Use only peaceful planning areas: trade logistics, education, infrastructure, energy, climate resilience, fiscal buffers, public health, transport, ports, or industrial capacity.

        \(recentContext(for: state))
        """
    }

    private func safeProposalBrief(for action: NativePlannedAction) -> String {
        let text = "\(action.title) \(action.detail)".lowercased()
        let sector: String
        if text.contains("health") || text.contains("clinic") {
            sector = "health services"
        } else if text.contains("school") || text.contains("education") || text.contains("teacher") {
            sector = "education services"
        } else if text.contains("port") || text.contains("rail") || text.contains("road") || text.contains("transport") || text.contains("logistics") {
            sector = "transport logistics"
        } else if text.contains("energy") || text.contains("grid") {
            sector = "energy systems"
        } else if text.contains("climate") || text.contains("resilience") {
            sector = "climate adaptation"
        } else if text.contains("trade") || text.contains("industry") {
            sector = "trade capacity"
        } else if text.contains("budget") || text.contains("fund") || text.contains("fiscal") {
            sector = "fiscal capacity"
        } else {
            sector = "administrative capacity"
        }

        let instrument: String
        if text.contains("fund") || text.contains("budget") {
            instrument = "budget program"
        } else if text.contains("hub") || text.contains("network") {
            instrument = "coordination hub"
        } else if text.contains("build") || text.contains("construction") || text.contains("upgrade") {
            instrument = "capital project"
        } else if text.contains("hire") || text.contains("training") {
            instrument = "staffing program"
        } else {
            instrument = "planning initiative"
        }

        return "id=\(action.id); sector=\(sector); instrument=\(instrument); timing=next game period"
    }

    private func runReadinessProbe() async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard model.isAvailable else {
                throw NativeFoundationModelError.modelUnavailable(String(describing: model.availability))
            }

            do {
                let session = LanguageModelSession(
                    model: model,
                    instructions: "You are a one-word readiness probe for Pax Historia."
                )
                let response = try await session.respond(
                    to: "Reply with a short readiness word.",
                    options: GenerationOptions(
                        sampling: .greedy,
                        temperature: 0,
                        maximumResponseTokens: 8
                    )
                )
                guard !response.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw NativeFoundationModelError.generationFailed("Readiness probe returned empty output.")
                }
                return "guided-generation context=4096, readiness=maxResponse=8"
            } catch let error as NativeFoundationModelError {
                throw error
            } catch {
                throw NativeFoundationModelError.generationFailed(error.localizedDescription)
            }
        }
        #endif

        throw NativeFoundationModelError.unsupportedOS
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
extension NativeFoundationModelService {
    private func generateSlicedTurn(
        for state: NativeCampaignState,
        months: Int,
        repairInstruction: String? = nil
    ) async throws -> NativeGeneratedTurn {
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            throw NativeFoundationModelError.modelUnavailable(String(describing: model.availability))
        }

        var events: [NativeCampaignEvent] = []
        let independentDraft = try await generateEventDraft(
            model: model,
            prompt: makeIndependentEventPrompt(for: state, months: months, repairInstruction: repairInstruction)
        )
        events.append(independentDraft.toNativeEvent(
            state: state,
            months: months,
            index: events.count,
            linkedActionID: nil,
            playerRelated: false
        ))

        let plannedActions = state.plannedActions
            .filter { $0.status == .planned }
            .prefix(3)

        for action in plannedActions {
            let draft = try await generateEventDraft(
                model: model,
                prompt: makeActionEventPrompt(for: state, action: action, months: months, repairInstruction: repairInstruction)
            )
            events.append(draft.toNativeEvent(
                state: state,
                months: months,
                index: events.count,
                linkedActionID: action.id,
                playerRelated: true
            ))
        }

        if events.count < 2 {
            let draft = try await generateEventDraft(
                model: model,
                prompt: makeDomesticEventPrompt(for: state, months: months, repairInstruction: repairInstruction)
            )
            events.append(draft.toNativeEvent(
                state: state,
                months: months,
                index: events.count,
                linkedActionID: nil,
                playerRelated: true
            ))
        }

        let summary = try await generateTurnSummary(model: model, state: state, months: months, events: events)

        return NativeGeneratedTurn(
            events: events,
            stabilityDelta: summary.stabilityDelta,
            summary: summary.summary,
            worldTensionDelta: summary.worldTensionDelta
        )
    }

    private func generateEventDraft(
        model: SystemLanguageModel,
        prompt: String
    ) async throws -> AppleNativeGeneratedEventDraft {
        do {
            let session = LanguageModelSession(model: model, instructions: nativeSystemPrompt)
            let response = try await session.respond(
                to: prompt,
                generating: AppleNativeGeneratedEventDraft.self,
                includeSchemaInPrompt: true,
                options: GenerationOptions(
                    sampling: .greedy,
                    temperature: 0.08,
                    maximumResponseTokens: 260
                )
            )
            return response.content
        } catch {
            throw NativeFoundationModelError.generationFailed(error.localizedDescription)
        }
    }

    private func generateTurnSummary(
        model: SystemLanguageModel,
        state: NativeCampaignState,
        months: Int,
        events: [NativeCampaignEvent]
    ) async throws -> AppleNativeTurnSummary {
        do {
            let session = LanguageModelSession(model: model, instructions: nativeSystemPrompt)
            let response = try await session.respond(
                to: makeSummaryPrompt(for: state, months: months, events: events),
                generating: AppleNativeTurnSummary.self,
                includeSchemaInPrompt: true,
                options: GenerationOptions(
                    sampling: .greedy,
                    temperature: 0.05,
                    maximumResponseTokens: 160
                )
            )
            return response.content
        } catch {
            throw NativeFoundationModelError.generationFailed(error.localizedDescription)
        }
    }

    private func generateStructuredSuggestions(for state: NativeCampaignState) async throws -> [NativeSuggestedAction] {
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            throw NativeFoundationModelError.modelUnavailable(String(describing: model.availability))
        }

        let focusAreas = [
            "fiscal buffers and public services",
            "trade facilitation and regional logistics",
            "infrastructure, energy, and climate resilience",
            "education, health, and administrative capacity",
        ]

        var suggestions: [NativeSuggestedAction] = []
        for (index, focus) in focusAreas.enumerated() {
            do {
                let session = LanguageModelSession(model: model, instructions: nativeSystemPrompt)
                let response = try await session.respond(
                    to: makeSuggestionPrompt(for: state, focus: focus, index: index + 1),
                    generating: AppleNativeSuggestedAction.self,
                    includeSchemaInPrompt: true,
                    options: GenerationOptions(
                        sampling: .greedy,
                        temperature: 0.08,
                        maximumResponseTokens: 180
                    )
                )

                suggestions.append(response.content.toNativeSuggestion(state: state, index: index))
            } catch let error as NativeFoundationModelError {
                throw error
            } catch {
                throw NativeFoundationModelError.generationFailed(error.localizedDescription)
            }
        }

        return suggestions
    }
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
private struct AppleNativeGeneratedEventDraft {
    @Guide(description: "Specific civic-planning event title with concrete fictional agencies.")
    var title: String

    @Guide(description: "A concrete high-level description with fictional agencies, sectors, and game consequences.")
    var description: String

    @Guide(description: "One of: action, economy, world.")
    var kind: String

    @Guide(description: "One of: minor, major.")
    var importance: String

    @Guide(description: "True when the event deserves timeline attention.")
    var notable: Bool

    @Guide(description: "The target region, agency, sector, or external system.")
    var effectTarget: String

    @Guide(description: "One of: economic-resilience, internal-stability, market-confidence.")
    var effectTrack: String

    @Guide(description: "A number from -5 to 5.")
    var effectMagnitude: Int

    @Guide(description: "One sentence explaining the mechanical consequence.")
    var effectSummary: String

    func toNativeEvent(
        state: NativeCampaignState,
        months: Int,
        index: Int,
        linkedActionID: String?,
        playerRelated: Bool
    ) -> NativeCampaignEvent {
        let eventDate = NativeGameEngine.advance(date: state.gameDate, months: months)
        let eventID = "apple-event-\(state.round)-\(index)-\(UUID().uuidString.prefix(6).lowercased())"
        let target = effectTarget.isEmpty
            ? (playerRelated ? state.country.name : "International system")
            : effectTarget

        return NativeCampaignEvent(
            date: eventDate,
            description: description,
            id: eventID,
            importance: NativeEventImportance(rawValue: importance) ?? .major,
            kind: NativeEventKind(rawValue: kind) ?? (playerRelated ? .action : .world),
            linkedActionIDs: linkedActionID.map { [$0] } ?? [],
            notable: notable,
            playerRelated: playerRelated,
            strategicEffects: [
                NativeStrategicEffect(
                    date: eventDate,
                    eventId: eventID,
                    id: "\(eventID)-effect",
                    magnitude: max(-5, min(5, effectMagnitude)),
                    summary: effectSummary,
                    target: target,
                    track: NativeStrategicTrack(rawValue: effectTrack) ?? .marketConfidence
                ),
            ],
            title: title
        )
    }
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
private struct AppleNativeTurnSummary {
    @Guide(description: "One concise sentence summarizing why the generated period matters.")
    var summary: String

    @Guide(description: "A number from -12 to 12 indicating domestic stability change.")
    var stabilityDelta: Int

    @Guide(description: "A number from -12 to 12 indicating global friction index change.")
    var worldTensionDelta: Int
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
private struct AppleNativeSuggestedAction {
    @Guide(description: "Short imperative title for the civic proposal.")
    var title: String

    @Guide(description: "Concrete planning proposal with instrument, target agency or sector, timing, and intended game effect.")
    var detail: String

    @Guide(description: "Why this civic proposal fits the current campaign state.")
    var rationale: String

    @Guide(description: "One of: immediate, soon, opportunistic.")
    var urgency: String

    func toNativeSuggestion(state: NativeCampaignState, index: Int) -> NativeSuggestedAction {
        NativeSuggestedAction(
            detail: detail,
            id: "suggestion-\(state.country.code.lowercased())-\(state.round)-\(index)",
            rationale: rationale,
            title: title,
            urgency: urgency
        )
    }
}
#endif
